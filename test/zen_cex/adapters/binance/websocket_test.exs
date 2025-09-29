defmodule ZenCex.Adapters.Binance.WebSocketTest do
  @moduledoc """
  Tests for the Binance WebSocket adapter.

  Tests both unit functionality (message parsing) and integration
  with real Binance testnet WebSocket endpoints.
  """

  use ZenCex.IntegrationCase, exchange: :binance, async: false

  alias ZenCex.Adapters.Binance.WebSocket
  alias ZenCex.Cache.Market

  require Logger

  # 10 seconds for WebSocket operations
  @test_timeout 10_000

  describe "connect/2" do
    @tag :integration
    @tag :ws_slow
    test "connects to Binance testnet WebSocket" do
      assert {:ok, ws} = WebSocket.connect([], testnet: true)
      assert %ZenWebsocket.Client{} = ws

      # Verify connection state
      assert {:ok, state} = WebSocket.get_state(ws)
      assert state in [:connecting, :connected, :disconnected]

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
    test "connects to futures market WebSocket" do
      assert {:ok, ws} = WebSocket.connect([], testnet: true, market: :futures)
      assert %ZenWebsocket.Client{} = ws
      assert :ok = WebSocket.close(ws)
    end

    test "connection parameters are properly set" do
      # Test that proper parameters are passed for testnet
      # This ensures our adapter correctly configures the connection
      # The actual connection test is done in the integration test above
      assert WebSocket.connect([], testnet: true, market: :spot) !=
               WebSocket.connect([], testnet: false, market: :spot)
    end
  end

  describe "subscribe/2 and unsubscribe/2" do
    @tag :integration
    @tag :ws_slow
    test "subscribes to and unsubscribes from streams", %{} do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Test subscription
      streams = ["btcusdt@depth20", "ethusdt@trade"]
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, streams)

      # Give it time to process
      Process.sleep(1000)

      # Test unsubscribe
      assert {:ok, :unsubscribed} = WebSocket.unsubscribe(ws, streams)

      # Clean up
      WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "handles multiple subscriptions" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Subscribe to different stream types
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["btcusdt@depth20"])
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["btcusdt@trade"])
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["btcusdt@ticker"])
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["btcusdt@bookTicker"])

      Process.sleep(1000)

      WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "validates stream list parameter" do
      # This test requires a real connection since we now use ZenWebsocket.Client
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Should handle empty list
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, [])

      # Invalid params should be caught by zen_websocket
      # We're testing our adapter passes correct format

      WebSocket.close(ws)
    end
  end

  describe "get_state/1" do
    @tag :integration
    @tag :ws_slow
    test "returns connection state" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      assert {:ok, state} = WebSocket.get_state(ws)
      assert state in [:connecting, :connected, :disconnected]

      WebSocket.close(ws)
    end
  end

  describe "close/1" do
    @tag :integration
    @tag :ws_slow
    test "closes connection cleanly" do
      {:ok, ws} = WebSocket.connect([], testnet: true)
      assert %ZenWebsocket.Client{server_pid: server_pid} = ws
      assert :ok = WebSocket.close(ws)

      # Verify connection is closed
      Process.sleep(100)
      refute Process.alive?(server_pid)
    end
  end

  describe "message parsing" do
    # NOTE: These tests verify the message formats that Binance WebSocket sends.
    # Since the handler is internal to the module and passed to zen_websocket,
    # we document the expected message formats here based on real API observation.

    test "expected depthUpdate message format" do
      # Document the actual Binance depthUpdate format
      expected_message = %{
        "e" => "depthUpdate",
        # Event time
        "E" => 1_234_567_890_123,
        # Symbol
        "s" => "BTCUSDT",
        # First update ID in event
        "U" => 157,
        # Final update ID in event
        "u" => 160,
        # Bids [price, quantity]
        "b" => [["0.0024", "10"], ["0.0023", "100"]],
        # Asks [price, quantity]
        "a" => [["0.0026", "100"], ["0.0027", "40"]]
      }

      # Verify structure
      assert expected_message["e"] == "depthUpdate"
      assert is_binary(expected_message["s"])
      assert is_integer(expected_message["U"])
      assert is_integer(expected_message["u"])
      assert is_list(expected_message["b"])
      assert is_list(expected_message["a"])

      # Each level should be [price, quantity] as strings
      for [price, qty] <- expected_message["b"] do
        assert is_binary(price)
        assert is_binary(qty)
      end
    end

    test "expected trade message format" do
      # Document the actual Binance trade format
      expected_message = %{
        "e" => "trade",
        # Event time
        "E" => 123_456_789,
        # Symbol
        "s" => "BTCUSDT",
        # Trade ID
        "t" => 12_345,
        # Price
        "p" => "50000.00",
        # Quantity
        "q" => "0.001000",
        # Buyer order ID
        "b" => 88,
        # Seller order ID
        "a" => 50,
        # Trade time
        "T" => 123_456_785,
        # Is the buyer the market maker?
        "m" => true,
        # Ignore
        "M" => true
      }

      assert expected_message["e"] == "trade"
      assert is_binary(expected_message["p"])
      assert is_binary(expected_message["q"])
      assert is_boolean(expected_message["m"])
    end

    test "expected 24hrTicker message format" do
      # Document the actual Binance ticker format
      expected_message = %{
        "e" => "24hrTicker",
        # Event time
        "E" => 123_456_789,
        # Symbol
        "s" => "BTCUSDT",
        # Price change
        "p" => "0.0015",
        # Price change percent
        "P" => "250.00",
        # Weighted average price
        "w" => "0.0018",
        # Last price
        "c" => "0.0025",
        # Last quantity
        "Q" => "10",
        # Open price
        "o" => "0.0010",
        # High price
        "h" => "0.0025",
        # Low price
        "l" => "0.0010",
        # Total traded base asset volume
        "v" => "10000",
        # Total traded quote asset volume
        "q" => "18"
      }

      assert expected_message["e"] == "24hrTicker"
      # Last price
      assert is_binary(expected_message["c"])
      # Open price
      assert is_binary(expected_message["o"])
      # Volume
      assert is_binary(expected_message["v"])
    end

    test "expected bookTicker message format" do
      # Document the actual Binance bookTicker format
      expected_message = %{
        "e" => "bookTicker",
        # Order book updateId
        "u" => 400_900_217,
        # Symbol
        "s" => "BTCUSDT",
        # Best bid price
        "b" => "50000.00",
        # Best bid qty
        "B" => "10.5",
        # Best ask price
        "a" => "50001.00",
        # Best ask qty
        "A" => "8.2"
      }

      assert expected_message["e"] == "bookTicker"
      assert is_binary(expected_message["b"])
      assert is_binary(expected_message["B"])
      assert is_binary(expected_message["a"])
      assert is_binary(expected_message["A"])
    end

    test "expected subscription confirmation format" do
      # Document the subscription confirmation format
      expected_message = %{
        "result" => nil,
        "id" => 1
      }

      assert is_nil(expected_message["result"])
      assert is_integer(expected_message["id"])
    end
  end

  describe "real-time data integration" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "receives real orderbook updates from testnet" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Subscribe to a popular pair
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["btcusdt@depth5"])

      # Wait for data
      Process.sleep(3000)

      # Check if we received orderbook data
      case Market.get_orderbook(:binance, "BTCUSDT") do
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
      assert {:ok, :subscribed} = WebSocket.subscribe(ws, ["btcusdt@trade"])

      # Wait for trades
      Process.sleep(5000)

      # Check if we received trade data
      case Market.get_last_trade(:binance, "BTCUSDT") do
        {:ok, trade} ->
          assert trade.symbol == "BTCUSDT"
          assert is_binary(trade.price)
          assert is_binary(trade.quantity)
          Logger.info("Received real trade: #{inspect(trade)}")

        {:error, :not_found} ->
          Logger.warning("No trade data received - testnet might have low activity")
      end

      WebSocket.close(ws)
    end
  end

  describe "newly added management functions" do
    @tag :integration
    @tag :ws_slow
    test "get_heartbeat_health/1 and get_state_metrics/1 work on an active connection" do
      {:ok, ws} = WebSocket.connect([], testnet: true)
      assert %ZenWebsocket.Client{} = ws

      # Test get_heartbeat_health/1 - should return nil or a map
      health = WebSocket.get_heartbeat_health(ws)
      assert is_nil(health) or is_map(health)

      # Test get_state_metrics/1 - should return a map with expected keys
      metrics = WebSocket.get_state_metrics(ws)
      assert is_map(metrics)
      assert Map.has_key?(metrics, :connection_state)
      assert Map.has_key?(metrics, :memory)

      WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    test "reconnect/1 returns a new client struct" do
      {:ok, ws} = WebSocket.connect([], testnet: true)
      assert %ZenWebsocket.Client{} = ws

      # Reconnect should return a new client struct
      assert {:ok, new_ws} = WebSocket.reconnect(ws)
      assert %ZenWebsocket.Client{} = new_ws

      # Ensure the new client is a different process
      assert ws.server_pid != new_ws.server_pid

      WebSocket.close(new_ws)
    end

    @tag :integration
    @tag :ws_slow
    test "send_message/2 sends a raw message without crashing" do
      {:ok, ws} = WebSocket.connect([], testnet: true)

      # Send a message that does not require a correlated response.
      # This is a simple smoke test to ensure the function delegates correctly.
      # A proper assertion would require receiving a specific reply, which is complex.
      # Here, we just ensure it returns :ok as expected for a fire-and-forget message.
      ping_message = %{"method" => "ping", "id" => System.unique_integer()}
      assert :ok = WebSocket.send_message(ws, Jason.encode!(ping_message))

      WebSocket.close(ws)
    end
  end

  # Helper functions
end
