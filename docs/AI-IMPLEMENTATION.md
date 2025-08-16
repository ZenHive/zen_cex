# ZenCex AI Implementation Guide

## CRITICAL: One Task Per Session Rule
**NEVER implement multiple modules in one session. Complete ONE task, update progress, then stop.**

## Quick Start for AI Coders

### Your Current Status
- **Architecture**: Req-powered adapters with built-in pooling, retry, telemetry
- **Progress**: 23% complete (7/30 tasks done) 
- **Next Task**: Remove redundant OTP - Req handles pooling, retry, telemetry
- **Priority**: Fully utilize Req's capabilities, avoid reimplementation
- **Focus**: Production-ready patterns with proper observability

### Navigation
1. Check "Current Task" section
2. Implement using "Essential Patterns"
3. Validate with "Success Criteria"
4. Update progress and stop

## Current Task

**Task #2**: Remove redundant OTP supervision - leverage Req's built-in features

**Why**: Req already provides connection pooling (Finch), retry logic, middleware pipeline, and telemetry. We don't need GenServers for what Req handles.

**Success Criteria**:
- [ ] Remove Core.Supervisor entirely
- [ ] Simplify Application to only start Finch
- [ ] Change RateLimiter.start_link to RateLimiter.init_tables
- [ ] Update tests to not expect supervision
- [ ] All existing tests still pass

## Essential Patterns

### Pattern 1: Req Request Step with Error Handling (Auth)
```elixir
# MUST return {request, options} tuple with proper error handling
def sign_request({request, options}) do
  with {:ok, api_key} <- fetch_credentials(:api_key),
       {:ok, secret} <- fetch_credentials(:api_secret),
       {:ok, signed_params} <- sign_params(request.options[:params], secret) do
    request = request
    |> Req.Request.put_header("x-mbx-apikey", api_key)
    |> Req.Request.merge_options(params: signed_params)
    
    {request, options}  # CRITICAL: Return tuple
  else
    {:error, reason} ->
      # Halt with proper error
      {Req.Request.halt(request), Keyword.put(options, :error, reason)}
  end
end
```

### Pattern 2: Rate Limiter with Sliding Window
```elixir
def rate_limit_step({request, options}) do
  exchange = request.private[:exchange]
  weight = calculate_weight(request)
  
  # Sliding window with microsecond precision
  now = System.os_time(:microsecond)
  window_start = now - :timer.seconds(60)
  
  # Atomic check and increment
  case check_and_consume_capacity(exchange, weight, window_start) do
    :ok -> 
      {request, options}
    {:error, :capacity_exceeded, retry_after} ->
      # Add retry-after header for client awareness
      request = request
      |> Req.Request.halt()
      |> Req.Request.put_private(:retry_after, retry_after)
      
      {request, Keyword.put(options, :error, {:rate_limited, retry_after})}
  end
end
```

### Pattern 3: Simple ETS Tables (No GenServer)
```elixir
# Just create tables at app startup, no process needed
def init_tables do
  :ets.new(:binance_rate_limits, [:named_table, :public, :set])
end

# Use atomic operations for concurrent access
:ets.update_counter(table, key, {2, increment}, {key, 0, 0})
```

### Pattern 4: Circuit Breaker as Req Middleware
```elixir
# Production pattern for fault tolerance
Req.Request.prepend_request_steps(req,
  circuit_breaker: fn {request, options} ->
    case check_circuit_state(request.url.host) do
      :closed -> {request, options}
      :open -> 
        request = Req.Request.halt(request)
        {request, Keyword.put(options, :error, :circuit_open)}
      :half_open -> 
        # Allow one request through for testing
        {request, Keyword.put(options, :circuit_test, true)}
    end
  end
)
```

### Pattern 5: Request Coalescing for Duplicate Calls
```elixir
# Prevents duplicate simultaneous requests
def get_with_coalescing(url, opts) do
  key = {url, opts[:params]}
  
  case :ets.lookup(:request_cache, key) do
    [{^key, pid}] when is_pid(pid) ->
      # Request in progress, wait for result
      ref = Process.monitor(pid)
      receive do
        {:DOWN, ^ref, :process, ^pid, reason} ->
          :ets.lookup(:request_cache, {:result, key})
      end
      
    [] ->
      # Start new request
      :ets.insert(:request_cache, {key, self()})
      result = Req.get(url, opts)
      :ets.insert(:request_cache, {{:result, key}, result})
      :ets.delete(:request_cache, key)
      result
  end
end
```

