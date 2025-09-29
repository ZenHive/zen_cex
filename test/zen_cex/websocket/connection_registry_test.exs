defmodule ZenCex.Websocket.ConnectionRegistryTest do
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.WebSocket
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

  describe "register/3 with real connections" do
    @tag :integration
    test "registers a real WebSocket connection" do
      # Create a real connection to testnet
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        assert :ok = ConnectionRegistry.register(:binance, "BTCUSDT", client)
        assert {:ok, ^client} = ConnectionRegistry.get(:binance, "BTCUSDT")
      after
        WebSocket.close(client)
      end
    end

    @tag :integration
    test "overwrites existing connection for same exchange/symbol" do
      {:ok, client1} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)
      {:ok, client2} = WebSocket.connect(["btcusdt@depth5"], testnet: true, supervised: false)

      try do
        assert :ok = ConnectionRegistry.register(:binance, "BTCUSDT", client1)
        assert :ok = ConnectionRegistry.register(:binance, "BTCUSDT", client2)
        assert {:ok, ^client2} = ConnectionRegistry.get(:binance, "BTCUSDT")
      after
        WebSocket.close(client1)
        WebSocket.close(client2)
      end
    end

    @tag :integration
    test "allows different symbols for same exchange" do
      {:ok, client1} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)
      {:ok, client2} = WebSocket.connect(["ethusdt@ticker"], testnet: true, supervised: false)

      try do
        assert :ok = ConnectionRegistry.register(:binance, "BTCUSDT", client1)
        assert :ok = ConnectionRegistry.register(:binance, "ETHUSDT", client2)
        assert {:ok, ^client1} = ConnectionRegistry.get(:binance, "BTCUSDT")
        assert {:ok, ^client2} = ConnectionRegistry.get(:binance, "ETHUSDT")
      after
        WebSocket.close(client1)
        WebSocket.close(client2)
      end
    end
  end

  describe "unregister/2" do
    @tag :integration
    test "removes a registered connection" do
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        assert :ok = ConnectionRegistry.register(:binance, "BTCUSDT", client)
        assert :ok = ConnectionRegistry.unregister(:binance, "BTCUSDT")
        assert {:error, :not_found} = ConnectionRegistry.get(:binance, "BTCUSDT")
      after
        WebSocket.close(client)
      end
    end

    test "returns :ok even if connection doesn't exist" do
      assert :ok = ConnectionRegistry.unregister(:binance, "NONEXISTENT")
    end
  end

  describe "get/2" do
    @tag :integration
    test "returns registered connection" do
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        assert :ok = ConnectionRegistry.register(:binance, "BTCUSDT", client)
        assert {:ok, ^client} = ConnectionRegistry.get(:binance, "BTCUSDT")
      after
        WebSocket.close(client)
      end
    end

    test "returns error for unregistered connection" do
      assert {:error, :not_found} = ConnectionRegistry.get(:binance, "UNREGISTERED")
    end
  end

  describe "list_all/0" do
    test "returns empty list when no connections" do
      assert [] = ConnectionRegistry.list_all()
    end

    @tag :integration
    test "returns all registered connections" do
      {:ok, client1} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)
      {:ok, client2} = WebSocket.connect(["ethusdt@ticker"], testnet: true, supervised: false)

      try do
        ConnectionRegistry.register(:binance, "BTCUSDT", client1)
        ConnectionRegistry.register(:binance, "ETHUSDT", client2)

        all = ConnectionRegistry.list_all()
        assert length(all) == 2

        assert Enum.any?(all, fn conn ->
                 conn.exchange == :binance && conn.symbol == "BTCUSDT"
               end)

        assert Enum.any?(all, fn conn ->
                 conn.exchange == :binance && conn.symbol == "ETHUSDT"
               end)
      after
        WebSocket.close(client1)
        WebSocket.close(client2)
      end
    end
  end

  describe "check_health/2 with real connections" do
    @tag :integration
    test "returns health info for registered connection" do
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        ConnectionRegistry.register(:binance, "BTCUSDT", client)

        assert {:ok, health} = ConnectionRegistry.check_health(:binance, "BTCUSDT")
        assert health.state == :connected
        assert Map.has_key?(health, :heartbeat)
        assert Map.has_key?(health, :metrics)
        assert is_integer(health.checked_at)
      after
        WebSocket.close(client)
      end
    end

    test "returns error for unregistered connection" do
      assert {:error, :not_found} = ConnectionRegistry.check_health(:binance, "UNREGISTERED")
    end

    @tag :integration
    test "health check updates last_health_check timestamp" do
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)

      try do
        ConnectionRegistry.register(:binance, "BTCUSDT", client)

        # Initial state - no health check yet
        [conn] = ConnectionRegistry.list_all()
        assert conn.last_health_check == nil

        # Perform health check
        {:ok, _health} = ConnectionRegistry.check_health(:binance, "BTCUSDT")

        # Give async cast time to process
        Process.sleep(50)

        # Verify timestamp was updated
        [conn] = ConnectionRegistry.list_all()
        assert conn.last_health_check
      after
        WebSocket.close(client)
      end
    end
  end

  describe "cleanup with real connections" do
    @tag :integration
    @tag :slow
    test "removes connections when GenServer stops" do
      {:ok, client} = WebSocket.connect(["btcusdt@ticker"], testnet: true, supervised: false)
      ConnectionRegistry.register(:binance, "BTCUSDT", client)

      # Close the connection (kills the GenServer)
      WebSocket.close(client)

      # Wait a moment for process to fully terminate
      Process.sleep(100)

      # Trigger cleanup
      send(Process.whereis(ConnectionRegistry), :cleanup_stale)

      # Give cleanup time to run
      Process.sleep(100)

      # Dead connection should be removed
      assert {:error, :not_found} = ConnectionRegistry.get(:binance, "BTCUSDT")
    end
  end

  describe "concurrent operations" do
    @tag :integration
    test "handles concurrent registrations" do
      # Create multiple connections concurrently
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            symbol = "test#{i}usdt"
            {:ok, client} = WebSocket.connect(["#{symbol}@ticker"], testnet: true, supervised: false)
            ConnectionRegistry.register(:binance, "TEST#{i}USDT", client)
            {i, client}
          end)
        end)

      results = Enum.map(tasks, &Task.await(&1, 10_000))

      try do
        # All clients should be registered
        Enum.each(results, fn {i, client} ->
          assert {:ok, ^client} = ConnectionRegistry.get(:binance, "TEST#{i}USDT")
        end)
      after
        # Clean up all connections
        Enum.each(results, fn {_i, client} ->
          WebSocket.close(client)
        end)
      end
    end
  end
end
