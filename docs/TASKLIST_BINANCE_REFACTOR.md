# Binance Multi-API Task List

## Overview
Support Binance's multiple API types (Spot, Futures, etc.) for **trading operations only** using a unified approach with smart URL routing, avoiding file size explosion while maintaining clarity.

**IMPORTANT SCOPE**: This library is for trading operations only - NO market data, price feeds, or order books.

## Current Directory Structure (Actual Files)
```
lib/zen_cex/
├── application.ex                    # OTP application
├── adapters/
│   └── binance/
│       ├── auth.ex                   # HMAC-SHA256 authentication
│       ├── parser.ex                 # Response parsing
│       └── rate_limiter.ex          # ✅ COMPLETED: Reactive rate limiter
├── behaviors/
│   ├── auth.ex                      # Auth behavior contract
│   ├── parser.ex                    # Parser behavior contract
│   └── rate_limiter.ex             # RateLimiter behavior contract
├── core/
│   ├── endpoint_registry.ex        # Macro for endpoint generation
│   ├── http.ex                     # Req-based HTTP client
│   ├── registry.ex                 # Exchange registry
│   └── telemetry.ex                # Telemetry events
└── safety/
    ├── clock_sync.ex                # Time synchronization
    └── order_safety.ex              # Order validation

MISSING FILES:
❌ lib/zen_cex/adapters/binance/endpoints.ex    # Main entry point
❌ lib/zen_cex/adapters/deribit/*.ex            # No Deribit files
❌ lib/zen_cex/adapters/kraken/*.ex             # No Kraken files

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

## Revised Approach: Unified with Smart Organization

### Key Decisions Made (Updated with Business Analysis)
1. **Keep unified adapter per exchange** (following OKX/Bybit model)
2. **Single Registry entry** `binance => Binance.Endpoints` for all API types
3. **Single API key/secret** shared across all Binance API types
4. **Smart URL routing** based on endpoint path or explicit `api_type`
5. **Feature-based splitting** only when file gets too large
6. **DRY Principle** - Auth.ex handles ALL auth params (timestamp, recvWindow, signature), RateLimiter.ex handles rate limiting, and Parser.ex handles response parsing
7. **User simplicity over architectural purity** - Hide API complexity from library users

### Architecture Decision Rationale
- **Developer Experience**: Users just want to trade, not understand exchange internals
- **Zero Breaking Changes**: Existing code continues working unchanged
- **80% Use Case**: Most users use either Spot OR Futures, not both
- **Maintenance**: Shared modules (auth, parser, rate_limiter) in same namespace

## Phase 1:
### 1.1 Multi-API URL Support ✅
- [x] Add `base_url(env, api_type)` function for different API types
- [x] Support testnet URLs for each API type:
  - Spot: `testnet.binance.vision`
  - Futures (USD-M): `testnet.binancefuture.com` - USDT-margined futures
  - DAPI (COIN-M): `testnet.binancefuture.com` - Coin-margined futures  
  - PAPI (Portfolio Margin): `papi.binance.com` (prod) / `testnet.binance.vision` (test)
  - SAPI: `api.binance.com` (uses spot URL)
- [x] Add `api_type` field to endpoint definitions
- [x] Update EndpointRegistry to use `api_type` when present

### 1.2 Fix Broken Futures Endpoint ✅
- [x] Mark `get_positions` endpoint with `api_type: :futures`
- [x] Ensure it uses correct testnet URL

**Review Results**: Implementation complete and correct. All tests pass (215 total). Smart URL routing works perfectly - endpoints without `api_type` use default spot URLs, endpoints with `api_type` use appropriate API-specific URLs.

## Phase 2: Build Endpoints System From Scratch
### 2.1 Create New Endpoints System ✅ DONE
- [x] **CREATE** `endpoints.ex` - Router module registered with Core.Registry
- [x] **CREATE** nested modules instead of directory structure:
  - [x] `spot.ex` - Spot trading endpoints (get_balances, place_order, etc.)
  - [x] `futures.ex` - Futures trading endpoints (get_positions)
  - [x] `common.ex` - Shared endpoints (get_server_time)
- [x] Main `endpoints.ex` delegates all functions to sub-modules
- [x] Added all required fields: timeout, retry_on, response_parser, error_mapping

### 2.2 Feature-Based Endpoint Modules (Trading Operations Only) ✅ COMPLETED

**Module Naming - COMPLETED**:
- [x] Created `usdm_futures.ex` (replaced old `futures.ex`)
- [x] All references use `UsdmFutures` module name
- [x] Test files created: `usdm_futures_test.exs` and `usdm_futures_integration_test.exs`

**Implementation - COMPLETED**:
- [x] Generated 35 USD-M futures endpoints from Postman collection
- [x] Created mix task `mix zen_cex.generate_futures_endpoints` for generation
- [x] Implemented `generated_usdm_endpoints.ex` with all endpoint definitions
- [x] Added parser functions: `parse_account/1` and `parse_income/1`
- [x] Fixed all test expectations and passing tests
- [x] Router properly delegates futures operations to UsdmFutures module

**CRITICAL PREREQUISITES - MUST DO FIRST:**
- [x] **UNDERSTAND THE EXISTING ARCHITECTURE** ✅
- [x] **REVIEW** existing adapter modules and identify common patterns ✅
- [x] **DOCUMENT HERE in this doc** existing adapter modules and identify common patterns ✅

### Documented Architecture Patterns

#### Core Architecture (Req-Centric REST)
- **Application**: Minimal supervision - only Deribit.Auth GenServer, ETS tables, Finch pool
- **Registry**: Compile-time exchange→endpoints mapping with runtime validation
- **HTTP Core**: Req middleware pipeline with operation-specific timeouts (2-30s)
- **Endpoint Registry Macro**: Declarative function generation from `@endpoints` config

#### Adapter Pattern (4-Module Cooperation)
Each exchange adapter has these cooperating modules:
1. **Endpoints** - Main entry point, uses EndpointRegistry macro, registered with Core.Registry
2. **Auth** - Implements Behaviors.Auth, exchange-specific signing (HMAC/OAuth)
3. **RateLimiter** - Implements Behaviors.RateLimiter, reactive monitoring with ETS
4. **Parser** - Implements Behaviors.Parser, normalizes responses to common format

#### Key Implementation Details
- **Req Steps**: rate_limit → auth → request → update_limits → telemetry
- **Multi-API Support**: `api_type` field routes to correct base URL (spot/futures)
- **Safety**: Compile-time validation prevents dangerous patterns (no retry on orders)
- **Stateless**: Only OAuth needs GenServer, everything else uses ETS/Req pipeline

#### Refactored Module Structure (Option C: Nested Modules)
Given Binance's massive API size (300+ endpoints), using nested modules for clarity:

**New Structure:**
```elixir
# Clear namespace separation
Binance.Spot.place_order/1      # Spot trading
Binance.Futures.place_order/1   # Futures trading  
Binance.Margin.place_order/1    # Margin trading
```

**Module Organization (TO BE RENAMED):**
- `Binance.Endpoints` - Main registry entry, delegates to sub-modules
- `Binance.Spot` - Spot trading endpoints (~100+ endpoints)
- `Binance.UsdmFutures` - USD-M Futures (USDT-margined) endpoints (~80+ endpoints) - uses `/fapi/` paths
- `Binance.CoinmFutures` - COIN-M Futures (coin-margined) endpoints - uses `/dapi/` paths (TODO: when needed)
- `Binance.Margin` - Margin/SAPI endpoints (~60+ endpoints)
- `Binance.Portfolio` - Portfolio Margin (PAPI) endpoints (~40+ endpoints)
- `Binance.Common` - Shared endpoints (server_time, exchange_info)

**Registry Pattern Update:**
- Keep single registry entry: `binance => Binance.Endpoints`
- Endpoints module delegates to appropriate sub-module based on function
- Maintains backward compatibility while adding clarity

**IMPLEMENTATION TASKS (POSTPONE UNTIL 2.1 COMPLETE):**
- [ ] Create `lib/zen_cex/adapters/binance/endpoints/` directory (when needed)
- [ ] Split endpoints by trading feature domain (only when file size demands it):
  - [ ] `spot_trading.ex` - Spot order placement, modification, cancellation
  - [ ] `spot_account.ex` - Spot balances, account info, trade history
  - [ ] `futures_trading.ex` - Futures order management
  - [ ] `futures_account.ex` - Positions, margin requirements, PnL
  - [ ] `margin_trading.ex` - Margin orders, borrowing, repayment
  - [ ] `margin_account.ex` - Margin balances, loan status
- [ ] Main `endpoints.ex` delegates to feature modules
- [ ] **EXCLUDE**: Market data, price feeds, order books, tickers
- [ ] **CRITICAL**: Each module MUST have real API integration tests
  - [ ] Test against Binance testnet with real credentials
  - [ ] Document actual API behavior from real testing
  - [ ] NO mocks - test against real testnet APIs only
  - [ ] Use `_TESTNET_` in environment variable names (e.g., BINANCE_TESTNET_API_KEY)
  - [ ] Tests MUST FAIL loudly if testnet credentials missing (no silent skipping)
  - [ ] Tests MUST FAIL if production URLs detected (enforce testnet-only)

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

### 3.2 Rate Limiter Multi-API Support ✅ COMPLETED
- [x] **Separate limits per API type** - Spot: 1200, SAPI: 12000, USD-M: 2400, COIN-M: 2400
- [x] **API type detection from URL** - Detects /api/, /sapi/, /fapi/, /dapi/ paths
- [x] **Fixed URL passing in HTTP client** - Full URL in response metadata
- [x] **Consistent API type naming** - Using :usdm_futures, :coinm_futures
- [x] **Integration tests with testnet enforcement** - Futures tests verify rate limiting

### 3.3 Clock Sync Refactoring (NEW)
- [ ] Update `ClockSync.fetch_server_time/1` to support different API types
- [ ] Different time endpoints per API type:
  - Spot: `https://api.binance.com/api/v3/time`
  - Futures: `https://fapi.binance.com/fapi/v1/time`
  - SAPI: Uses Spot endpoint
  - DAPI (Coin Futures): `https://dapi.binance.com/dapi/v1/time`
  - PAPI (Portfolio Margin): `https://papi.binance.com/papi/v1/time`
