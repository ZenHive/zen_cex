defmodule ZenCex.Safety.OrderSafety.MarketDataHealthTest do
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.WebSocket
  alias ZenCex.Safety.OrderSafety.MarketData
  alias ZenCex.Websocket.ConnectionRegistry

  setup do
    # Ensure ConnectionRegistry is started
    case Process.whereis(ConnectionRegistry) do
      nil ->
        {:ok, _pid} = ConnectionRegistry.start_link()
        :ok

      _pid ->
        # Clear any existing registrations
        Enum.each(ConnectionRegistry.list_all(), fn %{exchange: exchange, symbol: symbol} ->
          ConnectionRegistry.unregister(exchange, symbol)
        end)

        :ok
    end
  end

  describe "ensure_websocket_connection/2" do
    @tag :integration
    test "returns :ok when connection exists and is healthy" do
      # Create and register a real healthy connection
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        ConnectionRegistry.register(:binance, "BTCUSDT", client)
        assert :ok = MarketData.ensure_websocket_connection(:binance, "BTCUSDT")
      after
        WebSocket.close(client)
      end
    end

    @tag :integration
    test "creates new connection when none exists" do
      # No registered connection - should create one
      assert :ok = MarketData.ensure_websocket_connection(:binance, "BTCUSDT")

      # Verify the connection was registered
      assert {:ok, client} = ConnectionRegistry.get(:binance, "BTCUSDT")

      # Verify it's connected
      assert {:ok, :connected} = WebSocket.get_state(client)

      # Clean up
      WebSocket.close(client)
    end

    test "handles unsupported exchange" do
      assert {:error, {:unsupported_exchange, :unknown}} =
               MarketData.ensure_websocket_connection(:unknown, "BTCUSDT")
    end

    @tag :integration
    test "successfully creates Binance connection" do
      assert :ok = MarketData.ensure_websocket_connection(:binance, "BTCUSDT")

      # Verify connection was registered
      assert {:ok, client} = ConnectionRegistry.get(:binance, "BTCUSDT")

      # Verify it's actually connected
      assert {:ok, :connected} = WebSocket.get_state(client)

      # Clean up
      WebSocket.close(client)
    end

    @tag :integration
    test "successfully creates Bybit connection" do
      # Skip if Bybit testnet credentials not configured
      case System.get_env("BYBIT_TESTNET") do
        "false" ->
          # Skip test if Bybit testnet is disabled
          :ok

        _ ->
          alias ZenCex.Adapters.Bybit.WebSocket, as: BybitWebSocket

          assert :ok = MarketData.ensure_websocket_connection(:bybit, "BTCUSDT")

          # Verify connection was registered
          assert {:ok, client} = ConnectionRegistry.get(:bybit, "BTCUSDT")

          # Verify it's actually connected (Bybit returns a map)
          assert {:ok, state} = BybitWebSocket.get_state(client)
          assert state == :connected or Map.get(state, :status) == :connected

          # Clean up
          BybitWebSocket.close(client)
      end
    end
  end

  describe "health check integration" do
    @tag :integration
    test "health check updates last_health_check timestamp" do
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        ConnectionRegistry.register(:binance, "BTCUSDT", client)

        # Initial state - no health check yet
        [conn] = ConnectionRegistry.list_all()
        assert conn.last_health_check == nil

        # Perform health check
        {:ok, health} = ConnectionRegistry.check_health(:binance, "BTCUSDT")

        # Verify health contains expected fields
        assert health.state == :connected
        assert is_map(health.heartbeat)
        assert is_map(health.metrics)
        assert is_integer(health.checked_at)

        # Give async cast time to process
        Process.sleep(50)

        # Verify timestamp was updated
        [conn] = ConnectionRegistry.list_all()
        assert conn.last_health_check
      after
        WebSocket.close(client)
      end
    end

    @tag :integration
    test "health check works with Binance adapter check_health function" do
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        # Use the adapter's check_health function directly
        health = WebSocket.check_health(client)

        assert health.state == :connected
        assert health.adapter == :binance
        assert is_map(health.heartbeat)
        assert is_map(health.metrics)
      after
        WebSocket.close(client)
      end
    end
  end

  describe "reconnection scenarios" do
    @tag :integration
    test "handles reconnection when connection dies" do
      # Create initial connection
      assert :ok = MarketData.ensure_websocket_connection(:binance, "BTCUSDT")

      # Get the connection and close it
      {:ok, client} = ConnectionRegistry.get(:binance, "BTCUSDT")
      WebSocket.close(client)

      # Wait for connection to fully close
      Process.sleep(100)

      # Try to ensure connection again - should create new one
      assert :ok = MarketData.ensure_websocket_connection(:binance, "BTCUSDT")

      # Verify new connection is registered and healthy
      {:ok, new_client} = ConnectionRegistry.get(:binance, "BTCUSDT")
      assert {:ok, :connected} = WebSocket.get_state(new_client)

      # Clean up
      WebSocket.close(new_client)
    end
  end
end
