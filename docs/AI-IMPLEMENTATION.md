# AI-IMPLEMENTATION.md - ZenCex Task Guide for AI Coder

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

## Current Task


## Recently Completed


---

## Task Sequence (27 Tasks Total)

### Phase 1: Core Foundation (5 tasks)
done

### Phase 2: Binance Reference Implementation (7 tasks)
done

### Phase 3: Reliability & Observability (3 tasks)
```
[✅] Task 11: Circuit Breaker with req_fuse            <- COMPLETED
[✅] Task 12: Enhanced Telemetry Documentation          <- COMPLETED
[✅] Task 13: Debug Mode with curl_req                  <- COMPLETED
```

**Task 11: Circuit Breaker** - ✅ COMPLETED - Added req_fuse as optional dependency for per-exchange circuit breaking. Opt-in config, emits telemetry, returns 503 when blown.

**Task 12: Telemetry Docs** - ✅ COMPLETED - Created comprehensive telemetry documentation (docs/TELEMETRY.md), production-ready example handlers (lib/zen_cex/examples/telemetry_handlers.ex), and updated README with monitoring section. Leverages Req's built-in telemetry with ZenCex-specific events.

**Task 13: Debug Mode** - ✅ COMPLETED - Added curl_req as optional dev dependency for debugging. Created ZenCex.Core.Debug module that captures failed requests and exports them as curl commands. Automatic integration with HTTP error handling, ETS storage for recent requests, telemetry events, and comprehensive documentation in README.

### Phase 4: Production Safety (3 tasks)
```
[✅] Task 14: EmergencyBypass for rate limiting         <- COMPLETED
[✅] Task 15: OrderSafety pre-trade validation          <- COMPLETED
[ ] Task 16: Dynamic rate limit learning               <- USEFUL (1.5 hrs)
```

**Task Details:**

**Task 14: EmergencyBypass** - ✅ COMPLETED - Implemented emergency bypass system that reserves 10% of rate limit capacity for critical operations. Cancel orders, close positions, and other emergency operations always execute regardless of rate limits. Added comprehensive tests and documentation.

**Task 15: OrderSafety** - ✅ COMPLETED - Implemented comprehensive pre-trade validation module with 30-minute sliding window idempotency, balance checks, symbol validation with caching, notional limits, price/size sanity checks, and global kill switch. TODOs added for real API integration when market data endpoints are available.

**Task 16: Dynamic Rate Limit Learning** - **DEFERRED - Medium-High Complexity**
  - **Architecture fits**: ETS tables, header parsing, Req middleware already in place
  - **Implementation path**: 1) Passive observation phase (collect headers, track 429s), 2) Dynamic limits with confidence scoring, 3) Self-tuning request spacing
  - **Key changes**: New `RateLimitLearner` module, enhanced header extraction (retry-after, actual limits), adaptive spacing algorithms
  - **Benefits**: Auto-adapts to API changes, reduces 429s over time, no manual config updates
  - **Risks**: Learning period uncertainty, complex edge cases during API changes
  - **Recommendation**: Implement in phases after core functionality stable. Start with passive learning to validate approach.

**Deferred to WebSocket Phase:**
- PositionReconciliation (needs real-time updates for effectiveness)
- OrderLifecycle state machine (minimal value without streaming)

### Phase 5: Additional Exchanges (6 tasks)
```
[ ] Task 17: Bybit REST API implementation (complete)    <- NEXT - Standalone
[ ] Task 18: Kraken implementation (complete exchange)   <- Standalone
[ ] Task 19: Deribit OAuth implementation (complete)     <- Standalone
[ ] Task 20: Health monitoring with endpoint tracking   ┐
[ ] Task 21: Multi-account rotation for resilience      ├─ Operations
[ ] Task 22: Production runbook with exchange quirks    └─ group
```

**Task 17 Details (Bybit REST API)**:
- Complete REST API implementation for Bybit exchange
- Support for Spot, Linear (USDT), and Inverse (Coin) derivatives
- HMAC-SHA256 authentication similar to Binance
- Rate limiting per endpoint category (GET vs POST)
- Unified v5 API implementation
- Testnet: testnet.bybit.com

**Suggested Groupings**:
- Task 17 alone (Bybit complete exchange) 
- Task 18 alone (Kraken complete exchange)
- Task 19 alone (Deribit complete exchange)
- Tasks 20-22 together (operational excellence)

### Phase 6: WebSocket Implementation (Future - Not Current Scope)
```
[ ] Task 23: WebSocket connection manager with reconnection
[ ] Task 24: Real-time order status updates and fills
[ ] Task 25: Live position tracking with balance updates
[ ] Task 26: Market data streaming (order book, trades)
[ ] Task 27: Automatic reconciliation with drift detection
```

**Note**: WebSocket tasks are planned but explicitly out of scope for the current REST-only implementation. These features include:
- Real-time balance monitoring
- Order lifecycle tracking with status updates
- Automatic position reconciliation
- Market data feeds
- Push notifications for fills and errors

---

## Quick Pattern References

