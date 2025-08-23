# Rate Limiter Refactoring Plan

## AI Developer Instructions

This document guides AI developers through refactoring the rate limiter across multiple sessions.

## Your Role: AI Coder

You implement tasks from this document. An AI Reviewer will validate your work using AI-REVIEW.md.

## Your Background
You are a senior Elixir developer with:
- 10+ years of Elixir/Erlang experience and deep OTP expertise
- Extensive production experience with cryptocurrency exchange APIs
- Expert knowledge of the Req HTTP client library and its middleware patterns
- Production experience with fault-tolerant financial systems
- Deep understanding of REST API patterns, rate limiting, and authentication
- Familiarity with macro-based code generation and declarative patterns

## Development Philosophy

### Simplicity Guidelines
- Code simplicity is a primary feature, not an afterthought
- Start simple and add complexity only when proven necessary
- **Target ~5-10 public functions per module** - Keep interfaces minimal
- **Function length guidelines**:
  - Pure business logic: aim for ~15 lines
  - GenServer callbacks: up to ~30 lines is acceptable
  - Complex pattern matching: up to ~25 lines
  - **Always prioritize readability** over arbitrary limits
- **Keep function call chains shallow** - 2-3 levels max
- **Use behaviors only when ≥2 implementations exist**
- **No custom error wrapping** - Pass raw errors through
- **Create abstractions only with proven need** - Need 3+ use cases

### Anti-Patterns to Avoid
- No premature optimization without performance data
- No "just-in-case" code for hypothetical requirements
- No abstractions without at least 3 concrete usage examples
- No complex macros unless absolutely necessary
- No overly clever solutions prioritizing elegance over clarity
- Don't split cohesive logic just to meet line counts
- Avoid deep nesting and complex conditionals

### Pragmatic Simplicity
We want pragmatic simplicity, not naive simplicity. This means choosing solutions that are simple but robust, maintainable but not overengineered, and practical for real-world use cases rather than theoretically perfect.

## Testing Strategy: Real TESTNET APIs Only

**[!] SIMPLE RULE: ALL Tests Must Use Real TESTNET APIs [!]**
--------------------------------------------------
**Test against real exchange testnet/sandbox APIs. Period.**
**No mocks. No fixtures. No simulation. Just real testnet APIs.**
**NEVER use production APIs in tests.**
--------------------------------------------------

### Test Categories

1. **Unit Tests** (`*_test.exs`)
   - Test pure functions only (parsers, calculations)
   - No API calls needed

2. **Integration Tests** (`*_integration_test.exs`)
   - Test against REAL testnet/sandbox APIs only
   - Tag with `@tag :integration`
   - **FAIL if credentials missing** - Don't skip/hide missing tests
   - **FAIL if not using testnet** - Prevent production API calls
   - Must document actual API responses

### Testnet URLs (ENFORCED IN TESTS)

```elixir
# These are the ONLY allowed URLs in test environment
@test_hosts %{
  binance: "testnet.binance.vision",
  bybit: "api-testnet.bybit.com",
  kraken: "api.kraken.com",  # Uses different endpoints for testnet
  deribit: "test.deribit.com"
}

# Tests MUST verify testnet usage
assert Application.get_env(:zen_cex, :binance_host) == "testnet.binance.vision"
assert Application.get_env(:zen_cex, :bybit_host) == "api-testnet.bybit.com"
```

### Environment Variable Naming

**CRITICAL**: Use `_TESTNET_` in environment variable names:

```bash
# GOOD - Clear these are testnet credentials
BINANCE_TESTNET_API_KEY=xxx
BINANCE_TESTNET_API_SECRET=yyy
BYBIT_TESTNET_API_KEY=xxx
BYBIT_TESTNET_API_SECRET=yyy

# BAD - Ambiguous, could be production
BINANCE_API_KEY=xxx  # NEVER use in tests
BYBIT_API_KEY=xxx    # NEVER use in tests
```

## ⚠️ CRITICAL: Task Grouping Guidelines

### Phase-Based Sessions
You may implement **related tasks within the same phase** when they are tightly coupled:
- Tasks that share significant context (e.g., auth + rate limiter for same exchange)
- Tasks that would require redundant setup if separated
- Tasks that form a logical unit of work

### Session Boundaries
- **MUST complete all tasks in a group** before stopping
- **MUST NOT cross phase boundaries** in a single session
- **MUST mark each task as done** as you complete it
- **MUST provide clear handoff notes** when stopping mid-phase

### Example Groupings
- **Good**: Tasks 7-9 (Binance auth, rate limiter, parser) in one session
- **Good**: Tasks 3-5 (HTTP, telemetry, OrderSafety) if working on core infrastructure
- **Bad**: Task 5 (Phase 1) + Task 6 (Phase 2) - crosses phase boundary
- **Bad**: Starting Task 8 without completing Task 7 - breaks dependencies

## What This Library Does (and Does NOT Do)

### This Library DOES (REST Trading Operations):
- **Order Management**: Place, modify, cancel orders via REST
- **Position Management**: Query positions, balances, margins
- **Account Operations**: Withdrawals, deposits, transfers
- **Risk Management**: Liquidation prices, margin requirements

### This Library does NOT do:
- **No Market Data**: No price feeds, order books, or tick data
- **No HFT**: Focus on reliability over microsecond latency
- **No Market Making**: No order book management

## Session Breakdown

