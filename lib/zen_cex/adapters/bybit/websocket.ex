defmodule ZenCex.Adapters.Bybit.WebSocket do
  @moduledoc """
  Bybit WebSocket adapter for real-time market data.

  Handles WebSocket connections to Bybit V5 streams for order books,
  trades, and ticker updates. Data is automatically stored in ETS
  for fast access by other modules.

  ## Supported Streams

  - Order book: `orderbook.{depth}.{symbol}` (e.g., "orderbook.50.BTCUSDT")
  - Trades: `publicTrade.{symbol}`
  - Ticker: `tickers.{symbol}`
  - Best bid/ask: `bookticker.{symbol}`
  - Liquidations: `liquidation.{symbol}`

  ## Usage

      # Development - Direct connection
      {:ok, ws} = Bybit.WebSocket.connect()
      :ok = Bybit.WebSocket.subscribe(ws, ["orderbook.50.BTCUSDT", "publicTrade.ETHUSDT"])

      # Access cached data from ETS
      {:ok, orderbook} = ZenCex.Cache.Market.get_orderbook(:bybit, "BTCUSDT")
  """

  @behaviour ZenCex.WebSocket.Base

  alias ZenCex.Cache.Market
  alias ZenCex.Config.TimeConstants

  require Logger

  # WebSocket endpoints - Bybit V5 unified
  @public_ws_url "wss://stream.bybit.com/v5/public/spot"
  @public_ws_testnet_url "wss://stream-testnet.bybit.com/v5/public/spot"
  @futures_ws_url "wss://stream.bybit.com/v5/public/linear"
  @futures_ws_testnet_url "wss://stream-testnet.bybit.com/v5/public/linear"

  # Ping interval for Bybit (20 seconds)
  @ping_interval_ms TimeConstants.websocket_timeouts().bybit_ping_interval

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

    # Connect with auto-reconnect and custom ping
    case ZenWebsocket.Client.connect(url,
           handler: handler,
           heartbeat_interval: @ping_interval_ms,
           heartbeat_message: Jason.encode!(%{op: "ping"})
         ) do
      {:ok, client} ->
        Logger.info("Connected to Bybit WebSocket at #{url}")
        {:ok, client}

      {:error, reason} = error ->
        Logger.error("Failed to connect to Bybit WebSocket: #{inspect(reason)}")
        error
    end
  end

  @impl true
  def subscribe(connection, topics) when is_list(topics) do
    # Bybit V5 subscription format
    sub_message = %{
      op: "subscribe",
      args: topics
    }

    case ZenWebsocket.Client.send_message(connection, Jason.encode!(sub_message)) do
      :ok ->
        Logger.debug("Subscribed to Bybit topics: #{inspect(topics)}")
        :ok

      {:ok, _response} ->
        # Bybit returns a response with the subscription result
        Logger.debug("Subscribed to Bybit topics: #{inspect(topics)}")
        :ok

      error ->
        Logger.error("Failed to subscribe to Bybit topics: #{inspect(error)}")
        error
    end
  end

  @impl true
  def unsubscribe(connection, topics) when is_list(topics) do
    unsub_message = %{
      op: "unsubscribe",
      args: topics
    }

    case ZenWebsocket.Client.send_message(connection, Jason.encode!(unsub_message)) do
      :ok ->
        Logger.debug("Unsubscribed from Bybit topics: #{inspect(topics)}")
        :ok

      error ->
        Logger.error("Failed to unsubscribe from Bybit topics: #{inspect(error)}")
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

  defp get_ws_url(:spot, true), do: @public_ws_testnet_url
  defp get_ws_url(:spot, false), do: @public_ws_url
  defp get_ws_url(:linear, true), do: @futures_ws_testnet_url
  defp get_ws_url(:linear, false), do: @futures_ws_url
  defp get_ws_url(:futures, testnet?), do: get_ws_url(:linear, testnet?)

  defp handle_message(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok, data} ->
        process_stream_data(data)

      {:error, reason} ->
        Logger.error("Failed to decode Bybit WebSocket message: #{inspect(reason)}")
    end
  end

  defp process_stream_data(%{"topic" => topic, "data" => data}) do
    Logger.debug("Bybit stream data - topic: #{topic}")

    case parse_topic(topic) do
      {:orderbook, depth, symbol} ->
        process_orderbook(symbol, depth, data)

      {:trade, symbol} ->
        process_trades(symbol, data)

      {:ticker, symbol} ->
        process_ticker(symbol, data)

      {:bookticker, symbol} ->
        process_book_ticker(symbol, data)

      {:liquidation, symbol} ->
        process_liquidation(symbol, data)

      _ ->
        Logger.debug("Unknown Bybit topic: #{topic}")
    end
  end

  defp process_stream_data(%{"success" => true, "op" => op}) do
    Logger.debug("Bybit #{op} operation successful")
  end

  defp process_stream_data(%{"op" => "pong"}) do
    # Pong response, connection is alive
    :ok
  end

  defp process_stream_data(data) do
    Logger.debug("Unhandled Bybit WebSocket data: #{inspect(data)}")
  end

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

  defp process_orderbook(symbol, _depth, %{"s" => _symbol, "b" => bids, "a" => asks, "u" => update_id, "seq" => sequence}) do
    orderbook = %{
      symbol: symbol,
      update_id: update_id,
      sequence: sequence,
      bids: parse_orderbook_levels(bids),
      asks: parse_orderbook_levels(asks),
      timestamp: :os.system_time(:millisecond)
    }

    # Store in ETS cache
    Market.put_orderbook(:bybit, symbol, orderbook)

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :websocket, :orderbook_update],
      %{count: 1},
      %{exchange: :bybit, symbol: symbol}
    )
  end

  defp process_trades(symbol, trades) when is_list(trades) do
    # Process each trade
    Enum.each(trades, fn trade ->
      process_single_trade(symbol, trade)
    end)
  end

  defp process_single_trade(symbol, %{"p" => price, "v" => volume, "T" => timestamp, "S" => side, "i" => trade_id}) do
    trade = %{
      symbol: symbol,
      trade_id: trade_id,
      price: price,
      quantity: volume,
      side: side,
      time: timestamp,
      timestamp: :os.system_time(:millisecond)
    }

    # Store latest trade
    Market.put_last_trade(:bybit, symbol, trade)

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :websocket, :trade],
      %{count: 1},
      %{exchange: :bybit, symbol: symbol}
    )
  end

  defp process_ticker(symbol, data) do
    # Handle both formats - full ticker and simplified ticker
    last_price = Map.get(data, "lastPrice") || Map.get(data, "last_price")
    high_24h = Map.get(data, "highPrice24h") || Map.get(data, "high_price")
    low_24h = Map.get(data, "lowPrice24h") || Map.get(data, "low_price")
    prev_price_24h = Map.get(data, "prevPrice24h") || Map.get(data, "prev_price")
    volume_24h = Map.get(data, "volume24h") || Map.get(data, "volume")
    turnover_24h = Map.get(data, "turnover24h") || Map.get(data, "turnover")
    bid_price = Map.get(data, "bid1Price")
    bid_size = Map.get(data, "bid1Size")
    ask_price = Map.get(data, "ask1Price")
    ask_size = Map.get(data, "ask1Size")

    ticker = %{
      symbol: symbol,
      last_price: last_price,
      high_24h: high_24h,
      low_24h: low_24h,
      prev_price_24h: prev_price_24h,
      volume_24h: volume_24h,
      turnover_24h: turnover_24h,
      bid_price: bid_price,
      bid_size: bid_size,
      ask_price: ask_price,
      ask_size: ask_size,
      timestamp: :os.system_time(:millisecond)
    }

    # Store in cache
    Market.put_ticker(:bybit, symbol, ticker)

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :websocket, :ticker],
      %{count: 1},
      %{exchange: :bybit, symbol: symbol}
    )
  end

  defp process_book_ticker(symbol, %{
         "symbol" => _symbol,
         "bp" => bid_price,
         "bq" => bid_qty,
         "ap" => ask_price,
         "aq" => ask_qty
       }) do
    book_ticker = %{
      symbol: symbol,
      bid_price: bid_price,
      bid_qty: bid_qty,
      ask_price: ask_price,
      ask_qty: ask_qty,
      timestamp: :os.system_time(:millisecond)
    }

    # Store best bid/ask
    Market.put_book_ticker(:bybit, symbol, book_ticker)
  end

  defp process_liquidation(symbol, %{"updatedTime" => timestamp, "side" => side, "size" => size, "price" => price}) do
    _liquidation = %{
      symbol: symbol,
      side: side,
      size: size,
      price: price,
      timestamp: timestamp
    }

    # Could store liquidations if needed for risk monitoring
    Logger.info("Liquidation on #{symbol}: #{side} #{size} @ #{price}")

    # Emit telemetry
    :telemetry.execute(
      [:zen_cex, :websocket, :liquidation],
      %{size: String.to_float(size)},
      %{exchange: :bybit, symbol: symbol, side: side}
    )
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
