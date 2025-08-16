# ZenCex AI Implementation Guide

## CRITICAL: One Task Per Session Rule
**NEVER implement multiple modules in one session. Complete ONE task, update progress, then stop.**

## Quick Start for AI Coders

### Your Current Status
- **Architecture**: Plugin-based with Req middleware pipeline
- **Progress**: 21.2% complete (7/28 tasks done) 
- **Next Task**: Refactor Core.HTTP with Req steps pipeline
- **Priority**: Production hardening with Req patterns

### Navigation
1. Check "Current Task" section
2. Implement using "Essential Patterns"
3. Validate with "Success Criteria"
4. Update progress and stop

## Current Task

**Task #2**: Refactor Core.HTTP with Req middleware pipeline

**Command**: `mix test test/zen_cex/core/http_test.exs`

**Success Criteria**:
- [ ] Auth attached as request step
- [ ] Rate limiter can halt pipeline
- [ ] Circuit breaker handles failures
- [ ] Telemetry emits events
- [ ] Tests pass with 100% coverage

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

### Pattern 3: ETS Atomic Operations
```elixir
# NEVER use GenServer state for counters
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
# You are here: Task 2 of 8
[✅] Task 1: Core.Registry
[🔄] Task 2: Core.HTTP with Req steps  # <- CURRENT
[ ] Task 3: Core.RequestCoalescer
[ ] Task 4: Core.RateLimitBudget
[✅] Task 5: Behaviors (done)
[ ] Task 6: Binance.Auth as Req steps
[ ] Task 7: Binance.RateLimiter
[ ] Task 8: Binance.Parser
```

### Day 2: Testing + Other Exchanges
```bash
[ ] Task 9-10: Req.Test framework
[ ] Task 11-13: Kraken adapter
[ ] Task 14-16: Deribit adapter
```

### Day 3-4: Production
```bash
[ ] Task 17-22: Circuit breaker, health, telemetry
[ ] Task 23-28: Performance tests, documentation
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

### Mistake 3: Implementing Everything at Once
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

## File Creation Template

```elixir
defmodule ZenCex.Core.MODULE do
  @moduledoc """
  One-line description.
  """
  
  # Behaviors first
  @behaviour ZenCex.Behaviors.Something
  
  # Public API (5-10 functions max)
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  
  @impl true
  def callback_function(args) do
    # Implementation
  end
  
  # Private functions last
  defp helper_function(args), do: :ok
end
```

## Test File Template

```elixir
defmodule ZenCex.Core.MODULETest do
  use ExUnit.Case, async: true
  import Req.Test  # For unit tests
  
  describe "unit tests" do
    setup do
      stub(:exchange, fn conn -> json(conn, %{}) end)
      :ok
    end
    
    test "happy path" do
      assert :ok = Module.function()
    end
  end
  
  describe "integration tests" do
    @tag :integration
    test "real API call" do
      # Test against real API
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