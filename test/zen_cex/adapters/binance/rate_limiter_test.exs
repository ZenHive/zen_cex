defmodule ZenCex.Adapters.Binance.RateLimiterTest do
  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance.RateLimiter

  # Performance threshold in microseconds
  @performance_threshold_us 100

  # Test buckets for rate limit testing
  @test_bucket_size 10

  setup do
    # Initialize rate limiter
    RateLimiter.init()

    # Reset state before each test
    RateLimiter.reset()

    :ok
  end

  describe "check_and_increment/2" do
    test "allows requests within limits" do
      # Test with small weight that should always pass
      assert :ok = RateLimiter.check_and_increment("/api/v3/time", 1)
      assert :ok = RateLimiter.check_and_increment("/api/v3/exchangeInfo", 1)
    end

    test "tracks cumulative weight correctly" do
      # Add requests with different weights
      # /api/v3/account is authenticated (UID)
      assert :ok = RateLimiter.check_and_increment("/api/v3/account", 10)
      # /api/v3/time is public (IP only)
      assert :ok = RateLimiter.check_and_increment("/api/v3/time", 1)

      status = RateLimiter.get_status()

      # /api/v3/time counts against IP
      assert status.ip.used == 1
      # /api/v3/account counts against UID
      assert status.uid.used == 10
    end

    test "enforces rate limits using buckets" do
      # Test rate limiting with controlled buckets
      # This avoids hammering the API while still testing limits
      # IP limit is 1200, let's use requests of weight 150 to hit it after 8 requests

      results =
        for bucket <- 1..2 do
          # Process a bucket of requests
          bucket_results =
            for i <- 1..@test_bucket_size do
              # Use high weight to trigger limits faster (150 * 8 = 1200)
              # Use /api/v3/time which is IP-limited
              result = RateLimiter.check_and_increment("/api/v3/time", 150)

              # Small delay within bucket to avoid burst
              Process.sleep(10)

              {i, result, bucket}
            end

          # Don't delay between buckets for this test
          bucket_results
        end
        |> List.flatten()

      # Should see some rate limit errors after filling the window
      # With 2 buckets of 10 requests at 150 weight each = 3000 total weight
      # IP limit is 1200, so we should get errors after ~8 requests
      errors =
        Enum.filter(results, fn {_i, result, _bucket} ->
          match?({:error, {:rate_limited, _}}, result)
        end)

      assert length(errors) > 0, "Expected some rate limit errors"

      # Verify retry_after is reasonable
      case List.first(errors) do
        {_i, {:error, {:rate_limited, retry_after_ms}}, _bucket} ->
          assert retry_after_ms > 0
          # Should be within the window
          assert retry_after_ms <= 60_000

        _ ->
          :ok
      end
    end

    test "emergency operations bypass rate limits" do
      # Fill up IP rate limits first (since we're using /api/v3/time which is IP-limited)
      # IP limit is 1200, so let's use 13 requests of 100 weight each = 1300
      for _ <- 1..13 do
        RateLimiter.check_and_increment("/api/v3/time", 100)
      end

      # Verify we're rate limited for normal operations
      assert {:error, {:rate_limited, _}} =
               RateLimiter.check_and_increment("/api/v3/time", 1)

      # But emergency operations should still work
      # Note: These will log warnings but should always succeed
      assert :ok = RateLimiter.check_and_increment("DELETE /api/v3/order", 1)
      assert :ok = RateLimiter.check_and_increment("DELETE /api/v3/openOrders", 1)
    end

    test "sliding window removes old requests" do
      # Add a request
      assert :ok = RateLimiter.check_and_increment("/api/v3/time", 1)

      initial_status = RateLimiter.get_status()
      assert initial_status.ip.used == 1

      # Simulate old request by manipulating ETS directly (for testing only)
      # In production, this would happen naturally over time
      [{_, requests}] = :ets.lookup(:binance_rate_limits, :requests)

      # Create an old request (61 seconds ago)
      old_request = %{
        timestamp: System.system_time(:millisecond) - 61_000,
        endpoint: "/api/v3/old",
        weight: 10,
        type: :ip
      }

      :ets.insert(:binance_rate_limits, {:requests, [old_request | requests]})

      # Status should not include the old request
      current_status = RateLimiter.get_status()
      # Only the new request
      assert current_status.ip.used == 1
    end
  end

  describe "update_from_response/1" do
    test "updates usage from response headers" do
      response = %Req.Response{
        status: 200,
        headers: [
          {"x-mbx-used-weight-1m", "42"},
          {"x-mbx-used-weight-1m-uid", "100"}
        ],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)

      # Verify counters were updated
      [{_, ip_used}] = :ets.lookup(:binance_rate_limits, :ip_used)
      [{_, uid_used}] = :ets.lookup(:binance_rate_limits, :uid_used)

      assert ip_used == 42
      assert uid_used == 100
    end

    test "handles missing headers gracefully" do
      response = %Req.Response{
        status: 200,
        headers: [],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)
    end

    test "handles malformed headers gracefully" do
      response = %Req.Response{
        status: 200,
        headers: [
          {"x-mbx-used-weight-1m", "not-a-number"},
          {"x-mbx-used-weight-1m-uid", ""}
        ],
        body: %{}
      }

      assert :ok = RateLimiter.update_from_response(response)
    end
  end

  describe "get_status/1" do
    test "returns current rate limit status" do
      # Add some requests
      # IP only
      RateLimiter.check_and_increment("/api/v3/time", 1)
      # UID only
      RateLimiter.check_and_increment("/api/v3/account", 10)

      status = RateLimiter.get_status()

      assert is_map(status)
      assert Map.has_key?(status, :ip)
      assert Map.has_key?(status, :uid)

      # Only the time endpoint
      assert status.ip.used == 1
      # Default limit
      assert status.ip.limit == 1200
      assert status.ip.window == 60
      assert is_integer(status.ip.reset_at)

      # Only the account endpoint
      assert status.uid.used == 10
      # Default limit
      assert status.uid.limit == 6000
      assert status.uid.window == 60
      assert is_integer(status.uid.reset_at)
    end

    test "includes endpoint info when specified" do
      status = RateLimiter.get_status("/api/v3/account")

      assert status.endpoint == "/api/v3/account"
    end
  end

  describe "reset/1" do
    test "clears all rate limit tracking" do
      # Add some requests
      RateLimiter.check_and_increment("/api/v3/time", 5)
      RateLimiter.check_and_increment("/api/v3/account", 10)

      # Verify they're tracked
      status_before = RateLimiter.get_status()
      assert status_before.ip.used > 0

      # Reset
      assert :ok = RateLimiter.reset()

      # Verify cleared
      status_after = RateLimiter.get_status()
      assert status_after.ip.used == 0
      assert status_after.uid.used == 0
    end
  end

  describe "get_limits/0" do
    test "returns configured limits and endpoint weights" do
      limits = RateLimiter.get_limits()

      assert is_map(limits)
      assert limits.ip.limit == 1200
      assert limits.ip.window == 60
      assert limits.uid.limit == 6000
      assert limits.uid.window == 60

      # Check endpoint weights
      assert is_map(limits.endpoints)
      assert limits.endpoints["GET /api/v3/account"] == 10
      assert limits.endpoints["POST /api/v3/order"] == 1
    end
  end

  describe "performance" do
    test "check_and_increment performs under #{@performance_threshold_us}μs" do
      # Warm up
      RateLimiter.check_and_increment("/api/v3/time", 1)

      # Measure performance
      measurements =
        for _ <- 1..100 do
          start = System.monotonic_time()
          RateLimiter.check_and_increment("/api/v3/time", 1)
          duration = System.monotonic_time() - start
          System.convert_time_unit(duration, :native, :microsecond)
        end

      avg_duration = Enum.sum(measurements) / length(measurements)
      max_duration = Enum.max(measurements)

      assert avg_duration < @performance_threshold_us,
             "Average duration #{avg_duration}μs exceeds threshold #{@performance_threshold_us}μs"

      assert max_duration < @performance_threshold_us * 2,
             "Max duration #{max_duration}μs exceeds 2x threshold"
    end

    test "handles concurrent requests efficiently" do
      # Test concurrent access using Task.async_stream
      tasks =
        1..100
        |> Task.async_stream(
          fn i ->
            endpoint = if rem(i, 2) == 0, do: "/api/v3/time", else: "/api/v3/account"
            weight = if rem(i, 3) == 0, do: 10, else: 1

            start = System.monotonic_time()
            result = RateLimiter.check_and_increment(endpoint, weight)
            duration = System.monotonic_time() - start

            {result, System.convert_time_unit(duration, :native, :microsecond)}
          end,
          max_concurrency: 10,
          timeout: 5000
        )
        |> Enum.to_list()

      # All tasks should complete
      assert length(tasks) == 100

      # Check performance
      durations = Enum.map(tasks, fn {:ok, {_result, duration}} -> duration end)
      avg_duration = Enum.sum(durations) / length(durations)

      assert avg_duration < @performance_threshold_us * 2,
             "Concurrent average #{avg_duration}μs exceeds threshold"
    end
  end

  describe "cleanup" do
    test "old entries are cleaned up automatically" do
      # Add old and new requests to ETS directly
      now = System.system_time(:millisecond)

      old_requests =
        for i <- 1..10 do
          %{
            # 130+ seconds old (beyond 60s window + 60s buffer = 120s)
            timestamp: now - (130_000 + i * 1000),
            endpoint: "/api/v3/old_#{i}",
            weight: 1,
            type: :ip
          }
        end

      new_requests =
        for i <- 1..5 do
          %{
            # Recent
            timestamp: now - i * 1000,
            endpoint: "/api/v3/new_#{i}",
            weight: 1,
            type: :ip
          }
        end

      all_requests = old_requests ++ new_requests
      :ets.insert(:binance_rate_limits, {:requests, all_requests})

      # Trigger cleanup manually for testing
      RateLimiter.perform_cleanup()

      # Check that old requests were removed
      [{_, remaining}] = :ets.lookup(:binance_rate_limits, :requests)

      # All old requests (70+ seconds) should be removed
      # Only new requests (< 70 seconds) should remain
      assert length(remaining) == 5

      # All remaining should be recent (within 120s window)
      Enum.each(remaining, fn req ->
        age_ms = now - req.timestamp
        assert age_ms < 120_000, "Found old request that should have been cleaned"
      end)
    end
  end
end
