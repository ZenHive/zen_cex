# ZenCex AI Implementation Guide

## CRITICAL: One Task Per Session Rule
**NEVER implement multiple modules in one session. Complete ONE task, update progress, then stop.**

## Quick Start for AI Coders

### Your Current Status
- **Architecture**: Req-powered adapters with built-in pooling, retry, telemetry
- **Progress**: 8% complete (2/25 tasks done)
- **Next Task**: Remove redundant OTP - Req handles pooling, retry, telemetry
- **Priority**: Production hardening with idempotency, clock sync, dynamic rate limits
- **Focus**: Production-ready REST-only patterns for reliable trading operations.

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

### Pattern 1: Req Request Step with Error Context (Auth)
```elixir
# MUST return {request, options} tuple with proper error context
def sign_request({request, options} = req_tuple) do
  with {:ok, credentials} <- get_credentials(request),
       {:ok, signed_request} <- apply_signature(request, credentials) do
    {signed_request, options}
  else
    {:error, :missing_credentials} = error ->
      # Provide context for debugging
      error_request = Req.Request.halt(request, error)
      {error_request, Keyword.put(options, :error_context, :auth_failed)}
    
    {:error, reason} = error ->
      # Tag other errors appropriately
      error_request = Req.Request.halt(request, error)
      {error_request, Keyword.put(options, :error_type, :signature_failed)}
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

### Pattern 5: Request Coalescing with GenServer Coordination
```elixir
# Production-ready coalescing without race conditions
defmodule RequestCoalescer do
  use GenServer

  def get(url, opts) do
    key = {url, opts[:params]}
    GenServer.call(__MODULE__, {:coalesce, key, fn -> Req.get(url, opts) end})
  end

  def handle_call({:coalesce, key, fun}, from, state) do
    case Map.get(state, key) do
      nil ->
        # First request, execute in Task
        task = Task.async(fun)
        {:noreply, Map.put(state, key, {task, [from]})}

      {task, waiters} ->
        # Add to waiters
        {:noreply, Map.put(state, key, {task, [from | waiters]})}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    # Find and reply to all waiters
    {key, {task, waiters}} = Enum.find(state, fn
      {_k, {%Task{ref: ^ref}, _}} -> true
      _ -> false
    end)

    Enum.each(waiters, &GenServer.reply(&1, result))
    {:noreply, Map.delete(state, key)}
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

### Pattern 8: Optimized Req Configuration per Exchange
```elixir
def create_req_client(exchange) do
  config = get_exchange_config(exchange)

  Req.new(
    base_url: config.base_url,
    # Use Req's built-in retry with jitter
    retry: :safe_transient,  # Handles 429, 5xx, timeouts automatically
    retry_delay: &exponential_backoff_with_jitter/1,
    max_retries: get_max_retries(exchange),
    # Native caching for market data
    cache: true,
    cache_dir: System.tmp_dir!() <> "/zen_cex_#{exchange}",
    # Automatic compression and decompression
    compress_body: true,
    decode_body: true,
    # Backpressure control
    pool_timeout: 5_000,
    receive_timeout: 30_000,
    # Body size limits
    max_body: 10_485_760  # 10MB limit
  )
  |> attach_middleware(exchange)
  |> attach_telemetry()
  |> Req.Request.prepend_error_steps(
    circuit_recovery: &handle_circuit_recovery/1
  )
end

defp exponential_backoff_with_jitter(attempt) do
  base = :timer.seconds(attempt)
  jitter = :rand.uniform(1000)
  base + jitter
end
```

