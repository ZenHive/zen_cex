defmodule ZenCex.Adapters.BaseRateLimiterTest do
  use ExUnit.Case, async: true

  # Create a test module that uses BaseRateLimiter
  defmodule TestRateLimiter do
    @moduledoc false
    use ZenCex.Adapters.BaseRateLimiter,
      exchange: :test_exchange,
      emergency_operations: [:cancel_order, :close_position],
      emergency_path_patterns: ["/emergency/", "/critical/"]
  end

  describe "emergency_operation?/1" do
    test "identifies emergency operations by atom" do
      assert TestRateLimiter.emergency_operation?(:cancel_order)
      assert TestRateLimiter.emergency_operation?(:close_position)
      refute TestRateLimiter.emergency_operation?(:place_order)
      refute TestRateLimiter.emergency_operation?(:get_balance)
    end

    test "identifies emergency operations by path pattern" do
      assert TestRateLimiter.emergency_operation?("/api/v1/emergency/stop")
      assert TestRateLimiter.emergency_operation?("/critical/shutdown")
      refute TestRateLimiter.emergency_operation?("/api/v1/orders")
      refute TestRateLimiter.emergency_operation?("/normal/operation")
    end
  end

  describe "calculate_capacity_usage/2" do
    test "calculates usage percentage correctly" do
      assert TestRateLimiter.calculate_capacity_usage(50, 100) == 50.0
      assert TestRateLimiter.calculate_capacity_usage(75, 100) == 75.0
      assert TestRateLimiter.calculate_capacity_usage(100, 100) == 100.0
      assert TestRateLimiter.calculate_capacity_usage(0, 100) == 0.0
    end

    test "handles edge cases" do
      assert TestRateLimiter.calculate_capacity_usage(0, 0) == 0.0
      assert TestRateLimiter.calculate_capacity_usage(10, 0) == 0.0
      assert TestRateLimiter.calculate_capacity_usage(150, 100) == 150.0
    end

    test "returns rounded percentages" do
      assert TestRateLimiter.calculate_capacity_usage(333, 1000) == 33.3
      assert TestRateLimiter.calculate_capacity_usage(667, 1000) == 66.7
      assert TestRateLimiter.calculate_capacity_usage(999, 1000) == 99.9
    end
  end

  describe "has_regular_capacity?/2" do
    test "checks if under regular capacity threshold" do
      # Default threshold is 0.90 (90%)
      assert TestRateLimiter.has_regular_capacity?(89, 100)
      assert TestRateLimiter.has_regular_capacity?(0, 100)
      refute TestRateLimiter.has_regular_capacity?(90, 100)
      refute TestRateLimiter.has_regular_capacity?(95, 100)
      refute TestRateLimiter.has_regular_capacity?(100, 100)
    end

    test "handles different limit values" do
      assert TestRateLimiter.has_regular_capacity?(899, 1000)
      refute TestRateLimiter.has_regular_capacity?(900, 1000)

      assert TestRateLimiter.has_regular_capacity?(1799, 2000)
      refute TestRateLimiter.has_regular_capacity?(1800, 2000)
    end
  end

  describe "get_regular_capacity_ratio/0" do
    test "returns the configured ratio" do
      assert TestRateLimiter.get_regular_capacity_ratio() == 0.90
    end
  end

  describe "log_capacity_warning/1" do
    import ExUnit.CaptureLog

    test "logs critical warning at 95% or above" do
      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(95.0)
        end)

      assert log =~ "CRITICAL"
      assert log =~ "95.0%"

      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(100.0)
        end)

      assert log =~ "CRITICAL"
      assert log =~ "100.0%"
    end

    test "logs warning at 80% or above but below 95%" do
      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(80.0)
        end)

      assert log =~ "warning"
      assert log =~ "80.0%"
      refute log =~ "CRITICAL"

      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(94.9)
        end)

      assert log =~ "warning"
      assert log =~ "94.9%"
      refute log =~ "CRITICAL"
    end

    test "logs nothing below 80%" do
      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(79.9)
        end)

      assert log == ""

      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(50.0)
        end)

      assert log == ""

      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(0.0)
        end)

      assert log == ""
    end

    test "includes exchange name in log message" do
      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(85.0, :custom_exchange)
        end)

      assert log =~ "custom_exchange"

      log =
        capture_log(fn ->
          TestRateLimiter.log_capacity_warning(85.0)
        end)

      assert log =~ "test_exchange"
    end
  end
end