### Pattern 6: Health Check Integration
```elixir
# Monitor exchange connectivity
def health_check_step({request, options}) do
  start_time = System.monotonic_time(:millisecond)
  
  # Continue with request
  result = {request, options}
  
  # Record health metrics in response step
  response_step = fn {request, response} ->
    duration = System.monotonic_time(:millisecond) - start_time
    record_health_metric(request.url.host, duration, response.status)
    {request, response}
  end
  
  options = Keyword.put(options, :response_step, response_step)
  {request, options}
end
```

### Pattern 7: Telemetry Integration
```elixir
# Hook into Req's built-in telemetry
:telemetry.attach_many(
  "zen-cex-monitoring",
  [
    [:req, :request, :start],
    [:req, :request, :stop],
    [:req, :request, :exception],
    [:finch, :recv, :start],
    [:finch, :recv, :stop]
  ],
  &handle_telemetry_event/4,
  nil
)

def handle_telemetry_event([:req, :request, :stop], measurements, metadata, _config) do
  duration = measurements.duration
  exchange = metadata.request.private[:exchange]
  
  # Record metrics
  :telemetry.execute(
    [:zen_cex, :api, :request],
    %{duration: duration},
    %{exchange: exchange, status: metadata.response.status}
  )
end
```

### Pattern 8: Req Configuration per Exchange
```elixir
def create_req_client(exchange) do
  config = get_exchange_config(exchange)
  
  Req.new(
    base_url: config.base_url,
    # Exchange-specific retry strategy
    retry: [
      delay: fn attempt -> :timer.seconds(attempt) end,
      max_attempts: 3,
      should_retry: fn
        {:ok, %{status: 429}} -> {:delay, :timer.seconds(60)}
        {:ok, %{status: 503}} -> true
        {:error, %Mint.TransportError{}} -> true
        _ -> false
      end
    ],
    # Automatic decompression
    decode_body: true,
    # Backpressure control
    pool_timeout: 5_000,
    receive_timeout: 30_000,
    # Body size limits for memory protection
    max_body: 10_485_760  # 10MB limit
  )
  |> attach_middleware(exchange)
  |> attach_telemetry()
end
```

### Pattern 9: Stream Processing for Large Responses
```elixir
# For endpoints that return large datasets
def stream_request(url, opts) do
  Stream.resource(
    fn -> init_pagination(url, opts) end,
    fn state -> 
      case fetch_page(state) do
        {:ok, data, next_state} -> {[data], next_state}
        :done -> {:halt, state}
      end
    end,
    fn state -> cleanup(state) end
  )
end
```

### Pattern 10: Req.Test for Unit Testing
```elixir
import Req.Test

stub(:binance, fn conn ->
  assert conn.params["signature"]  # Verify auth
  json(conn, %{status: "ok"})
end)
```

## Exchange Requirements Table

| Exchange | Auth Method | Critical Requirement | Common Error | Production Gotcha |
|----------|------------|---------------------|-------------|-------------------|
| Binance | HMAC-SHA256 | Signature LAST in params | Wrong param order | IP weight != UID weight; Listen keys expire after 60m |
| Kraken | Nonce | Microsecond + counter | Using only microseconds | Different tiers (Starter/Pro); Some CSV responses |
| Deribit | OAuth2 | Refresh 120s before expiry | Token expiration | Testnet weekly reset; Options have separate margins |
| Bybit | HMAC-SHA256 | timestamp within 5s | Clock skew | Different endpoints for spot/derivatives |
| OKX | HMAC-SHA256 | passphrase required | Missing passphrase | Simulated trading affects rate limits |

### Critical Exchange Quirks

**Binance:**
- IP weight limits differ from UID (user) limits
- Weight system: simple requests = 1, complex = 5-50, OCO orders have special weights
- Order rate limits separate from request rate limits
- `recvWindow` default 5000ms, max 60000ms
- Listen keys expire after 60 minutes without keepalive
- Clock synchronization critical (±1000ms tolerance)

**Kraken:**
- Nonce must be STRICTLY increasing (no duplicates ever)
- Rate limit tiers: Starter (15/sec), Intermediate (20/sec), Pro (20/sec + higher burst)
- Some endpoints return CSV format (trades export)
- WebSocket has separate rate limiting from REST
- All private endpoints use POST with `application/x-www-form-urlencoded`
- API secret can be base64-encoded or raw