### Pattern 9: Dynamic Rate Limit Adjustment
```elixir
# Update rate limits from response headers
def update_rate_limits_from_response(exchange, response) do
  case exchange do
    :binance ->
      used = Req.Response.get_header(response, "x-mbx-used-weight-1m")
      limit = Req.Response.get_header(response, "x-mbx-used-weight-limit-1m")
      :ets.insert(:binance_rate_limits, {:current_usage, String.to_integer(used)})
      :ets.insert(:binance_rate_limits, {:current_limit, String.to_integer(limit || "1200")})
    
    :kraken ->
      # Kraken tier can change dynamically
      counter = Req.Response.get_header(response, "api-rate-limit-counter")
      tier = detect_kraken_tier(counter)
      :ets.insert(:kraken_rate_limits, {:tier, tier})
    
    :deribit ->
      remaining = Req.Response.get_header(response, "x-ratelimit-remaining")
      :ets.insert(:deribit_rate_limits, {:remaining, String.to_integer(remaining || "10")})
  end
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

### Pattern 11: Idempotency for Order Placement
```elixir
# Critical for safe retries in production
defmodule OrderPlacer do
  def place_order(exchange, params) do
    # Generate idempotency key
    idempotency_key = generate_idempotency_key(params)

    # Check if we've sent this before
    case check_idempotency_cache(idempotency_key) do
      {:ok, previous_result} ->
        {:ok, previous_result}

      :not_found ->
        params = Map.put(params, :client_order_id, idempotency_key)

        case send_order(exchange, params) do
          {:ok, result} ->
            cache_idempotency_result(idempotency_key, result)
            {:ok, result}

          {:error, :timeout} ->
            # On timeout, query order status by client_order_id
            check_order_status(exchange, idempotency_key)

          error ->
            error
        end
    end
  end

  defp generate_idempotency_key(params) do
    # Include timestamp with 5-minute window
    window = div(System.os_time(:second), 300)
    data = {window, params[:symbol], params[:side], params[:quantity], params[:price]}
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)  # Most exchanges limit client_order_id length
  end
end
```

### Pattern 12: Request Prioritization System
```elixir
# Tiered priority for production trading
defmodule SmartRateLimiter do
  @priorities %{
    cancel_order: 1,      # Highest - risk management
    place_order: 2,       # Trading
    modify_order: 3,      # Adjustments
    account_info: 4,      # Important queries
    market_data: 5,       # Can be cached
    historical: 6         # Lowest priority
  }

  def check_and_consume(exchange, endpoint, weight) do
    priority = @priorities[endpoint_type(endpoint)]
    capacity = get_remaining_capacity(exchange)

    cond do
      # Always allow critical risk management
      priority == 1 and capacity > 0 -> :ok

      # Reserve 20% capacity for high priority
      priority <= 3 and capacity > weight * 5 -> :ok

      # Normal requests need 50% capacity
      capacity > max_capacity(exchange) * 0.5 -> :ok

      # Reject low priority when constrained
      true -> {:error, :rate_limited, calculate_retry_after(exchange)}
    end
  end
end
```

### Pattern 13: Multi-Account API Key Rotation
```elixir
# Distribute load across multiple API keys
defmodule MultiAccountManager do
  def get_credentials(exchange, request_type) do
    accounts = get_exchange_accounts(exchange)

    # Round-robin with health awareness
    account = accounts
    |> Enum.filter(&account_healthy?/1)
    |> Enum.min_by(&get_account_usage(&1, request_type))

    case account do
      nil -> {:error, :no_healthy_accounts}
      acc -> {:ok, acc.api_key, acc.secret}
    end
  end

  defp account_healthy?(account) do
    case :ets.lookup(:account_health, account.id) do
      [{_, :healthy, _}] -> true
      [{_, :degraded, last_check}] ->
        # Retry degraded accounts after 5 minutes
        System.os_time(:second) - last_check > 300
      _ -> false
    end
  end
end
```

### Pattern 14: Per-Endpoint Health Monitoring
```elixir
# Track health at endpoint granularity
defmodule HealthMonitor do
  def record_request(exchange, endpoint, duration, status) do
    key = {exchange, endpoint, div(System.os_time(:second), 60)}

    :ets.update_counter(:health_metrics, key, [
      {2, 1},                          # request count
      {3, duration},                   # total duration
      {4, if(status < 400, do: 1, else: 0)}, # success count
      {5, if(status == 429, do: 1, else: 0)}  # rate limit count
    ], {key, 0, 0, 0, 0})
  end

  def get_endpoint_health(exchange, endpoint) do
    # Last 5 minutes
    keys = for i <- 0..4, do: {exchange, endpoint, div(System.os_time(:second), 60) - i}

    stats = keys
    |> Enum.flat_map(&:ets.lookup(:health_metrics, &1))
    |> Enum.reduce({0, 0, 0, 0}, fn {_, count, duration, success, rate_limited}, acc ->
      {elem(acc, 0) + count,
       elem(acc, 1) + duration,
       elem(acc, 2) + success,
       elem(acc, 3) + rate_limited}
    end)

    case stats do
      {0, _, _, _} -> :no_data
      {count, duration, success, rate_limited} ->
        %{
          avg_latency: div(duration, count),
          success_rate: success / count,
          rate_limit_rate: rate_limited / count,
          requests_per_minute: count / 5
        }
    end
  end
