defmodule ZenCex.Adapters.Binance.RateLimiterIntegrationTest do
  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance.RateLimiter

  @moduletag :integration
  @moduletag timeout: 30_000

  setup do
    # Clean up and initialize tables
    RateLimiter.cleanup_tables()
    RateLimiter.init_tables()

    on_exit(fn ->
      RateLimiter.cleanup_tables()
    end)

    :ok
  end

  describe "real API interaction" do
    test "respects rate limits with actual API calls" do
      # Only make a few real calls to avoid DDoS
      # Binance public endpoints don't require auth
      base_url = "https://api.binance.com"

      # Make 5 lightweight public API calls with rate limiting
      results =
        for _i <- 1..5 do
          # Check rate limit before making request
          case RateLimiter.check_and_increment("/api/v3/ping", 1) do
            :ok ->
              # Make actual API call
              response =
                Req.get!(
                  base_url <> "/api/v3/ping",
                  finch: ZenCex.Finch,
                  receive_timeout: 5_000
                )

              # Update rate limiter from response headers
              RateLimiter.update_from_response(response)

              # Add a small delay to be respectful
              Process.sleep(200)

              {:ok, response.status}

            {:error, :rate_limited} ->
              {:error, :rate_limited}
          end
        end

      # All should succeed since we're well under the limit
      assert Enum.all?(results, fn
               {:ok, 200} -> true
               _ -> false
             end)

      # Check our tracking
      status = RateLimiter.get_status("/api/v3/ping")
      assert status.used == 5
      assert status.remaining == 1195
    end

    test "tracks different weights for different endpoints" do
      base_url = "https://api.binance.com"

      # Test with different endpoint weights
      # ping = weight 1, time = weight 1, exchangeInfo = weight 10
      endpoints = [
        {"/api/v3/ping", 1},
        {"/api/v3/time", 1},
        # Heavy endpoint
        {"/api/v3/exchangeInfo", 10}
      ]

      total_weight =
        Enum.reduce(endpoints, 0, fn {endpoint, weight}, acc ->
          # Check rate limit with proper weight
          assert :ok = RateLimiter.check_and_increment(endpoint, weight)

          # Make the actual call (only for lightweight endpoints)
          if weight == 1 do
            response =
              Req.get!(
                base_url <> endpoint,
                finch: ZenCex.Finch,
                receive_timeout: 5_000
              )

            assert response.status == 200
            RateLimiter.update_from_response(response)

            # Be respectful
            Process.sleep(300)
          end

          acc + weight
        end)

      # Verify tracking
      status = RateLimiter.get_status("/api/v3/ping")
      assert status.used == total_weight
      # 1 + 1 + 10
      assert status.used == 12
    end

    test "handles rate limit headers from real responses" do
      base_url = "https://api.binance.com"

      # Make a single real API call
      assert :ok = RateLimiter.check_and_increment("/api/v3/time", 1)

      response =
        Req.get!(
          base_url <> "/api/v3/time",
          finch: ZenCex.Finch,
          receive_timeout: 5_000
        )

      # Check for rate limit headers
      headers = Map.new(response.headers)

      # Binance includes these headers
      case headers["x-mbx-used-weight-1m"] do
        [weight_str | _] when is_binary(weight_str) ->
          # Header is a list
          weight = String.to_integer(weight_str)
          assert weight > 0

        weight_str when is_binary(weight_str) ->
          # Header is a string
          weight = String.to_integer(weight_str)
          assert weight > 0

        _ ->
          # No header present
          :ok
      end

      # Update from response should handle both formats
      assert :ok = RateLimiter.update_from_response(response)
    end

    test "simulates approaching rate limit safely" do
      # Don't actually hit the API 1200 times!
      # Instead, artificially fill the rate limiter and test behavior

      # Fill to 1195 (leaving room for 5 more requests)
      now = System.system_time(:second)
      :ets.insert(:binance_spot_limits, {now, 1195})

      # Now make a few real requests to test near-limit behavior
      results =
        for _i <- 1..10 do
          case RateLimiter.check_and_increment("/api/v3/ping", 1) do
            :ok ->
              # Only make real call if rate limit allows
              response =
                Req.get!(
                  "https://api.binance.com/api/v3/ping",
                  finch: ZenCex.Finch,
                  receive_timeout: 5_000
                )

              Process.sleep(100)
              {:ok, response.status}

            {:error, :rate_limited} ->
              {:error, :rate_limited}
          end
        end

      # First 5 should succeed, rest should be rate limited
      {successes, failures} =
        Enum.split_with(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert length(successes) == 5
      assert length(failures) == 5
      assert Enum.all?(failures, &(&1 == {:error, :rate_limited}))
    end

    test "verifies futures endpoint tracking" do
      # Test with a futures endpoint (if we had futures API access)
      # For now, just verify the tracking works correctly

      # Simulate futures requests without hitting real API
      for _i <- 1..10 do
        assert :ok = RateLimiter.check_and_increment("/fapi/v1/ping", 1)
      end

      spot_status = RateLimiter.get_status("/api/v3/ping")
      futures_status = RateLimiter.get_status("/fapi/v1/ping")

      # Verify separate tracking
      assert spot_status.used == 0
      assert spot_status.limit == 1200

      assert futures_status.used == 10
      assert futures_status.limit == 2400
    end
  end

  describe "sliding window with time simulation" do
    test "verifies window expiration without waiting 60 seconds" do
      now = System.system_time(:second)

      # Insert data at different timestamps to simulate time passing
      # Should expire
      :ets.insert(:binance_spot_limits, {now - 65, 100})
      # Should count
      :ets.insert(:binance_spot_limits, {now - 55, 200})
      # Should count
      :ets.insert(:binance_spot_limits, {now - 30, 300})
      # Should count
      :ets.insert(:binance_spot_limits, {now - 10, 400})

      # Make a new request to trigger cleanup
      assert :ok = RateLimiter.check_and_increment("/api/v3/ping", 1)

      status = RateLimiter.get_status("/api/v3/ping")
      # Should be 200 + 300 + 400 + 1 = 901 (excluding expired)
      assert status.used == 901
      assert status.remaining == 299
    end
  end
end
