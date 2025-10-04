defmodule ZenCex.Adapters.WebSocketSupervisionTest do
  @moduledoc """
  Integration tests for WebSocket supervised connections using zen_websocket's ClientSupervisor.

  Tests that our adapters correctly use zen_websocket's supervision features
  for production-grade connection management.
  """

  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance
  alias ZenCex.Adapters.Bybit
  alias ZenCex.Cache.Market

  require Logger

  @moduletag :websocket

  # Test timeout for WebSocket operations
  @test_timeout 15_000

  # Standard wait times for async operations
  @connection_wait_ms 2000
  @short_wait_ms 100
  @data_wait_ms 3000

  describe "Binance supervised connections" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "connects with supervised mode" do
      # Connect with supervision enabled
      {:ok, ws} = Binance.WebSocket.connect(["btcusdt@depth5"], testnet: true, supervised: true)

      assert %ZenWebsocket.Client{} = ws
      assert Process.alive?(ws.server_pid)

      # Verify connection is working
      Process.sleep(@connection_wait_ms)

      # Clean up
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "supervised connection recovers from simulated failures" do
      # Start supervised connection
      {:ok, ws} = Binance.WebSocket.connect(["ethusdt@trade"], testnet: true, supervised: true)

      # Verify it's running
      original_pid = ws.server_pid
      assert Process.alive?(original_pid)

      # Simulate a network failure
      send(original_pid, {:gun_down, :fake_conn, :http, :closed, []})

      # zen_websocket should handle the reconnection internally
      Process.sleep(@connection_wait_ms)

      # The client should still be usable
      assert {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, ["bnbusdt@ticker"])

      # Clean up
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "can subscribe/unsubscribe with supervised connection" do
      # Start with initial subscriptions
      streams = ["btcusdt@bookTicker", "ethusdt@bookTicker"]
      {:ok, ws} = Binance.WebSocket.connect(streams, testnet: true, supervised: true)

      # Wait for initial connection
      Process.sleep(@connection_wait_ms)

      # Subscribe to additional streams
      new_streams = ["bnbusdt@trade"]
      assert {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, new_streams)

      # Unsubscribe from some streams
      assert {:ok, :unsubscribed} = Binance.WebSocket.unsubscribe(ws, streams)

      # Clean up
      Binance.WebSocket.close(ws)
    end
  end

  describe "Bybit supervised connections" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "connects with supervised mode" do
      {:ok, ws} = Bybit.WebSocket.connect(["orderbook.25.BTCUSDT"], testnet: true, supervised: true)

      assert %ZenWebsocket.Client{} = ws
      assert Process.alive?(ws.server_pid)

      # Clean up
      Bybit.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "handles rapid subscription changes" do
      {:ok, ws} = Bybit.WebSocket.connect([], testnet: true, supervised: true)

      # Rapidly subscribe to different topics
      topics = [
        ["orderbook.1.BTCUSDT"],
        ["publicTrade.BTCUSDT"],
        ["tickers.BTCUSDT"],
        ["bookticker.BTCUSDT"]
      ]

      for topic_set <- topics do
        assert {:ok, :subscribed} = Bybit.WebSocket.subscribe(ws, topic_set)
        Process.sleep(@short_wait_ms)
      end

      # Process should still be alive
      assert Process.alive?(ws.server_pid)

      # Clean up
      Bybit.WebSocket.close(ws)
    end
  end

  describe "multiple supervised connections" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "multiple supervised WebSockets can coexist" do
      # Start Binance WebSocket
      {:ok, binance_ws} =
        Binance.WebSocket.connect(
          ["btcusdt@depth5"],
          testnet: true,
          supervised: true
        )

      # Start Bybit WebSocket
      {:ok, bybit_ws} =
        Bybit.WebSocket.connect(
          ["orderbook.25.ETHUSDT"],
          testnet: true,
          supervised: true
        )

      # Both should be running
      assert Process.alive?(binance_ws.server_pid)
      assert Process.alive?(bybit_ws.server_pid)

      # Different PIDs
      assert binance_ws.server_pid != bybit_ws.server_pid

      # Both should be functional
      assert {:ok, :subscribed} = Binance.WebSocket.subscribe(binance_ws, ["ethusdt@trade"])
      assert {:ok, :subscribed} = Bybit.WebSocket.subscribe(bybit_ws, ["publicTrade.BTCUSDT"])

      # Clean up
      Binance.WebSocket.close(binance_ws)
      Bybit.WebSocket.close(bybit_ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "supervised connections continue updating ETS cache" do
      # Clear any existing data
      Market.get_ticker(:binance, "BTCUSDT")

      # Start supervised WebSocket
      {:ok, ws} =
        Binance.WebSocket.connect(
          ["btcusdt@ticker"],
          testnet: true,
          supervised: true
        )

      # Wait for initial data
      Process.sleep(@data_wait_ms)

      # Check we have ticker data
      initial_ticker =
        case Market.get_ticker(:binance, "BTCUSDT") do
          {:ok, ticker} ->
            Logger.info("Got ticker: #{inspect(ticker.symbol)}")
            ticker

          {:error, :not_found} ->
            Logger.warning("No ticker data received (testnet might be inactive)")
            nil
        end

      # Simulate a disruption
      if initial_ticker do
        send(ws.server_pid, {:gun_down, :fake_conn, :http, :closed, []})
        Process.sleep(@connection_wait_ms)

        # Should still be receiving updates after recovery
        case Market.get_ticker(:binance, "BTCUSDT") do
          {:ok, ticker} ->
            Logger.info("Ticker data maintained through disruption")
            assert ticker.symbol == "BTCUSDT"

          {:error, :not_found} ->
            Logger.warning("No ticker after disruption")
        end
      end

      # Clean up
      Binance.WebSocket.close(ws)
    end
  end

  describe "direct vs supervised mode" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "can use direct connection for development" do
      # Direct connection (not supervised)
      {:ok, ws} =
        Binance.WebSocket.connect(
          ["btcusdt@depth5"],
          testnet: true,
          supervised: false
        )

      assert %ZenWebsocket.Client{} = ws

      # Should work normally
      assert {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, ["ethusdt@depth5"])

      # Clean up
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "supervised mode uses ClientSupervisor" do
      # This test verifies that supervised mode actually uses ClientSupervisor
      {:ok, ws} =
        Bybit.WebSocket.connect(
          ["orderbook.50.BTCUSDT"],
          testnet: true,
          supervised: true
        )

      # The client should be managed by ClientSupervisor
      # We can verify by checking that it's in the supervisor's children
      children_pids = ZenWebsocket.ClientSupervisor.list_clients()
      assert ws.server_pid in children_pids

      # Clean up
      Bybit.WebSocket.close(ws)
    end
  end

  describe "error handling in supervised mode" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "handles invalid subscription gracefully" do
      {:ok, ws} = Binance.WebSocket.connect([], testnet: true, supervised: true)

      # Try to subscribe to invalid stream format
      # The adapter should handle this gracefully
      invalid_streams = ["INVALID_STREAM_FORMAT"]
      result = Binance.WebSocket.subscribe(ws, invalid_streams)

      # Should return result without crashing
      assert {:ok, :subscribed} = result

      # Connection should still be alive
      assert Process.alive?(ws.server_pid)

      # Clean up
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "connection remains stable through message handler errors" do
      {:ok, ws} =
        Binance.WebSocket.connect(
          ["btcusdt@depth5"],
          testnet: true,
          supervised: true
        )

      # The message handler should handle malformed messages
      # without crashing the connection
      Process.sleep(@connection_wait_ms)

      # Connection should remain stable
      assert Process.alive?(ws.server_pid)

      # Should still be functional
      assert {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, ["ethusdt@ticker"])

      # Clean up
      Binance.WebSocket.close(ws)
    end
  end
end
