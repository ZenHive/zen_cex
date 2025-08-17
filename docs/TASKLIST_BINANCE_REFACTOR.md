# Binance Multi-API Refactoring Task List

## Overview
Support Binance's multiple API types (Spot, Futures, etc.) for **trading operations only** using a unified approach with smart URL routing, avoiding file size explosion while maintaining clarity.

**IMPORTANT SCOPE**: This library is for trading operations only - NO market data, price feeds, or order books.

## Current Directory Structure
```
lib/zen_cex/adapters/binance/
├── auth.ex                    # HMAC-SHA256 authentication (shared)
├── endpoints.ex               # Main endpoint definitions (unified)
├── parser.ex                  # Response parsing (shared)
├── rate_limiter.ex           # Rate limiting (shared across all APIs)
└── rate_limiter_cleanup.ex   # ETS table cleanup

test/zen_cex/adapters/binance/
├── environment_consistency_test.exs  # Tests for env variable handling
└── binance_integration_test.exs     # Integration tests (needs splitting)
```

## Target Directory Structure (Incremental)
```
lib/zen_cex/adapters/binance/
├── auth.ex                    # HMAC-SHA256 authentication (shared)
├── endpoints.ex               # Core endpoints + delegation to features
├── parser.ex                  # Common parsing functions (shared)
├── rate_limiter.ex           # Rate limiting (shared across all APIs)
├── rate_limiter_cleanup.ex   # ETS table cleanup
└── endpoints/                 # Trading-focused endpoint modules (as needed)
    ├── spot_trading.ex        # Spot order management (~30 endpoints)
    ├── spot_account.ex        # Balances, account info (~20 endpoints)
    ├── futures_trading.ex     # Futures orders (~25 endpoints)
    ├── futures_account.ex     # Positions, margin (~15 endpoints)
    ├── margin_trading.ex      # Margin orders & positions (~20 endpoints)
    └── margin_account.ex      # Margin balances & loans (~15 endpoints)

test/zen_cex/adapters/binance/
├── environment_consistency_test.exs  # Tests for env variable handling
├── endpoints/                        # Feature-specific tests
│   ├── spot_trading_test.exs
│   ├── futures_trading_test.exs
│   └── ...
└── integration/                      # Integration tests by API type
    ├── spot_integration_test.exs
    ├── futures_integration_test.exs
    └── margin_integration_test.exs
```

## Current Problems
- [x] ~~All endpoints mixed in single module (`binance/endpoints.ex`)~~ **Decision: Keep unified**
- [x] ~~Futures endpoint (`/fapi/v2/positionRisk`) using wrong base URL in testnet~~ **Partially fixed**
- [ ] No clear separation between API types in endpoint definitions
- [x] ~~Environment variable `BINANCE_TESTNET` doesn't handle different testnet URLs~~ **Fixed with `base_url(env, api_type)`**
- [ ] Endpoint file will become too large as we add more endpoints (300+ potential endpoints)
- [ ] **CRITICAL: Rate limiter shares limits across all API types (should be separate)**

## Revised Approach: Unified with Smart Organization

### Key Decisions Made
1. **Keep unified adapter per exchange** (following OKX/Bybit model)
2. **Single API key/secret** shared across all Binance API types
3. **Smart URL routing** based on endpoint path or explicit `api_type`
4. **Feature-based splitting** only when file gets too large

## Phase 1: Fix Current Issues ✅ COMPLETED (5/5 ⭐)
### 1.1 Multi-API URL Support ✅
- [x] Add `base_url(env, api_type)` function for different API types
- [x] Support testnet URLs for each API type:
  - Spot: `testnet.binance.vision`
  - Futures: `testnet.binancefuture.com`
- [x] Add `api_type` field to endpoint definitions
- [x] Update EndpointRegistry to use `api_type` when present

### 1.2 Fix Broken Futures Endpoint ✅
- [x] Mark `get_positions` endpoint with `api_type: :futures`
- [x] Ensure it uses correct testnet URL

**Review Results**: Implementation complete and correct. All tests pass (215 total). Smart URL routing works perfectly - endpoints without `api_type` use default spot URLs, endpoints with `api_type` use appropriate API-specific URLs.

