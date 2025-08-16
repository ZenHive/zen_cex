# ZenCex AI Implementation Guide

## CRITICAL: One Task Per Session Rule
**NEVER implement multiple modules in one session. Complete ONE task, update progress, then stop.**

## Quick Start for AI Coders

### Your Current Status
- **Architecture**: Req-powered adapters (leveraging built-in middleware)
- **Progress**: 29% complete (7/24 tasks done) 
- **Next Task**: Remove redundant OTP - Req handles pooling, retry, telemetry
- **Priority**: Use Req's features instead of reimplementing them

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

### Pattern 1: Req Request Step (Auth)
```elixir
# MUST return {request, options} tuple
def sign_request({request, options}, opts) do
  request = request
  |> Req.Request.put_header("x-api-key", opts[:api_key])
  |> Map.put(:options, Keyword.put(request.options, :params, signed_params))
  
  {request, options}  # CRITICAL: Return tuple
end
```

### Pattern 2: Rate Limiter as Middleware
```elixir
Req.Request.prepend_request_steps(req,
  rate_limit: fn {request, options} ->
    case check_rate_limit(request) do
      :ok -> {request, options}
      {:error, _} -> 
        request = Req.Request.halt(request)
        {request, Keyword.put(options, :error, :rate_limited)}
    end
  end
)
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

### Pattern 4: Req.Test for Unit Testing
```elixir
import Req.Test

stub(:binance, fn conn ->
  assert conn.params["signature"]  # Verify auth
  json(conn, %{status: "ok"})
end)
```

## Exchange Requirements Table

| Exchange | Auth Method | Critical Requirement | Common Error |
|----------|------------|---------------------|-------------|
| Binance | HMAC-SHA256 | Signature LAST in params | Wrong param order |
| Kraken | Nonce | Microsecond + counter | Using only microseconds |
| Deribit | OAuth2 | Refresh 120s before expiry | Token expiration |

## Task Implementation Sequence

### Day 1: Core + Binance (Current)
```bash
# You are here: Task 2 - Simplifying architecture
[✅] Task 1: Core.Registry
[🔄] Task 2: Simplify architecture (remove Core.Supervisor)  # <- CURRENT
[ ] Task 3: Core.HTTP with Req steps
[ ] Task 4: Binance.Auth as Req steps
[ ] Task 5: Binance.RateLimiter (simple module)
[ ] Task 6: Binance.Parser
[ ] Task 7: Integration tests
[ ] Task 8: Performance validation
```

### Day 2: Testing + Other Exchanges
```bash
[ ] Task 9-10: Req.Test framework
[ ] Task 11-13: Kraken adapter
[ ] Task 14-16: Deribit adapter
```

### Day 3: Production Hardening
```bash
[ ] Task 17-20: Circuit breaker, health monitoring
[ ] Task 21-24: Performance tests, documentation
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
- Rate limiter: <1ms per check
- 10,000 concurrent requests: <100ms
- Memory growth: <1MB under load
- ETS cleanup: Every 60 seconds

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
- **Rate limiting** - Middleware step with ETS atomic ops (faster than GenServer)
- **Authentication** - Request step for signing (stateless except OAuth)
- **Error handling** - Retry logic with configurable strategies
- **Monitoring** - Built-in telemetry for all HTTP operations

### Application Supervisor
```elixir
def start(_type, _args) do
  # Initialize ETS tables for rate limiting
  init_ets_tables()
  
  children = [
    # Finch provides connection pooling for Req
    {Finch, name: ZenCex.Finch, pools: pool_config()}
    # Deribit OAuth when needed (only stateful component)
  ]
  
  # Minimal supervision - Req handles the complexity
  Supervisor.start_link(children, strategy: :one_for_one)
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