### Session 1: Core Module Implementation
**Context needed**: This document + existing Binance rate limiter
**Tasks**:
1. Create `lib/zen_cex/core/rate_limiter.ex` with common ETS operations
2. Extract these functions from Binance rate limiter:
   - `init_table/2` - Create ETS table with proper options
   - `check_and_increment/4` - Atomic weight checking
   - `update_from_headers/3` - Parse response headers
   - `cleanup_old_windows/2` - Remove expired entries
   - `get_current_window/1` - Time window calculation
3. ~~Create behaviour~~ - Use existing `ZenCex.Behaviors.RateLimiter` instead
4. Write tests in `test/zen_cex/core/rate_limiter_test.exs`
5. DO NOT modify existing rate limiters yet

### Session 2: Binance Migration
**Context needed**: This document + Session 1 results
**Tasks**:
1. Refactor `lib/zen_cex/adapters/binance/rate_limiter.ex` to use core
2. Keep Binance-specific: API type detection, weight calculations
3. Run all Binance tests - must pass
4. Run performance benchmark comparing old vs new

### Session 3: Other Exchanges
**Context needed**: This document + Session 2 results
**Tasks**:
1. Implement Kraken rate limiter using core
2. Implement Deribit rate limiter using core
3. Update tests for both exchanges
4. Remove any duplicate code

## Current Implementation Analysis

### Binance Rate Limiter Key Code to Extract

```elixir
# ETS table creation (lines ~50-60)
:ets.new(table_name, [:public, :named_table, :set, write_concurrency: true])

# Atomic increment pattern (lines ~100-150)
key = {api_type, endpoint, window}
case :ets.update_counter(table, key, {2, weight}, {key, 0}) do
  new_count when new_count <= limit -> :ok
  _ -> {:error, :rate_limited}
end

# Window calculation (lines ~200-210)
div(System.system_time(:millisecond), window_ms) * window_ms

# Cleanup pattern (lines ~250-280)
current_window = get_current_window(window_ms)
:ets.select_delete(table, [{{:_, :_, :"$1"}, [{:<, :"$1", current_window}], [true]}])
```

## Core Module Structure

```elixir
defmodule ZenCex.Core.RateLimiter do
  @moduledoc """
  Generic rate limiter for exchange adapters.
  Uses ETS with atomic counters for performance.
  
  NOTE: Exchange-specific rate limiters should:
  1. Use these core functions for ETS operations
  2. Implement the ZenCex.Behaviors.RateLimiter behaviour
  """

  # Create/verify ETS table exists
  def init_table(name, opts \\ %{})

  # Check and increment in one atomic operation
  def check_and_increment(table, key, weight, limit)

  # Parse headers using exchange-specific parser function
  def update_from_headers(table, headers, parser_fn)

  # Remove old windows
  def cleanup_old_windows(table, window_ms)

  # Calculate current time window
  def get_current_window(window_ms)
  
  # Get status for monitoring
  def get_status(table, key_pattern, limit, window_ms)
  
  # Reset specific counters
  def reset(table, key)
end
```

## Exchange Adapter Pattern

```elixir
defmodule ZenCex.Adapters.{Exchange}.RateLimiter do
  @behaviour ZenCex.Behaviors.RateLimiter  # Use existing behaviour
  
  alias ZenCex.Core.RateLimiter, as: Core

  # Implement behaviour callbacks using core functions
  @impl true
  def check_and_increment(endpoint, weight \\ 1) do
    table = get_or_create_table()
    key = {detect_api_type(endpoint), endpoint, Core.get_current_window(@window_ms)}
    Core.check_and_increment(table, key, weight, get_limit(endpoint))
  end

  @impl true
  def update_from_response(response) do
    Core.update_from_headers(get_or_create_table(), response.headers, &parse_headers/1)
  end

  # Exchange-specific logic
  defp detect_api_type(endpoint), do: # exchange logic
  defp parse_headers(headers), do: # exchange logic
  defp get_limit(endpoint), do: # exchange logic
end
```

## Testing Requirements

### Core Module Tests
- ETS table creation and options
- Atomic increment with race conditions
- Window calculation accuracy
- Cleanup removes only old entries
- Header parsing with different formats

### Migration Tests
- All existing tests must pass unchanged
- Performance benchmark showing no regression
- Concurrent request handling
- Memory usage under load

## Common Pitfalls to Avoid

1. **Don't break atomic operations** - Keep increment atomic
2. **Don't change ETS table structure** - Maintain tuple format
3. **Don't modify telemetry events** - Keep same event names
4. **Don't overcomplicate config** - Simple maps, not nested structs
5. **Don't forget cleanup timer** - Must start with application

## Validation Checklist

After each session, verify:
- [ ] All tests pass
- [ ] No performance regression
- [ ] Telemetry events unchanged
- [ ] ETS memory usage stable
- [ ] Concurrent requests handled correctly
- [ ] Cleanup removes expired entries
- [ ] Exchange-specific logic preserved

## Code Location Reference

- Binance: `lib/zen_cex/adapters/binance/rate_limiter.ex`
- Kraken: `lib/zen_cex/adapters/kraken/rate_limiter.ex`
- Deribit: `lib/zen_cex/adapters/deribit/rate_limiter.ex`
- Core (new): `lib/zen_cex/core/rate_limiter.ex`
- Tests: `test/zen_cex/core/rate_limiter_test.exs`

## Session Context Preservation

At end of each session, document:
1. Files created/modified
2. Tests added/passed
3. Any issues encountered
4. Decisions made
5. Next session starting point
