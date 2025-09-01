#!/usr/bin/env elixir
# Run with: mix run examples/rate_limiter_demo.exs

# Demo: Pragmatic rate limiting for non-HFT trading
# This shows how the rate limiter monitors but doesn't block

alias ZenCex.Core.HTTP
alias ZenCex.Adapters.Binance.RateLimiter

IO.puts """
===========================================
ZenCex Rate Limiter Demo (Non-HFT Approach)
===========================================

This demonstrates our pragmatic rate limiting:
1. Monitor rate limits from response headers
2. Log warnings when approaching limits
3. Never block requests (let Req handle 429s)
4. Emergency operations always allowed
"""

# Reset counters for clean demo
RateLimiter.reset(nil)

IO.puts "\n1. Making public API requests (no auth required)..."

# First request - Server time (weight = 1)
request1 =
  HTTP.base_request(:binance, :market)
  |> Req.merge(
    url: "/api/v3/time",
    skip_auth: true
  )

{:ok, response1} = Req.request(request1)
IO.puts "   ✓ Server time fetched: #{response1.body["serverTime"]}"

# Check status after first request
status = RateLimiter.get_status("/api/v3/time")
IO.puts "   Rate limit status: #{status.used}/#{status.limit} (#{status.usage_percent}%)"

# Second request - Exchange info for one symbol (weight ~10)
IO.puts "\n2. Fetching exchange info (higher weight)..."

request2 =
  HTTP.base_request(:binance, :market)
  |> Req.merge(
    url: "/api/v3/exchangeInfo",
    skip_auth: true,
    params: [symbols: ~s(["BTCUSDT"])]
  )

{:ok, response2} = Req.request(request2)
symbols = response2.body["symbols"] |> length()
IO.puts "   ✓ Exchange info fetched: #{symbols} symbol(s)"

# Check headers to see actual weight used
headers_map = Map.new(response2.headers)
if weight = headers_map["x-mbx-used-weight-1m"] do
  actual_weight = case weight do
    [w | _] when is_binary(w) -> w
    w when is_binary(w) -> w
  end
  IO.puts "   Actual weight reported by Binance: #{actual_weight}"
end

IO.puts "\n3. Simulating high usage scenario..."

# Simulate high usage (but don't actually make requests)
for _ <- 1..950 do
  RateLimiter.check_and_increment("/api/v3/ticker", 1)
end

status_high = RateLimiter.get_status("/api/v3/ticker")
IO.puts "   Simulated usage: #{status_high.used}/#{status_high.limit} (#{status_high.usage_percent}%)"

# Emergency operations still work
result = RateLimiter.check_and_increment("/api/v3/order", 1)
IO.puts "   Emergency operation (cancel order): #{inspect(result)}"
IO.puts "   ✓ Emergency operations are never blocked"

IO.puts "\n4. Rate limit monitoring in action..."

# Make a small request that should trigger warning logs
request3 =
  HTTP.base_request(:binance, :health)
  |> Req.merge(
    url: "/api/v3/ping",
    skip_auth: true
  )

{:ok, _response3} = Req.request(request3)
IO.puts "   ✓ Ping successful (logs show usage warnings if >80%)"

IO.puts "\n5. Cleanup demonstration..."

# Show cleanup works
deleted = RateLimiter.cleanup_old_entries()
IO.puts "   Cleaned up #{deleted} old entries"

# Show all API types have limits configured
limits = RateLimiter.get_limits()
IO.puts "\n6. Configured rate limits:"
IO.puts "   Spot API:    #{limits.spot.limit} requests/min"
IO.puts "   SAPI:        #{limits.sapi.limit} requests/min"
IO.puts "   Futures API: #{limits.futures.limit} requests/min"

IO.puts """

==========================================
Key Takeaways:
==========================================
1. Rate limiting is REACTIVE, not proactive
2. We monitor and log, but don't block
3. Req handles 429 responses with retry
4. Emergency operations always pass through
5. Perfect for non-HFT trading operations
==========================================
"""