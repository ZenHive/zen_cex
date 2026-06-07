defmodule ZenCex.Adapters.Binance.WebSocket do
  @moduledoc """
  Minimal Binance WebSocket adapter using zen_websocket directly.

  Provides a thin layer over zen_websocket for Binance-specific WebSocket handling.
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
     - Focuses on Binance-specific stream formats and message parsing

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

  ## Supported Streams

  - Order book: `{symbol}@depth{levels}` (e.g., "btcusdt@depth20")
  - Trades: `{symbol}@trade`
  - Ticker: `{symbol}@ticker`
  - Mini ticker: `{symbol}@miniTicker`
  - Book ticker: `{symbol}@bookTicker`
  - All book tickers: `!bookTicker` (for all symbols)

  ## Connection Modes

  ### Development Mode (Direct Connection)

  The Client GenServer runs unsupervised. If it crashes, the connection is lost.

      # Connect to spot market
      {:ok, client} = Binance.WebSocket.connect(["btcusdt@depth20", "ethusdt@trade"])

      # Connect to testnet
      {:ok, client} = Binance.WebSocket.connect(["btcusdt@ticker"], testnet: true)

      # The client struct contains:
      # - server_pid: The Client GenServer that owns the Gun connection
      # - gun_pid: The Gun process itself
      # - stream_ref: The WebSocket stream reference

      # Subscribe to additional streams
      {:ok, :subscribed} = Binance.WebSocket.subscribe(client, ["bnbusdt@bookTicker"])

      # Unsubscribe from streams
      {:ok, :unsubscribed} = Binance.WebSocket.unsubscribe(client, ["ethusdt@trade"])

      # Close when done
      :ok = Binance.WebSocket.close(client)

  ### Production Mode (Supervised Connection)

  The Client GenServer runs under ClientSupervisor and will be restarted on crashes.
  The supervisor must be started in your application supervision tree.

      # In your application.ex
      children = [
        ZenWebsocket.ClientSupervisor,
        # ... other children
      ]

      # In your code - returns the same client struct, but the GenServer is supervised
      {:ok, client} = Binance.WebSocket.connect(
        ["btcusdt@depth20", "btcusdt@ticker"],
        supervised: true
      )

      # For futures market (supervised)
      {:ok, client} = Binance.WebSocket.connect(
        ["btcusdt@depth20"],
        market: :futures,
        supervised: true
      )

  ## Data Access Pattern

  All market data is automatically cached in ETS by the message handler:

      # The WebSocket handler stores normalized data in ETS
      # Your application code reads from ETS cache
      {:ok, orderbook} = ZenCex.Cache.Market.get_orderbook(:binance, "BTCUSDT")
      {:ok, ticker} = ZenCex.Cache.Market.get_ticker(:binance, "BTCUSDT")
      {:ok, trade} = ZenCex.Cache.Market.get_last_trade(:binance, "ETHUSDT")

  ## Error Handling

  - **Connection failures**: zen_websocket handles retry with exponential backoff
  - **Message size limits**: Messages over 1MB are dropped to prevent memory exhaustion
  - **Invalid messages**: Malformed JSON is logged and ignored
  - **Gun ownership**: The Client GenServer maintains Gun ownership through reconnections
  - **Supervisor restarts**: In supervised mode, crashes trigger automatic restarts

  ## Market Type Configuration

      # Spot market (default)
      {:ok, client} = Binance.WebSocket.connect(streams)

      # Futures market
      {:ok, client} = Binance.WebSocket.connect(streams, market: :futures)

      # Testnet (both spot and futures have separate testnets)
      {:ok, client} = Binance.WebSocket.connect(streams, testnet: true, market: :spot)
      {:ok, client} = Binance.WebSocket.connect(streams, testnet: true, market: :futures)

  ## Implementation Notes

  The adapter creates a message handler function that processes Binance messages and
  stores them in ETS. This handler runs in the Client GenServer process, maintaining
  proper Gun message ownership. Unlike Bybit, Binance doesn't require periodic ping
  messages as it handles heartbeat internally.
  """

  alias ZenCex.Cache.Market

  require Logger

  # WebSocket endpoints
  @spot_ws_url "wss://stream.binance.com/ws"
  @spot_ws_testnet_url "wss://stream.testnet.binance.vision/ws"
  @futures_ws_url "wss://fstream.binance.com/ws"
  @futures_ws_testnet_url "wss://fstream.binancefuture.com/ws"

  # Binance 2026 new architecture (effective April 23, 2026)
  @futures_public_url "wss://fstream.binance.com/public"
  @futures_market_url "wss://fstream.binance.com/market"
  @futures_private_url "wss://fstream.binance.com/private"

  # Maximum message size to prevent memory exhaustion (1MB)
  @max_message_size 1_048_576

  # Public API

  @doc """
  Creates a new WebSocket connection for the given streams.

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
    * `streams` - List of streams to subscribe to
    * `opts` - Connection options

  ## Returns
    * `{:ok, client}` - The newly created WebSocket client
    * `{:error, reason}` - Error details
  """
  @spec ensure_connection(list(String.t()), keyword()) :: {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def ensure_connection(streams, opts \\ []) do
    # Always creates a new connection - connection reuse happens at the application layer
    # via ConnectionRegistry and MarketData.ensure_websocket_connection/2
    connect(streams, opts)
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
  @spec check_health(ZenWebsocket.Client.t()) :: map()
  def check_health(connection) do
    %{
      state: ZenWebsocket.Client.get_state(connection),
      heartbeat: ZenWebsocket.Client.get_heartbeat_health(connection),
      metrics: ZenWebsocket.Client.get_state_metrics(connection),
      adapter: :binance
    }
  end

  @doc """
  Connects to Binance WebSocket and subscribes to streams.

  ## Parameters
    * `streams` - List of streams to subscribe to initially
    * `opts` - Connection options

  ## Options
    * `:testnet` - Use testnet endpoints (default: false)
    * `:market` - Market type :spot or :futures (default: :spot)
    * `:supervised` - Use ClientSupervisor for production (default: false)
  """
  @spec connect(list(String.t()), keyword()) :: {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def connect(streams, opts) do
    testnet? = Keyword.get(opts, :testnet, false)
    market = Keyword.get(opts, :market, :spot)
    supervised? = Keyword.get(opts, :supervised, false)

    # Create message handler (user can override via :handler opt)
    handler = case Keyword.get(opts, :handler) do
      nil -> create_message_handler()
      user_fn -> wrap_handler(user_fn)
    end

    # Connection options for zen_websocket
    ws_opts = [
      handler: handler,
      retry_count: 5,
      retry_delay: 1000,
      max_backoff: 30_000,
      reconnect_on_error: true
    ]

    result = case market do
      :futures_private ->
        # User data stream (2026 new architecture)
        listen_key = Keyword.fetch!(opts, :listen_key)
        events = Keyword.get(opts, :events, ["ORDER_TRADE_UPDATE"])
        url = build_private_url(listen_key, events)
        do_connect(url, ws_opts, supervised?)

      m when m in [:futures_public, :futures_market] ->
        # Public/Market data (2026 new architecture)
        url = get_ws_url(m, testnet?) <> "/ws/" <> Enum.join(streams, "/")
        do_connect(url, ws_opts, supervised?)

      _ ->
        # Spot and legacy :futures
        url = get_ws_url(market, testnet?)
        with {:ok, client} <- do_connect(url, ws_opts, supervised?),
             {:ok, _} <- subscribe(client, streams) do
          {:ok, client}
        end
    end

    case result do
      {:ok, client} ->
        Logger.info("Connected to Binance WebSocket (market: #{market})")
        {:ok, client}
      {:error, reason} = error ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        error
    end
  end

  defp build_private_url(listen_key, events) do
    case events do
      [single] ->
        "#{@futures_private_url}/ws?listenKey=#{listen_key}&events=#{single}"
      multiple ->
        streams = Enum.map_join(multiple, "/", &"#{listen_key}@#{&1}")
        "#{@futures_private_url}/stream?streams=#{streams}"
    end
  end

  @doc """
  Subscribes to additional streams on existing connection.
  """
  @spec subscribe(ZenWebsocket.Client.t(), list(String.t())) :: {:ok, :subscribed} | {:error, term()}
  def subscribe(connection, streams) when is_list(streams) do
    # Return early if no streams to subscribe
    if streams == [] do
      {:ok, :subscribed}
    else
      sub_message = %{
        method: "SUBSCRIBE",
        params: streams,
        id: :os.system_time(:millisecond)
      }

      # Binance responds with {"result": nil, "id": <same_id>}
      case ZenWebsocket.Client.send_message(connection, Jason.encode!(sub_message)) do
        {:ok, %{"result" => nil}} ->
          Logger.debug("Subscribed to Binance streams: #{inspect(streams)}")
          {:ok, :subscribed}

        :ok ->
          Logger.debug("Subscribed to Binance streams: #{inspect(streams)}")
          {:ok, :subscribed}

        {:error, reason} = error ->
          Logger.error("Failed to subscribe to streams: #{inspect(reason)}")
          error

        other ->
          Logger.error("Unexpected subscription response: #{inspect(other)}")
          {:error, {:unexpected_response, other}}
      end
    end
  end

  @doc """
  Unsubscribes from streams.
  """
  @spec unsubscribe(ZenWebsocket.Client.t(), list(String.t())) :: {:ok, :unsubscribed} | {:error, term()}
  def unsubscribe(connection, streams) when is_list(streams) do
    if streams == [] do
      {:ok, :unsubscribed}
    else
      unsub_message = %{
        method: "UNSUBSCRIBE",
        params: streams,
        id: :os.system_time(:millisecond)
      }

      case ZenWebsocket.Client.send_message(connection, Jason.encode!(unsub_message)) do
        {:ok, %{"result" => nil}} ->
          Logger.debug("Unsubscribed from streams: #{inspect(streams)}")
          {:ok, :unsubscribed}

        :ok ->
          Logger.debug("Unsubscribed from streams: #{inspect(streams)}")
          {:ok, :unsubscribed}

        {:error, reason} = error ->
          Logger.error("Failed to unsubscribe from streams: #{inspect(reason)}")
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
  @spec close(ZenWebsocket.Client.t()) :: :ok
  def close(connection) do
    ZenWebsocket.Client.close(connection)
  end

  @doc """
  Gets connection state.
  """
  @spec get_state(ZenWebsocket.Client.t()) :: {:ok, :connected | :connecting | :disconnected}
  def get_state(connection) do
    state = ZenWebsocket.Client.get_state(connection)
    {:ok, state}
  end

  @doc """
  Sends a raw message to the WebSocket connection.
  Accepts a JSON-encodable map or a raw binary.
  """
  @spec send_message(ZenWebsocket.Client.t(), binary() | map()) :: :ok | {:ok, map()} | {:error, term()}
  def send_message(connection, message) when is_map(message) do
    ZenWebsocket.Client.send_message(connection, Jason.encode!(message))
  end

  def send_message(connection, message) when is_binary(message) do
    ZenWebsocket.Client.send_message(connection, message)
  end

  @doc """
  Gets the heartbeat health of the connection.
  Returns a map with details about the connection's heartbeat status.
  """
  @spec get_heartbeat_health(ZenWebsocket.Client.t()) :: map() | nil
  def get_heartbeat_health(connection) do
    ZenWebsocket.Client.get_heartbeat_health(connection)
  end

  @doc """
  Gets detailed metrics about the client's internal state.
  Returns a map containing data structure sizes, memory usage, and process stats.
  """
  @spec get_state_metrics(ZenWebsocket.Client.t()) :: map() | nil
  def get_state_metrics(connection) do
    ZenWebsocket.Client.get_state_metrics(connection)
  end

  @doc """
  Closes and re-establishes the WebSocket connection.
  """
  @spec reconnect(ZenWebsocket.Client.t()) :: {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  def reconnect(connection) do
    ZenWebsocket.Client.reconnect(connection)
  end

  # Private functions

  @spec get_ws_url(atom(), boolean()) :: String.t()
  defp get_ws_url(:spot, true), do: @spot_ws_testnet_url
  defp get_ws_url(:spot, false), do: @spot_ws_url
  defp get_ws_url(:futures, true), do: @futures_ws_testnet_url
  defp get_ws_url(:futures, false), do: @futures_ws_url
  defp get_ws_url(:futures_public, _testnet), do: @futures_public_url
  defp get_ws_url(:futures_market, _testnet), do: @futures_market_url
  defp get_ws_url(:futures_private, _testnet), do: @futures_private_url

  @spec do_connect(String.t(), keyword(), boolean()) :: {:ok, ZenWebsocket.Client.t()} | {:error, term()}
  defp do_connect(url, opts, false) do
    # Direct connection for development
    ZenWebsocket.Client.connect(url, opts)
  end

  defp do_connect(url, opts, true) do
    # Supervised connection for production
    # ClientSupervisor must be started in application supervisor
    ZenWebsocket.ClientSupervisor.start_client(url, opts)
  end

  @spec create_message_handler() :: (term() -> :ok)
  defp create_message_handler do
    # zen_websocket dispatches already-decoded maps: {:message, %{...}}
    # Raw binary frames are rare (non-JSON text), but handled for safety.
    fn
      {:message, %{} = decoded} ->
        process_stream_data(decoded)

      {:message, data} when is_binary(data) ->
        handle_message(data)

      _other ->
        :ok
    end
  end

  # Wraps user handler to also run built-in caching logic.
  # zen_websocket dispatches {:message, %{} = decoded} (already-decoded map).
  # For stream-mode wrapper {"stream": "lk@EVENT", "data": {...}}, we unwrap
  # before passing to the user handler so it always sees the inner event map.
  defp wrap_handler(user_handler) do
    fn msg ->
      # Normalize message: unwrap stream-mode wrapper if present
      normalized_msg =
        case msg do
          {:message, %{"stream" => _stream_name, "data" => data}} when is_map(data) ->
            {:message, data}
          other ->
            other
        end

      # Built-in caching on the normalized message
      case normalized_msg do
        {:message, %{} = decoded} -> process_stream_data(decoded)
        {:message, data} when is_binary(data) -> handle_message(data)
        _ -> :ok
      end

      # User handler receives the normalized (unwrapped) message
      user_handler.(normalized_msg)
    end
  end

  @spec handle_message(binary()) :: :ok
  defp handle_message(message) when is_binary(message) and byte_size(message) <= @max_message_size do
    case Jason.decode(message) do
      {:ok, data} ->
        process_stream_data(data)

      {:error, reason} ->
        Logger.error("Failed to decode Binance message: #{inspect(reason)}")
    end
  end

  defp handle_message(message) when is_binary(message) do
    Logger.warning(
      "Binance WebSocket message exceeded size limit: #{byte_size(message)} bytes (max: #{@max_message_size})"
    )

    :ok
  end

  @spec process_stream_data(map()) :: :ok
  # Stream-mode wrapper (multi-event private stream): {"stream": "lk@EVENT", "data": {...}}
  defp process_stream_data(%{"stream" => _stream_name, "data" => data}) when is_map(data) do
    process_stream_data(data)
  end

  defp process_stream_data(%{"e" => event_type} = data) do
    case event_type do
      "depthUpdate" ->
        process_orderbook_update(data)

      "trade" ->
        process_trade(data)

      "aggTrade" ->
        # Aggregate trades have similar structure to regular trades
        process_trade(data)

      "24hrTicker" ->
        process_ticker(data)

      "24hrMiniTicker" ->
        process_mini_ticker(data)

      "bookTicker" ->
        process_book_ticker(data)


      "kline" ->
        process_kline(data)

      # Binance futures markPrice stream sends event type "markPriceUpdate"
      t when t in ["markPrice", "markPriceUpdate"] ->
        process_mark_price(data)

      _ ->
        Logger.debug("Unhandled Binance event type: #{event_type}")
    end
  end

  defp process_stream_data(%{"result" => nil, "id" => _id}) do
    # Subscription/unsubscription confirmation
    :ok
  end

  defp process_stream_data(%{"code" => code, "msg" => msg}) do
    # Error response
    Logger.error("Binance WebSocket error: #{code} - #{msg}")
  end

  defp process_stream_data(data) do
    Logger.debug("Unhandled Binance message: #{inspect(data)}")
  end

  @spec process_kline(map()) :: :ok
  defp process_kline(%{"s" => symbol, "k" => k} = _data) do
    kline = %{
      symbol: symbol,
      interval: k["i"],
      open: k["o"],
      high: k["h"],
      low: k["l"],
      close: k["c"],
      volume: k["v"],
      close_time: k["T"],
      is_closed: k["x"],
      timestamp: :os.system_time(:millisecond)
    }
    ZenCex.Cache.Market.put_market_data(:binance, symbol, "kline_#{k["i"]}", kline, 300)
    :ok
  end

  @spec process_mark_price(map()) :: :ok
  defp process_mark_price(%{"s" => symbol, "p" => price} = data) do
    mark = %{
      symbol: symbol,
      mark_price: price,
      funding_rate: data["r"],
      next_funding_time: data["T"],
      timestamp: :os.system_time(:millisecond)
    }
    ZenCex.Cache.Market.put_market_data(:binance, symbol, "markPrice", mark, 300)
    :ok
  end

    @spec process_orderbook_update(map()) :: :ok
  defp process_orderbook_update(data) do
    %{
      "s" => symbol,
      "U" => first_update_id,
      "u" => final_update_id,
      "b" => bids,
      "a" => asks
    } = data

    orderbook = %{
      symbol: symbol,
      update_id: final_update_id,
      first_update_id: first_update_id,
      bids: parse_orderbook_levels(bids),
      asks: parse_orderbook_levels(asks),
      timestamp: :os.system_time(:millisecond)
    }

    # Store with infinite TTL - orderbook updates are frequent
    Market.put_orderbook(:binance, symbol, orderbook)
  end

  @spec process_trade(map()) :: :ok
  defp process_trade(data) do
    trade = %{
      symbol: data["s"],
      price: data["p"],
      quantity: data["q"],
      time: data["T"] || data["E"],
      is_buyer_maker: data["m"] || false,
      trade_id: to_string(data["t"] || data["a"]),
      timestamp: :os.system_time(:millisecond)
    }

    Market.put_last_trade(:binance, data["s"], trade)
  end

  @spec process_ticker(map()) :: :ok
  defp process_ticker(data) do
    ticker = %{
      symbol: data["s"],
      last_price: data["c"],
      open_price: data["o"],
      high_price: data["h"],
      low_price: data["l"],
      volume: data["v"],
      quote_volume: data["q"],
      open_time: data["O"],
      close_time: data["C"],
      first_trade_id: data["F"],
      last_trade_id: data["L"],
      trade_count: data["n"],
      timestamp: :os.system_time(:millisecond)
    }

    Market.put_ticker(:binance, data["s"], ticker)
  end

  @spec process_mini_ticker(map()) :: :ok
  defp process_mini_ticker(data) do
    ticker = %{
      symbol: data["s"],
      last_price: data["c"],
      open_price: data["o"],
      high_price: data["h"],
      low_price: data["l"],
      volume: data["v"],
      quote_volume: data["q"],
      timestamp: :os.system_time(:millisecond)
    }

    Market.put_ticker(:binance, data["s"], ticker, 30)
  end

  @spec process_book_ticker(map()) :: :ok
  defp process_book_ticker(data) do
    book_ticker = %{
      symbol: data["s"],
      bid_price: data["b"],
      bid_qty: data["B"],
      ask_price: data["a"],
      ask_qty: data["A"],
      update_id: data["u"],
      timestamp: :os.system_time(:millisecond)
    }

    Market.put_book_ticker(:binance, data["s"], book_ticker)
  end

  @spec parse_orderbook_levels(list()) :: list(map())
  defp parse_orderbook_levels(levels) do
    Enum.map(levels, fn [price, quantity] ->
      %{price: price, quantity: quantity}
    end)
  end
end
