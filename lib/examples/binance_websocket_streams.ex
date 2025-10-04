defmodule ZenCex.Examples.BinanceWebsocketStreams do
  @moduledoc """
  Example module demonstrating WebSocket streaming functionality with Binance.

  This module shows how to:
  - Connect to single or multiple WebSocket streams
  - Subscribe to additional streams on an existing connection
  - Access cached market data from WebSocket streams
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

  ## Usage

      alias ZenCex.Examples.BinanceWebsocketStreams

      # Connect to a single stream
      {:ok, client} = BinanceWebsocketStreams.connect_single_stream("btcusdt@ticker")

      # Wait for data to arrive, then access cached data
      Process.sleep(2000)
      {:ok, ticker} = BinanceWebsocketStreams.get_cached_ticker_data("BTCUSDT")

      # Close when done
      :ok = BinanceWebsocketStreams.close_connection(client)
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
end