**Deribit:**
- Test environment: test.deribit.com (completely separate, weekly reset)
- OAuth tokens work across REST and WebSocket
- Matching engine rate limits separate from API rate limits
- Options have different margin calculations than futures
- JSON-RPC style API even for REST endpoints
- Single-flight protection critical for OAuth token refresh

### Clock Synchronization Pattern
```elixir
# Critical for exchanges that reject time-skewed requests
def ensure_time_sync(exchange) do
  case get_server_time(exchange) do
    {:ok, server_time} ->
      local_time = System.os_time(:millisecond)
      offset = server_time - local_time
      
      if abs(offset) > 1000 do
        Logger.warning("Clock skew detected for #{exchange}: #{offset}ms")
        :ets.insert(:clock_sync, {exchange, offset})
      end
      
    {:error, _} -> 
      # Use last known offset or 0
      offset = case :ets.lookup(:clock_sync, exchange) do
        [{^exchange, saved_offset}] -> saved_offset
        [] -> 0
      end
      {ok, offset}
  end
end

# Apply offset when signing requests
def apply_time_offset(timestamp, exchange) do
  case :ets.lookup(:clock_sync, exchange) do
    [{^exchange, offset}] -> timestamp + offset
    [] -> timestamp
  end
end
```

### Finch Pool Configuration
```elixir
# Optimal pool configuration per exchange characteristics
defp pool_config do
  %{
    # Binance: High volume, supports HTTP/2
    {:https, "api.binance.com", 443} => [
      size: 50,                # Concurrent connections
      count: 2,                # Number of pools (load balancing)
      protocol: :http2,        # Use HTTP/2 if supported
      conn_opts: [
        transport_opts: [
          timeout: 30_000,
          # TCP keepalive for persistent connections
          tcp_keepalive: [
            tcp_keepidle: :timer.seconds(60),
            tcp_keepintvl: :timer.seconds(30),
            tcp_keepcnt: 3
          ]
        ]
      ]
    ],
    
    # Kraken: More conservative, HTTP/1.1
    {:https, "api.kraken.com", 443} => [
      size: 30,
      count: 1,
      protocol: :http1,       # Kraken doesn't support HTTP/2 well
      conn_opts: [
        transport_opts: [timeout: 60_000]  # Kraken can be slow
      ]
    ],
    
    # Deribit: OAuth-based, moderate volume
    {:https, "www.deribit.com", 443} => [
      size: 20,
      count: 1,
      protocol: :http2,
      conn_opts: [
        transport_opts: [timeout: 30_000]
      ]
    ]
  }
end
```

## Task Implementation Sequence

### Phase 1: Core + Binance (Current)
```bash
# You are here: Task 2 - Simplifying architecture
[✅] Task 1: Core.Registry
[🔄] Task 2: Simplify architecture (remove Core.Supervisor)  # <- CURRENT
[ ] Task 3: Add telemetry integration for observability
[ ] Task 4: Core.HTTP with Req steps and backpressure
[ ] Task 5: Binance.Auth with proper error handling
[ ] Task 6: Binance.RateLimiter with sliding window
[ ] Task 7: Binance.Parser with body size limits
[ ] Task 8: Integration tests against real API
[ ] Task 9: Performance validation and benchmarks
```

### Phase 2: Testing + Other Exchanges
```bash
[ ] Task 10-11: Req.Test framework with real response fixtures
[ ] Task 12: Clock synchronization handling
[ ] Task 13-15: Kraken adapter with nonce management
[ ] Task 16-18: Deribit adapter with OAuth state
[ ] Task 19: Request deduplication integration
```

### Phase 3: Production Hardening
```bash
[ ] Task 20: Circuit breaker with exchange-specific thresholds
[ ] Task 21: Health monitoring with SLA tracking
[ ] Task 22: Stream processing for large datasets
[ ] Task 23: Connection pool optimization per exchange
[ ] Task 24: Multi-tier rate limiting implementation
[ ] Task 25: Memory protection and backpressure tuning
[ ] Task 26: Load testing with 10K concurrent requests
[ ] Task 27: Error recovery with exponential backoff
[ ] Task 28: Production dashboard and alerting
[ ] Task 29: Comprehensive troubleshooting guide
[ ] Task 30: Performance benchmarks documentation
```

