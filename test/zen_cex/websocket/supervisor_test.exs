defmodule ZenCex.WebSocket.SupervisorTest do
  use ExUnit.Case, async: false

  alias ZenCex.Cache.Market
  alias ZenCex.WebSocket.Supervisor

  @moduletag :integration

  setup do
    # Ensure supervisor is running (started by application)
    assert Process.whereis(Supervisor)

    # Clean up any existing test connections
    on_exit(fn ->
      Supervisor.stop_connection(:binance, :test_connection)
      Supervisor.stop_connection(:bybit, :test_connection)
    end)

    :ok
  end

  describe "start_connection/3" do
    test "starts a WebSocket connection successfully" do
      assert {:ok, pid} =
               Supervisor.start_connection(
                 :binance,
                 :test_connection,
                 symbols: ["BTCUSDT"],
                 streams: [:book_ticker],
                 testnet: false
               )

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify connection is registered
      assert Supervisor.connection_active?(:binance, :test_connection)
    end

    test "returns existing connection if already started" do
      # Start first connection
      {:ok, pid1} =
        Supervisor.start_connection(
          :binance,
          :test_connection,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      # Try to start same connection again
      {:ok, pid2} =
        Supervisor.start_connection(
          :binance,
          :test_connection,
          # Different config should be ignored
          symbols: ["ETHUSDT"],
          streams: [:orderbook]
        )

      # Should return same PID
      assert pid1 == pid2
    end

    test "starts multiple connections for different names" do
      assert {:ok, pid1} =
               Supervisor.start_connection(
                 :binance,
                 :test_connection_1,
                 symbols: ["BTCUSDT"],
                 streams: [:book_ticker]
               )

      assert {:ok, pid2} =
               Supervisor.start_connection(
                 :binance,
                 :test_connection_2,
                 symbols: ["ETHUSDT"],
                 streams: [:book_ticker]
               )

      assert pid1 != pid2
      assert Supervisor.connection_active?(:binance, :test_connection_1)
      assert Supervisor.connection_active?(:binance, :test_connection_2)
    end

    test "supports different exchanges" do
      assert {:ok, binance_pid} =
               Supervisor.start_connection(
                 :binance,
                 :test_connection,
                 symbols: ["BTCUSDT"],
                 streams: [:book_ticker]
               )

      assert {:ok, bybit_pid} =
               Supervisor.start_connection(
                 :bybit,
                 :test_connection,
                 symbols: ["BTCUSDT"],
                 streams: [:orderbook]
               )

      assert binance_pid != bybit_pid
      assert Supervisor.connection_active?(:binance, :test_connection)
      assert Supervisor.connection_active?(:bybit, :test_connection)
    end

    test "raises for unsupported exchange" do
      assert_raise RuntimeError, "Unsupported exchange: kraken", fn ->
        Supervisor.start_connection(:kraken, :test_connection)
      end
    end
  end

  describe "stop_connection/2" do
    test "stops an active connection" do
      # Start a connection
      {:ok, pid} =
        Supervisor.start_connection(
          :binance,
          :test_connection,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      assert Process.alive?(pid)

      # Stop the connection
      assert :ok = Supervisor.stop_connection(:binance, :test_connection)

      # Wait a bit for termination
      Process.sleep(100)

      # Verify it's stopped
      refute Process.alive?(pid)
      refute Supervisor.connection_active?(:binance, :test_connection)
    end

    test "returns error for non-existent connection" do
      assert {:error, :not_found} = Supervisor.stop_connection(:binance, :non_existent)
    end
  end

  describe "connection_active?/2" do
    test "returns true for active connection" do
      {:ok, _pid} =
        Supervisor.start_connection(
          :binance,
          :test_connection,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      assert Supervisor.connection_active?(:binance, :test_connection)
    end

    test "returns false for non-existent connection" do
      refute Supervisor.connection_active?(:binance, :non_existent)
    end

    test "returns false after connection is stopped" do
      {:ok, _pid} =
        Supervisor.start_connection(
          :binance,
          :test_connection,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      assert Supervisor.connection_active?(:binance, :test_connection)

      Supervisor.stop_connection(:binance, :test_connection)
      Process.sleep(100)

      refute Supervisor.connection_active?(:binance, :test_connection)
    end
  end

  describe "get_connection_pid/2" do
    test "returns PID for active connection" do
      {:ok, expected_pid} =
        Supervisor.start_connection(
          :binance,
          :test_connection,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      assert {:ok, actual_pid} = Supervisor.get_connection_pid(:binance, :test_connection)
      assert expected_pid == actual_pid
    end

    test "returns error for non-existent connection" do
      assert {:error, :not_found} = Supervisor.get_connection_pid(:binance, :non_existent)
    end
  end

  describe "list_connections/0" do
    test "returns empty list when no connections" do
      # Make sure we start clean
      Supervisor.stop_connection(:binance, :test_connection)
      Supervisor.stop_connection(:bybit, :test_connection)
      Process.sleep(100)

      connections = Supervisor.list_connections()

      # Filter out our test connections
      test_connections =
        Enum.filter(connections, fn
          {{:binance, :test_connection}, _} -> true
          {{:bybit, :test_connection}, _} -> true
          _ -> false
        end)

      assert test_connections == []
    end

    test "lists all active connections" do
      # Start multiple connections
      {:ok, _} =
        Supervisor.start_connection(
          :binance,
          :test_connection_1,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      {:ok, _} =
        Supervisor.start_connection(
          :binance,
          :test_connection_2,
          symbols: ["ETHUSDT"],
          streams: [:book_ticker]
        )

      {:ok, _} =
        Supervisor.start_connection(
          :bybit,
          :test_connection_3,
          symbols: ["BTCUSDT"],
          streams: [:orderbook]
        )

      connections = Supervisor.list_connections()

      # Check our test connections are listed
      assert {{:binance, :test_connection_1}, _} =
               Enum.find(connections, fn {{exchange, name}, _} ->
                 exchange == :binance and name == :test_connection_1
               end)

      assert {{:binance, :test_connection_2}, _} =
               Enum.find(connections, fn {{exchange, name}, _} ->
                 exchange == :binance and name == :test_connection_2
               end)

      assert {{:bybit, :test_connection_3}, _} =
               Enum.find(connections, fn {{exchange, name}, _} ->
                 exchange == :bybit and name == :test_connection_3
               end)

      # Clean up
      Supervisor.stop_connection(:binance, :test_connection_1)
      Supervisor.stop_connection(:binance, :test_connection_2)
      Supervisor.stop_connection(:bybit, :test_connection_3)
    end
  end

  describe "restart_connection/2" do
    test "restarts an existing connection" do
      # Start a connection
      {:ok, old_pid} =
        Supervisor.start_connection(
          :binance,
          :test_connection,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      # Restart it
      assert {:ok, new_pid} = Supervisor.restart_connection(:binance, :test_connection)

      # Should get a different PID
      assert old_pid != new_pid

      # Old PID should be dead
      refute Process.alive?(old_pid)

      # New connection should be active
      assert Process.alive?(new_pid)
      assert Supervisor.connection_active?(:binance, :test_connection)
    end

    test "returns error when restarting non-existent connection" do
      assert {:error, :not_found} = Supervisor.restart_connection(:binance, :non_existent)
    end
  end

  describe "data flow integration" do
    @tag :integration
    @tag timeout: 10_000
    test "WebSocket data flows to ETS cache" do
      # Start a connection for real market data
      {:ok, _pid} =
        Supervisor.start_connection(
          :binance,
          :test_data_flow,
          symbols: ["BTCUSDT", "ETHUSDT"],
          streams: [:book_ticker],
          testnet: false
        )

      # Wait for data to arrive
      Process.sleep(5_000)

      # Check if we have ticker data in cache
      assert {:ok, btc_ticker} = Market.get_book_ticker(:binance, "BTCUSDT")
      assert btc_ticker.bid_price
      assert btc_ticker.ask_price
      assert btc_ticker.bid_qty
      assert btc_ticker.ask_qty

      assert {:ok, eth_ticker} = Market.get_book_ticker(:binance, "ETHUSDT")
      assert eth_ticker.bid_price
      assert eth_ticker.ask_price

      # Clean up
      Supervisor.stop_connection(:binance, :test_data_flow)
    end
  end

  describe "error handling" do
    @tag :integration
    test "handles WebSocket connection failures gracefully" do
      # Start with invalid URL to trigger connection failure
      {:ok, pid} =
        Supervisor.start_connection(
          :binance,
          :test_error,
          symbols: ["INVALID"],
          streams: [:book_ticker],
          # Invalid URL
          url: "wss://invalid.example.com"
        )

      # Connection worker should still be alive (attempting reconnects)
      assert Process.alive?(pid)

      # Clean up
      Supervisor.stop_connection(:binance, :test_error)
    end

    test "supervisor restarts failed workers" do
      # Start a connection
      {:ok, pid} =
        Supervisor.start_connection(
          :binance,
          :test_restart,
          symbols: ["BTCUSDT"],
          streams: [:book_ticker]
        )

      # Kill the worker process (simulate crash)
      Process.exit(pid, :kill)

      # Wait a bit for supervisor to restart it
      Process.sleep(1000)

      # Connection should still be active (with new PID)
      assert Supervisor.connection_active?(:binance, :test_restart)

      case Supervisor.get_connection_pid(:binance, :test_restart) do
        {:ok, new_pid} ->
          assert new_pid != pid
          assert Process.alive?(new_pid)

        {:error, :not_found} ->
          # Worker might be in restart cycle
          Process.sleep(2000)

          # Try again
          assert Supervisor.connection_active?(:binance, :test_restart)
      end

      # Clean up
      Supervisor.stop_connection(:binance, :test_restart)
    end
  end
end
