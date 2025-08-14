# CEX Implementation Tasks

## Progress Summary
**Overall Status**: 5/8 modules completed (62.5%) ✅
**Average Rating**: 4.6/5 ⭐⭐⭐⭐⭐

### Completed Modules
- ✅ 1.1 Exchange.HTTP Module (4.5/5) - REQ integration with exponential backoff
- ✅ 1.2 Exchange.Auth Module (4.5/5) - HMAC/OAuth authentication  
- ✅ 1.3 Clock Sync Validation (5/5) - Health monitoring with consensus
- ✅ 1.4 Exchange.Cache Module (4.5/5) - TTL-based caching with cleanup
- ✅ 1.5 Exchange.RateLimit Module (4.5/5) - Atomic ETS rate limiting

### Pending Modules
- ⏳ 2.1 Exchange.MarketData (WebSocket) - Not started
- ⏳ 2.2 Exchange.Parser - Not started
- ⏳ 2.3 Exchange.Client (Orchestration) - Not started

## Overview
Implementation of 8 shared modules for CEX integration as defined in `cex-shared-modules-final.md` (v10.1).
- **Architecture**: WebSocket for public market data, REST for authenticated operations
- **Timeline**: 4 days
- **Dependencies**: REQ, zen_websocket, Jason, Decimal
- **Methodology**: Test-Driven Development (TDD) - Write tests first, then implement

## Day 1: REST APIs with Authentication

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

### ✅ 1.6 Authenticated Endpoints Integration
- [ ] **Integration test** positions fetching for each exchange
- [ ] **Integration test** balance retrieval
- [ ] **Integration test** rate limit tracking in practice
- [ ] **Integration test** auth signatures with real APIs
- [ ] **Document** any discovered API quirks

## Day 2: ZenWebsocket Discovery & Implementation

### ⚠️ 2.1 MANDATORY Discovery Phase (Morning)
**Reference**: Lines 352-369, 593-607, 2163-2196 in plan
**CRITICAL**: Cannot skip - zen_websocket not in AI training data
- [ ] Add `{:zen_websocket, "~> 0.1.0"}` to mix.exs
- [ ] Read https://github.com/ZenHive/zen_websocket/blob/main/docs/Examples.md
- [ ] **TDD: Write tests** for echo server connection
- [ ] Test with echo.websocket.org
- [ ] Document actual API methods (not assumptions)
- [ ] Test text, binary, ping/pong frame types
- [ ] Verify reconnection behavior
- [ ] Create working examples document

### ✅ 2.2 Exchange.MarketData Base Module (Afternoon)
**Reference**: Lines 335-509 in plan
- [ ] **TDD: Write tests** for GenServer lifecycle (init, terminate)
- [ ] **Implement** GenServer wrapper around ZenWebsocket
- [ ] **TDD: Write tests** for frame type detection logic
- [ ] **Implement** frame type detection (lines 404-419)
- [ ] **TDD: Write tests** for dedup buffer operations
- [ ] **Implement** 10-second dedup buffer with :queue (lines 467-504)
- [ ] **TDD: Write tests** for health check scheduling
- [ ] **Implement** connection to public endpoints only (no auth)
- [ ] **Implement** health checks every 30s (lines 442-459)
- [ ] **Integration test** with mock WebSocket server

### ✅ 2.3 Test Exchange Connections
**Reference**: Lines 461-465, 2098-2139 in plan
- [ ] **Integration test** Binance connection: `wss://fstream.binance.com/ws`
- [ ] **Integration test** subscription to `!markPrice@arr` for funding rates
- [ ] **Integration test** Kraken connection: `wss://ws.kraken.com`
- [ ] **Integration test** binary frame decompression (zlib/gzip)
- [ ] **Integration test** Deribit connection: `wss://www.deribit.com/ws/api/v2`
- [ ] **Document** connection quirks and requirements

## Day 3: Complete WebSocket Implementation

### ✅ 3.1 Kraken WebSocket Implementation
**Reference**: Lines 720-748 in plan
- [ ] **TDD: Write tests** for zlib decompression (0x78,0x9c header)
- [ ] **Implement** binary frame handling with zlib
- [ ] **TDD: Write tests** for gzip decompression (0x1f,0x8b header)
- [ ] **Implement** binary frame handling with gzip
- [ ] **TDD: Write tests** for ping/pong handling
- [ ] **Implement** 10-second ping requirement
- [ ] **TDD: Write tests** for reconnection scenarios
- [ ] **Implement** ticker subscription for funding info
- [ ] **Integration test** reconnection handling with real Kraken WS

