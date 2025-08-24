defmodule ZenCex.Adapters.Bybit.RateLimiterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZenCex.Adapters.Bybit.RateLimiter
  alias ZenCex.Core.RateLimiter, as: Core

  setup do
    # Clean up the Bybit rate limiter table before each test
    reset_bybit_rate_limiter_table()
    :ok
  end

  describe "check_and_increment/2" do
    test "always returns :ok for regular operations (non-HFT approach)" do
      # In our non-HFT approach, we don't block proactively
      assert :ok = RateLimiter.check_and_increment("/v5/market/kline", 1)
      assert :ok = RateLimiter.check_and_increment("/v5/account/wallet-balance", 1)
      assert :ok = RateLimiter.check_and_increment("/v5/order/create", 1)
    end

    test "always allows emergency operations" do
      # Cancel order operations should never be blocked
      assert :ok = RateLimiter.check_and_increment("/v5/order/cancel", 1)
      assert :ok = RateLimiter.check_and_increment("/v5/order/cancel-all", 1)
      assert :ok = RateLimiter.check_and_increment("/v5/position/close", 1)
    end

    test "blocks regular operations when regular capacity exceeded" do
      # Bybit has 600 limit per 5 seconds, regular capacity is 540 (90%)
      table_name = String.to_atom("#{RateLimiter}.Table")
      Core.init_table(table_name)

      # Manually set usage to exceed regular capacity but not total
      key = {:bybit, get_current_window()}
      :ets.insert(table_name, {key, 541})

      # Regular operation should be rate limited
      result = RateLimiter.check_and_increment("/v5/market/kline", 1)
      assert {:error, {:rate_limited, retry_after_ms}} = result
      assert is_integer(retry_after_ms)
      assert retry_after_ms > 0
    end

    test "emergency operations work even when total capacity exceeded" do
      # First fill up to exceed total capacity with regular operations
      # This ensures we're using the same time window
      RateLimiter.check_and_increment("/v5/market/kline", 650)

      # Emergency operation should still work even at 650 (over 600 limit)
      assert :ok = RateLimiter.check_and_increment("/v5/order/cancel", 1)
    end

    test "detects emergency operations by operation atom" do
      # Set usage to exceed regular capacity
      table_name = String.to_atom("#{RateLimiter}.Table")
      Core.init_table(table_name)

      key = {:bybit, get_current_window()}
      :ets.insert(table_name, {key, 550})

      # Emergency operation via atom should work
      assert :ok = RateLimiter.check_and_increment("/v5/order", 1, :cancel_order)
      assert :ok = RateLimiter.check_and_increment("/v5/order", 1, :spot_cancel_all_orders)
      assert :ok = RateLimiter.check_and_increment("/v5/position", 1, :close_position)
    end

    test "supports category-prefixed emergency operations" do
      assert :ok = RateLimiter.check_and_increment("/v5/order", 1, :linear_cancel_order)
      assert :ok = RateLimiter.check_and_increment("/v5/order", 1, :inverse_cancel_all_orders)
      assert :ok = RateLimiter.check_and_increment("/v5/order", 1, :option_cancel_order)
    end
  end

  describe "update_from_response/1" do
    test "handles response without rate limit headers gracefully" do
      response = %Req.Response{
        status: 200,
        headers: [],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)
    end

    test "processes x-ratelimit-remaining header if present" do
      response = %Req.Response{
        status: 200,
        headers: [
          # Remaining: 100 out of 600 (used: 500)
          {"x-ratelimit-remaining", "100"}
        ],
        body: %{}
      }

      log =
        capture_log([level: :info], fn ->
          assert :ok = RateLimiter.update_from_response(response)
        end)

      # 500 used out of 540 regular capacity = 92.5%
      assert log =~ "Bybit API at 93% of regular capacity"
    end

    test "logs critical when in emergency reserve zone" do
      response = %Req.Response{
        status: 200,
        headers: [
          # Remaining: 20 out of 600 (used: 580)
          {"x-ratelimit-remaining", "20"}
        ],
        body: %{}
      }

      log =
        capture_log([level: :critical], fn ->
          assert :ok = RateLimiter.update_from_response(response)
        end)

      assert log =~ "Bybit API using EMERGENCY RESERVE"
      # 580/600 = 96.66% which rounds to 97%
      assert log =~ "97% of total limit"
    end

    test "handles header as list" do
      response = %Req.Response{
        status: 200,
        headers: [
          {"x-ratelimit-remaining", ["100"]}
        ],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)
    end
  end

  describe "get_status/1" do
    test "returns status for unified Bybit API" do
      # Increment some counters
      RateLimiter.check_and_increment("/v5/order/create", 10)
      RateLimiter.check_and_increment("/v5/market/kline", 5)

      status = RateLimiter.get_status(nil)

      assert is_map(status)
      assert status.used >= 15
      assert status.limit == 600
      assert status.window == 5
      assert status.regular_limit == 540
      assert status.emergency_reserve == 60
      assert is_integer(status.reset_at)
      assert is_integer(status.usage_percent)
      assert is_integer(status.regular_usage_percent)
      assert is_boolean(status.at_limit)
      assert is_boolean(status.in_emergency_zone)
    end

    test "ignores endpoint parameter (unified API)" do
      status1 = RateLimiter.get_status("/v5/order/create")
      status2 = RateLimiter.get_status("/v5/market/kline")
      status3 = RateLimiter.get_status(nil)

      # All should return the same status
      assert status1.limit == status2.limit
      assert status1.limit == status3.limit
      assert status1.window == status2.window
      assert status1.window == status3.window
    end

    test "shows emergency zone status correctly" do
      # Set usage to emergency zone
      table_name = String.to_atom("#{RateLimiter}.Table")
      Core.init_table(table_name)

      key = {:bybit, get_current_window()}
      :ets.insert(table_name, {key, 550})

      status = RateLimiter.get_status(nil)
      assert status.in_emergency_zone == true
      assert status.used == 550
    end
  end

  describe "reset/1" do
    test "resets the rate limit counter" do
      # Add some usage
      RateLimiter.check_and_increment("/v5/order/create", 100)

      status_before = RateLimiter.get_status(nil)
      assert status_before.used >= 100

      # Reset
      assert :ok = RateLimiter.reset(nil)

      status_after = RateLimiter.get_status(nil)
      assert status_after.used == 0
    end

    test "reset ignores endpoint parameter (unified API)" do
      RateLimiter.check_and_increment("/v5/order/create", 100)

      # Reset with any endpoint should reset the single table
      assert :ok = RateLimiter.reset("/v5/market/kline")

      status = RateLimiter.get_status(nil)
      assert status.used == 0
    end
  end

  describe "get_limits/0" do
    test "returns Bybit rate limit configuration" do
      limits = RateLimiter.get_limits()

      assert is_map(limits)
      assert Map.has_key?(limits, :bybit)
      assert limits.bybit.limit == 600
      assert limits.bybit.window == 5
    end
  end

  describe "cleanup_old_entries/0" do
    test "removes old entries from the table" do
      table_name = String.to_atom("#{RateLimiter}.Table")
      Core.init_table(table_name)

      # Insert old entries (older than 24 windows = 2 minutes)
      current_window = get_current_window()
      # Well beyond cleanup threshold
      old_window = current_window - 30

      :ets.insert(table_name, {{:bybit, old_window}, 100})
      :ets.insert(table_name, {{:bybit, current_window}, 50})

      # Should have 2 entries
      assert length(:ets.tab2list(table_name)) == 2

      # Run cleanup
      deleted = RateLimiter.cleanup_old_entries()
      assert deleted == 1

      # Should only have current window entry
      assert length(:ets.tab2list(table_name)) == 1
      assert [{_, 50}] = :ets.lookup(table_name, {:bybit, current_window})
    end

    test "handles empty table gracefully" do
      assert RateLimiter.cleanup_old_entries() == 0
    end
  end

  describe "emergency operation logging" do
    test "logs emergency bypass when using reserved capacity" do
      # Set ETS state directly for deterministic testing
      table_name = String.to_atom("#{RateLimiter}.Table")
      Core.init_table(table_name)

      # Set usage to 550 (in emergency zone, above 540 regular limit)
      key = {:bybit, get_current_window()}
      :ets.insert(table_name, {key, 550})

      log =
        capture_log([level: :debug], fn ->
          # Emergency operation should work and log that we're using reserve
          assert :ok = RateLimiter.check_and_increment("/v5/order/cancel", 1, :cancel_order)
        end)

      assert log =~ "Emergency operation"
      assert log =~ "bypassing rate limits"
      assert log =~ "using reserved capacity"
    end

    test "logs debug for emergency operations under regular capacity" do
      log =
        capture_log([level: :debug], fn ->
          # Using operation atom to ensure emergency detection
          assert :ok = RateLimiter.check_and_increment("/v5/order", 1, :cancel_order)
        end)

      assert log =~ "Emergency operation"
      assert log =~ "bypassing rate limits"
    end
  end

  # Helper functions

  defp reset_bybit_rate_limiter_table do
    table_name = String.to_atom("#{RateLimiter}.Table")

    case :ets.whereis(table_name) do
      :undefined ->
        :ok

      _tid ->
        Core.reset(table_name, :all)
    end
  end

  defp get_current_window do
    # Bybit uses 5-second windows
    :second |> System.system_time() |> div(5)
  end
end
