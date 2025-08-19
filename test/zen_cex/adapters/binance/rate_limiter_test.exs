defmodule ZenCex.Adapters.Binance.RateLimiterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ZenCex.Adapters.Binance.RateLimiter

  describe "check_and_increment/2" do
    test "always returns :ok for regular operations (non-HFT approach)" do
      # In our non-HFT approach, we don't block proactively
      assert :ok = RateLimiter.check_and_increment("/api/v3/ticker/price", 1)
      assert :ok = RateLimiter.check_and_increment("/api/v3/klines", 1)
      assert :ok = RateLimiter.check_and_increment("/sapi/v1/asset/assetDetail", 10)
    end

    test "always allows emergency operations" do
      # Cancel order operations should never be blocked
      assert :ok = RateLimiter.check_and_increment("/api/v3/order", 1)
      assert :ok = RateLimiter.check_and_increment("/fapi/v1/order", 1)
      assert :ok = RateLimiter.check_and_increment("/fapi/v1/allOpenOrders", 1)
    end
  end

  describe "update_from_response/1" do
    test "logs warning when approaching rate limit (80%)" do
      response = %Req.Response{
        status: 200,
        headers: [
          # 80% of 1200
          {"x-mbx-used-weight-1m", "960"}
        ],
        body: %{}
      }

      log =
        capture_log([level: :warning], fn ->
          assert :ok = RateLimiter.update_from_response(response)
        end)

      assert log =~ "Binance spot API at 80% of rate limit"
    end

    test "logs critical when near rate limit (95%)" do
      response = %Req.Response{
        status: 200,
        headers: [
          # 95% of 1200
          {"x-mbx-used-weight-1m", "1140"}
        ],
        body: %{}
      }

      log =
        capture_log([level: :critical], fn ->
          assert :ok = RateLimiter.update_from_response(response)
        end)

      assert log =~ "Binance spot API at 95% of rate limit"
    end

    test "handles SAPI rate limit headers" do
      response = %Req.Response{
        status: 200,
        headers: [
          # 80% of 12000
          {"x-sapi-used-ip-weight-1m", "9600"}
        ],
        body: %{}
      }

      log =
        capture_log([level: :warning], fn ->
          assert :ok = RateLimiter.update_from_response(response)
        end)

      assert log =~ "Binance sapi API at 80% of rate limit"
    end

    test "handles missing headers gracefully" do
      response = %Req.Response{
        status: 200,
        headers: [],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)
    end
  end

  describe "get_status/1" do
    test "returns status for specific API type" do
      # Increment some counters
      RateLimiter.check_and_increment("/api/v3/ticker", 10)

      status = RateLimiter.get_status("/api/v3/ticker")

      assert is_map(status)
      assert status.limit == 1200
      assert status.window == 60
      assert status.used >= 10
      assert status.usage_percent >= 0
    end

    test "returns status for all API types when endpoint is nil" do
      status = RateLimiter.get_status(nil)

      assert is_map(status)
      assert Map.has_key?(status, :spot)
      assert Map.has_key?(status, :sapi)
      assert Map.has_key?(status, :usdm_futures)
      assert Map.has_key?(status, :coinm_futures)

      assert status.spot.limit == 1200
      assert status.sapi.limit == 12_000
      assert status.usdm_futures.limit == 2400
      assert status.coinm_futures.limit == 2400
    end
  end

  describe "reset/1" do
    test "resets counter for specific API type" do
      # Add some usage
      RateLimiter.check_and_increment("/api/v3/ticker", 100)

      # Get initial status
      status_before = RateLimiter.get_status("/api/v3/ticker")
      assert status_before.used >= 100

      # Reset
      assert :ok = RateLimiter.reset("/api/v3/ticker")

      # Check status after reset
      status_after = RateLimiter.get_status("/api/v3/ticker")
      assert status_after.used == 0
    end

    test "resets all counters when endpoint is nil" do
      # Add usage to multiple API types
      RateLimiter.check_and_increment("/api/v3/ticker", 50)
      RateLimiter.check_and_increment("/sapi/v1/asset", 100)
      RateLimiter.check_and_increment("/fapi/v1/order", 75)

      # Reset all
      assert :ok = RateLimiter.reset(nil)

      # Check all are reset
      status = RateLimiter.get_status(nil)
      assert status.spot.used == 0
      assert status.sapi.used == 0
      assert status.usdm_futures.used == 0
      assert status.coinm_futures.used == 0
    end
  end

  describe "get_limits/0" do
    test "returns configured limits for all API types" do
      limits = RateLimiter.get_limits()

      assert limits.spot.limit == 1200
      assert limits.spot.window == 60

      assert limits.sapi.limit == 12_000
      assert limits.sapi.window == 60

      assert limits.usdm_futures.limit == 2400
      assert limits.usdm_futures.window == 60

      assert limits.coinm_futures.limit == 2400
      assert limits.coinm_futures.window == 60
    end
  end

  describe "cleanup_old_entries/0" do
    test "removes old entries from ETS table" do
      # This is an internal maintenance function
      # Just verify it doesn't crash
      assert is_integer(RateLimiter.cleanup_old_entries())
    end
  end

  describe "API type detection" do
    test "correctly identifies Spot API endpoints" do
      RateLimiter.check_and_increment("/api/v3/ticker/price", 1)
      status = RateLimiter.get_status("/api/v3/ticker/price")
      # Spot limit
      assert status.limit == 1200
    end

    test "correctly identifies SAPI endpoints" do
      RateLimiter.check_and_increment("/sapi/v1/asset/assetDetail", 1)
      status = RateLimiter.get_status("/sapi/v1/asset/assetDetail")
      # SAPI limit
      assert status.limit == 12_000
    end

    test "correctly identifies Futures API endpoints" do
      RateLimiter.check_and_increment("/fapi/v1/ticker/price", 1)
      status = RateLimiter.get_status("/fapi/v1/ticker/price")
      # Futures limit
      assert status.limit == 2400
    end
  end
end