end
```

### Pattern 15: Proactive NTP Clock Synchronization
```elixir
# Proactive NTP sync prevents auth failures
defmodule ClockSync do
  @ntp_servers ~w(time.google.com time.cloudflare.com pool.ntp.org)
  @sync_interval :timer.minutes(5)

  def ensure_time_sync(exchange) do
    case :ets.lookup(:clock_sync, {exchange, :last_sync}) do
      [{_, last_sync}] when System.os_time(:second) - last_sync < @sync_interval ->
        :ok  # Recent sync, use cached offset
      
      _ ->
        # Proactively sync with NTP first, fallback to exchange
        sync_with_ntp() || sync_with_exchange(exchange)
    end
  end

  defp sync_with_ntp do
    # Try multiple NTP servers for resilience
    Enum.find_value(@ntp_servers, fn server ->
      case get_ntp_time(server) do
        {:ok, ntp_time} ->
          offset = ntp_time - System.os_time(:millisecond)
          store_offset(:global, offset)
          {:ok, offset}
        _ -> nil
      end
    end)
  end

  defp sync_with_exchange(exchange) do
    case get_server_time(exchange) do
      {:ok, server_time} ->
        local_time = System.os_time(:millisecond)
        offset = server_time - local_time
        
        if abs(offset) > 1000 do
          Logger.warning("Clock skew detected for #{exchange}: #{offset}ms")
        end
        
        store_offset(exchange, offset)
        {:ok, offset}
      
      {:error, reason} ->
        use_cached_offset(exchange, reason)
    end
  end

  # Apply offset when signing requests
  def apply_time_offset(timestamp, exchange) do
    case :ets.lookup(:clock_sync, {exchange, :offset}) do
      [{_, offset}] -> timestamp + offset
      [] -> timestamp
    end
  end
end
```

## Exchange Requirements Table

| Exchange | Auth Method | Critical Requirement | Common Error | Production Gotcha |
|----------|------------|---------------------|-------------|-------------------|
| Binance | HMAC-SHA256 | Signature LAST in params | Wrong param order | IP weight != UID weight; User data streams expire after 30m (not 60m); Dynamic rate limits in headers |
| Kraken | Nonce + HMAC | Microsecond + counter; Base64 secret | Using only microseconds | Ledger exports async; Edit orders = cancel+new; Some endpoints return CSV; All private use POST |
| Deribit | OAuth2 | Refresh 120s before expiry | Token expiration | Options assignment at 08:00 UTC causes 1min downtime; JSON-RPC even for REST |
| Bybit | HMAC-SHA256 | timestamp within 5s; Different base URLs | Clock skew | api.bybit.com (spot) vs api-testnet.bybit.com (derivatives) |
| OKX | HMAC + Passphrase | passphrase required in headers | Missing passphrase | Simulated trading affects rate limits; Requires OK-ACCESS-PASSPHRASE header |

### Critical Exchange Quirks

**Binance:**
- IP weight limits differ from UID (user) limits
- Weight system: simple requests = 1, complex = 5-50, OCO orders consume 2x weight when both legs fill
- Order rate limits separate from request rate limits
- `recvWindow` default 5000ms, max 60000ms
- User data streams expire after 30 minutes without keepalive (not 60)
- Clock synchronization critical (±1000ms tolerance)
- Testnet has different rate limits than production

**Kraken:**
- Nonce must be STRICTLY increasing (no duplicates ever)
- Rate limit tiers: Starter (15/sec), Intermediate (20/sec), Pro (20/sec + higher burst)
- Ledger exports are async - returns job ID, must poll for completion
- Different decimal precision per pair (XBTUSD: 1, ADAUSD: 5)
- Edit orders count as cancel + new for rate limiting
- Some endpoints return CSV format (trades export)
- All private endpoints use POST with `application/x-www-form-urlencoded`
- API secret can be base64-encoded or raw

**Deribit:**
- Test environment: test.deribit.com (completely separate, weekly reset)
- OAuth tokens work across REST
- Portfolio margin vs standard margin use different endpoints and calculations
- Options assignment happens at 08:00 UTC, API unavailable for ~1 minute
- Index price != mark price (critical for liquidation calculations)
- Matching engine rate limits separate from API rate limits
- JSON-RPC style API even for REST endpoints
- Single-flight protection critical for OAuth token refresh

### Exchange-Specific Authentication Patterns
```elixir
# OKX requires passphrase beyond standard HMAC
def sign_okx_request({request, options}) do
  with {:ok, api_key} <- fetch_credentials(:okx_api_key),
       {:ok, secret} <- fetch_credentials(:okx_api_secret),
       {:ok, passphrase} <- fetch_credentials(:okx_passphrase) do
    
    timestamp = System.os_time(:second) |> to_string()
    method = to_string(request.method) |> String.upcase()
    path = request.url.path <> format_query_string(request.options[:params])
    body = request.body || ""
    
    # OKX signature: timestamp + method + path + body
    prehash = timestamp <> method <> path <> body
    signature = :crypto.mac(:hmac, :sha256, secret, prehash) |> Base.encode64()
    
    request = request
    |> Req.Request.put_header("ok-access-key", api_key)
    |> Req.Request.put_header("ok-access-sign", signature)
    |> Req.Request.put_header("ok-access-timestamp", timestamp)
    |> Req.Request.put_header("ok-access-passphrase", passphrase)  # CRITICAL
    
    {request, options}
  else
    error -> {Req.Request.halt(request, error), options}
  end