### ✅ 3.2 Deribit WebSocket Implementation  
**Reference**: Lines 749-805 in plan
- [ ] **TDD: Write tests** for JSON-RPC 2.0 message formatting
- [ ] **Implement** JSON-RPC 2.0 message format
- [ ] **TDD: Write tests** for heartbeat scheduling
- [ ] **Implement** heartbeat with `public/test` every 30s
- [ ] **TDD: Write tests** for subscription management
- [ ] **Implement** `public/subscribe` method (no auth)
- [ ] **Implement** ticker channel subscriptions
- [ ] **Implement** test vs production endpoint handling
- [ ] **Integration test** with real Deribit WS

### ✅ 3.3 Deduplication & State Management
**Reference**: Lines 467-504, 1342-1407 in plan
- [ ] **TDD: Write tests** for phash2-based deduplication
- [ ] **Implement** phash2-based deduplication
- [ ] **TDD: Write tests** for memory limit enforcement
- [ ] **Implement** message byte size tracking
- [ ] **Implement** 1000 entries or 10MB limit
- [ ] **TDD: Write tests** for TTL cleanup
- [ ] **Implement** 10-second TTL cleanup
- [ ] **TDD: Write tests** for subscription version tracking
- [ ] **Implement** subscription version tracking (lines 1086-1131)
- [ ] **Performance test** dedup under high message volume

### ✅ 3.4 Error Handling & Monitoring
**Reference**: Lines 806-847 in plan
- [ ] **TDD: Write tests** for REST error categorization
- [ ] **Implement** granular REST error handling
- [ ] **TDD: Write tests** for WebSocket reconnection logic
- [ ] **Implement** WebSocket reconnection tracking
- [ ] **TDD: Write tests** for telemetry event emission
- [ ] **Implement** telemetry event logging
- [ ] **TDD: Write tests** for heartbeat timeout detection
- [ ] **Implement** heartbeat timeout monitoring
- [ ] **Implement** message lag tracking
- [ ] **Integration test** error recovery scenarios

## Day 4: Integration & Production Readiness

### ✅ 4.1 Exchange.Parser Module
**Reference**: Lines 517-526 in plan
- [ ] **TDD: Write tests** for position normalization (each exchange format)
- [ ] **Implement** position normalization per exchange
- [ ] **TDD: Write tests** for funding rate extraction
- [ ] **Implement** funding rate extraction
- [ ] **TDD: Write tests** for balance parsing edge cases
- [ ] **Implement** balance parsing
- [ ] **TDD: Write tests** for Decimal conversion precision
- [ ] **Implement** ticker transformation
- [ ] **Implement** Decimal conversion safety
- [ ] **Integration test** with real API response samples

### ✅ 4.2 Exchange.Client Module
**Reference**: Lines 527-556 in plan
- [ ] **TDD: Write tests** for cache-first retrieval logic
- [ ] **Implement** cache-first retrieval
- [ ] **TDD: Write tests** for auth coordination
- [ ] **Implement** auth coordination for requests
- [ ] **TDD: Write tests** for circuit breaker states
- [ ] **Implement** circuit breaker pattern (lines 1250-1339)
- [ ] **TDD: Write tests** for trading function validation
- [ ] **Implement** trading functions (REST only)
- [ ] **Implement** health check coordination
- [ ] **Integration test** full request flow

### ✅ 4.3 Exchange.Supervisor Module
**Reference**: Lines 557-567 in plan
- [ ] **TDD: Write tests** for supervision tree structure
- [ ] **Implement** WebSocket connection supervision
- [ ] **TDD: Write tests** for restart strategies
- [ ] **Implement** restart strategy configuration
- [ ] **TDD: Write tests** for dynamic process addition
- [ ] **Implement** Registry for named processes
- [ ] **Implement** dynamic exchange addition
- [ ] **Implement** cleanup process supervision
- [ ] **Integration test** failure recovery scenarios

### ✅ 4.4 Telemetry & Monitoring
**Reference**: Lines 848-902 in plan
- [ ] **TDD: Write tests** for telemetry event emission
- [ ] **Implement** REQ telemetry handler attachment
- [ ] **TDD: Write tests** for latency calculations
- [ ] **Implement** P95/P99 latency tracking
- [ ] **TDD: Write tests** for metric aggregation
- [ ] **Implement** WebSocket message lag monitoring
- [ ] **Implement** cache efficiency tracking
- [ ] **Implement** circuit breaker trip monitoring
- [ ] **Performance test** telemetry overhead

