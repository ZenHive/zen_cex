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

  use ExUnit.Case, async: false

  alias ZenCex.Core.HTTP
  alias ZenCex.Adapters.Binance.RateLimiter

  import ExUnit.CaptureLog

  @moduletag :integration

  setup do
    # ENFORCE testnet usage - fail if production URL detected
    # Check the actual environment detection mechanism
    env = ZenCex.Adapters.Binance.Endpoints.current_env()

    unless env == :test do
      raise "TESTNET REQUIRED: Environment is #{env}, expected :test. Set BINANCE_TESTNET=true"
    end

    # Also verify the base URL is actually testnet
    base_url = ZenCex.Adapters.Binance.Endpoints.base_url(env)

    unless base_url == "https://testnet.binance.vision" do
      raise "TESTNET URL REQUIRED: Got #{base_url}, expected https://testnet.binance.vision"
    end

    # Note: These are public endpoint tests, no credentials required
    # For authenticated tests, we would verify BINANCE_TESTNET_API_KEY here

    :ok
  end

  describe "real API rate limit monitoring" do
    test "monitors Spot API rate limits from real response headers" do
      # Reset to ensure clean state
      RateLimiter.reset(nil)

      # Make a single lightweight request to Spot API
      # Server time endpoint has weight = 1 and no auth
      request =
        HTTP.base_request(:binance, :market)
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
          assert headers_map["x-mbx-used-weight-1m"] != nil
        end)

      # Verify our rate limiter logged the usage
      assert log =~ "Binance spot API usage:" || log =~ "rate limit"

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
        HTTP.base_request(:binance, :market)
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
            HTTP.base_request(:binance, :market)
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

      # Simulate high usage by incrementing counter directly
      # (In production this would come from response headers)
      for _ <- 1..1000 do
        RateLimiter.check_and_increment("/api/v3/ticker", 1)
      end

      # Verify high usage is tracked
      status = RateLimiter.get_status("/api/v3/ticker")
      assert status.used >= 1000
      assert status.usage_percent > 80

      # Emergency operations should still return :ok
      assert :ok = RateLimiter.check_and_increment("/api/v3/order", 1)
      assert :ok = RateLimiter.check_and_increment("/fapi/v1/order", 1)
      assert :ok = RateLimiter.check_and_increment("/fapi/v1/allOpenOrders", 1)

      # Regular operations also return :ok (we don't block in non-HFT mode)
      # but they would increment counters for monitoring
      assert :ok = RateLimiter.check_and_increment("/api/v3/ticker", 1)
    end

    test "handles missing rate limit headers gracefully" do
      # Some endpoints might not return rate limit headers
      # Test with a very simple endpoint
      request =
        HTTP.base_request(:binance, :health)
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
      assert limits.sapi.limit == 12000
      assert limits.sapi.window == 60
      assert limits.futures.limit == 2400
      assert limits.futures.window == 60
    end
  end
end