end

# Kraken requires careful secret handling
def normalize_kraken_secret(secret) do
  case Base.decode64(secret) do
    {:ok, decoded} -> decoded  # Already base64, use decoded bytes
    :error -> secret  # Raw bytes, use as-is
  end
end

# Bybit requires different base URLs
def get_bybit_base_url(:spot), do: "https://api.bybit.com"
def get_bybit_base_url(:derivatives), do: "https://api-testnet.bybit.com"
def get_bybit_base_url(:options), do: "https://api.bybit.com"  # Same as spot
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

## Task Implementation Sequence (Simplified: 25 Tasks)

### Phase 1: Core Foundation (5 tasks)
```bash
[✅] Task 1: Core.Registry - Adapter registration and validation
[🔄] Task 2: Remove Core.Supervisor - Use Req's built-in features  # <- CURRENT
[ ] Task 3: Req-native telemetry integration
[ ] Task 4: Proactive NTP clock sync with caching
[ ] Task 5: Idempotency with conflict resolution
```

### Phase 2: Binance Implementation (5 tasks)
```bash
[ ] Task 6: Core.HTTP with proper Req patterns
[ ] Task 7: Binance.Auth with clock sync
[ ] Task 8: Binance.RateLimiter with dynamic header updates
[ ] Task 9: Integration tests with fixture capture
[ ] Task 10: Load testing validation
```

### Phase 3: Additional Exchanges (10 tasks)
```bash
# Kraken (5 tasks)
[ ] Task 11: Kraken.Auth with nonce management
[ ] Task 12: Kraken.RateLimiter with tier detection
[ ] Task 13: Kraken.Parser for CSV and JSON
[ ] Task 14: Kraken decimal precision handling
[ ] Task 15: Kraken integration tests

# Deribit (5 tasks)
[ ] Task 16: Deribit.Auth GenServer with OAuth
[ ] Task 17: Deribit.RateLimiter for matching engine
[ ] Task 18: Deribit JSON-RPC adapter
[ ] Task 19: Portfolio margin calculations
[ ] Task 20: Deribit integration tests
```

### Phase 4: Production Hardening (5 tasks)
```bash
[ ] Task 21: Circuit breaker with Req error steps
[ ] Task 22: Request coalescing GenServer
[ ] Task 23: Health monitoring and alerting
[ ] Task 24: Security audit and credential rotation
[ ] Task 25: Production runbooks and troubleshooting
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

### Mistake 11: No Idempotency for Orders
**Wrong**: Retrying order placement without client_order_id
**Right**: Generate deterministic client_order_id for safe retries
**Why**: Network timeout + retry = potential duplicate orders

### Mistake 12: Ignoring Partial Fills
**Wrong**: Assuming orders are fully filled or cancelled
**Right**: Track fill quantity and handle partial execution
**Why**: Large orders often partially fill in volatile markets

### Mistake 13: Static Rate Limit Assumptions
**Wrong**: Hardcoding rate limits from documentation
**Right**: Read actual limits from response headers dynamically
**Why**: Exchanges adjust limits based on tier/load/time

### Mistake 14: Ignoring Req's Built-in Features
**Wrong**: Implementing custom retry, caching, compression
**Right**: Use `retry: :safe_transient`, `cache: true`, `compress_body: true`
**Why**: Req already handles these optimally

### Mistake 15: Missing Exchange-Specific Requirements
**Wrong**: Assuming all exchanges use same auth pattern
**Right**: Handle OKX passphrase, Bybit URL split, Kraken POST-only
**Why**: Each exchange has unique quirks that break auth

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

### Common Production Issues Not in Docs

#### Issue: Order Rejected After Timeout
**Symptoms**: Timeout on order placement, but order actually executed
**Root Cause**: Network timeout shorter than exchange processing time
**Solution**:
```elixir
# Always check order status after timeout
case place_order_with_timeout(params, timeout: 5_000) do
  {:error, :timeout} ->
    # Order might have succeeded - check by client_order_id
    check_order_status(params.client_order_id)
  result ->
    result