### Declarative Endpoint Registry Pattern
- See `lib/zen_cex/core/endpoint_registry.ex` for macro documentation
- See `lib/zen_cex/adapters/binance/endpoints.ex` for reference implementation
- Key rule: NEVER set `retry: true` for order placement operations
- Use @endpoints for standard operations, hand-code complex ones (OCO orders, etc.)

### Req Step Implementation Patterns
- Request steps: Return `request` OR `{request, response/exception}` to halt
- Response steps: Take `{request, response}`, return modified tuple
- Error steps: Take `{request, exception}`, return tuple or convert to response
- See `lib/zen_cex/adapters/binance/auth.ex` for reference implementation

### Safety Patterns (0.x)
```elixir
# 0.1 Clock Sync: Sync every 5 min, store offset in ETS
# 0.2 Idempotency: 30-min sliding window, store order IDs with timestamps
# 0.3 Reconciliation: Manual verification only (auto-reconcile in Future Enhancements)
# 0.4 Emergency: Never rate limit cancel_all operations
# 0.5 Lifecycle: Track order placement only (status monitoring in Future Enhancements)
# 0.6 Kill Switch: cancel_all_orders/1 must always work, even during failures
# 0.7 Distributed: Redis for coordination - use Redix client with atomic operations
# 0.8 Audit: Immutable logs, 7-year retention, structured JSON format
# 0.9 Draining: Track in-flight, 30s timeout, graceful shutdown
# 0.10 Rotation: 5-min overlap, weighted selection, automatic failover
# 0.11 Data Integrity: Validate responses, ETS snapshot recovery, state reconstruction
```

### Module Organization Patterns
- Each exchange has 4 cooperating modules: Endpoints, Auth, RateLimiter, Parser
- Endpoints module is the main entry point (uses EndpointRegistry macro)
- Core.Registry maps exchange name to its Endpoints module
- See `lib/zen_cex/adapters/binance/` for reference implementation

### Core Patterns (1.x)
```elixir
# Req request steps: Return request OR {request, response/exception} to halt
# Req response steps: Take {request, response}, return modified tuple
# Req error steps: Take {request, exception}, return tuple or convert to response
# ETS tables: Use atomic operations with :ets.update_counter/3
# Circuit breaker: Per-endpoint tracking, exponential backoff on half-open
# Network partitions: Detect via timeout patterns, fallback to cached responses
# API versioning: Store version in module metadata, migration strategy required
```

### Trading Patterns (2.x)
```elixir
# Order tracking: Store in ETS with timestamps
# Partial fills: >95% accept, <10% replace
# Pre-trade validation: Check balance, margin, limits
```

### Exchange Requirements Quick Reference

| Exchange | Auth Method | Critical Requirement | Common Gotcha |
|----------|-------------|---------------------|---------------|
| Binance | HMAC | Signature LAST in params | Spot vs Futures different URLs/limits |
| Bybit | HMAC | Unified v5 API, timestamp required | Rate limits differ by endpoint category |
| Kraken | Nonce+HMAC | Microsecond timestamp + counter | Async margin check after accept |
| Deribit | OAuth2 | Refresh 120s before expiry | Mark price lags in volatility |

**Critical Exchange Quirks**:
- **Binance**: `recvWindow` max 60s, OCO orders = 2x weight, test orders consume limits
- **Bybit**: Unified v5 API consolidates spot/derivatives, category parameter required, position API for derivatives only
- **Kraken**: "EOrder:Insufficient funds" can occur AFTER accept, "Busy" needs backoff
- **Deribit**: Weekly test reset Sunday 08:00 UTC, portfolio margin different endpoints

---

## Common Mistakes to Avoid

1. **Using mocks or fixtures** → ALWAYS test real testnet APIs, no mocks needed
2. **DDoSing exchanges in tests** → Use max 5-10 requests with controlled concurrency
3. **Using 5-minute idempotency window** → Use 30-minute sliding window with timestamps
4. **Using Process.sleep** → Use Task.async or send_after
5. **Bucket-based idempotency** → Use proper sliding window with timestamp storage
6. **Hardcoded rate limits** → Learn from headers dynamically
7. **Missing cleanup** → Clean ETS every 60 seconds, remove entries older than window
8. **Wrong settlement delays** → Binance 100ms, Kraken 500ms, Deribit 200ms
9. **No circuit breaker** → Add per-endpoint failure protection
10. **Static nonce** → Must increase monotonically for Kraken
11. **No telemetry** → Emit events for all operations
12. **Blocking operations** → Keep everything async
13. **Missing rollback** → Define rollback procedures for each operation
14. **No version check** → Verify exchange API version compatibility
15. **Uncontrolled test concurrency** → Max 2-3 parallel requests in tests

---

## Testing Requirements

**SIMPLE RULE: Real TESTNET APIs or No Test**
- **ALL** integration tests use real testnet/sandbox APIs
- **NO** mocks, fixtures, or simulations
- **FAIL** loudly if testnet credentials missing
- **FAIL** if production URLs detected in tests
- **DOCUMENT** actual testnet API responses

For each module you implement:
1. **Unit tests** (`*_test.exs`)
   - Test pure functions only
   - No API calls needed
   - Fast, no credentials required

