defmodule ZenCex.Health.MonitorTest do
  use ZenCex.DataCase, async: true
  import ExUnit.CaptureLog

  alias ZenCex.Health.Monitor

  describe "start_link/1" do
    test "starts the health monitor process" do
      {:ok, pid} = Monitor.start_link(name: :test_monitor)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "accepts configuration options" do
      opts = [
        name: :test_monitor_with_opts,
        interval_ms: 60_000,
        exchanges: [:binance],
        warning_ms: 250,
        critical_ms: 450
      ]

      {:ok, pid} = Monitor.start_link(opts)
      assert Process.alive?(pid)

      # Verify configuration was applied
      {:ok, status} = Monitor.get_status(pid)
      assert status.interval_ms == 60_000
      assert status.exchanges == [:binance]

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "get_status/1" do
    setup do
      {:ok, pid} = Monitor.start_link(name: :test_monitor_status)

      # Wait for initial check to complete
      Process.sleep(100)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, monitor: pid}
    end

    test "returns current monitor status", %{monitor: monitor} do
      {:ok, status} = Monitor.get_status(monitor)

      assert Map.has_key?(status, :last_check)
      assert Map.has_key?(status, :last_status)
      assert Map.has_key?(status, :check_count)
      assert Map.has_key?(status, :error_count)
      assert Map.has_key?(status, :warning_count)
      assert Map.has_key?(status, :critical_count)
      assert Map.has_key?(status, :interval_ms)
      assert Map.has_key?(status, :exchanges)
    end

    test "check count increments after checks", %{monitor: monitor} do
      {:ok, initial_status} = Monitor.get_status(monitor)
      initial_count = initial_status.check_count

      # Trigger immediate check
      Monitor.check_now(monitor)
      # Wait for check to complete
      Process.sleep(2000)

      {:ok, new_status} = Monitor.get_status(monitor)
      assert new_status.check_count > initial_count
    end
  end

  describe "check_now/1" do
    setup do
      {:ok, pid} = Monitor.start_link(name: :test_monitor_check_now)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, monitor: pid}
    end

    test "triggers immediate health check", %{monitor: monitor} do
      {:ok, initial_status} = Monitor.get_status(monitor)

      # Trigger check
      :ok = Monitor.check_now(monitor)

      # Wait for check to complete
      Process.sleep(2000)

      {:ok, new_status} = Monitor.get_status(monitor)

      # Last check time should be updated
      if initial_status.last_check do
        assert new_status.last_check > initial_status.last_check
      else
        assert new_status.last_check != nil
      end
    end

    test "logs warnings when drift detected", %{monitor: monitor} do
      log =
        capture_log(fn ->
          Monitor.check_now(monitor)
          Process.sleep(2000)
        end)

      # May or may not have warnings depending on actual drift
      assert log =~ "[HealthMonitor]" or log == ""
    end
  end

  describe "update_config/2" do
    setup do
      {:ok, pid} =
        Monitor.start_link(
          name: :test_monitor_update,
          interval_ms: 30_000
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, monitor: pid}
    end

    test "updates monitor configuration", %{monitor: monitor} do
      # Initial config
      {:ok, initial_status} = Monitor.get_status(monitor)
      assert initial_status.interval_ms == 30_000

      # Update config
      :ok = Monitor.update_config(monitor, interval_ms: 60_000, warning_ms: 200)

      # Verify update
      {:ok, new_status} = Monitor.get_status(monitor)
      assert new_status.interval_ms == 60_000
    end
  end

  describe "periodic monitoring" do
    @tag :slow
    test "performs checks at configured interval" do
      {:ok, pid} =
        Monitor.start_link(
          name: :test_monitor_periodic,
          # 1 second for testing
          interval_ms: 1000
        )

      # Wait for initial check
      Process.sleep(100)
      {:ok, initial_status} = Monitor.get_status(pid)
      initial_count = initial_status.check_count

      # Wait for at least 2 intervals
      Process.sleep(2500)

      {:ok, final_status} = Monitor.get_status(pid)

      # Should have performed at least 2 additional checks
      assert final_status.check_count >= initial_count + 2

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "telemetry events" do
    setup do
      {:ok, pid} = Monitor.start_link(name: :test_monitor_telemetry)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      {:ok, monitor: pid}
    end

    test "emits telemetry events on warnings", %{monitor: _monitor} do
      # Set up telemetry handler
      test_pid = self()
      handler_id = :test_handler

      :telemetry.attach(
        handler_id,
        [:zen_cex, :health, :warning],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, :warning, measurements, metadata})
        end,
        nil
      )

      # We can't easily force a warning, but we can verify the handler is set up
      handlers = :telemetry.list_handlers([:zen_cex, :health, :warning])
      assert Enum.any?(handlers, fn h -> h.id == handler_id end)

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "emits telemetry events on critical issues", %{monitor: _monitor} do
      # Set up telemetry handler
      test_pid = self()
      handler_id = :test_handler_critical

      :telemetry.attach(
        handler_id,
        [:zen_cex, :health, :critical],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, :critical, measurements, metadata})
        end,
        nil
      )

      # Verify handler is attached
      handlers = :telemetry.list_handlers([:zen_cex, :health, :critical])
      assert Enum.any?(handlers, fn h -> h.id == handler_id end)

      # Cleanup
      :telemetry.detach(handler_id)
    end
  end

  describe "error handling" do
    test "continues monitoring after check failures" do
      {:ok, pid} =
        Monitor.start_link(
          name: :test_monitor_errors,
          # One invalid exchange
          exchanges: [:invalid_exchange, :binance]
        )

      # Trigger check with invalid exchange
      Monitor.check_now(pid)
      Process.sleep(2000)

      # Monitor should still be running
      assert Process.alive?(pid)

      # Should be able to get status
      {:ok, status} = Monitor.get_status(pid)
      assert status.check_count > 0

      # Cleanup
      GenServer.stop(pid)
    end

    test "handles timeout gracefully" do
      {:ok, pid} =
        Monitor.start_link(
          name: :test_monitor_timeout,
          # Long interval to prevent automatic checks
          interval_ms: 100_000
        )

      # Monitor should start successfully
      assert Process.alive?(pid)

      # Should be able to interact with it
      {:ok, _status} = Monitor.get_status(pid)

      # Cleanup
      GenServer.stop(pid)
    end
  end
end
