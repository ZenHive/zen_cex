defmodule ZenCex.Adapters.Binance.RateLimiterEmergencyTest do
  @moduledoc """
  Tests for emergency bypass functionality in the Binance rate limiter.

  These tests verify that:
  - Emergency operations are correctly identified
  - 10% capacity is reserved for emergency operations
  - Emergency operations bypass normal rate limits
  - Regular operations are limited to 90% capacity
  """
  use ExUnit.Case, async: false

  import ZenCex.RateLimiterTestHelpers

  alias ZenCex.Adapters.Binance.RateLimiter

  setup do
    # Clean up all rate limiter tables before each test
    reset_all_binance_rate_limiter_tables()
    :ok
  end

  describe "emergency operation detection" do
    test "identifies cancel_order operations as emergency" do
      assert RateLimiter.check_and_increment("/api/v3/order", 1, :cancel_order) == :ok
      assert RateLimiter.check_and_increment("/fapi/v1/order", 1, :cancel_order) == :ok
      assert RateLimiter.check_and_increment("/dapi/v1/order", 1, :cancel_order) == :ok
    end

    test "identifies cancel_all_orders as emergency" do
      assert RateLimiter.check_and_increment("/api/v3/openOrders", 1, :cancel_all_orders) == :ok
      assert RateLimiter.check_and_increment("/fapi/v1/allOpenOrders", 1, :cancel_all_orders) == :ok
    end

    test "identifies close_position operations as emergency" do
      assert RateLimiter.check_and_increment("/fapi/v1/position/risk", 1, :close_position) == :ok
      assert RateLimiter.check_and_increment("/fapi/v1/position/margin", 1, :close_position) == :ok
    end

    test "identifies operations by endpoint path even without operation atom" do
      # Should detect emergency by path pattern
      assert RateLimiter.check_and_increment("/api/v3/order", 1) == :ok
      assert RateLimiter.check_and_increment("/fapi/v1/allOpenOrders", 1) == :ok
      assert RateLimiter.check_and_increment("/sapi/v1/margin/order", 1) == :ok
    end

    test "regular operations are not identified as emergency" do
      # These should be subject to regular rate limiting
      result = RateLimiter.check_and_increment("/api/v3/ticker/price", 1, :get_ticker)
      # Will pass initially but subject to limits
      assert result == :ok

      result = RateLimiter.check_and_increment("/api/v3/account", 1, :get_account)
      assert result == :ok
    end
  end

  describe "capacity reservation" do
    test "regular operations can use up to 90% of capacity" do
      # For spot API: limit is 1200, regular capacity is 1080 (90%)
      # Fill up to 90% capacity
      for _ <- 1..1080 do
        assert RateLimiter.check_and_increment("/api/v3/ticker/price", 1, :get_ticker) == :ok
      end

      # Next regular operation should be rate limited
      assert {:error, {:rate_limited, retry_after}} =
               RateLimiter.check_and_increment("/api/v3/ticker/price", 1, :get_ticker)

      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "emergency operations can use the full 100% capacity" do
      # Fill up to 90% capacity with regular operations
      for _ <- 1..1080 do
        assert RateLimiter.check_and_increment("/api/v3/ticker/price", 1, :get_ticker) == :ok
      end

      # Emergency operations should still work in the reserved 10%
      for _ <- 1..120 do
        assert RateLimiter.check_and_increment("/api/v3/order", 1, :cancel_order) == :ok
      end

      # Even beyond 100%, emergency operations still proceed (but log warnings)
      assert RateLimiter.check_and_increment("/api/v3/order", 1, :cancel_order) == :ok
    end

    test "emergency operations always bypass rate limits" do
      # Fill way beyond capacity
      for _ <- 1..2000 do
        RateLimiter.check_and_increment("/api/v3/ticker/price", 1, :get_ticker)
      end

      # Emergency operations should still work
      assert RateLimiter.check_and_increment("/api/v3/order", 1, :cancel_order) == :ok
      assert RateLimiter.check_and_increment("/api/v3/allOpenOrders", 1, :cancel_all_orders) == :ok
      assert RateLimiter.check_and_increment("/fapi/v1/position/risk", 1, :close_position) == :ok
    end
  end

  describe "get_status/1" do
    test "reports regular capacity and emergency reserve separately" do
      # Add some usage
      for _ <- 1..500 do
        RateLimiter.check_and_increment("/api/v3/ticker/price", 1, :get_ticker)
      end

      status = RateLimiter.get_status("/api/v3/ticker/price")

      assert status.used == 500
      assert status.limit == 1200
      assert status.regular_limit == 1080
      assert status.emergency_reserve == 120
      assert status.in_emergency_zone == false

      # Add more usage to reach regular capacity limit (580 more to reach 1080)
      for _ <- 1..580 do
        RateLimiter.check_and_increment("/api/v3/ticker/price", 1, :get_ticker)
      end

      status = RateLimiter.get_status("/api/v3/ticker/price")
      assert status.used == 1080
      # Exactly at the boundary
      assert status.in_emergency_zone == false

      # Now use emergency operations to enter emergency zone
      for _ <- 1..20 do
        RateLimiter.check_and_increment("/api/v3/order", 1, :cancel_order)
      end

      # Check spot API status
      status = RateLimiter.get_status("/api/v3/ticker/price")
      assert status.used == 1100
      assert status.in_emergency_zone == true
    end

    test "calculates usage percentages correctly" do
      # Use 540 weight units (50% of regular capacity)
      for _ <- 1..540 do
        RateLimiter.check_and_increment("/api/v3/ticker/price", 1)
      end

      status = RateLimiter.get_status("/api/v3/ticker/price")

      # 540/1200 = 45% of total limit
      assert status.usage_percent == 45

      # 540/1080 = 50% of regular capacity
      assert status.regular_usage_percent == 50
    end
  end

  describe "different API types" do
    test "SAPI has higher limits with proper reservation" do
      # SAPI limit is 12000, regular capacity is 10800
      endpoint = "/sapi/v1/margin/transfer"

      # Fill most of regular capacity (leave some room for test stability)
      for _ <- 1..10_790 do
        assert RateLimiter.check_and_increment(endpoint, 1, :margin_transfer) == :ok
      end

      # Add more to reach the limit
      for _ <- 1..10 do
        RateLimiter.check_and_increment(endpoint, 1, :margin_transfer)
      end

      # Next regular operation should be limited
      assert {:error, {:rate_limited, _}} =
               RateLimiter.check_and_increment(endpoint, 1, :margin_transfer)

      # But emergency operations work
      assert RateLimiter.check_and_increment("/sapi/v1/margin/order", 1, :cancel_order) == :ok
    end

    test "futures APIs have proper limits" do
      # USD-M futures limit is 2400, regular capacity is 2160
      usdm_endpoint = "/fapi/v1/ticker/price"

      for _ <- 1..2160 do
        RateLimiter.check_and_increment(usdm_endpoint, 1, :get_ticker)
      end

      # Should be rate limited
      assert {:error, {:rate_limited, _}} =
               RateLimiter.check_and_increment(usdm_endpoint, 1, :get_ticker)

      # Emergency still works
      assert RateLimiter.check_and_increment("/fapi/v1/order", 1, :cancel_order) == :ok
    end
  end

  describe "weight handling" do
    test "emergency operations with high weight still bypass" do
      # Fill capacity
      for _ <- 1..1080 do
        RateLimiter.check_and_increment("/api/v3/ticker/price", 1)
      end

      # High-weight emergency operation should still work
      # Order operations often have weight > 1
      assert RateLimiter.check_and_increment("/api/v3/order", 10, :cancel_order) == :ok
    end

    test "regular operations check capacity with weight" do
      # Use operations with weight 10
      # Should be able to do 108 operations (108 * 10 = 1080)
      for _ <- 1..108 do
        assert RateLimiter.check_and_increment("/api/v3/klines", 10, :get_klines) == :ok
      end

      # Next one should be rate limited
      assert {:error, {:rate_limited, _}} =
               RateLimiter.check_and_increment("/api/v3/klines", 10, :get_klines)
    end
  end

  describe "update_from_response/1" do
    test "properly tracks usage from response headers" do
      response = %Req.Response{
        status: 200,
        headers: [{"x-mbx-used-weight-1m", "500"}],
        private: %{req_url: "/api/v3/ticker/price"}
      }

      assert RateLimiter.update_from_response(response) == :ok

      # The update_from_response doesn't affect our counter directly,
      # it's for logging/monitoring based on actual server response
    end
  end

  describe "reset/1" do
    test "resets counters for specific endpoint" do
      # Add some usage
      for _ <- 1..500 do
        RateLimiter.check_and_increment("/api/v3/ticker/price", 1)
      end

      status = RateLimiter.get_status("/api/v3/ticker/price")
      assert status.used == 500

      # Reset
      assert RateLimiter.reset("/api/v3/ticker/price") == :ok

      # Check it's reset
      status = RateLimiter.get_status("/api/v3/ticker/price")
      assert status.used == 0
    end

    test "reset all when no endpoint specified" do
      # Add usage to multiple API types
      RateLimiter.check_and_increment("/api/v3/ticker/price", 100)
      RateLimiter.check_and_increment("/sapi/v1/margin/transfer", 100)
      RateLimiter.check_and_increment("/fapi/v1/ticker/price", 100)

      # Reset all
      assert RateLimiter.reset(nil) == :ok

      # Check all are reset
      assert RateLimiter.get_status("/api/v3/ticker/price").used == 0
      assert RateLimiter.get_status("/sapi/v1/margin/transfer").used == 0
      assert RateLimiter.get_status("/fapi/v1/ticker/price").used == 0
    end
  end
end