## Phase 2: Organize for Scale ✅ COMPLETED
### 2.1 Core Endpoints Module ✅
- [x] Keep current `endpoints.ex` with 20-30 most-used endpoints (10 core endpoints)
- [x] Document which endpoints are "core" vs "extended" 
- [x] Ensure core endpoints cover 80% of typical use cases
- [x] Add explicit `api_type` field to all endpoints for clarity

**Implementation Results**: 
- All endpoints now have explicit `api_type` field (:spot or :futures)
- Module documentation clearly identifies core vs extended endpoints
- Core set covers: account management, order operations, position tracking, system utilities
- Hand-written complex operations also specify their API type
- All tests pass (215 total)

### 2.2 Feature-Based Endpoint Modules (Trading Operations Only)
- [ ] Create `lib/zen_cex/adapters/binance/endpoints/` directory
- [ ] Split endpoints by trading feature domain:
  - [ ] `spot_trading.ex` - Spot order placement, modification, cancellation
  - [ ] `spot_account.ex` - Spot balances, account info, trade history
  - [ ] `futures_trading.ex` - Futures order management
  - [ ] `futures_account.ex` - Positions, margin requirements, PnL
  - [ ] `margin_trading.ex` - Margin orders, borrowing, repayment
  - [ ] `margin_account.ex` - Margin balances, loan status
- [ ] Main `endpoints.ex` delegates to feature modules
- [ ] **EXCLUDE**: Market data, price feeds, order books, tickers

### 2.3 Endpoint Discovery
- [ ] Add `list_available_endpoints/0` function
- [ ] Add `get_endpoint_info/1` for runtime discovery
- [ ] Document endpoint organization strategy

## Phase 3: Shared Infrastructure
### 3.1 Keep Shared Code in Place
- [ ] Keep `auth.ex` at current location (shared across all API types)
- [ ] ~~Keep `rate_limiter.ex` unified (tracks limits across all APIs)~~ **NEEDS REFACTOR**
- [ ] Keep `parser.ex` with common parsing functions
- [ ] Document that these are shared across all API types

### 3.2 Rate Limiter Refactoring (CRITICAL - NEW)
- [ ] Separate ETS tables per API type (spot, sapi, futures, coin_futures)
- [ ] Different rate limits per API type:
  - Spot (/api): 12,000 IP / 6,000 UID per minute
  - SAPI (/sapi): 12,000 IP / 180,000 UID per minute  
  - Futures (/fapi): 2,400 per minute (much lower!)
  - Coin Futures (/dapi): 2,400 per minute
- [ ] Parse different headers per API type:
  - Spot: `X-MBX-USED-WEIGHT-1M`
  - SAPI: `X-SAPI-USED-IP-WEIGHT-1M`, `X-SAPI-USED-UID-WEIGHT-1M`
  - Futures: Similar to spot but independent
- [ ] Pass `api_type` from endpoints to rate limiter
- [ ] Update `check_and_increment` to use correct table based on endpoint path

### 3.3 Parser Organization
- [ ] Keep common parsing in main `parser.ex`
- [ ] Add feature-specific parsing in endpoint modules if needed
- [ ] Use delegation pattern for specialized parsing

## Phase 4: Testing Updates
### 4.1 Update Integration Tests
- [ ] Add test for futures endpoint using correct testnet URL
- [ ] Test that spot endpoints use spot testnet URL
- [ ] Test that futures endpoints use futures testnet URL
- [ ] Verify `api_type` routing works correctly

### 4.2 Rate Limiter Tests (CRITICAL - NEW)
- [ ] Test separate rate limit tracking per API type
- [ ] Test that spot requests don't affect futures limits
- [ ] Test different header parsing per API type
- [ ] Test enforcement of different limits (futures has much lower limit)

### 4.3 Add Feature Module Tests
- [ ] Test endpoint delegation pattern
- [ ] Test that feature modules integrate with registry
- [ ] Test endpoint discovery functions

