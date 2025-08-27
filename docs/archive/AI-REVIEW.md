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

## Testing Strategy: Real TESTNET APIs Only

**[!] SIMPLE RULE: ALL Tests Must Use Real TESTNET APIs [!]**
--------------------------------------------------
**Test against real exchange testnet/sandbox APIs. Period.**
**No mocks. No fixtures. No simulation. Just real testnet APIs.**
**NEVER use production APIs in tests.**
--------------------------------------------------

### Critical Testing Requirements
1. **Unit Tests** (`*_test.exs`) - Test pure functions only, no API calls
2. **Integration Tests** (`*_integration_test.exs`) - REAL testnet APIs only
3. **Tests must FAIL if testnet credentials missing** - No silent skipping
4. **Tests must FAIL if production URL detected** - Enforce testnet usage
5. **Environment variables must use `_TESTNET_` naming** - Clear distinction from production

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
- ✅ **Task #10.5**: Binance Multi-API Refactoring - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #11**: CircuitBreaker with req_fuse - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #12**: Enhanced Telemetry Documentation - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #13**: Debug Mode with curl_req - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #14**: EmergencyBypass Module - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #15**: OrderSafety Pre-trade Validation - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- ✅ **Task #17**: Bybit REST API Implementation - COMPLETED (5/5 ⭐⭐⭐⭐⭐)
- 🚧 **Tasks #16, 18-25**: Remaining tasks in progress

### Task #11: CircuitBreaker with req_fuse ✅ COMPLETED
**File**: Uses `req_fuse` optional dependency

#### Required Elements:
- [✅] States: Closed, Open, Half-Open (via req_fuse)
- [✅] Opens after configurable failures (default 5)
- [✅] Half-open after configurable timeout (default 60s)
- [✅] Per-exchange tracking (configured per HTTP client)
- [✅] Integrated as Req plugin step
- [✅] Tests for circuit breaker behavior
- [✅] Telemetry events emitted
- [✅] Returns 503 when circuit blown

### Task #12: Enhanced Telemetry Documentation ✅ COMPLETED
**Files**: `docs/TELEMETRY.md`, `lib/zen_cex/examples/telemetry_handlers.ex`

#### Required Elements:
- [✅] Comprehensive telemetry documentation created
- [✅] Production-ready example handlers
- [✅] Updated README with monitoring section
- [✅] Leverages Req's built-in telemetry
- [✅] ZenCex-specific events documented
- [✅] Performance metrics included
- [✅] Error tracking patterns

### Task #13: Debug Mode with curl_req ✅ COMPLETED
**File**: `lib/zen_cex/core/debug.ex`

#### Required Elements:
- [✅] curl_req as optional dev dependency
- [✅] Captures failed requests automatically
- [✅] Exports requests as curl commands
- [✅] ETS storage for recent requests
- [✅] Telemetry events emitted
- [✅] Comprehensive documentation in README
- [✅] Integration with HTTP error handling

### Task #14: EmergencyBypass Module ✅ COMPLETED
**File**: `lib/zen_cex/safety/emergency_bypass.ex`

#### Required Elements:
- [✅] Emergency operations list (cancel_order, close_position, etc.)
- [✅] NEVER rate limit emergency ops
- [✅] Reserves 10% capacity for critical operations
- [✅] Normal ops need >20% capacity check
- [✅] Logs warning for emergency operations
- [✅] Tests for bypass logic
- [✅] Integration with rate limiters

### Task #15: OrderSafety Pre-trade Validation ✅ COMPLETED
**File**: `lib/zen_cex/safety/order_safety.ex`

#### Required Elements:
- [✅] 30-minute sliding window idempotency
- [✅] Balance checks (with TODOs for real API)
- [✅] Symbol validation with caching
- [✅] Notional limits checking
- [✅] Price/size sanity checks
- [✅] Global kill switch
- [✅] Comprehensive tests
- [✅] TODOs added for market data integration

### Task #16: Dynamic Rate Limit Learning (NOT COMPLETED)
**File**: `lib/zen_cex/core/rate_limit_learner.ex`

