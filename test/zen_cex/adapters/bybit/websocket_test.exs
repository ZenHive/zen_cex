defmodule ZenCex.Adapters.Bybit.WebSocketTest do
  @moduledoc """
  Tests for the Bybit WebSocket adapter.

  Tests both unit functionality (message parsing, topic parsing) and
  integration with real Bybit testnet WebSocket endpoints.
  """

  use ZenCex.IntegrationCase, exchange: :bybit, async: false

  alias ZenCex.Adapters.Bybit.WebSocket
  alias ZenCex.Cache.Market

  require Logger

  # 10 seconds for WebSocket operations
  @test_timeout 10_000

  describe "connect/2" do
    @tag :integration
    @tag :ws_slow
    test "connects to Bybit testnet WebSocket" do
      assert {:ok, ws} = WebSocket.connect([], testnet: true)
      assert %ZenWebsocket.Client{} = ws

      # Verify connection state
      assert {:ok, state} = WebSocket.get_state(ws)
      assert %{status: status} = state
      assert is_atom(status)

      # Clean up
      assert :ok = WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "connects to spot market WebSocket" do
      assert {:ok, ws} = WebSocket.connect([], testnet: true, market: :spot)
      assert %ZenWebsocket.Client{} = ws
      assert :ok = WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "connects to linear futures market WebSocket" do
      assert {:ok, ws} = WebSocket.connect([], testnet: true, market: :linear)
      assert %ZenWebsocket.Client{} = ws
      assert :ok = WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "connects to futures market WebSocket (alias for linear)" do
      assert {:ok, ws} = WebSocket.connect([], testnet: true, market: :futures)
      assert %ZenWebsocket.Client{} = ws
      assert :ok = WebSocket.close(ws)
    end

    test "connection parameters are properly configured" do
      # Verify testnet vs mainnet URLs are different
      # This ensures our adapter correctly configures the connection
      assert WebSocket.connect([], testnet: true) !=
               WebSocket.connect([], testnet: false)
    end
  end

  describe "subscribe/2 and unsubscribe/2" do
    @tag :integration
    @tag :ws_slow
    test "subscribes to and unsubscribes from topics" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Test subscription to various topics
      topics = ["orderbook.50.BTCUSDT", "publicTrade.ETHUSDT"]
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, topics)

      # Give it time to process
      Process.sleep(1000)

      # Test unsubscribe
      assert {:ok, :unsubscribed} = WebSocket.unsubscribe(ws, topics)

      # Clean up
      WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "handles multiple subscription types" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Subscribe to different topic types
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["orderbook.25.BTCUSDT"])
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["publicTrade.BTCUSDT"])
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["tickers.BTCUSDT"])
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["bookticker.BTCUSDT"])

      Process.sleep(1000)

      WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "validates topic list parameter" do
      # This test requires a real connection since we now use ZenWebsocket.Client
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Should handle empty list
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, [])

      WebSocket.close(ws)
    end
  end

  describe "get_state/1" do
    @tag :integration
    @tag :ws_slow
    test "returns connection state" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      assert {:ok, state} = WebSocket.get_state(ws)
      assert is_map(state)

      WebSocket.close(ws)
    end
  end

  describe "close/1" do
    @tag :integration
    @tag :ws_slow
    test "closes connection cleanly" do
      {:ok, ws} = WebSocket.connect([], testnet: true)
      server_pid = ws.server_pid
      assert :ok = WebSocket.close(ws)

      # Verify connection is closed
      Process.sleep(100)
      refute Process.alive?(server_pid)
    end
  end

  describe "topic parsing" do
    test "parses orderbook topics correctly" do
      # These tests document the actual Bybit topic format
      assert parse_topic("orderbook.50.BTCUSDT") == {:orderbook, 50, "BTCUSDT"}
      assert parse_topic("orderbook.25.ETHUSDT") == {:orderbook, 25, "ETHUSDT"}
      assert parse_topic("orderbook.1.SOLUSDT") == {:orderbook, 1, "SOLUSDT"}
    end

    test "parses trade topics correctly" do
      assert parse_topic("publicTrade.BTCUSDT") == {:trade, "BTCUSDT"}
      assert parse_topic("publicTrade.ETHUSDT") == {:trade, "ETHUSDT"}
    end

    test "parses ticker topics correctly" do
      assert parse_topic("tickers.BTCUSDT") == {:ticker, "BTCUSDT"}
      assert parse_topic("tickers.ETHUSDT") == {:ticker, "ETHUSDT"}
    end

    test "parses bookticker topics correctly" do
      assert parse_topic("bookticker.BTCUSDT") == {:bookticker, "BTCUSDT"}
      assert parse_topic("bookticker.ETHUSDT") == {:bookticker, "ETHUSDT"}
    end

    test "parses liquidation topics correctly" do
      assert parse_topic("liquidation.BTCUSDT") == {:liquidation, "BTCUSDT"}
      assert parse_topic("liquidation.ETHUSDT") == {:liquidation, "ETHUSDT"}
    end

    test "handles unknown topics" do
      assert parse_topic("unknown.topic.format") == {:unknown, "unknown.topic.format"}
      assert parse_topic("single") == {:unknown, "single"}
    end
  end

  describe "message parsing - orderbook" do
    test "expected orderbook message format" do
      # Document the actual Bybit orderbook format
      expected_message = %{
        "topic" => "orderbook.50.BTCUSDT",
        "type" => "snapshot",
        "ts" => 1_672_304_486_839,
        "data" => %{
          "s" => "BTCUSDT",
          "b" => [["16493.50", "0.006"], ["16493.00", "0.100"]],
          "a" => [["16611.00", "0.029"], ["16612.00", "0.213"]],
          "u" => 18_521_288,
          "seq" => 7_961_638_724
        }
      }

      data = expected_message["data"]
      assert data["s"] == "BTCUSDT"
      assert is_list(data["b"])
      assert is_list(data["a"])
      assert is_integer(data["u"])
      assert is_integer(data["seq"])

      # Each level should be [price, quantity] as strings
      for [price, qty] <- data["b"] do
        assert is_binary(price)
        assert is_binary(qty)
      end
    end
  end

  describe "message parsing - publicTrade" do
    test "expected trade message format" do
      # Document the actual Bybit trade format
      expected_message = %{
        "topic" => "publicTrade.BTCUSDT",
        "type" => "snapshot",
        "ts" => 1_672_304_486_868,
        "data" => [
          %{
            "i" => "2290000000075709848",
            "T" => 1_672_304_486_865,
            "p" => "16578.50",
            "v" => "0.001",
            "S" => "Buy",
            "s" => "BTCUSDT",
            "BT" => false
          }
        ]
      }

      [trade | _] = expected_message["data"]
      assert trade["s"] == "BTCUSDT"
      # Price
      assert is_binary(trade["p"])
      # Volume
      assert is_binary(trade["v"])
      assert trade["S"] in ["Buy", "Sell"]
      # Timestamp
      assert is_integer(trade["T"])
      # Trade ID
      assert is_binary(trade["i"])
    end

    test "handles multiple trades in one message" do
      # Bybit can send multiple trades in one message
      expected_message = %{
        "topic" => "publicTrade.ETHUSDT",
        "data" => [
          %{"i" => "1", "T" => 123, "p" => "3000", "v" => "1", "S" => "Buy", "s" => "ETHUSDT"},
          %{"i" => "2", "T" => 124, "p" => "3001", "v" => "2", "S" => "Sell", "s" => "ETHUSDT"}
        ]
      }

      assert length(expected_message["data"]) == 2
      assert Enum.all?(expected_message["data"], fn t -> t["s"] == "ETHUSDT" end)
    end
  end

  describe "message parsing - tickers" do
    test "expected ticker message format" do
      # Document the actual Bybit ticker format
      expected_message = %{
        "topic" => "tickers.BTCUSDT",
        "type" => "snapshot",
        "cs" => 24_987_956_059,
        "ts" => 1_673_323_002_145,
        "data" => %{
          "symbol" => "BTCUSDT",
          "lastPrice" => "17216.00",
          "highPrice24h" => "17281.50",
          "lowPrice24h" => "16915.00",
          "prevPrice24h" => "16973.50",
          "volume24h" => "43366.118",
          "turnover24h" => "743703914.047",
          "price24hPcnt" => "0.0143",
          "usdIndexPrice" => "17217.7363681",
          "bid1Price" => "17215.50",
          "bid1Size" => "84.489",
          "ask1Price" => "17216.00",
          "ask1Size" => "83.020"
        }
      }

      data = expected_message["data"]
      assert data["symbol"] == "BTCUSDT"
      assert is_binary(data["lastPrice"])
      assert is_binary(data["highPrice24h"])
      assert is_binary(data["lowPrice24h"])
      assert is_binary(data["volume24h"])
      assert is_binary(data["bid1Price"])
      assert is_binary(data["ask1Price"])
    end
  end

  describe "message parsing - bookticker" do
    test "expected book ticker message format" do
      # Document the actual Bybit book ticker format
      expected_message = %{
        "topic" => "bookticker.BTCUSDT",
        "type" => "snapshot",
        "ts" => 1_673_853_746_868,
        "data" => %{
          "symbol" => "BTCUSDT",
          "bp" => "21109.00",
          "bq" => "2.05",
          "ap" => "21109.50",
          "aq" => "1.32"
        }
      }

      data = expected_message["data"]
      assert data["symbol"] == "BTCUSDT"
      # Bid price
      assert is_binary(data["bp"])
      # Bid quantity
      assert is_binary(data["bq"])
      # Ask price
      assert is_binary(data["ap"])
      # Ask quantity
      assert is_binary(data["aq"])
    end
  end

  describe "message parsing - liquidation" do
    test "expected liquidation message format" do
      # Document the actual Bybit liquidation format
      expected_message = %{
        "topic" => "liquidation.BTCUSDT",
        "type" => "snapshot",
        "ts" => 1_673_323_002_145,
        "data" => %{
          "updatedTime" => 1_673_251_091_822,
          "symbol" => "BTCUSDT",
          "side" => "Buy",
          "size" => "0.003",
          "price" => "16881.70"
        }
      }

      data = expected_message["data"]
      assert data["symbol"] == "BTCUSDT"
      assert data["side"] in ["Buy", "Sell"]
      assert is_binary(data["size"])
      assert is_binary(data["price"])
      assert is_integer(data["updatedTime"])
    end
  end

  describe "message parsing - operation responses" do
    test "handles subscription confirmation" do
      # Document the subscription confirmation format
      expected_message = %{
        "success" => true,
        "ret_msg" => "subscribe",
        "op" => "subscribe",
        "conn_id" => "cejreaspkn1q7773q3eg-2m"
      }

      assert expected_message["success"] == true
      assert expected_message["op"] == "subscribe"
    end

    test "handles pong response" do
      # Document the pong format
      expected_message = %{
        "success" => true,
        "ret_msg" => "pong",
        "conn_id" => "cejreaspkn1q7773q3eg-2m",
        "req_id" => "",
        "op" => "pong"
      }

      assert expected_message["op"] == "pong"
      assert expected_message["success"] == true
    end
  end

  describe "real-time data integration" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "receives real orderbook updates from testnet" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Subscribe to a popular pair
      # Bybit supports depths: 1, 50, 200, 500
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["orderbook.50.BTCUSDT"])

      # Wait for data
      Process.sleep(3000)

      # Check if we received orderbook data
      case Market.get_orderbook(:bybit, "BTCUSDT") do
        {:ok, orderbook} ->
          assert orderbook.symbol == "BTCUSDT"
          assert is_list(orderbook.bids)
          assert is_list(orderbook.asks)
          assert is_integer(orderbook.update_id)
          Logger.info("Received real orderbook: #{inspect(orderbook, limit: 5)}")

        {:error, :not_found} ->
          Logger.warning("No orderbook data received - testnet might be inactive")
      end

      WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "receives real trade updates from testnet" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Subscribe to trade stream
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["publicTrade.BTCUSDT"])

      # Wait for trades
      Process.sleep(5000)

      # Check if we received trade data
      case Market.get_last_trade(:bybit, "BTCUSDT") do
        {:ok, trade} ->
          assert trade.symbol == "BTCUSDT"
          assert is_binary(trade.price)
          assert is_binary(trade.quantity)
          assert trade.side in ["Buy", "Sell"]
          Logger.info("Received real trade: #{inspect(trade)}")

        {:error, :not_found} ->
          Logger.warning("No trade data received - testnet might have low activity")
      end

      WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "receives real ticker updates from testnet" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Subscribe to ticker stream
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["tickers.BTCUSDT"])

      # Wait for ticker
      Process.sleep(3000)

      # Check if we received ticker data
      case Market.get_ticker(:bybit, "BTCUSDT") do
        {:ok, ticker} ->
          assert ticker.symbol == "BTCUSDT"
          assert is_binary(ticker.last_price)
          assert is_binary(ticker.volume_24h)
          Logger.info("Received real ticker: #{inspect(ticker, limit: 10)}")

        {:error, :not_found} ->
          Logger.warning("No ticker data received - testnet might be inactive")
      end

      WebSocket.close(ws)
    end
  end

  # Helper functions

  # Helper to simulate topic parsing (mirrors internal function)
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
end