## Phase 5: Documentation
### 5.1 Update Module Documentation
- [ ] Document unified approach with smart routing
- [ ] Explain `api_type` field usage
- [ ] Document how to add new endpoints
- [ ] Create endpoint organization guide

### 5.2 Update CLAUDE.md
- [ ] Document unified Binance adapter approach
- [ ] Add examples for different API types
- [ ] Document shared auth/rate limiting

### 5.3 API Reference
- [ ] Create `binance/ENDPOINTS.md` with full endpoint list
- [ ] Group by API type and feature
- [ ] Include testnet URLs for each API type
- [ ] Document which endpoints are "core" vs "extended"

## Phase 6: Future Considerations
### 6.1 OpenAPI Generation (Optional)
- [ ] Research Binance OpenAPI specs
- [ ] Create mix task for endpoint generation
- [ ] Generate extended endpoint modules from specs
- [ ] Keep hand-written core endpoints

### 6.2 Lazy Loading (Optional)
- [ ] Implement on-demand endpoint loading
- [ ] Cache loaded endpoints
- [ ] Measure performance impact

## Success Criteria
- [x] All tests pass
- [x] Spot trading works with correct testnet URL  
- [x] Futures endpoint can use different testnet URL (via `api_type`)
- [x] Shared auth/rate limiting works across API types
- [ ] File size manageable with trading-focused feature splitting
- [x] No breaking changes for existing users
- [ ] Clear documentation for adding new trading endpoints
- [ ] Library remains focused on trading operations only (no market data)

## Implementation Status
### Completed ✅
- Multi-API URL routing with `base_url(env, api_type)`
- Support for different testnet URLs per API type
- `api_type` field in endpoint definitions
- EndpointRegistry support for `api_type`
- Backward compatibility maintained

### Next Steps (Priority Order)
1. **CRITICAL: Fix rate limiter** to handle separate limits per API type (Phase 3.2)
2. Test the futures endpoint with real API calls
3. Add rate limiter tests for API type separation (Phase 4.2)
4. Implement feature-based endpoint modules when adding more endpoints
5. Document the pattern for other exchanges (Kraken, OKX, etc.)

## Revised Estimated Effort
- Phase 1: ✅ DONE (1 hour)
- Phase 2: 2-3 hours (when adding more endpoints)
- Phase 3: **3-4 hours** (rate limiter refactor is complex)
  - 3.1: ✅ DONE (auth, parser already in place)
  - 3.2: 3-4 hours (rate limiter refactor - CRITICAL)
  - 3.3: Already in place
- Phase 4: **2-3 hours** (additional rate limiter tests)
  - 4.1: 1 hour
  - 4.2: 1-2 hours (rate limiter tests)
  - 4.3: 1 hour
- Phase 5: 1-2 hours
- Phase 6: Optional/as needed
- **Total**: ~8-12 hours remaining (increased due to rate limiter complexity)

## Scope Clarification

### What This Library DOES (Trading Operations)
- ✅ Order management (place, modify, cancel)
- ✅ Position tracking (balances, margins, PnL)
- ✅ Account operations (withdrawals, deposits, transfers)
- ✅ Risk management (liquidation prices, margin requirements)
- ✅ Trade history and execution reports

### What This Library DOES NOT Do
- ❌ Market data (price feeds, tickers)
- ❌ Order book depth
- ❌ Trade streams or tick data
- ❌ Candlestick/OHLC data
- ❌ Real-time price updates
- ❌ Market making or HFT operations

**Rationale**: This is a trading operations library focused on order execution and account management, not a market data library. For market data needs, use a dedicated market data service or WebSocket library.

## Key Learnings
- Binance uses same API key across all API types (simplifies auth)
- Unified adapter per exchange is industry trend (OKX, Bybit)
- Smart URL routing solves the multi-API problem elegantly
- Feature-based splitting can be done incrementally as needed
- **CRITICAL: Each API type has completely separate rate limits that must be tracked independently**
- Futures API has much stricter limits (2,400/min) vs Spot (12,000/min)
- Different API types use different rate limit headers (X-MBX vs X-SAPI)

## Dependencies
- No external dependencies
- No breaking changes for existing users
- Can be extended incrementally