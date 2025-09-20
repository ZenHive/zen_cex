defmodule ZenCex.Adapters.Binance.WebSocket do
  @moduledoc """
  Binance WebSocket adapter for real-time market data.

  Handles WebSocket connections to Binance streams for order books,
  trades, and ticker updates. Data is automatically stored in ETS
  for fast access by other modules.

  ## Supported Streams

  - Order book: `{symbol}@depth{levels}` (e.g., "btcusdt@depth20")
  - Trades: `{symbol}@trade`
  - Ticker: `{symbol}@ticker`
  - Mini ticker: `{symbol}@miniTicker`
  - Book ticker: `{symbol}@bookTicker`

  ## Usage

      # Development - Direct connection
      {:ok, ws} = Binance.WebSocket.connect()
      :ok = Binance.WebSocket.subscribe(ws, ["btcusdt@depth20", "ethusdt@trade"])

      # Access cached data from ETS
      {:ok, orderbook} = ZenCex.Cache.Market.get_orderbook(:binance, "BTCUSDT")
  """

  @behaviour ZenCex.WebSocket.Base

  alias ZenCex.Cache.Market

  require Logger

  # WebSocket endpoints (no port needed in URL)
  @spot_ws_url "wss://stream.binance.com/ws"
  @spot_ws_testnet_url "wss://testnet.binance.vision/ws"
  @futures_ws_url "wss://fstream.binance.com/ws"
  @futures_ws_testnet_url "wss://stream.binancefuture.com/ws"

  # Stream update intervals (for reference)
  # @orderbook_update_ms 100
  # @trade_update_instant 0
  # @ticker_update_ms 1000

  @impl true
  def connect(opts \\ []) do
    testnet? = Keyword.get(opts, :testnet, false)
    market = Keyword.get(opts, :market, :spot)

    url = get_ws_url(market, testnet?)

    # Create a handler function that processes messages properly
    # Note: The client may send both raw and decoded messages
    handler = fn
      {:message, {:text, data}} when is_binary(data) -> handle_message(data)
      {:message, {:binary, data}} when is_binary(data) -> handle_message(data)
      {:message, data} when is_binary(data) -> handle_message(data)
      # Already decoded
      {:message, %{} = decoded} -> process_stream_data(decoded)
      _other -> :ok
    end

    # Connect with auto-reconnect and heartbeat
    case ZenWebsocket.Client.connect(url, handler: handler) do
      {:ok, client} ->
        Logger.info("Connected to Binance WebSocket at #{url}")
        {:ok, client}

      {:error, reason} = error ->
        Logger.error("Failed to connect to Binance WebSocket: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def subscribe(connection, streams) when is_list(streams) do
    # Binance uses a subscription message format
    sub_message = %{
      method: "SUBSCRIBE",
      params: streams,
      id: :os.system_time(:millisecond)
    }

    case ZenWebsocket.Client.send_message(connection, Jason.encode!(sub_message)) do
      :ok ->
        Logger.debug("Subscribed to Binance streams: #{inspect(streams)}")
        :ok

      {:ok, _response} ->
        # Binance returns a response with the subscription result
        Logger.debug("Subscribed to Binance streams: #{inspect(streams)}")
        :ok

      error ->
        Logger.error("Failed to subscribe to Binance streams: #{inspect(error)}")
        error
    end
  end

  @impl true
  def unsubscribe(connection, streams) when is_list(streams) do
    unsub_message = %{
      method: "UNSUBSCRIBE",
      params: streams,
      id: :os.system_time(:millisecond)
    }

    case ZenWebsocket.Client.send_message(connection, Jason.encode!(unsub_message)) do
      :ok ->
        Logger.debug("Unsubscribed from Binance streams: #{inspect(streams)}")
        :ok

      error ->
        Logger.error("Failed to unsubscribe from Binance streams: #{inspect(error)}")
        error
    end
  end

  @impl true
  def state(connection) do
    {:ok, %{status: ZenWebsocket.Client.get_state(connection)}}
  end

  @impl true
  def close(connection) do
    ZenWebsocket.Client.close(connection)
  end

  # Private functions

  defp get_ws_url(:spot, true), do: @spot_ws_testnet_url
  defp get_ws_url(:spot, false), do: @spot_ws_url
  defp get_ws_url(:futures, true), do: @futures_ws_testnet_url
  defp get_ws_url(:futures, false), do: @futures_ws_url

  defp handle_message(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, data} ->
        process_stream_data(data)

      {:error, reason} ->
        Logger.error("Failed to decode Binance WebSocket message: #{inspect(reason)}")
    end
  end

  defp process_stream_data(%{"e" => event_type} = data) do
    case event_type do
      "depthUpdate" ->
        process_orderbook_update(data)

      "trade" ->
        process_trade(data)

      "24hrTicker" ->
        process_ticker(data)

      "24hrMiniTicker" ->
        process_mini_ticker(data)

      "bookTicker" ->
        process_book_ticker(data)

      _ ->
        Logger.debug("Unknown Binance event type: #{event_type}")
    end
  end

  defp process_stream_data(%{"result" => nil, "id" => _id}) do
    # Subscription confirmation
    Logger.debug("Binance subscription confirmed")
  end

  # Handle book ticker data without "e" field (raw format from stream)
  defp process_stream_data(%{"s" => _symbol, "b" => _bid, "a" => _ask} = data) do
    # This is book ticker data in raw format
    process_book_ticker(data)
  end

  defp process_stream_data(data) do
    Logger.debug("Unhandled Binance WebSocket data: #{inspect(data)}")
  end

  defp process_orderbook_update(%{
         "s" => symbol,
         "U" => first_update_id,
         "u" => final_update_id,
         "b" => bids,
         "a" => asks
       }) do
    orderbook = %{
      symbol: symbol,
      update_id: final_update_id,
      first_update_id: first_update_id,
      bids: parse_orderbook_levels(bids),
      asks: parse_orderbook_levels(asks),
      timestamp: :os.system_time(:millisecond)
    }

    # Store in ETS cache
    Market.put_orderbook(:binance, symbol, orderbook)

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :websocket, :orderbook_update],
      %{count: 1},
      %{exchange: :binance, symbol: symbol}
    )
  end

  defp process_trade(%{"s" => symbol, "p" => price, "q" => quantity, "T" => trade_time, "m" => is_buyer_maker}) do
    trade = %{
      symbol: symbol,
      price: price,
      quantity: quantity,
      time: trade_time,
      is_buyer_maker: is_buyer_maker,
      timestamp: :os.system_time(:millisecond)
    }

    # Store latest trade
    Market.put_last_trade(:binance, symbol, trade)

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :websocket, :trade],
      %{count: 1},
      %{exchange: :binance, symbol: symbol}
    )
  end

  defp process_ticker(%{
         "s" => symbol,
         "c" => last_price,
         "o" => open_price,
         "h" => high_price,
         "l" => low_price,
         "v" => volume,
         "q" => quote_volume
       }) do
    ticker = %{
      symbol: symbol,
      last_price: last_price,
      open_price: open_price,
      high_price: high_price,
      low_price: low_price,
      volume: volume,
      quote_volume: quote_volume,
      timestamp: :os.system_time(:millisecond)
    }

    # Store in cache with appropriate TTL
    Market.put_ticker(:binance, symbol, ticker)

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :websocket, :ticker],
      %{count: 1},
      %{exchange: :binance, symbol: symbol}
    )
  end

  defp process_mini_ticker(%{"s" => symbol, "c" => close_price, "v" => volume}) do
    mini_ticker = %{
      symbol: symbol,
      close_price: close_price,
      volume: volume,
      timestamp: :os.system_time(:millisecond)
    }

    # Store as mini ticker
    Market.put_ticker(:binance, symbol, mini_ticker, 30)
  end

  defp process_book_ticker(%{
         "s" => symbol,
         "b" => best_bid_price,
         "B" => best_bid_qty,
         "a" => best_ask_price,
         "A" => best_ask_qty
       }) do
    book_ticker = %{
      symbol: symbol,
      bid_price: best_bid_price,
      bid_qty: best_bid_qty,
      ask_price: best_ask_price,
      ask_qty: best_ask_qty,
      timestamp: :os.system_time(:millisecond)
    }

    # Store best bid/ask
    Market.put_book_ticker(:binance, symbol, book_ticker)
  end

  defp parse_orderbook_levels(levels) do
    Enum.map(levels, fn [price, quantity] ->
      %{
        price: price,
        quantity: quantity
      }
    end)
  end
end
