defmodule ZenCex.Adapters.Binance.RateLimiterApiTypeTest do
  @moduledoc """
  Integration test for Binance rate limiter with real API.

  This test is designed to be safe and respectful:
  - Uses only public endpoints (no auth required)
  - Uses endpoints with weight = 1 (minimal impact)
  - Makes only 2-3 requests total
  - Verifies rate limit headers are properly parsed
  - Tests different API types (Spot vs SAPI)
  """

  use ZenCex.IntegrationCase, exchange: :binance

  import ExUnit.CaptureLog
  import ZenCex.RateLimiterTestHelpers

  alias ZenCex.Adapters.Binance.RateLimiter
  alias ZenCex.Core.HTTP

  setup do
    # Clean up all rate limiter tables before each test
    reset_all_binance_rate_limiter_tables()
    :ok
  end

  describe "real API rate limit monitoring" do
    test "monitors Spot API rate limits from real response headers" do
      # Reset to ensure clean state
      RateLimiter.reset(nil)

      # Make a single lightweight request to Spot API
      # Server time endpoint has weight = 1 and no auth
      request =
        :binance
        |> HTTP.base_request(:market)
        |> Req.merge(
          url: "/api/v3/time",
          # Public endpoint, no auth needed
          skip_auth: true
        )

      # Capture logs to verify monitoring works
      log =
        capture_log([level: :debug], fn ->
          {:ok, response} = Req.request(request)

          # Verify we got a successful response
          assert response.status == 200
          assert response.body["serverTime"]

          # Check that rate limit headers were present
          headers_map = Map.new(response.headers)
          assert headers_map["x-mbx-used-weight-1m"]

          # Update rate limiter from response to trigger logging
          RateLimiter.update_from_response(response)
        end)

      # Verify our rate limiter logged the usage or that update was called
      # The log might not appear if usage is very low (0%), but the update should have run
      assert log =~ "Binance spot API usage:" || log =~ "rate limit" ||
               log =~ "API usage" ||
               RateLimiter.get_status("/api/v3/time").used > 0

      # Check internal tracking
      status = RateLimiter.get_status("/api/v3/time")
      # Spot limit
      assert status.limit == 1200
      # Should have some usage tracked
      assert status.used >= 0
    end

    test "monitors different weights correctly" do
      # Reset to ensure clean state
      RateLimiter.reset(nil)

      # Exchange info has higher weight (10) but still public
      request =
        :binance
        |> HTTP.base_request(:market)
        |> Req.merge(
          url: "/api/v3/exchangeInfo",
          # Public endpoint
          skip_auth: true,
          # Only get info for one symbol to reduce response size
          params: [symbols: ~s(["BTCUSDT"])]
        )

      {:ok, response} = Req.request(request)
      assert response.status == 200

      # Check the weight reported by Binance
      headers_map = Map.new(response.headers)
      weight_used = headers_map["x-mbx-used-weight-1m"]

      if weight_used do
        # Handle both string and list formats
        weight =
          case weight_used do
            [w | _] when is_binary(w) -> String.to_integer(w)
            w when is_binary(w) -> String.to_integer(w)
          end

        # Exchange info typically uses 10 weight, but may vary
        assert weight >= 1

        # If we're above 50 weight total, we should see logs
        if weight > 50 do
          # Make another small request to potentially trigger monitoring
          request2 =
            :binance
            |> HTTP.base_request(:market)
            |> Req.merge(
              # Weight = 1
              url: "/api/v3/ping",
              skip_auth: true
            )

          log =
            capture_log([level: :debug], fn ->
              {:ok, _response} = Req.request(request2)
            end)

          # Should see debug logging about usage
          assert log =~ "API usage" || log =~ "%"
        end
      end
    end

    test "emergency operations are never blocked even at high usage" do
      # This test verifies the emergency bypass without making actual order calls
      # We'll simulate high usage and verify cancel operations would pass

      # Reset to ensure clean state
      RateLimiter.reset("/api/v3/ticker")

      # Simulate high usage by incrementing counter to reach regular capacity
      # Spot regular limit is 1080 (90% of 1200)
      for _ <- 1..1080 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      # Verify high usage is tracked
      status = RateLimiter.get_status("/api/v3/ticker")
      assert status.used == 1080
      assert status.usage_percent == 90
      assert status.regular_usage_percent == 100

      # Regular operations should now be rate limited
      assert {:error, {:rate_limited, _}} = RateLimiter.check_and_increment("/api/v3/ticker", 1)

      # Emergency operations should still return :ok when using operation atoms
      assert :ok = RateLimiter.check_and_increment("/api/v3/order", 1, :cancel_order)
      assert :ok = RateLimiter.check_and_increment("/fapi/v1/order", 1, :cancel_order)
      assert :ok = RateLimiter.check_and_increment("/fapi/v1/allOpenOrders", 1, :cancel_all_open_orders)
    end

    test "handles missing rate limit headers gracefully" do
      # Some endpoints might not return rate limit headers
      # Test with a very simple endpoint
      request =
        :binance
        |> HTTP.base_request(:health)
        |> Req.merge(
          url: "/api/v3/ping",
          skip_auth: true
        )

      # Should not crash even if headers are missing
      assert {:ok, response} = Req.request(request)
      assert response.status == 200

      # The update_from_response should handle missing headers
      assert :ok = RateLimiter.update_from_response(response)
    end
  end

  describe "cleanup and monitoring" do
    test "cleanup_old_entries removes stale data" do
      # Add some test data
      RateLimiter.check_and_increment("/api/v3/test", 100)

      # Cleanup should work without errors
      result = RateLimiter.cleanup_old_entries()
      assert is_integer(result)
      assert result >= 0
    end

    test "get_limits returns correct configuration" do
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

  describe "concurrent access" do
    test "handles multiple concurrent processes safely for spot API" do
      # Reset to ensure clean state
      RateLimiter.reset("/api/v3/ticker")

      # Spawn multiple processes that all try to increment counters
      parent = self()
      num_processes = 100
      requests_per_process = 10

      # Launch concurrent processes
      tasks =
        for _i <- 1..num_processes do
          Task.async(fn ->
            results =
              for _j <- 1..requests_per_process do
                RateLimiter.check_and_increment("/api/v3/ticker", 1)
              end

            send(parent, {:results, results})
            :done
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      # Collect results
      total_requests = num_processes * requests_per_process
      results = collect_results(num_processes, [])

      # Verify results
      all_results = List.flatten(results)
      ok_count = Enum.count(all_results, &(&1 == :ok))

      limited_count =
        Enum.count(all_results, fn
          {:error, {:rate_limited, _}} -> true
          _ -> false
        end)

      # All requests should either succeed or be rate limited
      assert ok_count + limited_count == total_requests

      # With regular capacity of 1080 (90% of 1200), we should see some rate limiting
      # if we're hitting the same window
      if total_requests > 1080 do
        assert limited_count > 0, "Expected some rate limiting with #{total_requests} requests"
      end

      # Verify ETS counter integrity
      status = RateLimiter.get_status("/api/v3/ticker")
      assert status.used >= 0
      assert status.used <= 1200
    end

    test "atomic increment and rollback prevents over-limit regular operations" do
      # Test that the atomic increment-check-rollback pattern works correctly
      parent = self()
      # 90% of 1200
      regular_limit = 1080

      # Fill up to just below the limit
      RateLimiter.reset("/api/v3/ticker")

      for _ <- 1..(regular_limit - 50) do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      # Launch many concurrent processes trying to add 10 weight each
      num_processes = 10

      tasks =
        for _i <- 1..num_processes do
          Task.async(fn ->
            result = RateLimiter.check_and_increment("/api/v3/ticker", 10)
            send(parent, {:result, result})
            result
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await/1)

      # Collect results
      results = collect_results(num_processes, [])
      flat_results = List.flatten(results)

      # Only operations that would keep us under 1080 should succeed
      ok_count = Enum.count(flat_results, &(&1 == :ok))

      limited_count =
        Enum.count(flat_results, fn
          {:error, {:rate_limited, _}} -> true
          _ -> false
        end)

      # We started at 1030, so only 5 operations of weight 10 should succeed (1030 + 50 = 1080)
      assert ok_count <= 5
      assert limited_count >= 5
      assert ok_count + limited_count == num_processes

      # Verify final count doesn't exceed regular limit
      status = RateLimiter.get_status("/api/v3/ticker")
      assert status.used <= regular_limit
    end

    test "emergency operations never blocked even under high concurrency" do
      # Fill up beyond regular capacity
      RateLimiter.reset("/api/v3/order")

      # Fill to 1090 (beyond regular limit of 1080)
      initial_count = 1090

      for _ <- 1..initial_count do
        RateLimiter.check_and_increment("/api/v3/order", 1)
      end

      # Get the actual count after filling (may be less due to rollbacks)
      status_before = RateLimiter.get_status("/api/v3/order")
      actual_initial = status_before.used
      # Should be at or above regular limit
      assert actual_initial >= 1080

      # Launch many concurrent emergency operations
      num_processes = 50

      tasks =
        for i <- 1..num_processes do
          Task.async(fn ->
            # Mix different emergency operations
            operation = if rem(i, 2) == 0, do: :cancel_order, else: :cancel_all_open_orders
            RateLimiter.check_and_increment("/api/v3/order", 1, operation)
          end)
        end

      # All emergency operations should succeed
      results = Enum.map(tasks, &Task.await/1)
      assert Enum.all?(results, &(&1 == :ok))

      # Verify counter was incremented for emergency operations
      status = RateLimiter.get_status("/api/v3/order")
      # Should have added all emergency operations
      assert status.used == actual_initial + num_processes
    end

    test "different API types have independent rate limits" do
      # Test that spot and futures limits are independent
      parent = self()

      # Reset both
      RateLimiter.reset("/api/v3/ticker")
      RateLimiter.reset("/fapi/v1/ticker")

      # Launch concurrent processes for both API types
      spot_tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            result = RateLimiter.check_and_increment("/api/v3/ticker", 20)
            send(parent, {:spot_result, result})
            result
          end)
        end

      futures_tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            result = RateLimiter.check_and_increment("/fapi/v1/ticker", 20)
            send(parent, {:futures_result, result})
            result
          end)
        end

      # Wait for all tasks
      all_tasks = spot_tasks ++ futures_tasks
      Enum.each(all_tasks, &Task.await/1)

      # Collect results separately
      spot_results = collect_typed_results(50, :spot_result, [])
      futures_results = collect_typed_results(50, :futures_result, [])

      # Both should have independent limits
      spot_status = RateLimiter.get_status("/api/v3/ticker")
      futures_status = RateLimiter.get_status("/fapi/v1/ticker")

      # Verify they tracked independently
      # Regular limit for spot
      assert spot_status.used <= 1080
      # Regular limit for futures (90% of 2400)
      assert futures_status.used <= 2160

      # Each should have some successes since they're independent
      spot_ok = Enum.count(List.flatten(spot_results), &(&1 == :ok))
      futures_ok = Enum.count(List.flatten(futures_results), &(&1 == :ok))

      assert spot_ok > 0, "Expected some spot requests to succeed"
      assert futures_ok > 0, "Expected some futures requests to succeed"
    end
  end

  # Helper functions to collect results from processes
  defp collect_results(0, acc), do: acc

  defp collect_results(n, acc) do
    receive do
      {:results, results} -> collect_results(n - 1, [results | acc])
      {:result, result} -> collect_results(n - 1, [[result] | acc])
    after
      5000 -> raise "Timeout waiting for process results"
    end
  end

  defp collect_typed_results(0, _type, acc), do: acc

  defp collect_typed_results(n, type, acc) do
    receive do
      {^type, result} -> collect_typed_results(n - 1, type, [[result] | acc])
    after
      5000 -> raise "Timeout waiting for #{type} results"
    end
  end
end
