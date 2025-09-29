defmodule ZenCex.Adapters.Bybit.WebSocket do
  @moduledoc """
  Minimal Bybit WebSocket adapter using zen_websocket directly.

  Provides a thin layer over zen_websocket for Bybit-specific WebSocket handling.
  Data is automatically stored in ETS cache for fast access by other modules.

  ## Connection Management Architecture

  This module operates as part of a three-layer architecture:

  1. **Transport Layer (zen_websocket)**:
     - Maintains Gun connection ownership through the Client GenServer
     - Handles automatic reconnection with exponential backoff
     - Returns stable client structs that survive reconnections
     - The `server_pid` in the client struct remains constant through reconnects

  2. **Adapter Layer (this module)**:
     - Provides exchange-specific protocol handling
     - Creates new connections when called directly (by design)
     - Does NOT manage connection reuse - that's an application concern
     - Handles Bybit-specific ping/pong requirements and topic formats

  3. **Application Layer (ConnectionRegistry + MarketData)**:
     - `ConnectionRegistry` tracks all active connections by `{exchange, symbol}`
     - `MarketData.ensure_websocket_connection/2` checks registry before creating
     - Implements actual connection reuse logic with application context
     - Manages connection lifecycle based on trading needs

  ## Why Connection Reuse is NOT at the Adapter Level

  The adapter intentionally creates new connections because:
  - It lacks context about which symbols are being traded together
  - Connection grouping decisions require application-level knowledge
  - The registry provides centralized connection tracking
  - Different use cases may want different connection strategies

  ## Architecture

  ## Supported Topics

  - Order book: `orderbook.{depth}.{symbol}` (e.g., "orderbook.50.BTCUSDT")
  - Public trades: `publicTrade.{symbol}`
  - Tickers: `tickers.{symbol}`
  - Book ticker: `bookticker.{symbol}`
  - Liquidations: `liquidation.{symbol}`

  ## Connection Modes

  ### Development Mode (Direct Connection)

  The Client GenServer runs unsupervised. If it crashes, the connection is lost.

      # Connect to testnet for development
      {:ok, client} = Bybit.WebSocket.connect(["orderbook.50.BTCUSDT"], testnet: true)

      # The client struct contains:
      # - server_pid: The Client GenServer that owns the Gun connection
      # - gun_pid: The Gun process itself
      # - stream_ref: The WebSocket stream reference

      # Subscribe to additional topics
      {:ok, :subscribed} = Bybit.WebSocket.subscribe(client, ["publicTrade.ETHUSDT"])

      # Close when done
      :ok = Bybit.WebSocket.close(client)

  ### Production Mode (Supervised Connection)

  The Client GenServer runs under ClientSupervisor and will be restarted on crashes.
  The supervisor must be started in your application supervision tree.

      # In your application.ex
      children = [
        ZenWebsocket.ClientSupervisor,
        # ... other children
      ]

      # In your code - returns the same client struct, but the GenServer is supervised
      {:ok, client} = Bybit.WebSocket.connect(
        ["orderbook.50.BTCUSDT", "tickers.BTCUSDT"],
        supervised: true
      )

  ## Data Access Pattern

  All market data is automatically cached in ETS by the message handler:

      # The WebSocket handler stores data in ETS
      # Your application code reads from ETS cache
      {:ok, orderbook} = ZenCex.Cache.Market.get_orderbook(:bybit, "BTCUSDT")

  ## Error Handling

  - **Connection failures**: zen_websocket handles retry with exponential backoff
  - **Message size limits**: Messages over 1MB are dropped to prevent memory exhaustion
  - **Gun ownership**: The Client GenServer maintains Gun ownership through reconnections
  - **Supervisor restarts**: In supervised mode, crashes trigger automatic restarts

  ## Implementation Notes

  The adapter creates a message handler function that processes Bybit messages and
  stores them in ETS. This handler runs in the Client GenServer process, maintaining
  proper Gun message ownership.
  """

  alias ZenCex.Cache.Market
  alias ZenWebsocket.Client

  require Logger

  # WebSocket endpoints
  @public_ws_url "wss://stream.bybit.com/v5/public/spot"
  @public_ws_testnet_url "wss://stream-testnet.bybit.com/v5/public/spot"
  @futures_ws_url "wss://stream.bybit.com/v5/public/linear"
  @futures_ws_testnet_url "wss://stream-testnet.bybit.com/v5/public/linear"

  # Bybit requires ping every 20 seconds to keep connection alive
  @ping_interval_ms 20_000

  # Maximum message size to prevent memory exhaustion (1MB)
  @max_message_size 1_048_576

  # Public API (5 functions max per zen_websocket guidelines)

  @doc """
  Creates a new WebSocket connection for the given topics.

  This is a convenience function that delegates to `connect/2`. It always creates
  a new connection by design.

  ## Architecture Note

  Connection reuse is handled at the application layer, not the adapter layer:

  - **Application Layer** (`ZenCex.Safety.OrderSafety.MarketData`): Checks the
    ConnectionRegistry for existing connections before creating new ones
  - **Registry Layer** (`ZenCex.Websocket.ConnectionRegistry`): Tracks all active
    connections by `{exchange, symbol}` for reuse
  - **Adapter Layer** (this module): Always creates new connections when called directly
  - **Transport Layer** (`zen_websocket`): Maintains connection stability through
    automatic reconnection with exponential backoff

  This separation ensures that connection management decisions are made at the
  appropriate level with full context about application needs.

  ## Parameters
    * `topics` - List of topics to subscribe to
    * `opts` - Connection options

  ## Returns
    * `{:ok, client}` - The newly created WebSocket client
    * `{:error, reason}` - Error details
  """
  @spec ensure_connection(list(String.t()), keyword()) :: {:ok, Client.t()} | {:error, term()}
  def ensure_connection(topics, opts \\ []) do
    # Always creates a new connection - connection reuse happens at the application layer
    # via ConnectionRegistry and MarketData.ensure_websocket_connection/2
    connect(topics, opts)
  end

  @doc """
  Checks the health of a WebSocket connection.

  Returns comprehensive health information including connection state,
  heartbeat status, and performance metrics.

  ## Returns
  A map containing:
    * `:state` - Connection state (:connected, :connecting, :disconnected)
    * `:heartbeat` - Heartbeat health information
    * `:metrics` - Connection performance metrics
  """
  @spec check_health(Client.t()) :: map()
  def check_health(connection) do
    %{
      state: Client.get_state(connection),
      heartbeat: Client.get_heartbeat_health(connection),
      metrics: Client.get_state_metrics(connection),
      adapter: :bybit
    }
  end

  @doc """
  Connects to Bybit WebSocket and optionally subscribes to topics.

  ## Parameters
    * `topics` - List of topics to subscribe to initially
    * `opts` - Connection options

  ## Options
    * `:testnet` - Use testnet endpoints (default: false)
    * `:market` - Market type :spot, :linear, :futures (default: :spot)
    * `:supervised` - Use ClientSupervisor for production (default: false)
  """
  @spec connect(list(String.t()), keyword()) :: {:ok, Client.t()} | {:error, term()}
  def connect(topics \\ [], opts \\ []) do
    testnet? = Keyword.get(opts, :testnet, false)
    market = normalize_market(Keyword.get(opts, :market, :spot))
    supervised? = Keyword.get(opts, :supervised, false)

    url = get_ws_url(market, testnet?)

    # Create message handler for Bybit data
    handler = create_message_handler()

    # Connection options for zen_websocket
    ws_opts = [
      handler: handler,
      retry_count: 5,
      retry_delay: 1000,
      max_backoff: 30_000,
      reconnect_on_error: true,
      heartbeat_interval: @ping_interval_ms
    ]

    # Connect using zen_websocket
    with {:ok, client} <- do_connect(url, ws_opts, supervised?),
         start_ping_timer(client),
         {:ok, _} <- subscribe(client, topics) do
      Logger.info("Connected to Bybit WebSocket: #{url}")
      {:ok, client}
    else
      {:error, reason} = error ->
        Logger.error("Failed to connect to Bybit WebSocket: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Subscribes to additional topics on existing connection.
  """
  @spec subscribe(Client.t(), list(String.t())) :: {:ok, :subscribed} | {:error, term()}
  def subscribe(connection, topics) when is_list(topics) do
    if topics == [] do
      {:ok, :subscribed}
    else
      sub_message = %{
        op: "subscribe",
        args: topics
      }

      case Client.send_message(connection, Jason.encode!(sub_message)) do
        {:ok, %{"success" => true}} ->
          Logger.debug("Subscribed to Bybit topics: #{inspect(topics)}")
          {:ok, :subscribed}

        :ok ->
          Logger.debug("Subscribed to Bybit topics: #{inspect(topics)}")
          {:ok, :subscribed}

        {:error, reason} = error ->
          Logger.error("Failed to subscribe to topics: #{inspect(reason)}")
          error

        other ->
          Logger.error("Unexpected subscription response: #{inspect(other)}")
          {:error, {:unexpected_response, other}}
      end
    end
  end

  @doc """
  Unsubscribes from topics.
  """
  @spec unsubscribe(Client.t(), list(String.t())) :: {:ok, :unsubscribed} | {:error, term()}
  def unsubscribe(connection, topics) when is_list(topics) do
    if topics == [] do
      {:ok, :unsubscribed}
    else
      unsub_message = %{
        op: "unsubscribe",
        args: topics
      }

      case Client.send_message(connection, Jason.encode!(unsub_message)) do
        {:ok, %{"success" => true}} ->
          Logger.debug("Unsubscribed from topics: #{inspect(topics)}")
          {:ok, :unsubscribed}

        :ok ->
          Logger.debug("Unsubscribed from topics: #{inspect(topics)}")
          {:ok, :unsubscribed}

        {:error, reason} = error ->
          Logger.error("Failed to unsubscribe from topics: #{inspect(reason)}")
          error

        other ->
          Logger.error("Unexpected unsubscribe response: #{inspect(other)}")
          {:error, {:unexpected_response, other}}
      end
    end
  end

  @doc """
  Closes the WebSocket connection.
  """
  @spec close(Client.t()) :: :ok
  def close(connection) do
    Client.close(connection)
  end

  @doc """
  Gets connection state.
  """
  @spec get_state(Client.t()) :: {:ok, %{status: :connected | :connecting | :disconnected}}
  def get_state(connection) do
    state = Client.get_state(connection)
    {:ok, %{status: state}}
  end

  # Private functions

  @spec normalize_market(atom()) :: atom()
  defp normalize_market(:futures), do: :linear
  defp normalize_market(market), do: market

  @spec get_ws_url(atom(), boolean()) :: String.t()
  defp get_ws_url(:spot, true), do: @public_ws_testnet_url
  defp get_ws_url(:spot, false), do: @public_ws_url
  defp get_ws_url(:linear, true), do: @futures_ws_testnet_url
  defp get_ws_url(:linear, false), do: @futures_ws_url

  @spec do_connect(String.t(), keyword(), boolean()) :: {:ok, Client.t()} | {:error, term()}
  defp do_connect(url, opts, false) do
    # Direct connection for development
    Client.connect(url, opts)
  end

  defp do_connect(url, opts, true) do
    # Supervised connection for production
    # ClientSupervisor must be started in application supervisor
    ZenWebsocket.ClientSupervisor.start_client(url, opts)
  end

  @spec start_ping_timer(Client.t()) :: :ok
  defp start_ping_timer(client) do
    # Schedule periodic ping messages
    Process.send_after(self(), {:send_ping, client}, @ping_interval_ms)
    :ok
  end

  @spec create_message_handler() :: (term() -> :ok)
  defp create_message_handler do
    fn
      {:message, {:text, data}} when is_binary(data) ->
        handle_message(data)

      {:message, {:binary, data}} when is_binary(data) ->
        handle_message(data)

      {:message, data} when is_binary(data) ->
        handle_message(data)

      {:message, %{} = decoded} ->
        process_message(decoded)

      _other ->
        :ok
    end
  end

  @spec handle_message(binary()) :: :ok
  defp handle_message(message) when is_binary(message) and byte_size(message) <= @max_message_size do
    case Jason.decode(message) do
      {:ok, data} ->
        process_message(data)

      {:error, reason} ->
        Logger.error("Failed to decode Bybit message: #{inspect(reason)}")
    end
  end

  defp handle_message(message) when is_binary(message) do
    Logger.warning("Bybit WebSocket message exceeded size limit: #{byte_size(message)} bytes (max: #{@max_message_size})")
    :ok
  end

  @spec process_message(map()) :: :ok
  defp process_message(%{"topic" => topic, "data" => data}) do
    case parse_topic(topic) do
      {:orderbook, _depth, symbol} ->
        process_orderbook(symbol, data)

      {:trade, symbol} ->
        process_trades(symbol, data)

      {:ticker, symbol} ->
        process_ticker(symbol, data)

      {:bookticker, symbol} ->
        process_book_ticker(symbol, data)

      {:liquidation, symbol} ->
        process_liquidation(symbol, data)

      {:unknown, _} ->
        Logger.debug("Unknown Bybit topic: #{topic}")
    end
  end

  defp process_message(%{"success" => true, "op" => op}) do
    Logger.debug("Bybit operation successful: #{op}")
  end

  defp process_message(%{"success" => false, "ret_msg" => msg}) do
    Logger.error("Bybit operation failed: #{msg}")
  end

  defp process_message(%{"op" => "pong"}) do
    Logger.debug("Received pong from Bybit")
  end

  defp process_message(msg) do
    Logger.debug("Unhandled Bybit message: #{inspect(msg)}")
  end

  @spec parse_topic(String.t()) ::
          {:orderbook, integer(), String.t()}
          | {:trade, String.t()}
          | {:ticker, String.t()}
          | {:bookticker, String.t()}
          | {:liquidation, String.t()}
          | {:unknown, String.t()}
  defp parse_topic(topic) do
    case String.split(topic, ".") do
      ["orderbook", depth, symbol] ->
        {:orderbook, String.to_integer(depth), symbol}

      ["publicTrade", symbol] ->
        {:trade, symbol}

      ["tickers", symbol] ->
        {:ticker, symbol}

      ["bookticker", symbol] ->
        {:bookticker, symbol}

      ["liquidation", symbol] ->
        {:liquidation, symbol}

      _ ->
        {:unknown, topic}
    end
  end

  @spec process_orderbook(String.t(), map()) :: :ok
  defp process_orderbook(symbol, data) do
    orderbook = %{
      symbol: symbol,
      update_id: data["u"],
      sequence: data["seq"],
      bids: parse_orderbook_levels(data["b"]),
      asks: parse_orderbook_levels(data["a"]),
      timestamp: :os.system_time(:millisecond)
    }

    Market.put_orderbook(:bybit, symbol, orderbook)
  end

  @spec process_trades(String.t(), list(map())) :: :ok
  defp process_trades(symbol, trades) when is_list(trades) do
    # Process multiple trades, keep only the last one
    Enum.each(trades, fn trade_data ->
      trade = %{
        symbol: symbol,
        trade_id: trade_data["i"],
        price: trade_data["p"],
        quantity: trade_data["v"],
        side: trade_data["S"],
        time: trade_data["T"],
        is_block_trade: trade_data["BT"] || false,
        timestamp: :os.system_time(:millisecond)
      }

      Market.put_last_trade(:bybit, symbol, trade)
    end)
  end

  @spec process_ticker(String.t(), map()) :: :ok
  defp process_ticker(symbol, data) do
    ticker = %{
      symbol: symbol,
      last_price: data["lastPrice"],
      high_24h: data["highPrice24h"],
      low_24h: data["lowPrice24h"],
      prev_price_24h: data["prevPrice24h"],
      volume_24h: data["volume24h"],
      turnover_24h: data["turnover24h"],
      price_24h_pcnt: data["price24hPcnt"],
      bid_price: data["bid1Price"],
      bid_size: data["bid1Size"],
      ask_price: data["ask1Price"],
      ask_size: data["ask1Size"],
      timestamp: :os.system_time(:millisecond)
    }

    Market.put_ticker(:bybit, symbol, ticker)
  end

  @spec process_book_ticker(String.t(), map()) :: :ok
  defp process_book_ticker(symbol, data) do
    book_ticker = %{
      symbol: symbol,
      bid_price: data["bp"],
      bid_qty: data["bq"],
      ask_price: data["ap"],
      ask_qty: data["aq"],
      timestamp: :os.system_time(:millisecond)
    }

    Market.put_book_ticker(:bybit, symbol, book_ticker)
  end

  @spec process_liquidation(String.t(), map()) :: :ok
  defp process_liquidation(symbol, data) do
    Logger.info("Liquidation on #{symbol}: #{data["size"]} @ #{data["price"]} (#{data["side"]})")
  end

  @spec parse_orderbook_levels(list()) :: list(map())
  defp parse_orderbook_levels(levels) do
    Enum.map(levels, fn [price, quantity] ->
      %{price: price, quantity: quantity}
    end)
  end
end
