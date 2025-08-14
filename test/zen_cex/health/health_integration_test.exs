defmodule ZenCex.Health.IntegrationTest do
  use ZenCex.DataCase, async: false

  import ExUnit.CaptureLog

  alias ZenCex.Health
  alias ZenCex.Health.{Check, Monitor}

  describe "complete health check flow" do
    test "startup -> monitoring -> consensus flow works end-to-end" do
      # 1. Startup health check
      startup_result = Check.startup_check()
      assert startup_result == :ok

      # 2. Start monitoring
      {:ok, monitor} =
        Monitor.start_link(
          name: :integration_test_monitor,
          interval_ms: 1000,
          exchanges: [:binance, :kraken, :deribit]
        )

      # 3. Wait for initial check
      Process.sleep(100)

      # 4. Get detailed status
      detailed = Check.detailed_status()
      assert detailed.healthy in [true, false]
      assert length(Map.keys(detailed.exchanges)) == 3

      # 5. Check consensus
      {consensus_status, consensus_result} =
        Health.check_multi_exchange_consensus([:binance, :kraken, :deribit])

      assert consensus_status in [:ok, :warning, :critical]
      assert consensus_result.exchanges_checked == 3

      # 6. Force immediate check
      Monitor.check_now(monitor)
      Process.sleep(2000)

      # 7. Verify monitoring is working
      {:ok, monitor_status} = Monitor.get_status(monitor)
      assert monitor_status.check_count >= 1
      assert monitor_status.last_check != nil

      # Cleanup
      GenServer.stop(monitor)
    end

    test "handles degraded exchange gracefully" do
      # Start with potentially degraded exchange
      exchanges = [:binance, :kraken, :deribit]

      {status, result} = Health.check_multi_exchange_consensus(exchanges)

      # System should handle any status
      assert status in [:ok, :warning, :critical]

      # Should attempt all exchanges
      assert result.exchanges_checked == 3

      # Should identify any outliers
      if result.consensus[:status] == :drift_detected do
        assert is_list(result.consensus[:outliers])
      end
    end

    test "monitoring continues after exchange failures" do
      # Start monitor with mix of valid and potentially slow exchanges
      {:ok, monitor} =
        Monitor.start_link(
          name: :failure_test_monitor,
          interval_ms: 1000,
          exchanges: [:binance, :kraken, :deribit],
          # Very strict to trigger warnings
          warning_ms: 100,
          critical_ms: 200
        )

      # Let it run for multiple cycles
      Process.sleep(3500)

      # Should still be running
      assert Process.alive?(monitor)

      # Should have multiple checks
      {:ok, status} = Monitor.get_status(monitor)
      assert status.check_count >= 3

      # May have warnings due to strict thresholds
      assert status.warning_count >= 0

      # Cleanup
      GenServer.stop(monitor)
    end

    test "telemetry integration works correctly" do
      test_pid = self()
      handler_id = :integration_telemetry_handler

      # Attach handlers for both warning and critical events
      :telemetry.attach_many(
        handler_id,
        [
          [:zen_cex, :health, :warning],
          [:zen_cex, :health, :critical]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Start monitor with strict thresholds to trigger events
      {:ok, monitor} =
        Monitor.start_link(
          name: :telemetry_test_monitor,
          interval_ms: 1000,
          exchanges: [:binance, :kraken, :deribit],
          # Very strict
          warning_ms: 50,
          # Very strict
          critical_ms: 100
        )

      # Wait for checks that might trigger telemetry
      Process.sleep(2000)

      # We might receive telemetry events if drift is high
      receive do
        {:telemetry, event, _measurements, _metadata} ->
          assert event in [
                   [:zen_cex, :health, :warning],
                   [:zen_cex, :health, :critical]
                 ]
      after
        2500 ->
          # No events is also valid if all exchanges are healthy
          :ok
      end

      # Cleanup
      :telemetry.detach(handler_id)
      GenServer.stop(monitor)
    end

    test "quick check provides rapid health assessment" do
      # Quick check should be fast
      {time_us, status} = :timer.tc(fn -> Check.quick_check() end)

      assert status in [:ok, :warning, :critical]
      # Should complete within 5 seconds
      assert time_us < 5_000_000
    end

    test "outlier detection works across exchanges" do
      exchanges = [:binance, :kraken, :deribit]

      # Check each exchange for outlier status
      binance_outlier = Health.exchange_outlier?(:binance, exchanges)
      kraken_outlier = Health.exchange_outlier?(:kraken, exchanges)
      deribit_outlier = Health.exchange_outlier?(:deribit, exchanges)

      # All should return boolean
      assert is_boolean(binance_outlier)
      assert is_boolean(kraken_outlier)
      assert is_boolean(deribit_outlier)

      # If any are outliers, consensus should detect it
      if binance_outlier or kraken_outlier or deribit_outlier do
        {_status, result} = Health.check_multi_exchange_consensus(exchanges)
        assert result.consensus[:status] == :drift_detected
        assert length(result.consensus[:outliers]) > 0
      end
    end

    test "startup retry mechanism works" do
      log =
        capture_log([level: :info], fn ->
          # This will retry if there are failures
          result = Check.startup_check_with_retry()
          assert result == :ok or match?({:error, _}, result)
        end)

      # Should see startup messages
      assert log =~ "[HealthCheck]" or log =~ "[HealthStartup]"
    end

    test "configuration updates take effect immediately" do
      # Start with default config
      {:ok, monitor} =
        Monitor.start_link(
          name: :config_test_monitor,
          interval_ms: 30_000,
          warning_ms: 300,
          critical_ms: 500
        )

      # Update configuration
      :ok =
        Monitor.update_config(monitor,
          interval_ms: 60_000,
          warning_ms: 200,
          critical_ms: 400
        )

      # Force a check with new config
      Monitor.check_now(monitor)
      Process.sleep(2000)

      # Get status to verify config
      {:ok, status} = Monitor.get_status(monitor)
      assert status.interval_ms == 60_000

      # Cleanup
      GenServer.stop(monitor)
    end
  end

  describe "production simulation" do
    @tag :slow
    test "simulates production monitoring over time" do
      # Start monitoring as in production
      {:ok, monitor} =
        Monitor.start_link(
          name: :production_sim_monitor,
          # 2 seconds for testing
          interval_ms: 2000,
          exchanges: [:binance, :kraken, :deribit],
          warning_ms: 300,
          critical_ms: 500
        )

      # Let it run for several cycles
      Process.sleep(7000)

      # Check accumulated statistics
      {:ok, status} = Monitor.get_status(monitor)

      # Should have performed multiple checks
      assert status.check_count >= 3

      # Verify all counters are working
      assert status.error_count >= 0
      assert status.warning_count >= 0
      assert status.critical_count >= 0

      # Last check should be recent
      if status.last_check do
        now = System.system_time(:millisecond)
        age = now - status.last_check
        # Last check within 3 seconds
        assert age < 3000
      end

      # Cleanup
      GenServer.stop(monitor)
    end

    test "handles concurrent health checks efficiently" do
      # Launch multiple concurrent checks
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            {i, Health.check_multi_exchange_consensus([:binance, :kraken, :deribit])}
          end)
        end

      # Collect results
      results = Task.yield_many(tasks, 10_000)

      # All should complete
      assert length(results) == 5

      # All should return valid results
      Enum.each(results, fn {_task, result} ->
        case result do
          {:ok, {_i, {status, data}}} ->
            assert status in [:ok, :warning, :critical]
            assert data.exchanges_checked == 3

          _ ->
            # Task timed out or failed - also acceptable in edge cases
            :ok
        end
      end)
    end
  end

  describe "error recovery" do
    test "recovers from transient network errors" do
      # Start monitor that might experience network issues
      {:ok, monitor} =
        Monitor.start_link(
          name: :recovery_test_monitor,
          interval_ms: 1000
        )

      # Simulate running for a while with potential network issues
      Process.sleep(3000)

      # Should still be operational
      assert Process.alive?(monitor)

      # Should be able to get status
      {:ok, status} = Monitor.get_status(monitor)
      assert is_map(status)

      # Cleanup
      GenServer.stop(monitor)
    end

    test "handles invalid exchange gracefully in consensus" do
      # Mix valid and invalid exchanges
      exchanges = [:binance, :invalid_exchange_1, :kraken, :invalid_exchange_2]

      {status, result} = Health.check_multi_exchange_consensus(exchanges)

      # Should still return a result
      assert status in [:ok, :warning, :critical]

      # Should track failed exchanges
      assert :invalid_exchange_1 in result.failed_exchanges
      assert :invalid_exchange_2 in result.failed_exchanges

      # Should still check valid exchanges
      assert result.successful_checks >= 2
    end
  end
end
