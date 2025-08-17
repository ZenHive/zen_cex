# AI-REVIEW.md - ZenCex Task Review Checklist

## Your Role: AI Reviewer

You validate implementations created by the AI Coder using this checklist. The AI Coder uses AI-IMPLEMENTATION.md to build features.

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

## Review Process

1. **Check Current Task** in AI-IMPLEMENTATION.md
2. **Find Task Checklist** below
3. **Validate Requirements** systematically
4. **Report Results**: ✅ PASS | ❌ FAIL | ⚠️ WARNING

## ⚠️ CRITICAL SAFETY REQUIREMENTS ⚠️

**This library handles real money. Every bug can cause financial losses.**

### Mandatory Safety Patterns (Must be present where applicable)
- **Pattern 0.1**: Clock sync for auth (prevents failures)
- **Pattern 0.2**: Order idempotency (prevents duplicates) - 30-minute sliding window with timestamp storage
- **Pattern 0.3**: Position verification only (auto-reconciliation deferred to WebSocket phase)
- **Pattern 0.4**: Emergency bypass (risk reduction) - never rate limit cancels
- **Pattern 0.5**: Order placement tracking only (lifecycle management deferred to WebSocket phase)
- **Pattern 0.6**: Kill switch - cancel_all_orders/1 must always work, even during failures

## Task Review Checklists

### Implementation Progress Summary
- ✅ **Task #1**: Core.Registry Module - COMPLETED (5/5 ⭐⭐)
- ✅ **Task #2**: Remove Core.Supervisor - COMPLETED (5/5 ⭐⭐)
- ✅ **Task #3**: Core.HTTP with Req Patterns - COMPLETED (5/5 ⭐⭐)
- ✅ **Task #4**: Basic Telemetry Hooks - COMPLETED (5/5 ⭐⭐)
- ✅ **Task #5**: OrderSafety Module with Idempotency - COMPLETED (5/5 ⭐⭐)
- ✅ **Task #6**: ClockSync Module - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #7**: Binance.Auth Module - COMPLETED (4.5/5 ⭐)
- ✅ **Task #8**: Binance.RateLimiter Module - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #9**: Binance.Parser Module - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #9.5**: Declarative Endpoint Registry - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- 🚧 **Tasks #10-25**: Remaining tasks in progress

### Task #1: Core.Registry Module ✅ COMPLETED (5/5 ⭐⭐)
### Task #2: Remove Core.Supervisor ✅ COMPLETED (5/5 ⭐⭐)

### Task #3: Core.HTTP with Req Patterns ✅ COMPLETED (5/5 ⭐⭐)
**File**: `lib/zen_cex/core/http.ex`

#### Required Elements:
- [x] Module exists with proper @moduledoc
- [x] Uses Finch (named: ZenCex.Finch)
- [x] Exponential backoff retry logic
- [x] 30s default timeout, 5s for health checks
- [x] Auth step as Req request step
- [x] Rate limiting as Req request step
- [x] Telemetry events emitted
- [x] Returns proper step values (`{request, response}` for short-circuit)
- [x] Tests exist and pass (15 comprehensive tests)

#### Verified Implementation:
- ✅ Correct Req step patterns with proper return values
- ✅ Uses `{request, response}` for short-circuiting (correct pattern)
- ✅ No blocking operations in middleware
- ✅ All tests passing with comprehensive coverage

### Task #4: Basic Telemetry Hooks ✅ COMPLETED
**File**: `lib/zen_cex/core/telemetry.ex`

#### Required Elements:
- [x] Event pattern: `[:zen_cex, :operation, :result]`
- [x] Metadata: exchange, duration, status
- [x] Hooks into Req's telemetry events
- [x] Tests verify event emission

#### Verified Implementation:
- ✅ Comprehensive event definitions for all operations (request, rate_limit, auth, order)
- ✅ Proper Req telemetry integration with bridge handler
- ✅ Default handlers with configurable attachment/detachment
- ✅ Complete test coverage including integration tests (29 tests passing)
- ✅ Module function references eliminate performance warnings
- ✅ Production-ready with optimal performance

