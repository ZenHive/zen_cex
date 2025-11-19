defmodule ZenCex.Websocket.ConnectionRegistry do
  @moduledoc """
  Registry for tracking active WebSocket connections.

  Maintains a central registry of WebSocket client connections, enabling
  connection reuse and health monitoring. Uses ETS for fast lookups with
  GenServer ownership for crash recovery.

  ## Architecture

  The registry stores zen_websocket Client structs indexed by `{exchange, symbol}`.
  Since the Client GenServer maintains stable PIDs through reconnections,
  we can reliably track connections even as the underlying Gun connection changes.

  ## Usage

      # Register a new connection
      {:ok, _} = ConnectionRegistry.register(:binance, "BTCUSDT", client)

      # Get an existing connection
      {:ok, client} = ConnectionRegistry.get(:binance, "BTCUSDT")

      # Check connection health
      {:ok, health} = ConnectionRegistry.check_health(:binance, "BTCUSDT")

  """

  use GenServer

  require Logger

  @table_name :zen_cex_ws_connections
  # Clean up stale connections every minute
  @cleanup_interval_ms 60_000

  # Client API

  @doc """
  Starts the connection registry.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a WebSocket connection for an exchange and symbol.
  """
  @spec register(atom(), String.t(), ZenWebsocket.Client.t()) :: :ok | {:error, term()}
  def register(exchange, symbol, client) when is_atom(exchange) and is_binary(symbol) do
    GenServer.call(__MODULE__, {:register, exchange, symbol, client})
  end

  @doc """
  Unregisters a WebSocket connection.
  """
  @spec unregister(atom(), String.t()) :: :ok
  def unregister(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    GenServer.call(__MODULE__, {:unregister, exchange, symbol})
  end

  @doc """
  Gets a registered WebSocket connection.
  """
  @spec get(atom(), String.t()) :: {:ok, ZenWebsocket.Client.t()} | {:error, :not_found}
  def get(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    case :ets.lookup(@table_name, {exchange, symbol}) do
      [{_key, entry}] -> {:ok, entry.client}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Lists all registered connections with their metadata.
  """
  @spec list_all() :: list(map())
  def list_all do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {{exchange, symbol}, entry} ->
      %{
        exchange: exchange,
        symbol: symbol,
        client: entry.client,
        streams: entry.streams,
        registered_at: entry.registered_at,
        last_health_check: entry.last_health_check
      }
    end)
  end

  @doc """
  Checks the health of a registered connection.

  Returns health information including connection state, heartbeat status,
  and connection metrics.
  """
  @spec check_health(atom(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def check_health(exchange, symbol) when is_atom(exchange) and is_binary(symbol) do
    with {:ok, client} <- get(exchange, symbol) do
      health = %{
        state: ZenWebsocket.Client.get_state(client),
        heartbeat: ZenWebsocket.Client.get_heartbeat_health(client),
        metrics: ZenWebsocket.Client.get_state_metrics(client),
        checked_at: System.system_time(:millisecond)
      }

      # Update last health check timestamp
      GenServer.cast(__MODULE__, {:update_health_check, exchange, symbol})

      # Emit telemetry event
      :telemetry.execute(
        [:zen_cex, :websocket, :health_check],
        %{duration: 0},
        %{exchange: exchange, symbol: symbol, state: health.state}
      )

      {:ok, health}
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for storing connections
    table =
      :ets.new(@table_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_stale, @cleanup_interval_ms)

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, exchange, symbol, client}, _from, state) do
    key = {exchange, symbol}

    # Extract streams from the client if available
    streams = extract_streams(client)

    entry = %{
      client: client,
      streams: streams,
      registered_at: System.system_time(:millisecond),
      last_health_check: nil
    }

    :ets.insert(@table_name, {key, entry})

    # Emit telemetry event
    :telemetry.execute(
      [:zen_cex, :websocket, :connection, :start],
      %{count: 1},
      %{exchange: exchange, symbol: symbol}
    )

    Logger.debug("Registered WebSocket connection for #{exchange}:#{symbol}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unregister, exchange, symbol}, _from, state) do
    key = {exchange, symbol}
    :ets.delete(@table_name, key)

    # Emit telemetry event
    :telemetry.execute(
      [:zen_cex, :websocket, :connection, :stop],
      %{count: 1},
      %{exchange: exchange, symbol: symbol}
    )

    Logger.debug("Unregistered WebSocket connection for #{exchange}:#{symbol}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:update_health_check, exchange, symbol}, state) do
    key = {exchange, symbol}

    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        updated_entry = %{entry | last_health_check: System.system_time(:millisecond)}
        :ets.insert(@table_name, {key, updated_entry})

      [] ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_stale, state) do
    # Remove connections that are no longer alive
    stale_count = cleanup_stale_connections()

    if stale_count > 0 do
      Logger.info("Cleaned up #{stale_count} stale WebSocket connections")
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_stale, @cleanup_interval_ms)

    {:noreply, state}
  end

  # Private Functions

  @spec extract_streams(ZenWebsocket.Client.t()) :: list(String.t())
  defp extract_streams(_client) do
    # TODO: Extract streams from client metadata if available
    # For now, return empty list as streams are managed internally
    []
  end

  @spec cleanup_stale_connections() :: non_neg_integer()
  defp cleanup_stale_connections do
    all_connections = :ets.tab2list(@table_name)

    stale_connections =
      Enum.filter(all_connections, fn {{_exchange, _symbol}, entry} ->
        client = entry.client

        # Check if the GenServer is still alive
        # The server_pid is stable through reconnections
        case client.server_pid do
          pid when is_pid(pid) -> not Process.alive?(pid)
          _ -> true
        end
      end)

    Enum.each(stale_connections, fn {{exchange, symbol}, _entry} ->
      :ets.delete(@table_name, {exchange, symbol})

      # Emit telemetry for cleanup
      :telemetry.execute(
        [:zen_cex, :websocket, :connection, :stop],
        %{count: 1, reason: :stale},
        %{exchange: exchange, symbol: symbol}
      )
    end)

    length(stale_connections)
  end
end