2. **Integration tests** (`*_integration_test.exs`)
   - Test against REAL testnet APIs only
   - Tag with `@tag :integration`
   - Enforce testnet URL in setup
   - Fail if credentials missing (no skipping)
   - Document actual testnet responses

3. **Running tests**
   ```bash
   # Unit tests only (fast)
   mix test --exclude integration

   # All tests (requires testnet credentials)
   BINANCE_TESTNET_API_KEY=xxx BINANCE_TESTNET_API_SECRET=yyy mix test
   ```

4. **Performance tests** (verify <50μs for critical operations)
   - Test performance locally without API calls
   - Use benchee for accurate measurements

Test file naming: `test/zen_cex/core/http_test.exs` (match module path)

**Integration Test Guidelines**:
- Tag with `@tag :integration` for separate test runs
- Maximum 5-10 requests per test
- Use `Task.async_stream` with `max_concurrency: 2`
- Add 1-second delays between test groups
- See `test/zen_cex/adapters/binance_integration_test.exs` for patterns

### Performance Measurement Example:
```elixir
test "idempotency check performance" do
  start = System.monotonic_time()
  OrderSafety.check_existing_order(:binance, "test_id")
  duration = System.monotonic_time() - start

  microseconds = System.convert_time_unit(duration, :native, :microsecond)
  assert microseconds < 50, "Check took #{microseconds}μs (max: 50μs)"
end
```

---

## Quick Troubleshooting

### Rate Limited (429)
- Check: `:ets.tab2list(:binance_rate_limits)`
- Fix: Reduce frequency, check for multiple processes

### Auth Failed (401)
- Check: Clock sync, nonce persistence
- Fix: `ClockSync.ensure_time_sync(:binance)`

### Order Stuck
- Check: `:ets.lookup(:order_tracking, {exchange, order_id})`
- Fix: Cancel if stuck > timeout

---

## Development Commands

```bash
# Run your specific test
mix test test/zen_cex/safety/order_safety_test.exs

# Check types
mix dialyzer

# Check code quality
mix credo --strict

# Format code
mix format
```

---

## When You're Done with a Task Group

1. Run all tests for completed tasks and ensure they pass
2. Run `mix format` and `mix credo`
3. Update task status to [✅] for each completed task
4. Document any rollback procedures needed for your changes
5. Verify exchange API version compatibility
6. Report completion with:
   - Tasks completed (e.g., "Tasks #7-9 complete")
   - Any deviations from requirements with justification
   - Performance metrics if applicable
   - Known limitations or edge cases
7. If stopping mid-phase, provide handoff notes:
   - What was completed
   - Any partial work or considerations
   - ETS table states and cleanup status
   - Recommended next task grouping
8. **STOP** at phase boundaries or logical breakpoints

## Failure Mode Handling

### Network Failures
- Detect via timeout patterns and connection errors
- Fallback to cached responses where safe
- Circuit breaker activation per endpoint
- Exponential backoff with jitter

### Exchange Maintenance
- Check exchange status endpoints
- Graceful degradation during maintenance
- Queue non-critical operations
- Alert on extended downtime

### API Deprecation
- Version checking on startup
- Migration path documentation
- Compatibility layer for transitions
- Feature flags for version-specific code

### Partial System Failures
- Endpoint-specific circuit breakers
- Fallback to alternative endpoints
- Health score tracking per endpoint
- Automatic rerouting when possible

---

## Architecture Notes

- **Req-centric**: Use Req's built-in features, don't reinvent
- **Declarative endpoints**: Use @endpoints configuration for standard operations
- **Minimal GenServers**: Only Deribit OAuth needs state
- **ETS for performance**: Atomic operations for counters
- **Safety first**: Idempotency, validation, reconciliation
- **REST only**: No WebSocket, no market data

### Endpoint Registry vs Hand-Coded Functions
- Use @endpoints for: standard CRUD, simple queries, predictable patterns
- Hand-code for: OCO orders, multi-step operations, special validation
- See Binance.Endpoints for examples of both approaches

## Future Enhancements (Not in Current Scope)

These features are documented for future implementation but explicitly excluded from current REST-only scope:

### WebSocket Support (Planned Next Phase)
- Real-time order status updates
- Market data streaming
- Push notifications for fills
- Live position tracking
- Automatic order reconciliation
- Order timeout detection and status checking
- Position drift detection with auto-reconciliation
- Real-time rate limit updates
- Heartbeat monitoring

### Advanced Order Management (Requires WebSocket)
- Automatic status checks after timeout
- Continuous order monitoring
- Background reconciliation with streaming updates
- Partial fill detection and handling
- Order lifecycle state machine with transitions
- Automatic retry on recoverable failures

### Market Data Features (Requires WebSocket)
- Order book depth
- Trade ticker streams
- Price feed aggregation
- Volume-weighted calculations

**Important**: The current REST-only implementation focuses on order placement, cancellation, and account queries. Advanced features like order status monitoring, automatic reconciliation, and real-time updates will be implemented in the WebSocket module.

For detailed patterns, requirements, and validation criteria, see AI-REVIEW.md.