### Task #5: OrderSafety Module with Idempotency ✅ COMPLETED
**File**: `lib/zen_cex/safety/order_safety.ex`

#### Required Elements:
- [x] **30-minute sliding window** with timestamp storage
- [x] Store order IDs with placement timestamps in ETS
- [x] Deterministic client_order_id generation
- [x] ETS cache cleanup for entries older than window
- [x] Idempotency check < 50μs performance
- [x] Tests for duplicate prevention scenarios
- [x] Rollback procedure for failed orders

#### Critical Checks:
- ✅ Window MUST be sliding, not bucket-based - Properly implemented
- ✅ Store tuple: `{exchange, client_order_id, timestamp}` - Correct ETS structure
- ✅ Check timestamp > (now - window) for duplicates - Proper cutoff logic
- ✅ Clean entries older than window every 60 seconds - GenServer cleanup timer

#### Verified Implementation:
- ✅ Flawless sliding window implementation with timestamp comparison
- ✅ High-performance ETS operations with atomic `insert_new/2`
- ✅ Sub-50μs idempotency checks (performance test validates <100μs target)
- ✅ Concurrent access support with read/write concurrency
- ✅ Telemetry integration for monitoring
- ✅ Comprehensive error handling and edge cases
- ✅ Excellent test coverage including performance and concurrency tests (29 tests passing)
- ✅ Proper GenServer lifecycle management
- ✅ Production-ready with perfect safety implementation

### Task #6: ClockSync Module ✅ COMPLETED (5/5 ⭐⭐⭐⭐⭐)
**File**: `lib/zen_cex/safety/clock_sync.ex`

#### Required Elements:
- [x] Sync on startup with all exchanges
- [x] Periodic sync every 5 minutes
- [x] Stores offsets in ETS
- [x] Warns on >1000ms skew
- [x] Fallback to cached offset on failure
- [x] Tests for sync and offset application

