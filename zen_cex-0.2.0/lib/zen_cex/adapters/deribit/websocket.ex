defmodule ZenCex.Adapters.Deribit.WebSocket do
  @moduledoc """
  Deribit WebSocket API adapter.

  Provides WebSocket connection management, authentication, and subscription
  handling for Deribit exchange. Message handlers automatically update the
  ETS cache for market data.

  ## Usage

      # Connect and authenticate
      {:ok, adapter} = Deribit.WebSocket.connect(
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      )

      {:ok, adapter} = Deribit.WebSocket.authenticate(adapter)

      # Subscribe to market data
      {:ok, adapter} = Deribit.WebSocket.subscribe(adapter, [
        "book.BTC-PERPETUAL.raw",
        "ticker.BTC-PERPETUAL.raw"
      ])

  """

  alias ZenCex.Adapters.Deribit.Rpc
  alias ZenCex.Cache.Market
  alias ZenWebsocket.Client

  require Logger

  defstruct [:client, :authenticated, :subscriptions, :client_id, :client_secret]

  @type t :: %__MODULE__{
          client: Client.t() | nil,
          authenticated: boolean(),
          subscriptions: MapSet.t(),
          client_id: String.t() | nil,
          client_secret: String.t() | nil
        }

  @deribit_prod_url "wss://www.deribit.com/ws/api/v2"
  @deribit_test_url "wss://test.deribit.com/ws/api/v2"
  @heartbeat_interval_seconds 30
  @milliseconds_per_second 1000

  @doc """
  Connect to Deribit WebSocket API.

  ## Options
  - `:client_id` - Client ID for authentication (required)
  - `:client_secret` - Client secret for authentication (required)
  - `:testnet` - Use testnet URL (default: true)
  - `:url` - Custom WebSocket URL (overrides testnet option)
  - `:heartbeat_interval` - Heartbeat interval in seconds (default: 30)

  ## Examples

      {:ok, adapter} = connect(
        client_id: "client_id",
        client_secret: "client_secret"
      )

      {:ok, adapter} = connect(
        client_id: "client_id",
        client_secret: "client_secret",
        testnet: false
      )

  """
  @spec connect(keyword()) :: {:ok, t()} | {:error, term()}
  def connect(opts \\ []) do
    testnet = Keyword.get(opts, :testnet, true)
    url = Keyword.get(opts, :url, if(testnet, do: @deribit_test_url, else: @deribit_prod_url))

    heartbeat_interval =
      Keyword.get(opts, :heartbeat_interval, @heartbeat_interval_seconds) *
        @milliseconds_per_second

    connect_opts = [
      heartbeat_config: %{
        type: :deribit,
        interval: heartbeat_interval
      },
      handler: create_message_handler()
    ]

    case Client.connect(url, connect_opts) do
      {:ok, client} ->
        {:ok,
         %__MODULE__{
           client: client,
           authenticated: false,
           subscriptions: MapSet.new(),
           client_id: opts[:client_id],
           client_secret: opts[:client_secret]
         }}

      error ->
        error
    end
  end

  @doc """
  Authenticate with Deribit using client credentials.

  ## Examples

      {:ok, adapter} = authenticate(adapter)

  """
  @spec authenticate(t()) :: {:ok, t()} | {:error, term()}
  def authenticate(%__MODULE__{client_id: nil}), do: {:error, :missing_credentials}

  def authenticate(%__MODULE__{client: client} = adapter) do
    request = Rpc.auth_request(adapter.client_id, adapter.client_secret)

    case send_json_rpc_sync(client, request) do
      {:ok, %{"result" => %{"access_token" => _}}} ->
        # Set up heartbeat after authentication
        heartbeat_req = Rpc.set_heartbeat(@heartbeat_interval_seconds)

        case send_json_rpc_sync(client, heartbeat_req) do
          {:ok, %{"result" => "ok"}} ->
            {:ok, %{adapter | authenticated: true}}

          {:ok, unexpected} ->
            {:error, {:unexpected_heartbeat_response, unexpected}}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Subscribe to Deribit channels.

  ## Parameters
  - `adapter` - The adapter struct
  - `channels` - List of channel names to subscribe to

  ## Channel Examples
  - `"book.BTC-PERPETUAL.raw"` - Order book updates
  - `"ticker.BTC-PERPETUAL.raw"` - Ticker updates
  - `"trades.BTC-PERPETUAL.raw"` - Trade updates

  ## Examples

      {:ok, adapter} = subscribe(adapter, ["book.BTC-PERPETUAL.raw"])

  """
  @spec subscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
  def subscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) do
    request = Rpc.subscribe(channels)

    case send_json_rpc_sync(client, request) do
      {:ok, %{"result" => subscribed_channels}} when is_list(subscribed_channels) ->
        # Only add channels that were successfully subscribed
        new_subs = Enum.reduce(subscribed_channels, subs, &MapSet.put(&2, &1))
        {:ok, %{adapter | subscriptions: new_subs}}

      {:ok, unexpected} ->
        {:error, {:unexpected_subscription_response, unexpected}}

      error ->
        error
    end
  end

  @doc """
  Unsubscribe from Deribit channels.

  ## Examples

      {:ok, adapter} = unsubscribe(adapter, ["book.BTC-PERPETUAL.raw"])

  """
  @spec unsubscribe(t(), list(String.t())) :: {:ok, t()} | {:error, term()}
  def unsubscribe(%__MODULE__{client: client, subscriptions: subs} = adapter, channels) do
    request = Rpc.unsubscribe(channels)

    case send_json_rpc_sync(client, request) do
      {:ok, %{"result" => unsubscribed_channels}} when is_list(unsubscribed_channels) ->
        # Only remove channels that were successfully unsubscribed
        new_subs = Enum.reduce(unsubscribed_channels, subs, &MapSet.delete(&2, &1))
        {:ok, %{adapter | subscriptions: new_subs}}

      {:ok, unexpected} ->
        {:error, {:unexpected_unsubscription_response, unexpected}}

      error ->
        error
    end
  end

  @doc """
  Send a request to Deribit API using any supported method.

  ## Examples

      {:ok, response} = send_request(adapter, "public/get_instruments", %{currency: "BTC"})

  """
  @spec send_request(t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def send_request(%__MODULE__{client: client}, method, params \\ %{}) do
    {:ok, request} = ZenWebsocket.JsonRpc.build_request(method, params)
    send_json_rpc_sync(client, request)
  end

  # Internal function for Task 5 (MarketData) - sends pre-built JSON-RPC requests
  # Used when MarketData needs to make direct API calls with specific request structures
  @doc false
  @spec send_request_sync(t(), map()) :: {:ok, map()} | {:error, term()}
  def send_request_sync(%__MODULE__{client: client}, request) do
    send_json_rpc_sync(client, request)
  end

  @doc """
  Close the WebSocket connection.

  ## Examples

      :ok = close(adapter)

  """
  @spec close(t()) :: :ok
  def close(%__MODULE__{client: client}) do
    Client.close(client)
  end

  # Private helper to send JSON-RPC requests and wait for response
  defp send_json_rpc_sync(client, request) do
    case Client.send_message(client, Jason.encode!(request)) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  # Creates a message handler function for the WebSocket client
  @spec create_message_handler() :: (term() -> :ok)
  defp create_message_handler do
    fn message ->
      handle_message(message)
    end
  end

  # Handles incoming WebSocket messages
  @spec handle_message(term()) :: :ok
  defp handle_message({:message, {:text, message}}) do
    case Jason.decode(message) do
      {:ok, %{"method" => "subscription", "params" => params}} ->
        handle_subscription_message(params)

      {:ok, %{"method" => "heartbeat", "params" => _}} ->
        # Heartbeat handled automatically by zen_websocket
        :ok

      {:ok, _other} ->
        # Request/response messages handled by correlation system
        :ok

      {:error, reason} ->
        Logger.warning("Failed to decode Deribit message: #{inspect(reason)}")
        :ok
    end
  end

  defp handle_message(_message), do: :ok

  # Routes subscription messages to specific handlers based on channel
  @spec handle_subscription_message(map()) :: :ok
  defp handle_subscription_message(%{"channel" => channel, "data" => data}) do
    cond do
      String.starts_with?(channel, "book.") ->
        handle_orderbook_update(channel, data)

      String.starts_with?(channel, "ticker.") ->
        handle_ticker_update(channel, data)

      String.starts_with?(channel, "trades.") ->
        handle_trade_update(channel, data)

      true ->
        Logger.debug("Unhandled Deribit subscription channel: #{channel}")
        :ok
    end
  end

  defp handle_subscription_message(_params), do: :ok

  # Handles order book updates and caches to ETS
  @spec handle_orderbook_update(String.t(), map()) :: :ok
  defp handle_orderbook_update(channel, data) do
    instrument = extract_instrument_from_channel(channel)

    orderbook = %{
      instrument: instrument,
      timestamp: data["timestamp"] || :os.system_time(:millisecond),
      change_id: data["change_id"],
      bids: parse_orderbook_levels(data["bids"] || []),
      asks: parse_orderbook_levels(data["asks"] || [])
    }

    # Infinite TTL - orderbook updates are continuous via WebSocket subscription
    # Data remains fresh as long as the connection is active
    Market.put_orderbook(:deribit, instrument, orderbook, :infinity)
  end

  # Handles ticker updates and caches to ETS
  @spec handle_ticker_update(String.t(), map()) :: :ok
  defp handle_ticker_update(channel, data) do
    instrument = extract_instrument_from_channel(channel)

    ticker = %{
      instrument: instrument,
      timestamp: data["timestamp"] || :os.system_time(:millisecond),
      last_price: data["last_price"],
      mark_price: data["mark_price"],
      index_price: data["index_price"],
      best_bid: data["best_bid_price"],
      best_ask: data["best_ask_price"],
      volume: data["stats"] && data["stats"]["volume"],
      high: data["stats"] && data["stats"]["high"],
      low: data["stats"] && data["stats"]["low"]
    }

    # 30 second TTL for ticker data (matches Binance pattern)
    # Short TTL ensures stale data is discarded if subscription stops
    Market.put_ticker(:deribit, instrument, ticker, 30)
  end

  # Handles trade updates and caches to ETS
  @spec handle_trade_update(String.t(), map()) :: :ok
  defp handle_trade_update(channel, data) do
    instrument = extract_instrument_from_channel(channel)

    # Deribit sends array of trades
    trades = if is_list(data), do: data, else: [data]

    Enum.each(trades, fn trade ->
      trade_data = %{
        instrument: instrument,
        timestamp: trade["timestamp"] || :os.system_time(:millisecond),
        trade_id: trade["trade_id"],
        price: trade["price"],
        amount: trade["amount"],
        direction: trade["direction"],
        tick_direction: trade["tick_direction"]
      }

      Market.put_last_trade(:deribit, instrument, trade_data)
    end)
  end

  # Extracts instrument name from channel string
  # "book.BTC-PERPETUAL.raw" -> "BTC-PERPETUAL"
  @spec extract_instrument_from_channel(String.t()) :: String.t()
  defp extract_instrument_from_channel(channel) do
    channel
    |> String.split(".")
    |> Enum.at(1, "")
  end

  # Parses order book levels from Deribit format
  #
  # Deribit sends order book data in different formats depending on the subscription type:
  # 1. Raw updates: ["new", price, amount] or ["change", price, amount] or ["delete", price, amount]
  # 2. Snapshot: [price, amount]
  # 3. Already parsed: %{price: ..., quantity: ...}
  #
  # This function handles all three formats for robustness:
  # - [_action, price, amount] - raw updates with action ("new", "change", "delete")
  # - [price, amount] - snapshot data or simplified format
  # - map - already parsed by other handlers
  #
  # Returns: [%{price: ..., quantity: ...}, ...]
  @spec parse_orderbook_levels(list()) :: list(map())
  defp parse_orderbook_levels(levels) when is_list(levels) do
    Enum.map(levels, fn
      [_action, price, amount] -> %{price: price, quantity: amount}
      [price, amount] -> %{price: price, quantity: amount}
      level when is_map(level) -> level
    end)
  end

  defp parse_orderbook_levels(_), do: []
end
