# defmodule ZenCex.Adapters.Binance.RateLimitIntegrationTest do
#   @moduledoc """
#   WARNING: This test file needs to be rewritten for the plugin architecture.

#   Current issues:
#   - Still references old centralized ZenCex.RateLimit module (lines below)
#   - Should use ZenCex.Adapters.Binance.RateLimiter instead (to be implemented Day 1)
#   - References methods that don't exist in the placeholder Adapter

#   TODO: Rewrite these tests when implementing the Binance adapter modules.
#   The test patterns (real API calls, Req.Test mocking) are good but need
#   to be adapted to the plugin architecture where each adapter has its own rate limiter.

#   See docs/cex-implementation-tasks.md for the implementation timeline.
#   """

#   use ExUnit.Case, async: true

#   alias ZenCex.Adapters.Binance.Adapter
#   alias ZenCex.Adapters.Binance.RateLimiter

#   describe "rate limiting with real API (safe tests)" do
#     @tag :integration
#     test "counts real requests accurately without approaching limits" do
#       # Start with clean rate limit state
#       {:ok, _} = Application.ensure_all_started(:zen_cex)

#       # Get initial usage - Plugin architecture: each adapter has its own rate limiter
#       {:ok, %{used: initial_used, limit: limit}} = RateLimiter.get_current_usage(:spot)

#       # Make exactly 2 lightweight requests (weight = 1 each)
#       {:ok, _time1} = Adapter.get_server_time()

#       # Get usage after first request
#       {:ok, %{used: after_first}} = RateLimiter.get_current_usage(:spot)

#       {:ok, _time2} = Adapter.get_server_time()

#       # Verify counter increased after requests
#       {:ok, %{used: new_used, limit: ^limit}} = RateLimiter.get_current_usage(:spot)

#       # The counter should have increased from the initial value
#       # But we need to account for possible resets or other tests running
#       assert new_used >= after_first, "Counter should not decrease"
#       assert after_first >= initial_used, "Counter should not decrease"

#       # Verify we're FAR from the limit (safety check)
#       assert new_used < 100, "Rate limit usage too high for safe testing: #{new_used}/#{limit}"
#       assert limit == 1200, "Expected Binance spot limit to be 1200"
#     end

#     @tag :integration
#     test "different endpoints have different weights" do
#       {:ok, _} = Application.ensure_all_started(:zen_cex)

#       # Check that our weight calculation is working
#       # We can verify this without making actual requests

#       # Plugin architecture: RateLimiter calculates weights
#       assert RateLimiter.calculate_weight("/api/v3/ticker/price", :get, %{}) == 1
#       assert RateLimiter.calculate_weight("/api/v3/order", :post, %{}) == 10
#       assert RateLimiter.calculate_weight("/api/v3/account", :get, %{}) == 10
#     end
#   end

#   describe "rate limiting with Req.Test (mock tests)" do
#     test "prevents requests when rate limit would be exceeded" do
#       # Start fresh with rate limiter
#       {:ok, _} = Application.ensure_all_started(:zen_cex)

#       # First, fill up the rate limit to just under the threshold
#       # Binance spot limit is 1200, so let's get to 1199
#       {current_used, limit} = RateLimit.get_usage(:binance_spot)
#       assert limit == 1200

#       # Calculate how much we need to add to get close to the limit
#       target_usage = 1199
#       needed_weight = max(0, target_usage - current_used)

#       # Add weight to get close to limit (if we're not already there)
#       if needed_weight > 0 do
#         :ok = RateLimit.check_and_increment(:binance_spot, "/api/v3/time", needed_weight)
#       end

#       # Verify we're at the expected usage
#       {new_used, ^limit} = RateLimit.get_usage(:binance_spot)

#       assert new_used >= target_usage - 5,
#              "Expected usage around #{target_usage}, got #{new_used}"

#       # Now the next request with weight 2 should be blocked (1199 + 2 = 1201 > 1200)
#       assert {:error, :rate_limited} =
#                RateLimit.check_and_increment(:binance_spot, "/api/v3/time", 2)
#     end

#     test "handles 429 responses correctly" do
#       stub_name = :"binance_429_#{System.unique_integer()}"

#       Req.Test.stub(stub_name, fn conn ->
#         # Simulate 429 Too Many Requests with a short retry-after
#         conn
#         |> Plug.Conn.put_status(429)
#         |> Plug.Conn.put_resp_header("retry-after", "1")
#         |> Req.Test.json(%{"msg" => "Too many requests"})
#       end)

#       # Test that our adapter handles 429 correctly
#       # Create a request with minimal retry configuration to avoid long waits
#       request =
#         Req.new(plug: {Req.Test, stub_name})
#         |> Req.merge(
#           base_url: "https://api.binance.com",
#           url: "/api/v3/account",
#           # Disable retries for faster test
#           retry: false
#         )

#       response = Req.request(request)

#       # Should get a 429 response without retries
#       assert {:ok, %{status: 429}} = response
#     end

#     test "separate limits for spot vs futures" do
#       {:ok, _} = Application.ensure_all_started(:zen_cex)

#       # Reset both counters
#       {_spot_used, spot_limit} = RateLimit.get_usage(:binance_spot)
#       {_futures_used, futures_limit} = RateLimit.get_usage(:binance_futures)

#       # Verify different limits
#       assert spot_limit == 1200
#       assert futures_limit == 2400

#       # Test that requests to different endpoints use different counters
#       # These should track separately
#       assert :ok = RateLimit.check_and_increment(:binance_spot, "/api/v3/time", 1)
#       assert :ok = RateLimit.check_and_increment(:binance_futures, "/fapi/v1/time", 1)

#       {spot_used, _} = RateLimit.get_usage(:binance_spot)
#       {futures_used, _} = RateLimit.get_usage(:binance_futures)

#       # Each should have incremented independently
#       assert spot_used >= 1
#       assert futures_used >= 1
#     end
#   end

#   describe "weight calculation (pure function tests)" do
#     test "calculates correct weights for different operations" do
#       # These are pure function tests - no API calls

#       # Market data - weight 1
#       ticker_req = %{options: %{url: "/api/v3/ticker/price", method: :get, params: %{}}}
#       assert get_weight(ticker_req) == 1

#       # Order operations - weight 10
#       order_req = %{options: %{url: "/api/v3/order", method: :post, params: %{}}}
#       assert get_weight(order_req) == 10

#       # Account info - weight 10
#       account_req = %{options: %{url: "/api/v3/account", method: :get, params: %{}}}
#       assert get_weight(account_req) == 10

#       # Depth with limits
#       depth_small = %{options: %{url: "/api/v3/depth", method: :get, params: %{limit: 50}}}
#       assert get_weight(depth_small) == 1

#       depth_medium = %{options: %{url: "/api/v3/depth", method: :get, params: %{limit: 500}}}
#       assert get_weight(depth_medium) == 5

#       depth_large = %{options: %{url: "/api/v3/depth", method: :get, params: %{limit: 1000}}}
#       assert get_weight(depth_large) == 10

#       depth_xlarge = %{options: %{url: "/api/v3/depth", method: :get, params: %{limit: 5000}}}
#       assert get_weight(depth_xlarge) == 50
#     end
#   end

#   # Helper to access private function for testing
#   defp get_weight(request) do
#     # We need to make calculate_request_weight public or test it indirectly
#     # For now, we'll test it through the module
#     apply(ZenCex.Adapters.Binance.Adapter, :calculate_request_weight, [request])
#   rescue
#     UndefinedFunctionError ->
#       # Function is private, so we test indirectly through integration
#       1
#   end
# end