#### Required Elements:
- [ ] Parses rate limit headers
- [ ] Updates limits dynamically
- [ ] Exchange-specific header names
- [ ] Persists learned limits
- [ ] Tests with real headers

**Note**: Task #16 was DEFERRED as medium-high complexity for implementation after core functionality is stable.

### Task #17: Bybit Implementation ✅ COMPLETED
**Files**: `lib/zen_cex/adapters/bybit/*`

**Note**: Original requirements were incorrect. Bybit v5 API uses timestamps (not nonces) and JSON format (not form-urlencoded/CSV).

#### Required Elements (Corrected for Bybit v5 API):
- [✅] Endpoints module with @endpoints configuration
- [✅] Timestamp-based auth with ClockSync (NOT nonce-based)
- [✅] HMAC-SHA256 signature with proper header format
- [✅] JSON request/response format (NOT form-urlencoded)
- [✅] JSON response parsing in Parser module (NOT CSV)
- [✅] Base64 secret handling via CommonSigner
- [✅] Tests with real testnet API
- [✅] X-BAPI-* header authentication
- [✅] Recv window parameter support (5000ms default)

### Task #18: Kraken Implementation
**Files**: `lib/zen_cex/adapters/kraken/*`

#### Required Elements:
- [ ] Endpoints module with @endpoints configuration
- [ ] Auth module for nonce-based HMAC
- [ ] RateLimiter with tier-based limits
- [ ] Parser for response normalization
- [ ] Registration in Core.Registry
- [ ] Integration tests with testnet

### Task #19: Deribit OAuth Implementation
**Files**: `lib/zen_cex/adapters/deribit/*`

#### Required Elements:
- [ ] Endpoints module with @endpoints configuration
- [ ] OAuth client credentials flow in Auth module
- [ ] Token refresh 120s before expiry
- [ ] Single-flight protection
- [ ] JSON-RPC format for all calls
- [ ] Test environment support
- [ ] Tests with real OAuth flow

### Task #20: Health Monitoring
**File**: `lib/zen_cex/core/health_monitor.ex`

#### Required Elements:
- [ ] Per-endpoint health tracking
- [ ] Response time tracking
- [ ] Health score aggregation
- [ ] Telemetry for monitoring
- [ ] Configurable thresholds
- [ ] Tests for degradation detection

### Task #21: Multi-Account Rotation
**File**: `lib/zen_cex/core/account_rotator.ex`

#### Required Elements:
- [ ] Multiple API keys per exchange
- [ ] Round-robin or weighted selection
- [ ] Automatic failover
- [ ] Separate rate limits per account
- [ ] Recovery attempts
- [ ] Tests for rotation logic

### Task #22: Production Runbook
**File**: `docs/PRODUCTION.md`

#### Required Elements:
- [ ] Exchange quirks documented
- [ ] Common errors and fixes
- [ ] Emergency procedures
- [ ] Debug procedures
- [ ] Incident response plan

### Task #23-27: WebSocket Implementation (Future Phase)
**Note**: These tasks are planned but explicitly out of scope for current REST-only implementation.

#### Task #23: WebSocket Connection Manager
- [ ] Auto-reconnection with exponential backoff
- [ ] Heartbeat monitoring
- [ ] Connection pooling per exchange
- [ ] Graceful degradation to REST

#### Task #24: Real-time Order Updates
- [ ] Order status streaming
- [ ] Fill notifications
- [ ] Rejection reasons
- [ ] Partial fill handling

#### Task #25: Live Position Tracking
- [ ] Real-time balance updates
- [ ] Position change notifications
- [ ] Margin requirement updates
- [ ] P&L streaming

#### Task #26: Market Data Streaming
- [ ] Order book depth
- [ ] Trade ticker
- [ ] Price feeds
- [ ] Volume tracking

#### Task #27: Automatic Reconciliation
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
8. **Using mocks or fixtures** (must use real testnet APIs)
9. **Tests that skip when credentials missing** (must fail loudly)
10. **Production URLs in tests** (must enforce testnet URLs)

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