## Common AI Coder Mistakes

### Mistake 1: Manual Request Manipulation
**Wrong**: `request = %{request | headers: [...]}` 
**Right**: `Req.Request.put_header(request, key, value)`
**Why**: Use Req functions for proper pipeline integration

### Mistake 2: GenServer State for Counters
**Wrong**: `{:reply, count + 1, %{state | count: count + 1}}`
**Right**: `:ets.update_counter(:table, :key, 1)`
**Why**: Atomic operations prevent bottlenecks

### Mistake 3: Creating Mocks Without Real API Testing
**Wrong**: Writing Req.Test stubs based on API documentation
**Right**: Test real API first, capture responses, then create mocks
**Why**: Docs lie; real APIs have quirks, headers, edge cases

### Mistake 4: Testing Rate Limits Against Real API
**Wrong**: `Enum.each(1..1000, fn _ -> Req.get!(url) end)`
**Right**: Manipulate ETS tables: `:ets.insert(:table, {:weight, 1199})`
**Why**: Test the logic, not the API's patience

### Mistake 5: Implementing Everything at Once
**Wrong**: Creating all modules in one session
**Right**: One module per session with tests
**Why**: Incremental progress ensures quality

### Mistake 6: Missing Circuit Breaker Protection
**Wrong**: Continuing to hammer failing endpoints
**Right**: Implement circuit breaker with exponential backoff
**Why**: Failed exchanges can cascade failures

### Mistake 7: No Request Deduplication
**Wrong**: Multiple simultaneous identical requests
**Right**: Coalesce duplicate requests and share results
**Why**: Prevents API abuse and improves performance

### Mistake 8: Ignoring Clock Synchronization
**Wrong**: Assuming local time matches exchange time
**Right**: Check and adjust for clock skew per exchange
**Why**: Many exchanges reject requests with >1s time difference

### Mistake 9: Not Using Req's Telemetry
**Wrong**: Custom logging and metrics throughout code
**Right**: Hook into [:req, :request, :*] events
**Why**: Req already emits comprehensive telemetry

### Mistake 10: Hardcoding Connection Pool Sizes
**Wrong**: Same pool configuration for all exchanges
**Right**: Tune pools based on exchange characteristics
**Why**: Binance handles 50+ concurrent, Kraken prefers fewer

## Troubleshooting Guide

### Common Production Errors

#### Error: Rate Limited (429)
**Symptoms**: `{:error, :rate_limited}` or HTTP 429 responses
**Diagnosis**:
```elixir
# Check current rate limit usage
:ets.tab2list(:binance_rate_limits)
# Look for: {:weight, current_usage}
```
**Solutions**:
- Reduce request frequency
- Check if multiple processes using same API key
- Verify rate limit calculations are correct
- Implement exponential backoff

#### Error: Authentication Failed (401)
**Symptoms**: `{:error, :unauthorized}` or signature validation errors
**Diagnosis**:
```elixir
# Verify signature generation
signature = Binance.Auth.sign_request(params, secret)
# Check parameter order (signature must be LAST for Binance)
```
**Solutions**:
- Verify API key and secret are correct
- Check system clock synchronization (±5 seconds)
- Ensure signature is generated with correct parameter order
- Validate recvWindow parameter

#### Error: Circuit Breaker Open
**Symptoms**: `{:error, :circuit_open}` without attempting request
**Diagnosis**:
```elixir
# Check circuit breaker state
:ets.lookup(:circuit_breakers, "api.binance.com")
# Look for: {host, :open, failure_count, last_failure_time}
```
**Solutions**:
- Wait for circuit breaker reset time
- Check if external issue resolved
- Manually reset circuit if needed: `reset_circuit_breaker(host)`

#### Error: Connection Timeout
**Symptoms**: Slow responses or timeout errors
**Diagnosis**:
```elixir
# Check connection pool status
:sys.get_state(ZenCex.Finch)
# Monitor pool utilization and queue sizes
```
**Solutions**:
- Increase connection pool size
- Check network connectivity to exchange
- Verify firewall settings
- Monitor DNS resolution

### Health Check Monitoring

#### Setting Up Health Checks
```elixir
# Check exchange connectivity
def health_status do
  exchanges = [:binance, :kraken, :deribit]
  
  results = Enum.map(exchanges, fn exchange ->
    case test_connectivity(exchange) do
      {:ok, latency} -> {exchange, :healthy, latency}
      {:error, reason} -> {exchange, :unhealthy, reason}
    end
  end)
  
  healthy_count = Enum.count(results, fn {_, status, _} -> status == :healthy end)
  {healthy_count, length(exchanges), results}
end
```

