defmodule ZenCex.Examples.BinanceWebsocketStreams do
  @moduledoc """
  Example module demonstrating WebSocket streaming functionality with Binance.

  This module shows how to:
  - Connect to single or multiple WebSocket streams
  - Subscribe to additional streams on an existing connection
  - Access cached market data from WebSocket streams
  - Monitor connection health and handle errors
  - Use production-ready patterns (retry, reconnection, supervision)
  - Close WebSocket connections properly

  ## Prerequisites

  WebSocket connections don't require API credentials for public streams.
  The connection will automatically cache market data in ETS for fast access.

  ## Stream Types

  - Order book: `{symbol}@depth{levels}` (e.g., "btcusdt@depth20")
  - Trades: `{symbol}@trade`
  - Ticker: `{symbol}@ticker`
  - Mini ticker: `{symbol}@miniTicker`
  - Book ticker: `{symbol}@bookTicker`

  ## Basic Usage

      alias ZenCex.Examples.BinanceWebsocketStreams

      # Simple connection
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Wait for data to arrive, then access cached data
      Process.sleep(2000)
      {:ok, ticker} = BinanceWebsocketStreams.get_cached_ticker_data("BTCUSDT")

      # Close when done
      :ok = BinanceWebsocketStreams.close_connection(client)

  ## Production Usage

      # Connect with automatic retry and exponential backoff
      {:ok, client} = BinanceWebsocketStreams.connect_with_retry(
        ["btcusdt@ticker"],
        retry_count: 5,
        max_backoff: 30_000
      )

      # Monitor connection health
      health = BinanceWebsocketStreams.check_connection_health(client)

      # The client struct remains valid through automatic reconnections
      # zen_websocket's Client GenServer maintains Gun ownership

  ## Key Architecture: Gun Ownership & Reconnection

  zen_websocket's Client GenServer owns the Gun connection. On network errors:
  1. The SAME GenServer process reconnects (not a new process)
  2. Gun messages continue routing to the correct GenServer
  3. Your client struct remains valid throughout
  4. No need to track new client structs or handle message routing failures

  This is superior to external reconnection because Gun ownership never
  transfers to the wrong process, ensuring message routing continuity.
  """

  alias ZenCex.Adapters.Binance.WebSocket, as: BinanceWS
  alias ZenCex.Cache.Market

  @doc """
  Connects to a single Binance WebSocket stream.

  ## Parameters
    * `stream` - Stream name (e.g., "btcusdt@ticker")

  ## Options
    * `:testnet` - Use testnet endpoint (default: false)
    * `:market` - Market type :spot or :futures (default: :spot)

  ## Examples

      # Connect to BTC ticker stream
      {:ok, client} = connect_single_stream("btcusdt@ticker")

      # Connect to ETH trade stream on testnet
      {:ok, client} = connect_single_stream("ethusdt@trade", testnet: true)

      # Connect to futures orderbook
      {:ok, client} = connect_single_stream("btcusdt@depth20", market: :futures)
  """
  @spec connect_single_stream(String.t(), keyword()) ::
          {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def connect_single_stream(stream, opts \\ []) when is_binary(stream) do
    BinanceWS.connect([stream], opts)
  end

  @doc """
  Connects to multiple Binance WebSocket streams at once.

  Multiple streams can be combined in a single connection for efficiency.

  ## Parameters
    * `streams` - List of stream names

  ## Options
    * `:testnet` - Use testnet endpoint (default: false)
    * `:market` - Market type :spot or :futures (default: :spot)

  ## Examples

      # Connect to multiple streams
      streams = ["btcusdt@ticker", "ethusdt@ticker", "bnbusdt@trade"]
      {:ok, client} = connect_multiple_streams(streams)

      # Connect to multiple futures streams
      streams = ["btcusdt@depth20", "ethusdt@depth20"]
      {:ok, client} = connect_multiple_streams(streams, market: :futures)
  """
  @spec connect_multiple_streams(list(String.t()), keyword()) ::
          {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def connect_multiple_streams(streams, opts \\ []) when is_list(streams) do
    BinanceWS.connect(streams, opts)
  end

  @doc """
  Subscribes to additional streams on an existing connection.

  This allows you to dynamically add streams without creating a new connection.

  ## Parameters
    * `client` - Existing WebSocket client
    * `new_streams` - List of additional streams to subscribe to

  ## Examples

      {:ok, client} = connect_single_stream("btcusdt@ticker")

      # Subscribe to additional streams
      {:ok, :subscribed} = subscribe_additional(client, ["ethusdt@ticker", "bnbusdt@trade"])
  """
  @spec subscribe_additional(ZenWebsocket.Client.t(), list(String.t())) ::
          {:ok, :subscribed} | {:error, term()}
  def subscribe_additional(client, new_streams) when is_list(new_streams) do
    BinanceWS.subscribe(client, new_streams)
  end

  @doc """
  Gets cached ticker data for a symbol.

  Data is automatically cached by the WebSocket message handler.
  Returns the most recently received ticker data from the stream.

  ## Parameters
    * `symbol` - Trading symbol (uppercase, e.g., "BTCUSDT")

  ## Examples

      # Start streaming ticker data
      {:ok, client} = connect_single_stream("btcusdt@ticker")

      # Wait for data to arrive
      Process.sleep(2000)

      # Access cached data
      {:ok, ticker} = get_cached_ticker_data("BTCUSDT")

      # ticker will contain: %{
      #   symbol: "BTCUSDT",
      #   last_price: "45000.00",
      #   open_price: "44500.00",
      #   high_price: "45200.00",
      #   low_price: "44300.00",
      #   volume: "1234.56",
      #   ...
      # }
  """
  @spec get_cached_ticker_data(String.t()) :: {:ok, map()} | {:error, :not_found | :expired}
  def get_cached_ticker_data(symbol) when is_binary(symbol) do
    Market.get_ticker(:binance, symbol)
  end

  @doc """
  Gets cached orderbook data for a symbol.

  Data is automatically cached from depth streams (e.g., "btcusdt@depth20").

  ## Parameters
    * `symbol` - Trading symbol (uppercase, e.g., "BTCUSDT")

  ## Examples

      # Start streaming orderbook data
      {:ok, client} = connect_single_stream("btcusdt@depth20")

      # Wait for data to arrive
      Process.sleep(2000)

      # Access cached orderbook
      {:ok, orderbook} = get_cached_orderbook_data("BTCUSDT")

      # orderbook will contain: %{
      #   symbol: "BTCUSDT",
      #   bids: [%{price: "44999.00", quantity: "1.5"}, ...],
      #   asks: [%{price: "45001.00", quantity: "2.0"}, ...],
      #   ...
      # }
  """
  @spec get_cached_orderbook_data(String.t()) :: {:ok, map()} | {:error, :not_found | :expired}
  def get_cached_orderbook_data(symbol) when is_binary(symbol) do
    Market.get_orderbook(:binance, symbol)
  end

  @doc """
  Gets cached trade data for a symbol.

  Returns the most recent trade from the trade stream (e.g., "btcusdt@trade").

  ## Parameters
    * `symbol` - Trading symbol (uppercase, e.g., "BTCUSDT")

  ## Examples

      # Start streaming trade data
      {:ok, client} = connect_single_stream("btcusdt@trade")

      # Wait for data to arrive
      Process.sleep(2000)

      # Access last trade
      {:ok, trade} = get_cached_trade_data("BTCUSDT")

      # trade will contain: %{
      #   symbol: "BTCUSDT",
      #   price: "45000.00",
      #   quantity: "0.5",
      #   time: 1234567890,
      #   is_buyer_maker: false,
      #   ...
      # }
  """
  @spec get_cached_trade_data(String.t()) :: {:ok, map()} | {:error, :not_found | :expired}
  def get_cached_trade_data(symbol) when is_binary(symbol) do
    Market.get_last_trade(:binance, symbol)
  end

  @doc """
  Gets cached book ticker data (best bid/ask) for a symbol.

  Book ticker provides the best bid and ask prices with quantities.

  ## Parameters
    * `symbol` - Trading symbol (uppercase, e.g., "BTCUSDT")

  ## Examples

      # Start streaming book ticker
      {:ok, client} = connect_single_stream("btcusdt@bookTicker")

      # Wait for data to arrive
      Process.sleep(2000)

      # Access book ticker
      {:ok, book_ticker} = get_cached_book_ticker_data("BTCUSDT")

      # book_ticker will contain: %{
      #   symbol: "BTCUSDT",
      #   bid_price: "44999.00",
      #   bid_qty: "1.5",
      #   ask_price: "45001.00",
      #   ask_qty: "2.0",
      #   ...
      # }
  """
  @spec get_cached_book_ticker_data(String.t()) :: {:ok, map()} | {:error, :not_found | :expired}
  def get_cached_book_ticker_data(symbol) when is_binary(symbol) do
    Market.get_book_ticker(:binance, symbol)
  end

  @doc """
  Closes a WebSocket connection.

  This properly shuts down the connection and cleans up resources.

  ## Parameters
    * `client` - WebSocket client to close

  ## Examples

      {:ok, client} = connect_single_stream("btcusdt@ticker")

      # When done streaming
      :ok = close_connection(client)
  """
  @spec close_connection(ZenWebsocket.Client.t()) :: :ok
  def close_connection(client) do
    BinanceWS.close(client)
  end

  @doc """
  Gets the current state of a WebSocket connection.

  ## Parameters
    * `client` - WebSocket client

  ## Returns
    * `{:ok, :connected}` - Connection is active
    * `{:ok, :connecting}` - Connection is being established
    * `{:ok, :disconnected}` - Connection is closed

  ## Examples

      {:ok, client} = connect_single_stream("btcusdt@ticker")
      {:ok, :connected} = get_connection_state(client)
  """
  @spec get_connection_state(ZenWebsocket.Client.t()) ::
          {:ok, :connected | :connecting | :disconnected}
  def get_connection_state(client) do
    BinanceWS.get_state(client)
  end

  @doc """
  Connects with production-ready configuration including automatic reconnection.

  This demonstrates connecting with retry logic and exponential backoff.
  The zen_websocket Client GenServer maintains Gun ownership through reconnections,
  so the same client struct continues to work even after reconnections.

  ## Parameters
    * `streams` - List of streams to subscribe to
    * `opts` - Additional options (merged with production defaults)

  ## Options
    * `:retry_count` - Number of reconnection attempts (default: 5)
    * `:retry_delay` - Initial retry delay in ms (default: 1000)
    * `:max_backoff` - Maximum backoff delay in ms (default: 30_000)
    * `:reconnect_on_error` - Enable automatic reconnection (default: true)

  ## Examples

      # Production connection with automatic retry
      {:ok, client} = connect_with_retry(["btcusdt@ticker"])

      # Custom retry configuration
      {:ok, client} = connect_with_retry(
        ["btcusdt@ticker"],
        retry_count: 10,
        max_backoff: 60_000
      )
  """
  @spec connect_with_retry(list(String.t()), keyword()) ::
          {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def connect_with_retry(streams, opts \\ []) do
    # Production-ready defaults
    production_opts =
      Keyword.merge(
        [
          retry_count: 5,
          retry_delay: 1000,
          max_backoff: 30_000,
          reconnect_on_error: true
        ],
        opts
      )

    BinanceWS.connect(streams, production_opts)
  end

  @doc """
  Connects with supervision for production deployments.

  In supervised mode, the Client GenServer runs under ClientSupervisor
  and will be restarted on crashes. The supervisor must be started
  in your application supervision tree.

  ## Key Architecture Points

  - **Gun Ownership**: The Client GenServer owns the Gun connection
  - **Reconnection**: On network errors, the SAME GenServer reconnects
  - **Supervision**: On GenServer crashes, supervisor restarts it
  - **Message Routing**: Gun always sends messages to the GenServer owner

  This ensures robust production operation with automatic recovery.

  ## Parameters
    * `streams` - List of streams to subscribe to
    * `opts` - Additional options

  ## Examples

      # In your application.ex
      children = [
        ZenWebsocket.ClientSupervisor,
        # ... other children
      ]

      # In your code - supervised connection
      {:ok, client} = connect_supervised(["btcusdt@ticker", "ethusdt@trade"])

      # The client will be automatically restarted on crashes
  """
  @spec connect_supervised(list(String.t()), keyword()) ::
          {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def connect_supervised(streams, opts \\ []) do
    supervised_opts =
      Keyword.merge(
        [
          supervised: true,
          retry_count: 5,
          max_backoff: 30_000,
          reconnect_on_error: true
        ],
        opts
      )

    BinanceWS.connect(streams, supervised_opts)
  end

  @doc """
  Gets comprehensive health information for a WebSocket connection.

  Returns detailed metrics including connection state, heartbeat status,
  and performance information.

  ## Returns
  A map containing:
    * `:state` - Connection state (:connected, :connecting, :disconnected)
    * `:heartbeat` - Heartbeat health information (if enabled)
    * `:metrics` - Connection performance metrics
    * `:adapter` - Adapter name (:binance)

  ## Examples

      {:ok, client} = connect_single_stream("btcusdt@ticker")

      # Get health information
      health = check_connection_health(client)

      # Example health map:
      # %{
      #   state: {:ok, :connected},
      #   heartbeat: %{
      #     last_heartbeat_at: 1234567890,
      #     heartbeat_failures: 0,
      #     active_heartbeats: MapSet.new()
      #   },
      #   metrics: %{
      #     subscriptions_count: 1,
      #     pending_requests_count: 0,
      #     memory_bytes: 12345
      #   },
      #   adapter: :binance
      # }
  """
  @spec check_connection_health(ZenWebsocket.Client.t()) :: map()
  def check_connection_health(client) do
    BinanceWS.check_health(client)
  end

  @doc """
  Manually triggers a reconnection for the WebSocket client.

  This closes the current connection and establishes a new one.
  Useful for handling degraded connections or forcing a fresh start.

  Note: With automatic reconnection enabled, this is rarely needed
  as zen_websocket handles reconnection automatically.

  ## Parameters
    * `client` - WebSocket client to reconnect

  ## Examples

      {:ok, client} = connect_single_stream("btcusdt@ticker")

      # Force reconnection if needed
      {:ok, new_client} = reconnect_connection(client)
  """
  @spec reconnect_connection(ZenWebsocket.Client.t()) ::
          {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def reconnect_connection(client) do
    BinanceWS.reconnect(client)
  end

  @doc """
  Complete example showing the full WebSocket workflow.

  This function demonstrates:
  1. Connecting to streams
  2. Waiting for data
  3. Accessing cached data
  4. Subscribing to additional streams
  5. Closing the connection

  ## Examples

      # Run the complete example
      run_complete_example()
  """
  @spec run_complete_example() :: :ok
  def run_complete_example do
    IO.puts("=== Binance WebSocket Streaming Example ===\n")

    # Step 1: Connect to initial streams
    IO.puts("Step 1: Connecting to BTC ticker and ETH trade streams...")

    {:ok, client} =
      connect_multiple_streams([
        "btcusdt@ticker",
        "ethusdt@trade"
      ])

    IO.puts("✓ Connected successfully\n")

    # Step 2: Wait for data to arrive
    IO.puts("Step 2: Waiting for data to arrive (3 seconds)...")
    Process.sleep(3000)
    IO.puts("✓ Data received\n")

    # Step 3: Access cached ticker data
    IO.puts("Step 3: Accessing cached BTC ticker data...")

    case get_cached_ticker_data("BTCUSDT") do
      {:ok, ticker} ->
        IO.puts("✓ BTC Ticker:")
        IO.puts("  Last Price: #{ticker.last_price}")
        IO.puts("  24h Volume: #{ticker.volume}\n")

      {:error, reason} ->
        IO.puts("✗ Failed to get ticker: #{inspect(reason)}\n")
    end

    # Step 4: Access cached trade data
    IO.puts("Step 4: Accessing cached ETH trade data...")

    case get_cached_trade_data("ETHUSDT") do
      {:ok, trade} ->
        IO.puts("✓ Last ETH Trade:")
        IO.puts("  Price: #{trade.price}")
        IO.puts("  Quantity: #{trade.quantity}\n")

      {:error, reason} ->
        IO.puts("✗ Failed to get trade: #{inspect(reason)}\n")
    end

    # Step 5: Subscribe to additional streams
    IO.puts("Step 5: Subscribing to BNB orderbook stream...")
    {:ok, :subscribed} = subscribe_additional(client, ["bnbusdt@depth20"])
    IO.puts("✓ Subscribed successfully\n")

    # Step 6: Wait and access new data
    IO.puts("Step 6: Waiting for BNB orderbook data (3 seconds)...")
    Process.sleep(3000)

    case get_cached_orderbook_data("BNBUSDT") do
      {:ok, orderbook} ->
        IO.puts("✓ BNB Orderbook:")
        IO.puts("  Best Bid: #{List.first(orderbook.bids).price}")
        IO.puts("  Best Ask: #{List.first(orderbook.asks).price}\n")

      {:error, reason} ->
        IO.puts("✗ Failed to get orderbook: #{inspect(reason)}\n")
    end

    # Step 7: Close connection
    IO.puts("Step 7: Closing WebSocket connection...")
    :ok = close_connection(client)
    IO.puts("✓ Connection closed\n")

    IO.puts("=== Example Complete ===")
    :ok
  end

  @doc """
  Production example demonstrating resilient WebSocket connections.

  This example shows:
  1. Connection with automatic retry and exponential backoff
  2. Health monitoring
  3. Connection state tracking
  4. Graceful error handling

  ## Key Architecture Features Demonstrated

  ### Gun Ownership & Reconnection
  - Client GenServer owns the Gun connection
  - On network errors, the SAME GenServer process reconnects
  - Gun messages continue routing to the correct process
  - Your client struct remains valid through reconnections

  ### Automatic Reconnection Flow
  1. Network error occurs (gun_down, gun_error, process DOWN)
  2. Client GenServer detects error via Gun messages
  3. GenServer cleans up old Gun connection
  4. GenServer opens NEW Gun connection (same process!)
  5. Gun messages route to same GenServer
  6. Your code continues using same client struct

  This is superior to external reconnection because:
  - No need to track new client structs
  - No message routing failures during reconnection
  - Gun ownership never transfers to wrong process

  ## Examples

      # Run production example
      run_production_example()
  """
  @spec run_production_example() :: :ok
  def run_production_example do
    IO.puts("=== Production WebSocket Example ===\n")

    # Step 1: Connect with production-ready configuration
    IO.puts("Step 1: Connecting with automatic retry and backoff...")

    {:ok, client} =
      connect_with_retry(["btcusdt@ticker", "ethusdt@trade"],
        retry_count: 5,
        retry_delay: 1000,
        max_backoff: 30_000
      )

    IO.puts("✓ Connected with production configuration\n")

    # Step 2: Check initial connection health
    IO.puts("Step 2: Checking connection health...")
    health = check_connection_health(client)
    IO.puts("✓ Connection health:")
    IO.puts("  State: #{inspect(health.state)}")
    IO.puts("  Adapter: #{health.adapter}\n")

    # Step 3: Monitor connection state
    IO.puts("Step 3: Monitoring connection state...")
    {:ok, state} = get_connection_state(client)
    IO.puts("✓ Connection state: #{state}\n")

    # Step 4: Wait for data
    IO.puts("Step 4: Waiting for market data (3 seconds)...")
    Process.sleep(3000)

    # Step 5: Access cached data with error handling
    IO.puts("Step 5: Accessing cached data with error handling...")

    case get_cached_ticker_data("BTCUSDT") do
      {:ok, ticker} ->
        IO.puts("✓ BTC Ticker received:")
        IO.puts("  Price: #{ticker.last_price}")
        IO.puts("  Volume: #{ticker.volume}")

      {:error, :not_found} ->
        IO.puts("⚠ Data not yet available (cache miss)")

      {:error, :expired} ->
        IO.puts("⚠ Cached data expired")

      {:error, reason} ->
        IO.puts("✗ Error: #{inspect(reason)}")
    end

    IO.puts("")

    # Step 6: Get final health check
    IO.puts("Step 6: Final health check before closing...")
    final_health = check_connection_health(client)
    IO.puts("✓ Final state: #{inspect(final_health.state)}\n")

    # Step 7: Clean shutdown
    IO.puts("Step 7: Closing connection...")
    :ok = close_connection(client)
    IO.puts("✓ Connection closed gracefully\n")

    IO.puts("=== Production Example Complete ===")
    IO.puts("")
    IO.puts("Note: In production, the client would automatically reconnect")
    IO.puts("on network errors, maintaining the same client struct throughout.")
    IO.puts("The Client GenServer owns Gun and handles all reconnections internally.")
    :ok
  end

  @doc """
  Example showing connection monitoring and health checks.

  Demonstrates how to monitor connection health in a long-running process.

  ## Examples

      run_monitoring_example()
  """
  @spec run_monitoring_example() :: :ok
  def run_monitoring_example do
    IO.puts("=== WebSocket Monitoring Example ===\n")

    {:ok, client} = connect_with_retry(["btcusdt@ticker"])

    IO.puts("Monitoring connection for 10 seconds...")
    IO.puts("(Client GenServer maintains Gun ownership through any reconnections)\n")

    # Monitor for 10 seconds
    Enum.each(1..5, fn i ->
      Process.sleep(2000)

      health = check_connection_health(client)
      {:ok, state} = get_connection_state(client)

      IO.puts("Check #{i}/5:")
      IO.puts("  State: #{state}")
      IO.puts("  Health: #{inspect(health.state)}")
    end)

    close_connection(client)

    IO.puts("\n✓ Monitoring complete")
    IO.puts("=== Example Complete ===")
    :ok
  end
end