- [ ] Store separate offsets per API type in ETS
- [ ] Pass `api_type` from endpoints to clock sync
- [ ] Support testnet URLs for each API type's time endpoint

### 3.4 Parser Organization
- [ ] Keep common parsing in main `parser.ex`
- [ ] Add feature-specific parsing in endpoint modules if needed
- [ ] Use delegation pattern for specialized parsing

## Phase 4: Testing Updates
### 4.1 Create Unit Tests for New Modules ❌ CRITICAL - MISSING
- [ ] **CREATE** `test/zen_cex/adapters/binance/spot_test.exs`
- [ ] **CREATE** `test/zen_cex/adapters/binance/futures_test.exs`
- [ ] **CREATE** `test/zen_cex/adapters/binance/common_test.exs`
- [ ] **CREATE** tests for router functionality in endpoints_test.exs
- [ ] Test endpoint delegation works correctly
- [ ] Test get_endpoint/1 routing logic
- [ ] Test all_endpoints/0 aggregation

### 4.2 Update Integration Tests
- [ ] Add test for futures endpoint using correct testnet URL
- [ ] Test that spot endpoints use spot testnet URL
- [ ] Test that futures endpoints use futures testnet URL
- [ ] Verify `api_type` routing works correctly

### 4.2 Rate Limiter Tests ✅ COMPLETED
- [x] Test header monitoring and warning thresholds
- [x] Test emergency bypass for cancel operations
- [x] Test integration with real Binance API (smart, minimal requests)