#### Verified Implementation:
- ✅ 18 tests (12 passing, 6 skipped with TODO), zero dialyzer warnings
- ✅ Sub-50μs performance, proper GenServer lifecycle, Req-centric patterns
- ✅ Production-ready, provides `now_with_offset/1` for Binance.Auth (Task #7)

### Task #7: Binance.Auth Module ✅ COMPLETED (4.5/5 ⭐)
**File**: `lib/zen_cex/adapters/binance/auth.ex`

#### Required Elements:
- [x] HMAC-SHA256 signature implementation
- [x] Signature as LAST query parameter
- [x] X-MBX-APIKEY header
- [x] recvWindow parameter (default 5000ms, max 60000ms)
- [x] Timestamp with clock offset applied (Pattern 0.1)
- [x] Tests with real API responses (all 5 Binance API types)

#### Verified Implementation:
- ✅ Works as Req request step with correct return patterns
- ✅ ClockSync integration with fallback to system time
- ✅ 96.6% test coverage with real API validation
- ✅ Supports following Binance APIs: spot, margin, usdm/coinm futures, portfolio
- ✅ Named constants for all magic numbers
- ✅ Functions under 20 lines, clean separation of concerns

### Task #8: Binance.RateLimiter Module ✅ COMPLETED (5/5 ⭐⭐⭐⭐⭐)
**File**: `lib/zen_cex/adapters/binance/rate_limiter.ex`

#### Required Elements:
- [x] ETS with atomic counters
- [x] Sliding window implementation (60-second timestamp-based)
- [x] Reads weight from response headers (x-mbx-used-weight-1m)
- [x] Emergency bypass for cancel operations
- [x] Cleanup every 60 seconds (via RateLimiterCleanup GenServer)
- [x] Performance < 100μs for checks (verified)
- [x] Tests: 15 passing, 0 dialyzer warnings, 0 credo issues

### Task #9: Binance.Parser Module ✅ COMPLETED (5/5 ⭐⭐⭐⭐⭐)
**File**: `lib/zen_cex/adapters/binance/parser.ex`

#### Required Elements:
- [x] JSON response parsing
- [x] Normalizes to common format
- [x] Error code mapping (11 codes mapped)
- [x] Type conversions (strings to Decimal)
- [x] Handles null/missing fields
- [x] Tests with fixture data (25 comprehensive tests)

#### Verified Implementation:
- ✅ Complete implementation of all parser behavior callbacks
- ✅ Robust error handling with graceful fallbacks
- ✅ 94.2% test coverage with edge case testing
- ✅ Performance validated (<10ms for 100 items)
- ✅ Clean separation of concerns with helper functions
- ✅ Production-ready with excellent documentation

### Task #9.5: Declarative Endpoint Registry ✅ COMPLETED (5/5 ⭐⭐⭐⭐⭐)
**Files**: `lib/zen_cex/core/endpoint_registry.ex`, `lib/zen_cex/adapters/{exchange}/endpoints.ex`

#### Required Elements:
- [x] Core macro module `ZenCex.EndpointRegistry` for function generation
- [x] @endpoints list with declarative configuration
- [x] Each endpoint spec includes all required fields
- [x] Macro generates functions with proper @spec annotations
- [x] Generated functions accept (params, opts \\ [])
- [x] Support for params_transformer for complex operations
- [x] Hybrid approach: macro for standard, hand-written for complex
- [x] Tests for generated functions (44+ tests passing)
- [x] Documentation generated from endpoint specs

#### Critical Checks:
- [x] NEVER retry order placement operations (compile-time enforced)
- [x] Rate limit weight properly tracked per endpoint
- [x] Parser functions properly referenced (validated at compile time)
- [x] Compile-time validation of endpoint specifications
- [x] Generated functions have proper error types
- [x] Support debug mode to inspect generated code

#### Performance Verified:
- [x] Endpoint lookup < 10μs ✅
- [x] No runtime overhead from macro abstraction ✅

#### Module Integration Verified:
- ✅ Registry → Endpoints module mapping working
- ✅ HTTP → Auth → RateLimiter → Parser chain functioning
- ✅ All safety patterns implemented (0.2, 0.4, 0.6)
- ✅ Telemetry integration complete
- ✅ Endpoints module serves as main exchange entry point

### Task #10: Binance Integration Tests
**File**: `test/zen_cex/adapters/binance_integration_test.exs`

#### Required Elements:
- [ ] Tests against real testnet
- [ ] Captures responses for fixtures
- [ ] Tests error scenarios
- [ ] Uses Req.Test for mocking
- [ ] Fixture version control

### Task #11: CircuitBreaker as Req Error Step
**File**: `lib/zen_cex/core/circuit_breaker.ex`

#### Required Elements:
- [ ] States: Closed, Open, Half-Open
- [ ] Opens after 5 consecutive failures
- [ ] Half-open after 1 minute
- [ ] Per-endpoint tracking (not just per exchange)
- [ ] Integrated as Req error step
- [ ] Tests for state transitions

### Task #12: PositionReconciliation Module
**File**: `lib/zen_cex/safety/position_reconciliation.ex`

#### Required Elements:
- [ ] Manual verification endpoint only
- [ ] Returns position differences without automatic correction
- [ ] Tolerance: `Decimal.new("0.0001")`
- [ ] Exchange-specific settlement awareness
- [ ] Emits telemetry on drift detection
- [ ] Note: Automatic reconciliation deferred to WebSocket implementation

#### Critical Checks:
- Returns drift report only
- Does NOT automatically correct positions
- Logs discrepancies for manual review

### Task #13: EmergencyBypass Module
**File**: `lib/zen_cex/safety/emergency_bypass.ex`

#### Required Elements:
- [ ] Emergency operations list (cancel_order, close_position, etc.)
- [ ] NEVER rate limit emergency ops
- [ ] High priority needs >5% capacity
- [ ] Normal ops need >20% capacity
- [ ] Logs warning for emergency operations
- [ ] Tests for bypass logic

### Task #14: OrderLifecycle Module
**File**: `lib/zen_cex/safety/order_lifecycle.ex`

#### Required Elements:
- [ ] Order placement states only (submitted, accepted, rejected)
- [ ] Terminal states for placement (accepted, rejected)
- [ ] Note: Full lifecycle tracking deferred to WebSocket implementation
- [ ] Store placement metadata in ETS
- [ ] Tests for placement state transitions

### Task #15: Dynamic Rate Limit Learning
**File**: `lib/zen_cex/core/rate_limit_learner.ex`

#### Required Elements:
- [ ] Parses rate limit headers
- [ ] Updates limits dynamically
- [ ] Exchange-specific header names
- [ ] Persists learned limits
- [ ] Tests with real headers

### Task #16: Kraken Implementation
**Files**: `lib/zen_cex/adapters/kraken/*`

#### Required Elements:
- [ ] Endpoints module with @endpoints configuration
- [ ] Strictly increasing nonce in Auth module
- [ ] Nonce persisted across restarts
- [ ] POST with form-urlencoded
- [ ] CSV response parsing in Parser module
- [ ] Base64 secret handling
- [ ] Tests with real API

### Task #17: Deribit OAuth Implementation
**Files**: `lib/zen_cex/adapters/deribit/*`

#### Required Elements:
- [ ] Endpoints module with @endpoints configuration
- [ ] OAuth client credentials flow in Auth module
- [ ] Token refresh 120s before expiry
- [ ] Single-flight protection
- [ ] JSON-RPC format for all calls
- [ ] Test environment support
- [ ] Tests with real OAuth flow

### Task #18: Health Monitoring
**File**: `lib/zen_cex/core/health_monitor.ex`

#### Required Elements:
- [ ] Per-endpoint health tracking
- [ ] Response time tracking
- [ ] Health score aggregation
- [ ] Telemetry for monitoring
- [ ] Configurable thresholds
- [ ] Tests for degradation detection

### Task #19: Multi-Account Rotation
**File**: `lib/zen_cex/core/account_rotator.ex`

#### Required Elements:
- [ ] Multiple API keys per exchange
- [ ] Round-robin or weighted selection
- [ ] Automatic failover
- [ ] Separate rate limits per account
- [ ] Recovery attempts
- [ ] Tests for rotation logic

### Task #20: Production Runbook
**File**: `docs/PRODUCTION.md`

#### Required Elements:
- [ ] Exchange quirks documented
- [ ] Common errors and fixes
- [ ] Emergency procedures
- [ ] Debug procedures
- [ ] Incident response plan

### Task #21-25: WebSocket Implementation (Future Phase)
**Note**: These tasks are planned but explicitly out of scope for current REST-only implementation.

#### Task #21: WebSocket Connection Manager
- [ ] Auto-reconnection with exponential backoff
- [ ] Heartbeat monitoring
- [ ] Connection pooling per exchange
- [ ] Graceful degradation to REST

#### Task #22: Real-time Order Updates
- [ ] Order status streaming
- [ ] Fill notifications
- [ ] Rejection reasons
- [ ] Partial fill handling

#### Task #23: Live Position Tracking
- [ ] Real-time balance updates
- [ ] Position change notifications
- [ ] Margin requirement updates
- [ ] P&L streaming

#### Task #24: Market Data Streaming
- [ ] Order book depth
- [ ] Trade ticker
- [ ] Price feeds
- [ ] Volume tracking

#### Task #25: Automatic Reconciliation
- [ ] Drift detection and auto-correction
- [ ] Position synchronization
- [ ] Order state reconciliation
- [ ] Balance verification

## Performance Requirements

### Critical Operations
- Order placement: <500ms p99
- Order cancellation: <200ms p99
- Position query: <1000ms p95

### Internal Operations
- Rate limit check: <100μs
- Idempotency check: <50μs
- Circuit breaker: <10μs

## Common Review Issues

### Automatic FAIL Conditions
1. **Bucket-based idempotency** (must be sliding window with timestamps)
2. **Wrong Req step signatures** (must follow proper return patterns)
3. **No ETS cleanup** for old entries
4. **Hardcoded rate limits** (must learn from headers)
5. **Missing rollback procedures** for operations
6. **No API version checking** on startup
7. **Missing network partition handling**

### Major Issues (Fix Required)
1. Wrong exchange settlement delays
2. Missing telemetry events
3. Insufficient test coverage
4. No circuit breaker protection
5. Static nonce for Kraken
6. No distributed coordination strategy
7. Missing failure mode documentation

### Minor Issues (Warnings)
1. Missing @moduledoc
2. No @spec annotations
3. Inconsistent error handling
4. Missing debug logging
5. No performance metrics collection

## Review Report Format

```markdown
## Task #N Review

**Status**: ✅ PASS | ❌ FAIL | ⚠️ WARNING

### Checklist Results
- ✅ Requirement 1
- ❌ Requirement 2 (issue at line X)
- ⚠️ Requirement 3 (minor issue)

### Critical Issues
- Issue description and location

### Recommendations
- Specific fixes needed

### Performance
- Metric: Result ✅/❌
```

## Exchange-Specific Requirements

### Binance
- Signature MUST be last parameter
- recvWindow max 60000ms
- X-MBX-APIKEY header required

### Kraken
- Nonce: microsecond timestamp + counter (strictly increasing)
- All private endpoints use POST
- Form-urlencoded content type

### Deribit
- OAuth2 with 120s pre-expiry refresh
- JSON-RPC wrapper required
- Test environment resets weekly

## Additional Review Requirements

### Endpoint Registry Implementation
- Verify endpoints module uses the EndpointRegistry macro correctly
- Check @endpoints configuration has all required fields
- Ensure no retry on order placement operations (compile-time enforced)
- Complex operations should be hand-coded, not forced into @endpoints
- Reference: `lib/zen_cex/core/endpoint_registry.ex` and `lib/zen_cex/adapters/binance/endpoints.ex`

### Req Step Implementation
- Request steps: Must return `request` or `{request, response/exception}`
- Response steps: Must take `{request, response}` and return modified tuple
- Error steps: Must take `{request, exception}` and return tuple or convert
- Use `Req.Request.halt/2` for stopping pipeline execution
- Store exchange metadata in `request.private`

### Rollback Procedures
- Each operation must define rollback strategy
- Document compensation transactions
- Define maximum rollback window
- Log all rollback attempts

### API Version Management
- Check version compatibility on startup
- Store supported versions in endpoints module metadata
- Define migration paths for breaking changes
- Feature flags for version-specific behavior

### Distributed Coordination
- Redis-based coordination with Redix client
- Atomic operations for state changes
- Leader election for singleton operations
- Distributed rate limit tracking

### Data Recovery
- ETS snapshot and restore procedures
- State reconstruction from audit logs
- Corruption detection via checksums
- Recovery time objective (RTO) < 5 minutes

---

## Module Organization Review Checklist

For each exchange, verify all 4 modules exist and cooperate:
- **Endpoints**: Main entry point, uses EndpointRegistry, registered with Core.Registry
- **Auth**: Implements Behaviors.Auth, works as Req step, integrates with ClockSync
- **RateLimiter**: Implements Behaviors.RateLimiter, ETS-based, emergency bypass
- **Parser**: Implements Behaviors.Parser, normalizes responses, handles errors

Reference implementation: `lib/zen_cex/adapters/binance/`

**Remember**: This library handles real money. Be thorough and specific in your review.