#### Health Metrics to Track
- Response time percentiles (p50, p95, p99)
- Error rates by exchange and endpoint
- Circuit breaker state changes
- Rate limit utilization
- Connection pool statistics

## Production Readiness Checklist

### Configuration
- [ ] Environment variables configured for all exchanges
- [ ] Rate limits properly calibrated per exchange
- [ ] Connection pool sizes optimized
- [ ] Circuit breaker thresholds set
- [ ] Health check intervals configured

### Monitoring
- [ ] Telemetry events captured
- [ ] Error tracking implemented
- [ ] Performance metrics collected
- [ ] Alerting rules defined
- [ ] Dashboard created for operational visibility

### Error Handling
- [ ] All error cases tested
- [ ] Circuit breaker tested under load
- [ ] Rate limit recovery verified
- [ ] Authentication failure handling
- [ ] Network timeout handling

### Performance
- [ ] Load testing completed
- [ ] Memory usage under sustained load verified
- [ ] Rate limiter performance validated
- [ ] Connection pool sizing optimized
- [ ] Request coalescing effectiveness measured

### Security
- [ ] API keys stored securely
- [ ] No credentials in logs
- [ ] TLS certificate validation enabled
- [ ] Request signing verified
- [ ] Rate limiting protects against abuse

## Validation Checklist

### Before Marking Task Complete
```elixir
# Run these commands:
mix test path/to/test.exs        # Unit tests pass
mix dialyzer                      # No type errors
mix credo --strict               # Code quality
mix test --cover                 # >80% coverage
```

### Memory & Performance Targets
- Rate limiter: <0.5ms per check (sub-millisecond)
- 10,000 concurrent requests: <200ms total orchestration time
- Memory growth: <2MB under sustained load
- ETS cleanup: Every 30 seconds for sliding windows
- Circuit breaker: <0.1ms decision time
- Health check: Max 5 second timeout with exponential backoff
- Connection pool: 50-100 connections per exchange (configurable)
- Request coalescing: 95% duplicate elimination
- Body size limit: 10MB default, streaming for larger
- Telemetry overhead: <2% of request time
- Clock sync check: Every 5 minutes per exchange
- OAuth refresh: 120 seconds before expiry

## Architecture: Leveraging Req's Built-in Capabilities

### Why We Don't Need OTP Supervision
- **Connection Pooling**: Req uses Finch - no custom pool supervision needed
- **Retry & Circuit Breaking**: Req has built-in retry with exponential backoff
- **Middleware Pipeline**: Req's steps handle auth, rate limiting, telemetry
- **Observability**: Req emits comprehensive telemetry events automatically

### What Actually Needs GenServers
- **Deribit.Auth** - OAuth token state management
- **That's it!** Everything else is handled by Req or uses ETS tables

### What Req Handles For Us
- **Connection pooling** - Finch integration with HTTP/2 support
- **Retry logic** - Configurable per exchange with exponential backoff
- **Decompression** - Automatic gzip/deflate/br handling
- **Telemetry** - Built-in events for request lifecycle
- **Backpressure** - Pool and receive timeouts prevent overload
- **Body streaming** - For large responses without loading into memory
- **Request pipelining** - Middleware steps for auth, rate limit, circuit breaker
- **Error handling** - Automatic retry with custom should_retry logic