## Critical Production Patterns

### ✅ 5.1 Request Coalescing
**Reference**: Lines 929-1082 in plan
- [ ] **TDD: Write tests** for duplicate request detection
- [ ] **Implement** duplicate concurrent request prevention
- [ ] **TDD: Write tests** for result sharing mechanism
- [ ] **Implement** result sharing among waiters
- [ ] **TDD: Write tests** for TTL expiration
- [ ] **Implement** 30-second TTL with cleanup
- [ ] **Implement** coalescing effectiveness tracking
- [ ] **Performance test** under concurrent load

### ✅ 5.2 Adaptive Rate Limiting
**Reference**: Lines 1135-1190 in plan
- [ ] **TDD: Write tests** for header-based adjustment
- [ ] **Implement** response header-based adjustment
- [ ] **TDD: Write tests** for backpressure thresholds
- [ ] **Implement** backpressure at 60% usage
- [ ] **Implement** critical backpressure at 80%
- [ ] **TDD: Write tests** for backpressure removal
- [ ] **Implement** backpressure removal at <20%
- [ ] **Performance test** adaptive behavior

### ✅ 5.3 Sequence Tracking (Optional)
**Reference**: Lines 1193-1245 in plan
- [ ] **TDD: Write tests** for sequence gap detection
- [ ] **Implement** sequence number tracking
- [ ] **Implement** missed message detection
- [ ] **TDD: Write tests** for recovery request logic
- [ ] **Implement** recovery request mechanism
- [ ] **Implement** gap statistics logging
- [ ] **Integration test** with simulated gaps

### ✅ 5.4 Connection Warmup
**Reference**: Lines 1476-1483 in plan
- [ ] **TDD: Write tests** for staggered connection timing
- [ ] **Implement** staggered initial connections
- [ ] **TDD: Write tests** for jitter calculation
- [ ] **Implement** 100-150ms random jitter
- [ ] **Implement** timing pattern prevention
- [ ] **Integration test** connection timing distribution

## Operational Excellence

### ✅ 6.1 Graceful Degradation
**Reference**: Lines 1486-1593 in plan
- [ ] **TDD: Write tests** for fallback logic
- [ ] **Implement** fallback exchanges per data type
- [ ] **TDD: Write tests** for cache age validation
- [ ] **Implement** max cache age per exchange
- [ ] **TDD: Write tests** for criticality determination
- [ ] **Implement** critical vs non-critical exchange marking
- [ ] **Implement** critical failure alerting
- [ ] **Integration test** degradation scenarios

### ✅ 6.2 Metrics Dashboard
**Reference**: Lines 1595-1718 in plan
- [ ] **TDD: Write tests** for metric calculations
- [ ] **Implement** circuit breaker states visualization
- [ ] **Implement** rate limit usage gauges
- [ ] **TDD: Write tests** for LiveView data updates
- [ ] **Implement** WebSocket health tracking
- [ ] **Implement** system metrics (memory, ETS, processes)
- [ ] **Implement** LiveView integration
- [ ] **Integration test** dashboard updates

### ✅ 6.3 Alerting Configuration
**Reference**: Lines 1720-1956 in plan
- [ ] **TDD: Write tests** for threshold detection
- [ ] **Implement** clock drift thresholds (300ms warn, 500ms critical)
- [ ] **Implement** circuit breaker trip limits (3/hour critical)
- [ ] **TDD: Write tests** for alert suppression logic
- [ ] **Implement** memory growth tracking (50MB/hour critical)
- [ ] **Implement** WebSocket reconnect limits (10/hour critical)
- [ ] **TDD: Write tests** for escalation paths
- [ ] **Implement** escalation and suppression logic
- [ ] **Integration test** alert triggering

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

## Success Criteria (Lines 917-925)
- ✅ Survives production (handles all failure modes)
- ✅ Simple to understand (new dev productive in 30 min)
- ✅ Easy to extend (new exchange in 30 min)
- ✅ Observable (know what's happening without debugging)
- ✅ Bounded resources (no memory leaks)

## References
- Main Plan: `docs/CEX/cex-shared-modules-final.md`
- ZenWebsocket Examples: https://github.com/ZenHive/zen_websocket/blob/main/docs/Examples.md
- Binance API: https://binance-docs.github.io/apidocs/spot/en/
- Kraken API: https://docs.kraken.com/rest/
- Deribit API: https://docs.deribit.com/v2/