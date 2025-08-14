# CEX Implementation Tasks

## Progress Summary
**Overall Status**: Strategic Pivot: Fresh start with plugin architecture (Expert Validated)
**Reference Implementation**: 5 modules completed (4.6/5 avg rating) - Now serving as reference only
**New Approach**: 18 modules with locked scope, ~2,000 lines
**Timeline**: 5 days with realistic scope (includes 2-3 hour burn-in)
**Expert Assessment**: "Strong direction, production patterns, scope realism"

### Reference Implementation (Not Production)
- 📚 1.1 Exchange.HTTP Module (4.5/5) - REQ integration with exponential backoff
- 📚 1.2 Exchange.Auth Module (4.5/5) - HMAC/OAuth authentication  
- 📚 1.3 Clock Sync Validation (5/5) - Health monitoring with consensus
- 📚 1.4 Exchange.Cache Module (4.5/5) - TTL-based caching with cleanup
- 📚 1.5 Exchange.RateLimit Module (4.5/5) - Atomic ETS rate limiting

### New Plugin Structure (Day 1-5) - Expert Validated
- ✅ Core Modules (5): HTTP (with Retry-After), Registry (compile-time), Supervisor, Circuit (per-endpoint), Health (continuous)
- ✅ Behaviors (5): Adapter (@optional_callbacks), Auth, RateLimiter, Parser, PubSub (pluggable)
- ✅ Core MarketData (1): Shared WebSocket with connection caps and batching
- ✅ Binance Adapter (4): adapter, auth, rate_limiter (with endpoint weights), parser
- ✅ Kraken Adapter (4): adapter, auth (ETS nonce), rate_limiter, parser
- ✅ Deribit Adapter (4): adapter, auth (single-flight OAuth), rate_limiter, parser

## Overview
Strategic pivot to plugin architecture - building fresh from Day 1 rather than refactoring.

**Expert Review Applied**:
- Fixed critical bugs (Process.list() broadcast, ETS match specs)
- Added production patterns (per-endpoint circuits, Retry-After)
- Removed unnecessary complexity (Phoenix.PubSub dependency)
- Enhanced security (redaction in telemetry)
- Realistic timeline with burn-in testing
- **Approach**: Plugin-based architecture with isolated adapters per exchange
- **Timeline**: 5 days (vs 3-4 weeks refactoring)
- **Architecture**: Each exchange is self-contained (no cross-contamination)
- **Core**: Just 5 thin coordinator modules (~300 lines total)
- **Status**: Using existing 5 modules as reference, not production code

## Why Plugin Architecture?
- **No refactoring needed** - Build it right from Day 1
- **Clean separation** - Exchange bugs don't cascade
- **Parallel development** - Teams can work independently  
- **Easy testing** - Each adapter tested in isolation
- **Simple to extend** - New exchange = new adapter folder

## Day 1: Foundation + Complete Binance Adapter

### Core Foundation Modules
- [ ] Core.HTTP - Thin coordinator using REQ
- [ ] Core.Registry - Process discovery
- [ ] Core.Supervisor - Adapter supervision
- [ ] Behaviors (Adapter, Auth, RateLimiter, MarketData, Parser)

### Binance Adapter Implementation
- [ ] Binance.HTTP - Exchange-specific configuration
- [ ] Binance.Auth - HMAC-SHA256 signatures
- [ ] Binance.RateLimiter - 1200/min spot, 2400/min futures
  - **WARNING**: Tests in `test/zen_cex/adapters/binance/` need rewriting for plugin architecture
- [ ] Binance.MarketData - WebSocket for public data
- [ ] Binance.Parser - Response normalization
- [ ] Binance.Client - Orchestration

## Day 2: Kraken + Deribit Adapters

### Kraken Adapter
- [ ] Kraken.HTTP - Force HTTP/1.1
- [ ] Kraken.Auth - Nonce with microseconds + counter
- [ ] Kraken.RateLimiter - Tier-based limits
- [ ] Kraken.MarketData - Binary frame decompression
- [ ] Kraken.Parser - Response normalization
- [ ] Kraken.Client - Orchestration

