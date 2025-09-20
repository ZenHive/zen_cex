defmodule ZenCex.WebSocket.Supervisor do
  @moduledoc """
  Supervisor for managing WebSocket connections across all exchanges.

  This supervisor uses a dynamic supervisor pattern to allow starting
  and stopping connections at runtime. Each connection runs under its
  own process and is automatically restarted on failure.

  ## Architecture

  - DynamicSupervisor for flexible connection management
  - Registry for named connection lookup
  - Automatic restart with exponential backoff
  - Connection pooling support per exchange

  ## Usage

      # Start a Binance WebSocket connection
      {:ok, pid} = ZenCex.WebSocket.Supervisor.start_connection(
        :binance,
        :market_data,
        symbols: ["BTCUSDT", "ETHUSDT"]
      )

      # Stop a specific connection
      ZenCex.WebSocket.Supervisor.stop_connection(:binance, :market_data)

      # List all active connections
      ZenCex.WebSocket.Supervisor.list_connections()
  """

  use DynamicSupervisor

  alias ZenCex.Config.TimeConstants

  require Logger

  @registry ZenCex.WebSocket.Registry
  @restart_delay_ms TimeConstants.websocket_timeouts().restart_delay
  @max_supervisor_restarts 10
  @max_supervisor_seconds 60

  # Client API

  @doc """
  Starts the WebSocket supervisor.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new WebSocket connection for an exchange.

  ## Options

    * `:symbols` - List of trading symbols to subscribe to
    * `:streams` - List of stream types (:orderbook, :trades, :ticker)
    * `:url` - Optional custom WebSocket URL
    * `:restart` - Restart strategy, defaults to :transient
  """
  @spec start_connection(atom(), atom(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_connection(exchange, connection_name, opts \\ []) do
    connection_id = {exchange, connection_name}

    # Check if connection already exists
    case Registry.lookup(@registry, connection_id) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          # Clean up dead process and restart
          Registry.unregister(@registry, connection_id)
          do_start_connection(exchange, connection_name, opts)
        end

      [] ->
        do_start_connection(exchange, connection_name, opts)
    end
  end

  @doc """
  Stops a WebSocket connection.
  """
  @spec stop_connection(atom(), atom()) :: :ok | {:error, :not_found}
  def stop_connection(exchange, connection_name) do
    connection_id = {exchange, connection_name}

    case Registry.lookup(@registry, connection_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active WebSocket connections.
  """
  @spec list_connections() :: [{atom(), atom(), pid()}]
  def list_connections do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Restarts a WebSocket connection.
  """
  @spec restart_connection(atom(), atom()) :: {:ok, pid()} | {:error, term()}
  def restart_connection(exchange, connection_name) do
    with :ok <- stop_connection(exchange, connection_name) do
      Process.sleep(@restart_delay_ms)
      start_connection(exchange, connection_name, [])
    end
  end

  @doc """
  Checks if a connection is active.
  """
  @spec connection_active?(atom(), atom()) :: boolean()
  def connection_active?(exchange, connection_name) do
    connection_id = {exchange, connection_name}

    case Registry.lookup(@registry, connection_id) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end

  @doc """
  Gets the PID of a connection.
  """
  @spec get_connection_pid(atom(), atom()) :: {:ok, pid()} | {:error, :not_found}
  def get_connection_pid(exchange, connection_name) do
    connection_id = {exchange, connection_name}

    case Registry.lookup(@registry, connection_id) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  # Server callbacks

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: @max_supervisor_restarts,
      max_seconds: @max_supervisor_seconds
    )
  end

  # Private functions

  defp do_start_connection(exchange, connection_name, opts) do
    adapter_module = get_adapter_module(exchange)

    child_spec = %{
      id: {exchange, connection_name, System.unique_integer()},
      start: {
        ZenCex.WebSocket.Supervisor.ConnectionWorker,
        :start_link,
        [{exchange, connection_name, adapter_module, opts}]
      },
      restart: Keyword.get(opts, :restart, :transient),
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        :telemetry.execute(
          [:zen_cex, :websocket, :connection, :started],
          %{count: 1},
          %{exchange: exchange, name: connection_name, pid: pid}
        )

        Logger.info("Started WebSocket connection: #{exchange}:#{connection_name} (#{inspect(pid)})")
        {:ok, pid}

      {:error, reason} = error ->
        :telemetry.execute(
          [:zen_cex, :websocket, :connection, :start_failed],
          %{count: 1},
          %{exchange: exchange, name: connection_name, reason: reason}
        )

        Logger.error("Failed to start WebSocket connection: #{exchange}:#{connection_name} - #{inspect(reason)}")
        error
    end
  end

  defp get_adapter_module(:binance), do: ZenCex.Adapters.Binance.WebSocket
  defp get_adapter_module(:bybit), do: ZenCex.Adapters.Bybit.WebSocket
  defp get_adapter_module(exchange), do: raise("Unsupported exchange: #{exchange}")

  # Internal connection worker module
  defmodule ConnectionWorker do
    @moduledoc false

    use GenServer

    require Logger

    @registry ZenCex.WebSocket.Registry
    @reconnect_delay_ms TimeConstants.websocket_timeouts().reconnect_delay
    @max_reconnect_attempts 10
    @max_reconnect_delay_ms TimeConstants.websocket_timeouts().max_reconnect_delay
    @jitter_percentage 0.25

    def start_link({exchange, connection_name, adapter_module, opts}) do
      GenServer.start_link(__MODULE__, {exchange, connection_name, adapter_module, opts})
    end

    @impl true
    def init({exchange, connection_name, adapter_module, opts}) do
      # Register this connection
      connection_id = {exchange, connection_name}

      Registry.register(@registry, connection_id, %{
        exchange: exchange,
        name: connection_name,
        started_at: System.system_time(:second)
      })

      # Start connection
      state = %{
        exchange: exchange,
        connection_name: connection_name,
        adapter_module: adapter_module,
        opts: opts,
        ws_pid: nil,
        ws_client: nil,
        reconnect_attempts: 0
      }

      {:ok, state, {:continue, :connect}}
    end

    @impl true
    def handle_continue(:connect, state) do
      case start_websocket(state) do
        {:ok, ws_client} ->
          # Extract the server PID from the client struct
          ws_pid = ws_client.server_pid
          # Monitor the WebSocket process
          Process.monitor(ws_pid)
          {:noreply, %{state | ws_pid: ws_pid, ws_client: ws_client, reconnect_attempts: 0}}

        {:error, reason} ->
          Logger.error("Failed to connect WebSocket for #{state.exchange}:#{state.connection_name}: #{inspect(reason)}")
          schedule_reconnect(state)
      end
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, ws_pid, reason}, %{ws_pid: ws_pid} = state) do
      :telemetry.execute(
        [:zen_cex, :websocket, :connection, :lost],
        %{count: 1},
        %{exchange: state.exchange, name: state.connection_name, reason: reason}
      )

      Logger.warning("WebSocket connection lost for #{state.exchange}:#{state.connection_name}: #{inspect(reason)}")
      schedule_reconnect(state)
    end

    @impl true
    def handle_info(:reconnect, state) do
      if state.reconnect_attempts < @max_reconnect_attempts do
        :telemetry.execute(
          [:zen_cex, :websocket, :connection, :reconnecting],
          %{attempt: state.reconnect_attempts + 1},
          %{exchange: state.exchange, name: state.connection_name}
        )

        Logger.info(
          "Attempting to reconnect #{state.exchange}:#{state.connection_name} (attempt #{state.reconnect_attempts + 1})"
        )

        case start_websocket(state) do
          {:ok, ws_client} ->
            # Extract the server PID from the client struct
            ws_pid = ws_client.server_pid
            Process.monitor(ws_pid)

            :telemetry.execute(
              [:zen_cex, :websocket, :connection, :reconnected],
              %{count: 1, attempts: state.reconnect_attempts + 1},
              %{exchange: state.exchange, name: state.connection_name}
            )

            {:noreply, %{state | ws_pid: ws_pid, ws_client: ws_client, reconnect_attempts: 0}}

          {:error, reason} ->
            :telemetry.execute(
              [:zen_cex, :websocket, :connection, :reconnect_failed],
              %{count: 1, attempt: state.reconnect_attempts + 1},
              %{exchange: state.exchange, name: state.connection_name, reason: reason}
            )

            Logger.error("Reconnection failed: #{inspect(reason)}")
            schedule_reconnect(%{state | reconnect_attempts: state.reconnect_attempts + 1})
        end
      else
        :telemetry.execute(
          [:zen_cex, :websocket, :connection, :max_reconnects_reached],
          %{count: 1},
          %{exchange: state.exchange, name: state.connection_name}
        )

        Logger.error("Max reconnection attempts reached for #{state.exchange}:#{state.connection_name}")
        {:stop, :max_reconnect_attempts, state}
      end
    end

    @impl true
    def terminate(reason, state) do
      :telemetry.execute(
        [:zen_cex, :websocket, :connection, :terminated],
        %{count: 1},
        %{exchange: state.exchange, name: state.connection_name, reason: reason}
      )

      Logger.info("Terminating WebSocket worker for #{state.exchange}:#{state.connection_name}: #{inspect(reason)}")

      if state.ws_client do
        # Clean shutdown of WebSocket connection using the client struct
        ZenWebsocket.Client.close(state.ws_client)
      end

      :ok
    end

    defp start_websocket(state) do
      symbols = Keyword.get(state.opts, :symbols, ["BTCUSDT"])
      streams = Keyword.get(state.opts, :streams, [:orderbook])

      # Start the WebSocket connection using the adapter
      case state.adapter_module.connect(state.opts) do
        {:ok, ws_client} ->
          # Subscribe to the requested streams
          stream_names = build_stream_names(state.exchange, symbols, streams)
          state.adapter_module.subscribe(ws_client, stream_names)
          {:ok, ws_client}

        error ->
          error
      end
    end

    defp build_stream_names(:binance, symbols, streams) do
      for symbol <- symbols, stream <- streams do
        symbol_lower = String.downcase(symbol)

        case stream do
          :orderbook -> "#{symbol_lower}@depth20"
          :trades -> "#{symbol_lower}@trade"
          :ticker -> "#{symbol_lower}@ticker"
          :book_ticker -> "#{symbol_lower}@bookTicker"
          _ -> "#{symbol_lower}@#{stream}"
        end
      end
    end

    defp build_stream_names(:bybit, symbols, streams) do
      for symbol <- symbols, stream <- streams do
        case stream do
          :orderbook -> "orderbook.50.#{symbol}"
          :trades -> "publicTrade.#{symbol}"
          :ticker -> "tickers.#{symbol}"
          _ -> "#{stream}.#{symbol}"
        end
      end
    end

    defp build_stream_names(_exchange, _symbols, _streams) do
      []
    end

    defp schedule_reconnect(state) do
      # Exponential backoff with jitter
      delay =
        min(
          @reconnect_delay_ms * :math.pow(2, state.reconnect_attempts),
          @max_reconnect_delay_ms
        )

      # Add jitter (±25%)
      jitter = delay * @jitter_percentage
      final_delay = trunc(delay + (:rand.uniform() * jitter * 2 - jitter))

      Process.send_after(self(), :reconnect, final_delay)

      {:noreply, %{state | ws_pid: nil, ws_client: nil, reconnect_attempts: state.reconnect_attempts + 1}}
    end
  end
end