### Application Supervisor
```elixir
def start(_type, _args) do
  # Initialize ETS tables for rate limiting and caching
  init_ets_tables()
  
  # Exchange-specific connection pools
  pools = %{
    "api.binance.com" => [size: 50, count: 2, protocol: :http2],
    "api.kraken.com" => [size: 30, count: 1, protocol: :http1],
    "www.deribit.com" => [size: 20, count: 1, protocol: :http2],
    "test.deribit.com" => [size: 10, count: 1, protocol: :http2]
  }
  
  children = [
    # Finch provides connection pooling for Req
    {Finch, name: ZenCex.Finch, pools: pools},
    # Telemetry reporter for metrics
    {Telemetry.Metrics.ConsoleReporter, metrics: metrics()},
    # Only Deribit OAuth needs state (when using Deribit)
    # {ZenCex.Adapters.Deribit.Auth, []}
  ]
  
  # Attach telemetry handlers
  attach_telemetry_handlers()
  
  # Minimal supervision - Req handles the complexity
  Supervisor.start_link(children, strategy: :one_for_one)
end

defp init_ets_tables do
  # Rate limiting tables per exchange
  :ets.new(:binance_rate_limits, [:named_table, :public, :set, {:write_concurrency, true}])
  :ets.new(:kraken_rate_limits, [:named_table, :public, :set, {:write_concurrency, true}])
  :ets.new(:deribit_rate_limits, [:named_table, :public, :set, {:write_concurrency, true}])
  
  # Request coalescing cache
  :ets.new(:request_cache, [:named_table, :public, :set])
  
  # Circuit breaker states
  :ets.new(:circuit_breakers, [:named_table, :public, :set])
  
  # Clock synchronization offsets
  :ets.new(:clock_sync, [:named_table, :public, :set])
end
```

## File Creation Template

```elixir
defmodule ZenCex.Adapters.Exchange.Module do
  @moduledoc """
  One-line description.
  """
  
  @behaviour ZenCex.Behaviors.Something
  
  # For stateless modules (most cases)
  def init_tables do
    :ets.new(:table_name, [:named_table, :public, :set])
  end
  
  # Public API (5-10 functions max)
  @impl true
  def callback_function(args) do
    # Implementation
  end
  
  # Private functions last
  defp helper_function(args), do: :ok
end
```

## CRITICAL: Testing Philosophy

**[!] ALWAYS TEST AGAINST REAL APIs FIRST [!]**
```
1. Write integration tests against REAL exchange APIs (sparse, strategic)
2. Verify actual behavior before creating any mocks
3. Create Req.Test stubs based on captured real responses
4. Keep minimal integration tests to validate mock accuracy
```

**Smart Testing Strategy:**
- **Integration tests**: 1-2 real API calls per endpoint (capture responses)
- **Unit tests**: Fast, comprehensive using verified mocks
- **Rate limit tests**: Use ETS table manipulation, not real API hammering
- **Error tests**: Req.Test to simulate timeouts, 429s, 503s

## Test File Template

```elixir
defmodule ZenCex.Adapters.Binance.RateLimiterTest do
  use ExUnit.Case, async: true
  import Req.Test
  
  # ONE strategic integration test to verify real behavior
  @tag :integration
  @tag :skip  # Run manually when needed: mix test --include integration
  test "verify real Binance rate limit headers" do
    # Make ONE real API call to understand headers
    {:ok, response} = Binance.HTTP.get("/api/v3/time")
    
    # Capture the ACTUAL rate limit headers
    assert response.headers["x-mbx-used-weight-1m"]
    assert response.headers["x-mbx-order-count-1m"]
    
    # Save this structure for mocks
    File.write!("test/fixtures/binance_headers.json", Jason.encode!(response.headers))
  end
  
  # FAST unit tests using ETS manipulation
  describe "rate limiting logic" do
    setup do
      # Initialize ETS table for tests
      Binance.RateLimiter.init_tables()
      
      # Mock Req to return saved headers
      stub(:binance, fn conn ->
        conn
        |> put_resp_header("x-mbx-used-weight-1m", "50")
        |> json(%{serverTime: System.os_time(:millisecond)})
      end)
    end
    
    test "allows requests under limit" do
      # Manually set ETS counter
      :ets.insert(:binance_rate_limits, {:weight, 500})
      
      assert {:ok, _} = Binance.HTTP.get("/api/v3/time")
    end
    
    test "blocks requests over limit" do
      # Fill the bucket manually - NO REAL API CALLS
      :ets.insert(:binance_rate_limits, {:weight, 1199})
      
      assert {:error, :rate_limited} = Binance.HTTP.get("/api/v3/time")
    end
    
    test "sliding window cleanup" do
      # Insert old entries
      now = System.os_time(:millisecond)
      :ets.insert(:binance_rate_limits, {{:window, now - 61_000}, 100})
      
      # Trigger cleanup
      Binance.RateLimiter.cleanup_old_entries()
      
      # Verify old entries removed
      assert [] = :ets.lookup(:binance_rate_limits, {:window, now - 61_000})
    end
  end
  
  # Test error scenarios with Req.Test
  describe "error handling" do
    test "handles 429 Too Many Requests" do
      stub(:binance, fn conn ->
        conn
        |> put_status(429)
        |> json(%{code: -1003, msg: "Too many requests"})
      end)
      
      assert {:error, :rate_limited} = Binance.HTTP.get("/api/v3/time")
    end
  end
end
```