### Deribit Adapter
- [ ] Deribit.HTTP - JSON-RPC format
- [ ] Deribit.Auth - OAuth2 with refresh
- [ ] Deribit.RateLimiter - 20/sec limits
- [ ] Deribit.MarketData - JSON-RPC WebSocket
- [ ] Deribit.Parser - Response normalization
- [ ] Deribit.Client - Orchestration

## Day 3: WebSocket Discovery & Implementation

### ZenWebsocket Discovery
- [ ] Add dependency and explore API
- [ ] Test with echo servers
- [ ] Document patterns and limitations

### WebSocket Implementation
- [ ] Implement MarketData behavior
- [ ] Add deduplication buffers
- [ ] Connection health monitoring
- [ ] Reconnection strategies

## Day 4: Integration & Client Facade

### Client Facade
- [ ] ZenCex.Client - Unified interface
- [ ] Dynamic adapter loading
- [ ] Fallback strategies
- [ ] Cache coordination

### Circuit Breaker & Health
- [ ] Core.Circuit implementation
- [ ] Core.Health monitoring
- [ ] Multi-exchange consensus
- [ ] Alert thresholds

## Day 5: Testing & Documentation

### Integration Testing
- [ ] End-to-end adapter tests
- [ ] Performance benchmarks
- [ ] Failure scenario testing
- [ ] Memory leak validation

### Documentation
- [ ] API documentation
- [ ] Adapter development guide
- [ ] Migration guide from v1
- [ ] Performance tuning guide

---

## Reference Implementation Details

### 📚 REFERENCE IMPLEMENTATION - Will be rebuilt as adapter modules

### ✅ 1.1 Exchange.HTTP Module - **COMPLETED** ⭐⭐⭐⭐½ (4.5/5)
**Reference**: Lines 165-230 in plan
- [x] **TDD: Write tests** for pure functions (request building, response parsing)
- [x] **Implement** base module with pure functions
- [x] **TDD: Write tests** for REQ configuration (exponential backoff: 2^attempt * 100ms + 25% jitter)
- [x] **Implement** REQ configuration with exponential backoff and jitter
- [x] **TDD: Write tests** for Finch pool configuration
- [x] **Implement** Finch pool configuration (lines 634-688)
- [x] **TDD: Write tests** for request/response middleware
- [x] **Implement** request middleware for timestamps
- [x] **Implement** response middleware for weight extraction
- [x] **TDD: Write tests** for operation-specific timeouts
- [x] **Implement** operation-specific timeouts (trading: 2s, market: 5s, historical: 30s)
- [x] **Integration test** with real test endpoints (if available)

**Review Notes:**
- Excellent REQ integration with proper exponential backoff and jitter
- Clean middleware architecture using REQ's prepend/append pattern
- Comprehensive test coverage with good edge cases
- Rate limit enforcement placeholder (TODO) - correctly deferred to Task 1.5
- REQ cache plugin for slow-changing data - can be added in optimization phase
- **Implemented in**: `lib/zen_cex/exchange/http.ex`
- **Tests in**: `test/zen_cex/exchange/http_test.exs`

**Plugin Architecture Impact:**
- Will become: Binance.HTTP, Kraken.HTTP, Deribit.HTTP (adapter-specific)
- Core keeps only: Thin REQ coordinator (~50 lines)
- Each adapter owns: Exchange-specific middleware, timeout configuration

### ✅ 1.2 Exchange.Auth Module - **COMPLETED** ⭐⭐⭐⭐½ (4.5/5)
**Reference**: Lines 231-259 in plan
- [x] **TDD: Write tests** for HMAC-SHA256 signature generation (Binance)
- [x] **Implement** HMAC-SHA256 for Binance
- [x] **TDD: Write tests** for Kraken nonce (microsecond + counter)
- [x] **Implement** Kraken microsecond + counter nonce with atomic ETS operations
- [x] **TDD: Write tests** for Deribit OAuth flow with refresh
- [x] **Implement** Deribit OAuth with 120s refresh buffer + scheduled refresh
- [x] **TDD: Write tests** for timestamp validation windows
- [x] **Implement** timestamp validation within windows
- [x] **Implement** API key retrieval from environment variables
- [x] **Integration test** auth signatures with real exchanges

