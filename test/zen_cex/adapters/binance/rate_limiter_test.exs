defmodule ZenCex.Adapters.Binance.RateLimiterTest do
  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance.RateLimiter

  setup do
    # Clean up any existing tables
    RateLimiter.cleanup_tables()
    # Initialize fresh tables
    RateLimiter.init_tables()

    on_exit(fn ->
      RateLimiter.cleanup_tables()
    end)

    :ok
  end

  describe "check_and_increment/2" do
    test "allows requests under the spot limit" do
      # Spot limit is 1200/min
      for i <- 1..100 do
        assert :ok = RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      status = RateLimiter.get_status("/api/v3/ticker")
      assert status.used == 100
      assert status.remaining == 1100
    end

    test "allows requests under the futures limit" do
      # Futures limit is 2400/min
      for i <- 1..200 do
        assert :ok = RateLimiter.check_and_increment("/fapi/v1/ticker", 1)
      end

      status = RateLimiter.get_status("/fapi/v1/ticker")
      assert status.used == 200
      assert status.remaining == 2200
    end

    test "rejects requests over the spot limit" do
      # Fill up to the limit
      for i <- 1..1200 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      # Next request should be rejected
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("/api/v3/ticker", 1)
    end

    test "rejects requests over the futures limit" do
      # Fill up to the limit
      for i <- 1..2400 do
        RateLimiter.check_and_increment("/fapi/v1/ticker", 1)
      end

      # Next request should be rejected
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("/fapi/v1/ticker", 1)
    end

    test "respects weight parameter" do
      # Use weight of 10 per request
      for i <- 1..100 do
        assert :ok = RateLimiter.check_and_increment("/api/v3/ticker", 10)
      end

      status = RateLimiter.get_status("/api/v3/ticker")
      assert status.used == 1000
      assert status.remaining == 200

      # Should allow 20 more requests with weight 10
      for i <- 1..20 do
        assert :ok = RateLimiter.check_and_increment("/api/v3/ticker", 10)
      end

      # But not 21
      assert {:error, :rate_limited} = RateLimiter.check_and_increment("/api/v3/ticker", 10)
    end

    test "separates spot and futures limits" do
      # Fill spot to near limit
      for i <- 1..1100 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      # Futures should still have full capacity
      for i <- 1..2000 do
        assert :ok = RateLimiter.check_and_increment("/fapi/v1/ticker", 1)
      end

      spot_status = RateLimiter.get_status("/api/v3/ticker")
      futures_status = RateLimiter.get_status("/fapi/v1/ticker")

      assert spot_status.used == 1100
      assert futures_status.used == 2000
    end

    test "handles /dapi endpoints as futures" do
      assert :ok = RateLimiter.check_and_increment("/dapi/v1/ticker", 100)

      status = RateLimiter.get_status("/dapi/v1/ticker")
      assert status.limit == 2400
      assert status.used == 100
    end
  end

  describe "sliding window behavior" do
    test "implements true sliding window" do
      # Add requests at different seconds
      now = System.system_time(:second)

      # Insert historical data (mock different timestamps)
      # 30s ago
      :ets.insert(:binance_spot_limits, {now - 30, 500})
      # 10s ago
      :ets.insert(:binance_spot_limits, {now - 10, 300})
      # now
      :ets.insert(:binance_spot_limits, {now, 200})

      status = RateLimiter.get_status("/api/v3/ticker")
      # All within 60s window
      assert status.used == 1000

      # Insert data older than 60s (should not count)
      :ets.insert(:binance_spot_limits, {now - 61, 100})

      status = RateLimiter.get_status("/api/v3/ticker")
      # Old data not counted
      assert status.used == 1000
    end

    test "cleans up old entries" do
      now = System.system_time(:second)

      # Insert old and new data
      :ets.insert(:binance_spot_limits, {now - 100, 50})
      :ets.insert(:binance_spot_limits, {now - 80, 50})
      :ets.insert(:binance_spot_limits, {now, 50})

      # Make a request which triggers cleanup
      RateLimiter.check_and_increment("/api/v3/ticker", 1)

      # Old entries should be deleted
      all_entries = :ets.tab2list(:binance_spot_limits)
      timestamps = Enum.map(all_entries, fn {ts, _} -> ts end)

      # Should only have recent entries
      assert Enum.all?(timestamps, fn ts -> ts >= now - 70 end)
    end
  end

  describe "update_from_response/1" do
    test "processes Binance rate limit headers" do
      response = %Req.Response{
        status: 200,
        headers: [
          {"x-mbx-used-weight-1m", "75"},
          {"x-mbx-order-count-1m", "10"}
        ],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)
    end

    test "handles response without rate limit headers" do
      response = %Req.Response{
        status: 200,
        headers: [
          {"content-type", "application/json"}
        ],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)
    end
  end

  describe "get_status/1" do
    test "returns correct status for spot endpoint" do
      # Add some usage
      for i <- 1..250 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      status = RateLimiter.get_status("/api/v3/ticker")

      assert status.used == 250
      assert status.limit == 1200
      assert status.window == 60
      assert status.remaining == 950
      assert is_integer(status.reset_at)
    end

    test "returns correct status for futures endpoint" do
      # Add some usage
      for i <- 1..500 do
        RateLimiter.check_and_increment("/fapi/v1/ticker", 1)
      end

      status = RateLimiter.get_status("/fapi/v1/ticker")

      assert status.used == 500
      assert status.limit == 2400
      assert status.window == 60
      assert status.remaining == 1900
      assert is_integer(status.reset_at)
    end

    test "defaults to spot when endpoint is nil" do
      status = RateLimiter.get_status(nil)
      assert status.limit == 1200
    end
  end

  describe "reset/1" do
    test "resets specific endpoint table" do
      # Add usage to both tables
      for i <- 1..100 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
        RateLimiter.check_and_increment("/fapi/v1/ticker", 1)
      end

      # Reset only spot
      assert :ok = RateLimiter.reset("/api/v3/ticker")

      # Spot should be reset
      spot_status = RateLimiter.get_status("/api/v3/ticker")
      assert spot_status.used == 0

      # Futures should still have usage
      futures_status = RateLimiter.get_status("/fapi/v1/ticker")
      assert futures_status.used == 100
    end

    test "resets all tables when endpoint is nil" do
      # Add usage to both tables
      for i <- 1..100 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
        RateLimiter.check_and_increment("/fapi/v1/ticker", 1)
      end

      # Reset all
      assert :ok = RateLimiter.reset(nil)

      # Both should be reset
      spot_status = RateLimiter.get_status("/api/v3/ticker")
      futures_status = RateLimiter.get_status("/fapi/v1/ticker")

      assert spot_status.used == 0
      assert futures_status.used == 0
    end
  end

  describe "get_limits/0" do
    test "returns complete limit configuration" do
      limits = RateLimiter.get_limits()

      assert limits.spot.limit == 1200
      assert limits.spot.window == 60
      assert "/api" in limits.spot.endpoints

      assert limits.futures.limit == 2400
      assert limits.futures.window == 60
      assert "/fapi" in limits.futures.endpoints
    end
  end

  describe "concurrent access" do
    test "handles concurrent requests correctly" do
      # Spawn multiple processes making requests concurrently
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            for j <- 1..10 do
              RateLimiter.check_and_increment("/api/v3/ticker", 1)
            end
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)

      # Should have tracked exactly 1000 requests
      status = RateLimiter.get_status("/api/v3/ticker")
      assert status.used == 1000
    end

    test "rate limiting is consistent under concurrency" do
      # Fill almost to limit
      for i <- 1..1190 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      # Spawn 20 concurrent requests
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            RateLimiter.check_and_increment("/api/v3/ticker", 1)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # Exactly 10 should succeed, 10 should fail
      successes = Enum.count(results, &(&1 == :ok))
      failures = Enum.count(results, &(&1 == {:error, :rate_limited}))

      assert successes == 10
      assert failures == 10
    end
  end
end
