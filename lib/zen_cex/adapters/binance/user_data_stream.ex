defmodule ZenCex.Adapters.Binance.UserDataStream do
  @moduledoc """
  Manages Binance USD-M Futures user data streams (private WebSocket streams).

  Provides a supervised GenServer per account that:
  - Creates and maintains the listenKey lifecycle (auto-keepalive every 20 min)
  - Connects to the private WebSocket stream
  - Dispatches events to registered handlers by event type
  - Supports multiple accounts simultaneously (one process per account_id)

  ## Design

  Private stream events are **event-driven**, not market data snapshots.
  This module deliberately does NOT cache events in ETS — each event is
  dispatched to handlers immediately and then discarded.

  For market data (kline, depth, markPrice), use `WebSocket.connect/2` directly;
  those are cached in ETS via `Cache.Market`.

  ## Usage

      # Start a stream for an account
      {:ok, _pid} = UserDataStream.start_link(
        account_id: :main,
        credentials: %{api_key: "...", api_secret: "..."},
        events: ["ORDER_TRADE_UPDATE", "ACCOUNT_UPDATE"],
        handlers: %{
          "ORDER_TRADE_UPDATE" => &MyApp.OrderTracker.handle/1,
          "ACCOUNT_UPDATE"     => &MyApp.RiskManager.handle/1,
          :default             => &MyApp.AuditLog.handle/1
        }
      )

      # Or add to your supervision tree
      children = [
        {ZenCex.Adapters.Binance.UserDataStream, [
          account_id: :hedge_account,
          credentials: %{api_key: "...", api_secret: "..."},
          events: ["ORDER_TRADE_UPDATE"],
          handlers: %{"ORDER_TRADE_UPDATE" => &MyHedger.on_order/1}
        ]}
      ]

      # Inspect state
      {:ok, info} = UserDataStream.get_info(:main)
      # => %{account_id: :main, listen_key: "fS7mg5...", connected: true, ...}

      # Stop a stream
      UserDataStream.stop(:main)

  ## Multiple Accounts

      UserDataStream.start_link(account_id: :account_a, credentials: creds_a, ...)
      UserDataStream.start_link(account_id: :account_b, credentials: creds_b, ...)

  ## Event Handler Contract

  Handlers receive the raw Binance event map:

      def handle_order(%{"e" => "ORDER_TRADE_UPDATE", "o" => order}) do
        symbol   = order["s"]  # "BTCUSDT"
        order_id = order["i"]  # 12345678
        status   = order["X"]  # "NEW" | "FILLED" | "CANCELED" | ...
      end

      def handle_account(%{"e" => "ACCOUNT_UPDATE", "a" => account}) do
        balances  = account["B"]  # list of balance changes
        positions = account["P"]  # list of position changes
        reason    = account["m"]  # "ORDER" | "FUNDING_FEE" | ...
      end

  ## listenKey Lifecycle

  - listenKey expires after 60 minutes without keepalive
  - Keepalive (PUT /fapi/v1/listenKey) is sent every 20 minutes
  - On listenKey expiry (code -1125), a new listenKey is created and reconnected
  - On terminate, the listenKey is deleted from Binance
  """

  use GenServer

  require Logger

  alias ZenCex.Adapters.Binance.WebSocket

  @keepalive_interval_ms 20 * 60 * 1000
  @reconnect_delay_ms    3_000
  @fapi_base             "https://fapi.binance.com"

  # ── Public API ───────────────────────────────────────────────

  @doc """
  Starts a UserDataStream process for the given account.

  Options:
  - `:account_id`   — atom, unique per account (required)
  - `:credentials`  — `%{api_key: String.t(), api_secret: String.t()}` (required)
  - `:events`       — list of event types (default: `["ORDER_TRADE_UPDATE"]`)
  - `:handlers`     — `%{event_type => handler_fn}`, `:default` key for catch-all (required)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    GenServer.start_link(__MODULE__, opts, name: via(account_id))
  end

  @doc "Returns current stream info for the given account."
  @spec get_info(atom()) :: {:ok, map()} | {:error, :not_found}
  def get_info(account_id) do
    case GenServer.whereis(via(account_id)) do
      nil  -> {:error, :not_found}
      _pid -> {:ok, GenServer.call(via(account_id), :get_info)}
    end
  end

  @doc "Stops the stream for the given account."
  @spec stop(atom()) :: :ok
  def stop(account_id) do
    case GenServer.whereis(via(account_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  # ── GenServer callbacks ──────────────────────────────────────

  @impl true
  def init(opts) do
    state = %{
      account_id:  Keyword.fetch!(opts, :account_id),
      credentials: Keyword.fetch!(opts, :credentials),
      handlers:    Keyword.fetch!(opts, :handlers),
      events:      Keyword.get(opts, :events, ["ORDER_TRADE_UPDATE"]),
      listen_key:  nil,
      ws_client:   nil,
      connected:   false,
      started_at:  System.system_time(:millisecond)
    }
    send(self(), :connect)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case fapi_request(:post, "/fapi/v1/listenKey", state.credentials, "") do
      {:ok, %{"listenKey" => lk}} ->
        Logger.info("[UserDataStream:#{state.account_id}] listenKey obtained: #{String.slice(lk, 0, 8)}...")
        handler = build_dispatch_handler(state.account_id, state.handlers)
        case WebSocket.connect([], market: :futures_private, listen_key: lk, events: state.events, handler: handler) do
          {:ok, client} ->
            Logger.info("[UserDataStream:#{state.account_id}] Connected")
            schedule_keepalive()
            {:noreply, %{state | listen_key: lk, ws_client: client, connected: true}}
          {:error, reason} ->
            Logger.error("[UserDataStream:#{state.account_id}] WS connect failed: #{inspect(reason)}, retrying...")
            Process.send_after(self(), :connect, @reconnect_delay_ms)
            {:noreply, %{state | listen_key: lk, connected: false}}
        end
      {:error, reason} ->
        Logger.error("[UserDataStream:#{state.account_id}] listenKey creation failed: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :connect, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:keepalive, state) do
    case fapi_request(:put, "/fapi/v1/listenKey", state.credentials, "listenKey=#{state.listen_key}") do
      {:ok, _} ->
        Logger.debug("[UserDataStream:#{state.account_id}] listenKey keepalive OK")
        schedule_keepalive()
        {:noreply, state}
      {:error, {:http_error, 400, body}} ->
        case Jason.decode(body) do
          {:ok, %{"code" => -1125}} ->
            Logger.warning("[UserDataStream:#{state.account_id}] listenKey expired, reconnecting...")
            if state.ws_client, do: WebSocket.close(state.ws_client)
            send(self(), :connect)
            {:noreply, %{state | listen_key: nil, ws_client: nil, connected: false}}
          _ ->
            Logger.warning("[UserDataStream:#{state.account_id}] keepalive 400: #{body}, will retry")
            schedule_keepalive()
            {:noreply, state}
        end
      {:error, reason} ->
        Logger.warning("[UserDataStream:#{state.account_id}] keepalive failed: #{inspect(reason)}, will retry")
        schedule_keepalive()
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      account_id: state.account_id,
      listen_key: state.listen_key && String.slice(state.listen_key, 0, 8) <> "...",
      connected:  state.connected,
      events:     state.events,
      started_at: state.started_at
    }
    {:reply, info, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.ws_client, do: WebSocket.close(state.ws_client)
    if state.listen_key do
      fapi_request(:delete, "/fapi/v1/listenKey", state.credentials, "listenKey=#{state.listen_key}")
    end
    Logger.info("[UserDataStream:#{state.account_id}] Stopped, listenKey deleted")
    :ok
  end

  # ── Private helpers ──────────────────────────────────────────

  defp build_dispatch_handler(account_id, handlers) do
    fn
      {:message, %{"e" => event_type} = event} ->
        handler = Map.get(handlers, event_type) || Map.get(handlers, :default)
        if handler do
          try do
            handler.(event)
          rescue
            e -> Logger.error("[UserDataStream:#{account_id}] Handler for #{event_type} raised: #{Exception.message(e)}")
          end
        else
          Logger.debug("[UserDataStream:#{account_id}] No handler for event: #{event_type}")
        end
      _other -> :ok
    end
  end

  defp schedule_keepalive do
    Process.send_after(self(), :keepalive, @keepalive_interval_ms)
  end

  defp via(account_id) do
    {:via, Registry, {ZenCex.UserDataStreamRegistry, account_id}}
  end

  # ── Shared fapi REST helper ──────────────────────────────────
  # Handles HMAC signing, request dispatch, and response parsing for all
  # /fapi/v1/listenKey operations (POST create, PUT keepalive, DELETE close).

  defp fapi_request(method, path, %{api_key: api_key, api_secret: api_secret}, extra_qs) do
    ts  = :os.system_time(:millisecond)
    qs  = if extra_qs == "", do: "timestamp=#{ts}&recvWindow=5000",
                             else: "#{extra_qs}&timestamp=#{ts}&recvWindow=5000"
    sig = :crypto.mac(:hmac, :sha256, api_secret, qs) |> Base.encode16(case: :lower)
    url = String.to_charlist("#{@fapi_base}#{path}?#{qs}&signature=#{sig}")
    headers = [{~c"X-MBX-APIKEY", String.to_charlist(api_key)}]
    request = if method == :get, do: {url, headers}, else: {url, headers, ~c"application/x-www-form-urlencoded", ~c""}
    case :httpc.request(method, request, [], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        Jason.decode(List.to_string(body))
      {:ok, {{_, status, _}, _, body}} ->
        {:error, {:http_error, status, List.to_string(body)}}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