**Review Notes:**
- Comprehensive telemetry instrumentation (start/stop/exception events)
- Superior Kraken nonce implementation using atomic ETS (better than plan's Agent approach)
- OAuth token management with proactive refresh (every 30 seconds)
- Excellent documentation including edge case handling
- Complete typespec coverage for dialyzer
- **Implemented in**: `lib/zen_cex/exchange/auth.ex`, `lib/zen_cex/exchange/auth/deribit_oauth.ex`
- **Tests in**: `test/zen_cex/exchange/auth_test.exs`, `test/zen_cex/exchange/auth_integration_test.exs`

**Plugin Architecture Impact:**
- Will become: Binance.Auth, Kraken.Auth, Deribit.Auth (adapter-specific)
- Core keeps only: Auth behavior definition
- Each adapter owns: Signature algorithms, nonce generation, OAuth flows

### ✅ 1.3 Clock Sync Validation - **COMPLETED** ⭐⭐⭐⭐⭐ (5/5)
**Reference**: Lines 1409-1485 in plan
- [x] **TDD: Write tests** for drift detection logic
- [x] **Implement** Exchange.Health module
- [x] **TDD: Write tests** for multi-exchange consensus
- [x] **Implement** multi-exchange consensus checking
- [x] **TDD: Write tests** for alert thresholds
- [x] **Implement** alerts for >300ms warning, >500ms critical
- [x] **Implement** startup health checks
- [x] **Implement** 30-second drift monitoring schedule
- [x] **Integration test** with real exchange time endpoints

**Review Notes:**
- Perfect implementation with all requirements met
- Excellent architecture with 4 specialized modules (Health, HealthCheck, HealthMonitor, HealthStartup)
- Sophisticated median-based consensus algorithm with outlier detection
- Production-ready with proper supervision, retry logic, and telemetry
- Comprehensive test coverage across 5 test files (all tests passing)
- Correct thresholds implemented (300ms warning, 500ms critical)
- **Implemented in**: `lib/zen_cex/exchange/health.ex`, `health_check.ex`, `health_monitor.ex`, `health_startup.ex`
- **Tests in**: `test/zen_cex/exchange/health/` directory (5 test files)

**Plugin Architecture Impact:**
- Will become: Core.Health (shared across all adapters)
- Core keeps: Consensus logic, monitoring, thresholds
- Adapters provide: Time endpoint URLs only

### ✅ 1.4 Exchange.Cache Module - **COMPLETED** ⭐⭐⭐⭐½ (4.5/5)
**Reference**: Lines 320-334 in plan
- [x] **TDD: Write tests** for TTL expiration logic
- [x] **Implement** ETS-based cache with TTL
- [x] **TDD: Write tests** for automatic cleanup
- [x] **Implement** automatic cleanup every 60 seconds
- [x] **TDD: Write tests** for memory-bounded operations
- [x] **Implement** separate tables for different data types (positions, balances, market_data)
- [x] **Implement** memory-bounded operations with statistics
- [x] **Performance test** concurrent access patterns

**Review Notes:**
- Clean implementation with 4-tuple format only (removed unnecessary backward compatibility)
- Public ETS tables with read concurrency for optimal performance
- GenServer used only for cleanup scheduling (not for cache operations)
- Comprehensive telemetry integration for monitoring
- Memory statistics with `get_stats/0` function
- Automatic TTL cleanup prevents memory leaks
- Minor test stability issues with process lifecycle (test infrastructure, not implementation)
- **Implemented in**: `lib/zen_cex/exchange/cache.ex`
- **Tests in**: `test/zen_cex/exchange/cache_test.exs`

**Plugin Architecture Impact:**
- Will become: Optional adapter feature (adapters can use Core cache or custom)
- Core provides: Basic caching behavior
- Adapters decide: Cache strategies, TTLs, what to cache

### ✅ 1.5 Exchange.RateLimit Module - **COMPLETED** ⭐⭐⭐⭐½ (4.5/5)
**Reference**: Lines 260-322 in plan
- [x] **TDD: Write tests** for atomic counter operations
- [x] **Implement** atomic ETS counters (uses GenServer for cleanup only)
- [x] **TDD: Write tests** for per-exchange limit tracking
- [x] **Implement** Binance spot (1200/min) vs futures (2400/min) tracking
- [x] **Implement** Kraken tier limits (15/sec starter)
- [x] **Implement** Deribit limits (20/sec)
- [x] **TDD: Write tests** for window cleanup
- [x] **Implement** cleanup for old windows (60-second interval)
- [x] **Performance test** high-throughput scenarios

**Review Notes:**
- Excellent atomic ETS implementation with lock-free operations
- Handles 10,000 concurrent requests in 50ms with <1MB memory growth
- Per-exchange limits correctly implemented with table partitioning
- Automatic cleanup prevents memory leaks (runs every 60 seconds)
- Comprehensive test suite: 24 unit tests, 10 integration tests, 6 performance tests
- Minor architectural deviation: uses GenServer for cleanup (better than pure ETS approach)
- Complete documentation and typespec coverage after linter improvements
- **Implemented in**: `lib/zen_cex/exchange/rate_limit.ex`
- **Tests in**: `test/zen_cex/exchange/rate_limit_test.exs`, `rate_limit_integration_test.exs`, `rate_limit_performance_test.exs`

**Plugin Architecture Impact:**
- Will become: Binance.RateLimiter, Kraken.RateLimiter, Deribit.RateLimiter
- Core keeps only: RateLimiter behavior definition
- Each adapter owns: Limits, windows, weight calculations

---

## Pending Implementation (Days 1-5)

### Day 1 Tasks: Foundation + Binance
Focus on building the core foundation and complete Binance adapter as the reference implementation.

### Day 2 Tasks: Kraken + Deribit  
Replicate the pattern with exchange-specific adaptations.

### Day 3 Tasks: WebSocket Discovery
Discover zen_websocket API and implement WebSocket support.

### Day 4 Tasks: Integration  
Complete client facade and circuit breaker implementation.

### Day 5 Tasks: Testing & Documentation
Comprehensive testing and documentation of the plugin architecture.

## Non-Negotiable Day-One Features
**Reference**: Lines 143-149, 1968-1985 in plan

**MUST HAVE:**
- ✅ 10-Second Dedup Buffer (simple :queue ring buffer)
- ✅ Subscription Tracking (remember channels for reconnect)
- ✅ Kraken Nonce Counter (microseconds + counter)
- ✅ ETS Cleanup (periodic memory leak prevention)
- ✅ Clock Sync Check (reject >1000ms drift)
- ✅ Exponential Backoff (with jitter for REST)

**DO NOT BUILD:**
- ❌ WebSocket Authentication (all public streams)
- ❌ Listen Key Management (not needed)
- ❌ OAuth for WebSocket (Deribit public doesn't need)
- ❌ Complex Sequence Tracking (simple dedup sufficient)
- ❌ User Streams (use REST polling)
- ❌ Order Updates via WS (REST for certainty)

## Exchange-Specific Requirements

### Binance (Lines 690-714)
- Timestamp within 5000ms window
- Track X-MBX-USED-WEIGHT-1M header
- Separate spot (1200/min) vs futures (2400/min) limits
- HMAC-SHA256 signatures
- Public WS: `wss://fstream.binance.com/ws`

### Kraken (Lines 715-748)
- Microsecond + counter nonce (not just microseconds!)
- 10-second WebSocket timeout
- Binary frames need zlib/gzip decompression
- Force HTTP/1.1 (HTTP/2 issues)
- Public WS: `wss://ws.kraken.com`

### Deribit (Lines 749-805)
- OAuth2 with 120s refresh buffer (REST only)
- JSON-RPC 2.0 format
- Heartbeat every 30 seconds
- Test vs production endpoints
- Public WS: `wss://www.deribit.com/ws/api/v2`

## Success Criteria
- ✅ Survives production (handles all failure modes)
- ✅ Simple to understand (new dev productive in 30 min)
- ✅ Easy to extend (new exchange in 30 min)
- ✅ Observable (know what's happening without debugging)
- ✅ Bounded resources (no memory leaks)
- ✅ Zero cross-contamination (adapter isolation verified)
- ✅ Behavior compliance (100% contract adherence)
- ✅ Add exchange without touching core (<30 min)

## References
- Main Plan: `docs/CEX/cex-shared-modules-final.md`
- ZenWebsocket Examples: https://github.com/ZenHive/zen_websocket/blob/main/docs/Examples.md
- Binance API: https://binance-docs.github.io/apidocs/spot/en/
- Kraken API: https://docs.kraken.com/rest/
- Deribit API: https://docs.deribit.com/v2/