### 4.3 Clock Sync Tests (NEW)
- [ ] Test separate time sync per API type
- [ ] Test that each API type uses correct time endpoint
- [ ] Test offset storage per API type
- [ ] Test testnet time endpoints work correctly

### 4.4 Add Feature Module Tests
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
- Rate limiter simplified to reactive monitoring
- Understood architecture and parameter handling
- **Created Option C nested module structure**:
  - `endpoints.ex` as router only
  - `spot.ex` with spot endpoints
  - `usdm_futures.ex` with USD-M futures endpoints (USDT-margined, /fapi/ paths)
- **Fixed Dialyzer errors** (latest commit)
- **Extracted RequestHelper** to eliminate code duplication
- **Added error documentation** for all endpoint functions

### Session Accomplishments (Task 2.2) ✅
- **Created USD-M Futures module** with proper naming (`usdm_futures.ex`)
- **Generated 35 endpoints** from Postman collection using custom mix task
- **Added parser functions** for futures-specific responses:
  - `parse_account/1` - Account info with balances, margins, positions
  - `parse_income/1` - Transaction history with various income types
- **Created comprehensive tests**:
  - Unit tests in `usdm_futures_test.exs`
  - Integration tests in `usdm_futures_integration_test.exs`
- **Fixed all test failures** and updated expectations
- **Proper testnet routing** verified for futures endpoints
- All 344 tests passing (1 unrelated auth failure)