end
```

#### Issue: Nonce Already Used (Kraken)
**Symptoms**: "Invalid nonce" errors after restart
**Root Cause**: Nonce must always increase, even across restarts
**Solution**:
```elixir
# Persist last nonce and add buffer on startup
def init_nonce do
  last_nonce = read_persisted_nonce()
  buffer = 1000  # Safety buffer
  :ets.insert(:nonces, {:kraken, last_nonce + buffer})
end
```

#### Issue: Decimal Precision Errors
**Symptoms**: Orders rejected for invalid quantity/price
**Root Cause**: Each trading pair has specific decimal requirements
**Solution**:
```elixir
# Cache and apply pair-specific precision
def format_quantity(pair, quantity) do
  precision = get_pair_precision(pair, :quantity)
  Decimal.round(quantity, precision, :down)  # Always round down for quantities
end
```

#### Issue: IP Whitelist Changes
**Symptoms**: Sudden authentication failures in production
**Root Cause**: Cloud provider IP rotation or failover
**Solution**: Use API key restrictions by API permissions, not IP whitelist

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
- [ ] API keys stored securely in environment variables
- [ ] No credentials in logs or error messages
- [ ] TLS certificate validation enabled
- [ ] Request signing verified with test mode
- [ ] Rate limiting protects against abuse
- [ ] Idempotency keys prevent duplicate orders
- [ ] Multi-account rotation for resilience
- [ ] Clock sync prevents auth failures

## Validation Checklist

### Before Marking Task Complete
```elixir
# Run these commands:
mix test path/to/test.exs        # Unit tests pass
mix dialyzer                      # No type errors
mix credo --strict               # Code quality
mix test --cover                 # >80% coverage
```

### Memory & Performance Targets (REST-Optimized)
- Rate limiter: <1ms per check (sufficient for REST)
- 10,000 concurrent requests: <100ms total orchestration
- Memory growth: <1MB under sustained load
- ETS cleanup: Every 60 seconds for sliding windows
- Circuit breaker: <0.1ms decision time
- Health check: Max 5 second timeout with exponential backoff
- Connection pool: 20-50 per exchange (Finch-managed)
- Request coalescing: 95% duplicate elimination (good enough)
- Body size limit: 10MB default
- Telemetry overhead: <1% of request time
- Clock sync: Proactive NTP + exchange sync every 5 min
- OAuth refresh: 120 seconds before expiry
- Idempotency window: 5 minutes for order operations

## Architecture: Leveraging Req's Built-in Capabilities

### Why We Don't Need OTP Supervision
- **Connection Pooling**: Req uses Finch - no custom pool supervision needed
- **Retry & Circuit Breaking**: Req has built-in retry with exponential backoff
- **Middleware Pipeline**: Req's steps handle auth, rate limiting, telemetry
- **Observability**: Req emits comprehensive telemetry events automatically

### What Actually Needs GenServers
- **Deribit.Auth** - OAuth token state management with single-flight refresh
- **RequestCoalescer** - Coordinate duplicate request handling (one GenServer)
- **That's it!** Everything else uses Req features or ETS atomic operations

### What Req Handles For Us
- **Connection pooling** - Finch integration with HTTP/2 support
- **Retry logic** - `:safe_transient` handles 429, 5xx, timeouts automatically
- **Compression** - Automatic gzip/deflate/br with `compress_body: true`
- **Caching** - Native caching with `cache: true` and custom keys
- **Telemetry** - Built-in `[:req, :request, :*]` events
- **Backpressure** - Pool and receive timeouts prevent overload
- **Error steps** - `prepend_error_steps/2` for circuit breaker recovery
- **Response parsing** - Automatic JSON with `decode_body: true`

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
