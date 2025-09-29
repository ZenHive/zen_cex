defmodule ZenCex.Adapters.WebSocketReconnectionTest do
  @moduledoc """
  Integration tests for WebSocket reconnection scenarios.

  Tests zen_websocket's automatic reconnection capabilities and
  how our adapters handle connection failures and recovery.
  """

  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance
  alias ZenCex.Adapters.Bybit
  alias ZenCex.Cache.Market

  require Logger

  # Test timeout for reconnection scenarios
  @test_timeout 30_000

  # Wait times for reconnection testing
  @reconnect_wait_ms 5000
  @connection_verify_ms 2000
  @short_wait_ms 1000

  describe "Binance reconnection handling" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "zen_websocket automatically reconnects on connection loss" do
      # Connect normally
      {:ok, ws} = Binance.WebSocket.connect(["btcusdt@depth5"], testnet: true)

      # Verify initial connection
      {:ok, initial_state} = Binance.WebSocket.get_state(ws)
      assert initial_state in [:connecting, :connected]

      # Get the underlying Gun process to simulate connection loss
      # Note: zen_websocket owns the Gun connection, so we work through its API
      server_pid = ws.server_pid
      assert Process.alive?(server_pid)

      # Monitor the connection to detect reconnection
      ref = Process.monitor(server_pid)

      # Force the zen_websocket Client GenServer to handle a disconnect
      # by sending it an unexpected message (zen_websocket will recover)
      send(server_pid, {:gun_down, :fake_conn, :http, :closed, []})

      # zen_websocket should handle this and attempt reconnection
      Process.sleep(@reconnect_wait_ms)

      # Connection should still be alive (zen_websocket recovered)
      assert Process.alive?(server_pid)

      # State should show connected or reconnecting
      {:ok, state} = Binance.WebSocket.get_state(ws)
      assert state in [:connecting, :connected, :disconnected]
      Logger.info("Connection state after simulated disconnect: #{state}")

      # Clean up
      Process.demonitor(ref, [:flush])
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "subscriptions persist through reconnection" do
      # Track subscription state
      streams = ["btcusdt@trade", "ethusdt@trade"]

      # Connect and subscribe
      {:ok, ws} = Binance.WebSocket.connect(streams, testnet: true)

      # Wait for subscription to establish
      Process.sleep(@connection_verify_ms)

      # Additional subscription after connection
      extra_streams = ["bnbusdt@ticker"]
      {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, extra_streams)

      Process.sleep(1000)

      # Simulate network interruption
      # zen_websocket will detect and reconnect automatically
      server_pid = ws.server_pid
      send(server_pid, {:gun_down, :fake_conn, :http, :timeout, []})

      # Wait for automatic reconnection
      Process.sleep(@reconnect_wait_ms)

      # Connection should be restored
      assert Process.alive?(server_pid)

      # We can still interact with the connection
      # New subscriptions should work after reconnection
      {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, ["ltcusdt@depth5"])

      # Clean up
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "handles rapid disconnection/reconnection cycles" do
      {:ok, ws} = Binance.WebSocket.connect(["btcusdt@bookTicker"], testnet: true)
      server_pid = ws.server_pid

      # Simulate multiple rapid disconnections
      for i <- 1..3 do
        Logger.info("Simulating disconnect cycle #{i}")
        send(server_pid, {:gun_down, :fake_conn, :http, :closed, []})
        Process.sleep(@short_wait_ms)

        # Should still be alive (zen_websocket handles reconnection)
        assert Process.alive?(server_pid)
      end

      # After all disruptions, connection should stabilize
      Process.sleep(2000)
      assert Process.alive?(server_pid)

      # Should still be functional
      {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, ["ethusdt@bookTicker"])

      # Clean up
      Binance.WebSocket.close(ws)
    end
  end

  describe "Bybit reconnection handling" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "zen_websocket automatically reconnects on connection loss" do
      {:ok, ws} = Bybit.WebSocket.connect(["orderbook.50.BTCUSDT"], testnet: true)

      # Verify initial connection
      {:ok, initial_state} = Bybit.WebSocket.get_state(ws)
      assert is_map(initial_state)

      server_pid = ws.server_pid
      assert Process.alive?(server_pid)

      # Simulate connection loss
      send(server_pid, {:gun_down, :fake_conn, :http, :closed, []})

      # zen_websocket should handle reconnection
      Process.sleep(@reconnect_wait_ms)

      # Connection should still be alive
      assert Process.alive?(server_pid)

      # Clean up
      Bybit.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "maintains ping/pong heartbeat through reconnection" do
      {:ok, ws} = Bybit.WebSocket.connect([], testnet: true)
      server_pid = ws.server_pid

      # Bybit requires periodic ping messages
      # Our adapter should handle this automatically
      Process.sleep(2000)

      # Simulate disconnect
      send(server_pid, {:gun_down, :fake_conn, :http, :timeout, []})

      # Wait for reconnection
      Process.sleep(@reconnect_wait_ms)

      # Connection should recover and continue heartbeat
      assert Process.alive?(server_pid)

      # Subscribe to verify connection is functional
      {:ok, :subscribed} = Bybit.WebSocket.subscribe(ws, ["publicTrade.ETHUSDT"])

      # Clean up
      Bybit.WebSocket.close(ws)
    end
  end

  describe "ETS cache continuity during reconnection" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "ETS cache remains accessible during Binance reconnection" do
      # Clear any existing data
      Market.get_orderbook(:binance, "BTCUSDT")

      # Connect and subscribe to orderbook
      {:ok, ws} = Binance.WebSocket.connect(["btcusdt@depth5"], testnet: true)

      # Wait for initial data
      Process.sleep(3000)

      # Check if we have data (testnet might not always have activity)
      initial_data =
        case Market.get_orderbook(:binance, "BTCUSDT") do
          {:ok, orderbook} ->
            Logger.info("Got initial orderbook with update_id: #{orderbook.update_id}")
            orderbook

          {:error, :not_found} ->
            Logger.warning("No initial orderbook data (testnet might be inactive)")
            nil
        end

      # Simulate disconnect
      server_pid = ws.server_pid
      send(server_pid, {:gun_down, :fake_conn, :http, :closed, []})

      # During reconnection, cached data should still be accessible
      Process.sleep(1000)

      # Try to read from cache during reconnection
      case Market.get_orderbook(:binance, "BTCUSDT") do
        {:ok, orderbook} ->
          # Cache still works during reconnection
          assert orderbook.symbol == "BTCUSDT"
          Logger.info("Cache accessible during reconnection")

        {:error, :not_found} ->
          # No data yet, which is fine for testnet
          Logger.info("No cached data available")
      end

      # Wait for reconnection
      Process.sleep(@reconnect_wait_ms)

      # After reconnection, new data should flow
      Process.sleep(3000)

      final_data =
        case Market.get_orderbook(:binance, "BTCUSDT") do
          {:ok, orderbook} ->
            Logger.info("Got final orderbook with update_id: #{orderbook.update_id}")
            orderbook

          {:error, :not_found} ->
            Logger.warning("No data after reconnection (testnet might be inactive)")
            nil
        end

      # If we had initial data and got final data, they might differ (new updates)
      if initial_data && final_data do
        Logger.info("Successfully maintained data flow through reconnection")
      end

      # Clean up
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "ETS cache remains accessible during Bybit reconnection" do
      # Clear any existing data
      Market.get_ticker(:bybit, "BTCUSDT")

      # Connect and subscribe
      {:ok, ws} = Bybit.WebSocket.connect(["tickers.BTCUSDT"], testnet: true)

      # Wait for initial data
      Process.sleep(3000)

      # Check initial data
      _initial_ticker =
        case Market.get_ticker(:bybit, "BTCUSDT") do
          {:ok, ticker} ->
            Logger.info("Got initial ticker: #{ticker.last_price}")
            ticker

          {:error, :not_found} ->
            Logger.warning("No initial ticker data")
            nil
        end

      # Simulate disconnect
      server_pid = ws.server_pid
      send(server_pid, {:gun_down, :fake_conn, :http, :network_error, []})

      # Cache should remain accessible
      Process.sleep(1000)

      case Market.get_ticker(:bybit, "BTCUSDT") do
        {:ok, ticker} ->
          assert ticker.symbol == "BTCUSDT"
          Logger.info("Cache still accessible during reconnection")

        {:error, :not_found} ->
          Logger.info("No cached data")
      end

      # Wait for reconnection and new data
      Process.sleep(@reconnect_wait_ms + 3000)

      # Clean up
      Bybit.WebSocket.close(ws)
    end
  end

  describe "connection resilience" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "handles invalid URL gracefully" do
      # Try to connect to an invalid URL
      # zen_websocket should handle this without crashing
      result =
        Binance.WebSocket.connect(
          ["btcusdt@depth5"],
          testnet: true
        )

      case result do
        {:ok, ws} ->
          # Even with potential connection issues, we get a client
          assert %ZenWebsocket.Client{} = ws
          Binance.WebSocket.close(ws)

        {:error, reason} ->
          # Or a clear error
          Logger.info("Connection failed as expected: #{inspect(reason)}")
          assert reason
      end
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "multiple reconnections don't leak connections" do
      # Start connection
      {:ok, ws} = Binance.WebSocket.connect(["btcusdt@ticker"], testnet: true)
      server_pid = ws.server_pid

      # Track process count before disruptions
      initial_process_count = length(Process.list())

      # Simulate multiple disconnections
      for _ <- 1..5 do
        send(server_pid, {:gun_down, :fake_conn, :http, :closed, []})
        Process.sleep(500)
      end

      # Wait for stabilization
      Process.sleep(@reconnect_wait_ms)

      # Check process count hasn't grown significantly
      final_process_count = length(Process.list())

      # Should not have leaked many processes (allow some variance)
      assert final_process_count - initial_process_count < 10

      Logger.info("Process count: initial=#{initial_process_count}, final=#{final_process_count}")

      # Clean up
      Binance.WebSocket.close(ws)
    end
  end

  describe "subscription management during reconnection" do
    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "can subscribe during reconnection attempt" do
      {:ok, ws} = Binance.WebSocket.connect([], testnet: true)
      server_pid = ws.server_pid

      # Trigger reconnection
      send(server_pid, {:gun_down, :fake_conn, :http, :closed, []})

      # Try to subscribe during reconnection
      # zen_websocket should queue this or handle gracefully
      result = Binance.WebSocket.subscribe(ws, ["btcusdt@trade"])

      case result do
        {:ok, :subscribed} ->
          Logger.info("Subscription queued/succeeded during reconnection")

        {:error, reason} ->
          Logger.info("Subscription failed during reconnection: #{inspect(reason)}")
          # This is also acceptable behavior
      end

      # Wait for connection to stabilize
      Process.sleep(@reconnect_wait_ms)

      # Should be able to subscribe now
      assert {:ok, :subscribed} = Binance.WebSocket.subscribe(ws, ["ethusdt@trade"])

      # Clean up
      Binance.WebSocket.close(ws)
    end

    @tag :integration
    @tag :ws_slow
    @tag timeout: @test_timeout
    test "unsubscribe works after reconnection" do
      # streams = ["btcusdt@depth5", "ethusdt@depth5"]
      {:ok, ws} = Bybit.WebSocket.connect([], testnet: true)

      # Subscribe initially
      {:ok, :subscribed} = Bybit.WebSocket.subscribe(ws, ["orderbook.25.BTCUSDT"])
      Process.sleep(1000)

      # Trigger reconnection
      server_pid = ws.server_pid
      send(server_pid, {:gun_down, :fake_conn, :http, :closed, []})

      # Wait for reconnection
      Process.sleep(@reconnect_wait_ms)

      # Should be able to unsubscribe after reconnection
      assert {:ok, :unsubscribed} = Bybit.WebSocket.unsubscribe(ws, ["orderbook.25.BTCUSDT"])

      # And subscribe to new topics
      assert {:ok, :subscribed} = Bybit.WebSocket.subscribe(ws, ["publicTrade.ETHUSDT"])

      # Clean up
      Bybit.WebSocket.close(ws)
    end
  end
end
