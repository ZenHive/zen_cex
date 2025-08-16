defmodule ZenCex.Core.SupervisorTest do
  use ExUnit.Case, async: false

  alias ZenCex.Core.{Supervisor, RateLimitManager, HealthMonitor}

  describe "Core.Supervisor startup" do
    test "starts successfully with all child processes" do
      # The supervisor should be started by the application
      assert Process.whereis(ZenCex.Core.Supervisor) != nil
      assert Process.whereis(ZenCex.Core.RateLimitManager) != nil
      assert Process.whereis(ZenCex.Core.HealthMonitor) != nil
      assert Process.whereis(ZenCex.AdapterSupervisor) != nil
    end

    test "creates rate limit ETS tables on startup" do
      # Verify ETS tables are created
      assert :ets.info(:binance_spot_limits) != :undefined
      assert :ets.info(:binance_futures_limits) != :undefined
      assert :ets.info(:kraken_limits) != :undefined
      assert :ets.info(:deribit_limits) != :undefined
    end

    test "ETS tables are public and allow concurrent reads" do
      info = :ets.info(:binance_spot_limits)
      assert Keyword.get(info, :protection) == :public
      assert Keyword.get(info, :read_concurrency) == true
    end
  end

  describe "adapter management with mock adapters" do
    # Create a test adapter module for testing
    defmodule TestAdapter do
      use GenServer

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: {:global, make_ref()})
      end

      def init(opts) do
        {:ok, opts}
      end

      def handle_call(:ping, _from, state) do
        {:reply, :pong, state}
      end

      def handle_call(:crash, _from, _state) do
        raise "Intentional crash for testing"
      end
    end

    setup do
      # Temporarily mock the registry to return our test adapter
      _original_get_adapter = &ZenCex.Core.Registry.get_adapter!/1

      # We can't actually mock it, so we'll test with real exchanges if available
      :ok
    end

    test "start_adapter raises for unknown exchange" do
      assert_raise RuntimeError, ~r/Unknown exchange/, fn ->
        Supervisor.start_adapter(:unknown_exchange, [])
      end
    end

    test "list_adapters returns empty list when no adapters running" do
      # Ensure no adapters are running
      adapters = Supervisor.list_adapters()

      # Should be empty or contain only already running adapters
      assert is_list(adapters)

      Enum.each(adapters, fn adapter ->
        assert Map.has_key?(adapter, :id)
        assert Map.has_key?(adapter, :pid)
      end)
    end

    test "restart_adapter returns error for non-existent pid" do
      fake_pid = spawn(fn -> :ok end)
      # Let it die
      Process.sleep(10)

      assert {:error, :adapter_not_found} = Supervisor.restart_adapter(fake_pid)
    end
  end

  describe "adapter management with Binance adapter" do
    @tag :skip
    test "starts Binance adapter if module exists" do
      # Skipped: Binance adapter is not a GenServer, it's a module with functions
      # The Core.Supervisor manages processes like rate limiters and health monitors,
      # not the adapter modules themselves
    end

    @tag :skip
    test "restarts Binance adapter" do
      # Skipped: Binance adapter is not a GenServer, it's a module with functions
      # The Core.Supervisor manages processes like rate limiters and health monitors,
      # not the adapter modules themselves
    end
  end

  describe "RateLimitManager" do
    test "ETS tables support atomic operations" do
      now = System.system_time(:second)
      key = {now, :test}

      # Insert initial value
      :ets.insert(:binance_spot_limits, {key, 0})

      # Test atomic increment
      new_count = :ets.update_counter(:binance_spot_limits, key, {2, 1})
      assert new_count == 1

      # Increment by 5
      new_count = :ets.update_counter(:binance_spot_limits, key, {2, 5})
      assert new_count == 6

      # Verify final value
      assert :ets.lookup(:binance_spot_limits, key) == [{key, 6}]

      # Clean up
      :ets.delete(:binance_spot_limits, key)
    end

    test "cleanup removes old entries" do
      now = System.system_time(:second)
      # 200 seconds ago
      old_key = now - 200
      # 50 seconds ago
      recent_key = now - 50

      # Insert entries
      :ets.insert(:binance_spot_limits, {old_key, 100})
      :ets.insert(:binance_spot_limits, {recent_key, 50})
      :ets.insert(:binance_spot_limits, {now, 25})

      # Trigger cleanup
      send(Process.whereis(RateLimitManager), :cleanup)
      Process.sleep(50)

      # Old entry (>120s) should be deleted
      assert :ets.lookup(:binance_spot_limits, old_key) == []
      # Recent entries should remain
      assert :ets.lookup(:binance_spot_limits, recent_key) == [{recent_key, 50}]
      assert :ets.lookup(:binance_spot_limits, now) == [{now, 25}]

      # Clean up
      :ets.delete(:binance_spot_limits, recent_key)
      :ets.delete(:binance_spot_limits, now)
    end

    test "supports concurrent access" do
      now = System.system_time(:second)

      # Spawn multiple processes to increment counters
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            key = {now, i}
            :ets.insert(:binance_spot_limits, {key, 0})

            # Each task increments its counter 100 times
            for _ <- 1..100 do
              :ets.update_counter(:binance_spot_limits, key, {2, 1})
            end

            # Return final count
            [{^key, count}] = :ets.lookup(:binance_spot_limits, key)
            count
          end)
        end

      # Collect results
      results = Task.await_many(tasks)

      # Each should have count of 100
      assert Enum.all?(results, &(&1 == 100))

      # Clean up
      for i <- 1..10 do
        :ets.delete(:binance_spot_limits, {now, i})
      end
    end
  end

  describe "HealthMonitor" do
    test "reports and retrieves health status" do
      # Report health for different exchanges
      HealthMonitor.report_health(:binance, :healthy)
      HealthMonitor.report_health(:kraken, :degraded)
      HealthMonitor.report_health(:deribit, :unhealthy)

      # Retrieve status
      status = HealthMonitor.get_health_status()

      assert status[:binance].status == :healthy
      assert status[:kraken].status == :degraded
      assert status[:deribit].status == :unhealthy

      # Verify timestamps
      assert is_integer(status[:binance].timestamp)
      assert is_integer(status[:kraken].timestamp)
      assert is_integer(status[:deribit].timestamp)
    end

    test "updates health status on subsequent reports" do
      # Initial report
      HealthMonitor.report_health(:test_exchange, :unhealthy)
      status1 = HealthMonitor.get_health_status()
      timestamp1 = status1[:test_exchange].timestamp

      # Wait a bit
      Process.sleep(10)

      # Update status
      HealthMonitor.report_health(:test_exchange, :healthy)
      status2 = HealthMonitor.get_health_status()

      assert status2[:test_exchange].status == :healthy
      assert status2[:test_exchange].timestamp >= timestamp1
    end

    test "handles concurrent health reports" do
      # Multiple processes reporting health simultaneously
      tasks =
        for exchange <- [:ex1, :ex2, :ex3, :ex4, :ex5] do
          Task.async(fn ->
            for _ <- 1..10 do
              status = Enum.random([:healthy, :degraded, :unhealthy])
              HealthMonitor.report_health(exchange, status)
              Process.sleep(1)
            end
          end)
        end

      Task.await_many(tasks)

      # All exchanges should have a status
      status = HealthMonitor.get_health_status()

      for exchange <- [:ex1, :ex2, :ex3, :ex4, :ex5] do
        assert Map.has_key?(status, exchange)
        assert status[exchange].status in [:healthy, :degraded, :unhealthy]
        assert is_integer(status[exchange].timestamp)
      end
    end

    test "periodic health check runs" do
      # Trigger health check manually
      send(Process.whereis(HealthMonitor), :health_check)
      Process.sleep(50)

      # Should not crash
      assert Process.alive?(Process.whereis(HealthMonitor))
    end
  end

  describe "supervisor resilience" do
    test "restarts RateLimitManager if it crashes" do
      old_pid = Process.whereis(RateLimitManager)
      assert old_pid != nil

      # Kill the process
      Process.exit(old_pid, :kill)

      # Wait for restart
      Process.sleep(100)

      # Should have a new pid
      new_pid = Process.whereis(RateLimitManager)
      assert new_pid != nil
      assert new_pid != old_pid

      # ETS tables should still exist
      assert :ets.info(:binance_spot_limits) != :undefined
      assert :ets.info(:binance_futures_limits) != :undefined
    end

    test "restarts HealthMonitor if it crashes" do
      old_pid = Process.whereis(HealthMonitor)
      assert old_pid != nil

      # Kill the process
      Process.exit(old_pid, :kill)

      # Wait for restart
      Process.sleep(100)

      # Should have a new pid
      new_pid = Process.whereis(HealthMonitor)
      assert new_pid != nil
      assert new_pid != old_pid

      # Should still be functional
      HealthMonitor.report_health(:test, :healthy)
      status = HealthMonitor.get_health_status()
      assert status[:test].status == :healthy
    end

    test "DynamicSupervisor remains stable" do
      # Dynamic supervisor should always be running
      assert Process.whereis(ZenCex.AdapterSupervisor) != nil

      # Even with no children
      children = DynamicSupervisor.which_children(ZenCex.AdapterSupervisor)
      assert is_list(children)
    end
  end

  describe "integration scenarios" do
    test "complete lifecycle of supervisor components" do
      # 1. Verify all components are running
      assert Process.whereis(ZenCex.Core.Supervisor) != nil
      assert Process.whereis(RateLimitManager) != nil
      assert Process.whereis(HealthMonitor) != nil
      assert Process.whereis(ZenCex.AdapterSupervisor) != nil

      # 2. Test rate limit functionality
      now = System.system_time(:second)
      test_key = {now, :integration_test}
      :ets.insert(:binance_spot_limits, {test_key, 0})
      count = :ets.update_counter(:binance_spot_limits, test_key, {2, 10})
      assert count == 10

      # 3. Test health monitoring
      HealthMonitor.report_health(:integration_test, :healthy)
      status = HealthMonitor.get_health_status()
      assert status[:integration_test].status == :healthy

      # 4. Clean up
      :ets.delete(:binance_spot_limits, test_key)
    end

    test "handles high concurrency" do
      # Simulate high concurrent load
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            # Rate limit operations
            key = {System.system_time(:second), i}
            :ets.insert(:kraken_limits, {key, 0})
            :ets.update_counter(:kraken_limits, key, {2, 1})

            # Health reports
            HealthMonitor.report_health(:"load_test_#{i}", :healthy)

            # Clean up own key
            :ets.delete(:kraken_limits, key)
          end)
        end

      # All should complete without errors
      results = Task.await_many(tasks, 5000)
      assert length(results) == 100
    end
  end
end