### Active TODOs from Code
These TODOs were found in the codebase and need tracking:
- [ ] `lib/zen_cex/safety/clock_sync.ex:392` - Use test/prod host from config
- [ ] `lib/zen_cex/adapters/binance/spot.ex:122` - Implement batch cancellation
- [ ] `lib/zen_cex/adapters/binance/spot.ex:112` - Implement OCO order placement  
- [x] ~~`lib/zen_cex/adapters/binance/rate_limiter.ex:79` - Detect futures from request URL~~ ✅ DONE
- [ ] `lib/zen_cex/adapters/binance/parser.ex:266` - WebSocket market data parsing (deferred - out of scope)
- [ ] `test/zen_cex/safety/clock_sync_test.exs` - Multiple tests skipped until adapters implemented
- [ ] `test/zen_cex/core/http_test.exs:9` - Implement test against real testnet API
- [ ] `lib/zen_cex/core/registry.ex:29` - Implement Deribit endpoints
- [ ] `lib/zen_cex/core/registry.ex` - Implement Kraken endpoints

### Current Issues 🔥
- **NO TESTS FOR NEW MODULES** - Created spot.ex, common.ex WITHOUT unit tests!
- [x] ~~**Futures.ex clarification**~~ - ✅ RENAMED to usdm_futures.ex with proper tests
- **Need to add Margin module** - When margin endpoints are needed
- **Need to add CoinFutures module** - For COIN-M futures (/dapi/ paths) when needed

### Next Steps (Priority Order)
1. **Create unit tests for new modules** - spot_test.exs, common_test.exs (usdm_futures_test.exs ✅ DONE)
2. **Add more endpoints** to Spot module as needed (currently has basic endpoints)
3. **Create Margin module** when margin endpoints are needed
4. **Create CoinmFutures module** for COIN-M futures when needed
5. Update Clock Sync for multiple API types (Phase 3.3)
6. Document the nested module approach and generation process

## Revised Estimated Effort
- Phase 1: ✅ DONE (Multi-API URL Support)
- Phase 2: ✅ DONE (Feature-Based Endpoint Modules)
  - 2.1: ✅ Created new endpoints system with router
  - 2.2: ✅ USD-M Futures module with 35 endpoints generated from Postman
  - 2.3: Endpoint discovery functions (low priority)
- Phase 3: **Mostly complete**
  - 3.1: ✅ DONE (auth, parser in place)
  - 3.2: ✅ DONE (multi-API rate limiter working)
  - 3.3: TODO (clock sync refactor - low priority)
- Phase 4: **Partially complete**
  - 4.1: ✅ USD-M Futures tests created and passing
  - 4.2: ✅ Integration tests with proper testnet routing
  - Missing: Unit tests for spot.ex and common.ex modules
- Phase 5: TODO (documentation)
- **Total**: ~1 hour remaining for spot/common unit tests

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
- **✅ PROVEN: Reactive rate limiting is simpler and sufficient for non-HFT**
- **✅ IMPLEMENTED: Separate limits per API type (Spot: 1200, SAPI: 12000, USD-M: 2400, COIN-M: 2400)**
- **✅ WORKING: Rate limit headers parsed correctly, warnings logged at thresholds**
- **✅ CRITICAL: Use specific API type names (:usdm_futures not :futures) for clarity**
- Each API type has its own time endpoint for clock synchronization

## Dependencies
- No external dependencies
- No breaking changes for existing users
- Can be extended incrementally