## Environment Setup

```bash
# Required for tests
export BINANCE_API_KEY="test_key"
export BINANCE_API_SECRET="test_secret" 
export TEST_MODE="true"  # Uses Req.Test stubs
```

## Production Deployment Patterns

### Multi-Tier Rate Limiting
```elixir
defmodule ZenCex.RateLimiter do
  @windows [
    {:second, 1_000},
    {:minute, 60_000}, 
    {:hour, 3_600_000}
  ]
  
  def check_limits(exchange, endpoint, weight) do
    limits = get_limits(exchange, endpoint)
    now = System.os_time(:millisecond)
    
    Enum.all?(@windows, fn {window, duration} ->
      window_start = now - duration
      current = get_usage(exchange, window, window_start)
      current + weight <= limits[window]
    end)
  end
  
  defp get_usage(exchange, window, start_time) do
    # Sum weights in sliding window
    table = :"#{exchange}_rate_limits"
    :ets.select(table, [
      {{{:request, :"$1"}, :"$2"}, 
       [{:>, :"$1", start_time}], 
       [:"$2"]}
    ])
    |> Enum.sum()
  end
end
```

### Connection Manager Pattern
```elixir
defmodule ZenCex.ConnectionManager do
  def create_client(exchange) do
    config = get_exchange_config(exchange)
    
    Req.new()
    |> attach_base_config(config)
    |> attach_middleware(exchange)
    |> attach_telemetry()
    |> attach_circuit_breaker()
  end
  
  defp attach_middleware(req, exchange) do
    req
    |> Req.Request.prepend_request_steps(
      clock_sync: &ensure_time_sync/1,
      auth: get_auth_module(exchange),
      rate_limit: get_rate_limiter(exchange),
      validate: &validate_request/1
    )
    |> Req.Request.append_response_steps(
      parse: get_parser(exchange),
      record_metrics: &record_metrics/1,
      check_health: &update_health_status/1
    )
  end
  
  defp attach_telemetry(req) do
    Req.Request.register_options(req, [
      :exchange,
      :endpoint_weight,
      :request_id
    ])
  end
end
```

### Production Monitoring Setup
```elixir
defmodule ZenCex.Telemetry do
  def metrics do
    [
      # Request metrics
      counter("zen_cex.request.count", tags: [:exchange, :status]),
      summary("zen_cex.request.duration", tags: [:exchange, :endpoint]),
      
      # Rate limit metrics  
      gauge("zen_cex.rate_limit.usage", tags: [:exchange, :window]),
      counter("zen_cex.rate_limit.rejected", tags: [:exchange]),
      
      # Circuit breaker metrics
      counter("zen_cex.circuit_breaker.opened", tags: [:exchange]),
      gauge("zen_cex.circuit_breaker.state", tags: [:exchange]),
      
      # Health metrics
      gauge("zen_cex.health.latency", tags: [:exchange]),
      gauge("zen_cex.health.success_rate", tags: [:exchange]),
      
      # Connection pool metrics
      gauge("zen_cex.pool.size", tags: [:exchange]),
      gauge("zen_cex.pool.queue_length", tags: [:exchange])
    ]
  end
  
  def attach_handlers do
    :telemetry.attach_many(
      "zen-cex-req",
      [
        [:req, :request, :start],
        [:req, :request, :stop],
        [:req, :request, :exception],
        [:finch, :queue, :start],
        [:finch, :queue, :stop],
        [:finch, :connect, :start],
        [:finch, :connect, :stop]
      ],
      &handle_event/4,
      nil
    )
  end
end
```

## After Completing Current Task

1. Run validation checklist
2. Update this file's "Current Task" section
3. Mark task complete in sequence
4. Report: "Task N complete. Next: Task N+1"
5. **STOP** - Do not continue

## Quick Reference

- **Req steps**: Return `{request, options}` tuple
- **Halt pipeline**: `Req.Request.halt(request)`
- **ETS atomic**: `:ets.update_counter/3`
- **Test stubs**: `import Req.Test; stub/2`
- **One task**: Complete, validate, stop

---
**Remember**: This guide is your single source of truth. Ignore other docs.