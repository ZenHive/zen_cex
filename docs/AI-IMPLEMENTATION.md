# AI-IMPLEMENTATION.md - ZenCex Task Guide for AI Coder

## Your Role: AI Coder

You implement tasks from this document. An AI Reviewer will validate your work using AI-REVIEW.md.

## Your Background
You are a senior Elixir developer with:
- 10+ years of Elixir/Erlang experience and deep OTP expertise
- Extensive production experience with cryptocurrency exchange APIs
- Expert knowledge of the Req HTTP client library
- Production experience with fault-tolerant financial systems
- Deep understanding of REST API patterns, rate limiting, and authentication

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

**Task #7**: Binance.Auth - HMAC-SHA256 as Req step (Next task in Phase 2)

**File**: `lib/zen_cex/adapters/binance/auth.ex`

**Key Requirements**:
- HMAC-SHA256 signature as Req request step
- Signature as LAST query parameter
- X-MBX-APIKEY header
- recvWindow parameter
- Timestamp with clock offset applied
- Tests with real API responses

**Full Requirements & Review Criteria**: See Task #7 in AI-REVIEW.md

---

## Task Sequence (20 Tasks Total)

### Phase 1: Core Foundation (5 tasks)
```
[✅] Task 1: Core.Registry - Adapter registration and validation
[✅] Task 2: Remove Core.Supervisor - Use Req's built-in features
[✅] Task 3: Core.HTTP with Req patterns and middleware  <- COMPLETED
[✅] Task 4: Basic telemetry hooks with Req events       <- COMPLETED
[✅] Task 5: OrderSafety module with idempotency         <- COMPLETED
```

**Suggested Grouping**: Tasks 3-5 form the core HTTP infrastructure and can be implemented together.

### Phase 2: Binance Reference Implementation (5 tasks)
```
[✅] Task 6: ClockSync with proactive NTP sync           <- COMPLETED
[ ] Task 7: Binance.Auth - HMAC-SHA256 as Req step     ┐
[ ] Task 8: Binance.RateLimiter - ETS tables           ├─ Natural group
[ ] Task 9: Binance.Parser - Response parsing          └─ (auth chain)
[ ] Task 10: Integration tests with real API           <- Requires 7-9
```

**Suggested Groupings**:
- Task 6 alone (foundational)
- Tasks 7-9 together (complete Binance adapter)
- Task 10 alone (comprehensive testing)

### Phase 3: Production Safety (5 tasks)
```
[ ] Task 11: CircuitBreaker as Req error step          ┐
[ ] Task 12: PositionReconciliation with drift         ├─ Safety group
[ ] Task 13: EmergencyBypass for rate limiting         └─ (resilience)
[ ] Task 14: OrderLifecycle state machine               <- Standalone
[ ] Task 15: Dynamic rate limit learning                <- Enhancement
```

**Suggested Groupings**:
- Tasks 11-13 together (core safety mechanisms)
- Task 14 alone (complex state machine)
- Task 15 alone (optimization)

### Phase 4: Additional Exchanges (5 tasks)
```
[ ] Task 16: Kraken adapter (complete implementation)    <- Standalone
[ ] Task 17: Deribit OAuth adapter (complete impl)       <- Standalone
[ ] Task 18: Health monitoring with endpoint tracking   ┐
[ ] Task 19: Multi-account rotation for resilience      ├─ Operations
[ ] Task 20: Production runbook with exchange quirks    └─ group
```

**Suggested Groupings**:
- Task 16 alone (complete exchange)
- Task 17 alone (complete exchange)
- Tasks 18-20 together (operational excellence)

### Phase 5: WebSocket Implementation (Future - Not Current Scope)
```
[ ] Task 21: WebSocket connection manager with reconnection
[ ] Task 22: Real-time order status updates and fills
[ ] Task 23: Live position tracking with balance updates
[ ] Task 24: Market data streaming (order book, trades)
[ ] Task 25: Automatic reconciliation with drift detection
```

**Note**: WebSocket tasks are planned but explicitly out of scope for the current REST-only implementation. These features include:
- Real-time balance monitoring
- Order lifecycle tracking with status updates
- Automatic position reconciliation
- Market data feeds
- Push notifications for fills and errors

---

## Quick Pattern References

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

### Core Patterns (1.x)
```elixir
# Req request steps: Return request OR {request, response/exception} to halt
# Req response steps: Take {request, response}, return modified tuple
# Req error steps: Take {request, exception}, return tuple or convert to response
# ETS tables: Use atomic operations with :ets.update_counter/3
# Circuit breaker: Per-endpoint tracking, exponential backoff on half-open
# Network partitions: Detect via timeout patterns, fallback to cached responses
# API versioning: Store version in adapter metadata, migration strategy required
```

### Trading Patterns (2.x)
```elixir
# Order tracking: Store in ETS with timestamps
# Partial fills: >95% accept, <10% replace
# Pre-trade validation: Check balance, margin, limits
```

### Exchange Requirements Quick Reference

| Exchange | Auth | Critical Requirement | Common Gotcha |
|----------|------|---------------------|---------------|
| Binance | HMAC | Signature LAST in params | Spot vs Futures different URLs/limits |
| Kraken | Nonce+HMAC | Microsecond timestamp + counter | Async margin check after accept |
| Deribit | OAuth2 | Refresh 120s before expiry | Mark price lags in volatility |

**Critical Exchange Quirks**:
- **Binance**: `recvWindow` max 60s, OCO orders = 2x weight, test orders consume limits
- **Kraken**: "EOrder:Insufficient funds" can occur AFTER accept, "Busy" needs backoff
- **Deribit**: Weekly test reset Sunday 08:00 UTC, portfolio margin different endpoints

---

## Common Mistakes to Avoid

1. **Using 5-minute idempotency window** → Use 30-minute sliding window with timestamps
2. **Using Process.sleep** → Use Task.async or send_after
3. **Bucket-based idempotency** → Use proper sliding window with timestamp storage
4. **Hardcoded rate limits** → Learn from headers dynamically
5. **Missing cleanup** → Clean ETS every 60 seconds, remove entries older than window
6. **Wrong settlement delays** → Binance 100ms, Kraken 500ms, Deribit 200ms
7. **No circuit breaker** → Add per-endpoint failure protection
8. **Static nonce** → Must increase monotonically for Kraken
9. **No telemetry** → Emit events for all operations
10. **Blocking operations** → Keep everything async
11. **Missing rollback** → Define rollback procedures for each operation
12. **No version check** → Verify exchange API version compatibility

---

## Testing Requirements

For each module you implement:
1. Unit tests for all public functions
2. Integration test with mock exchange
3. Error scenario tests (timeout, rate limit, auth failure)
4. Performance test (verify <50μs for critical operations)

Test file naming: `test/zen_cex/core/http_test.exs` (match module path)

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
- **Minimal GenServers**: Only Deribit OAuth needs state
- **ETS for performance**: Atomic operations for counters
- **Safety first**: Idempotency, validation, reconciliation
- **REST only**: No WebSocket, no market data

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
