# Code TODOs

Actionable tasks extracted from codebase TODOs, organized for AI-assisted implementation.

**Last Verified:** 2025-09-29 - All TODOs confirmed present in codebase

## Recently Completed ✅

### ~~1. Bybit Rate Limiter Headers~~ ✅ COMPLETED
**File:** `lib/zen_cex/adapters/bybit/rate_limiter.ex:181`
**Status:** Implemented support for `X-Bapi-Limit`, `X-Bapi-Limit-Status`, and `X-Bapi-Limit-Reset-Timestamp` headers.

### ~~2. Order Safety - Replace Stub Implementations~~ ✅ COMPLETED
**Files:** `lib/zen_cex/safety/order_safety.ex:843-856`
**Status:** Replaced stubs with real API calls using Binance.MarketData and Bybit.MarketData for symbol info, Binance.Spot and Bybit.Unified for balances.

### ~~3. Order Safety - Market Price Estimation~~ ✅ COMPLETED
**File:** `lib/zen_cex/safety/order_safety.ex:722`
**Status:** Implemented `fetch_current_price/2` using ticker APIs from both exchanges.

### ~~4. Order Safety - Dynamic Min Order Values~~ ✅ COMPLETED
**File:** `lib/zen_cex/safety/order_safety.ex:760`
**Status:** Modified `get_min_notional/2` to extract minimum values from exchange symbol filters.

### ~~5. Portfolio Margin Position Consolidation~~ ✅ COMPLETED
**File:** `lib/zen_cex/adapters/binance/portfolio_margin.ex:305`
**Status:** Fully implemented with `aggregate_by_underlying/2` and `aggregate_positions/1` functions. Properly combines USDM and COINM futures positions with total exposure calculation.

### ~~6. Binance Strategies - Balance Percentage Validation~~ ✅ COMPLETED
**Files:** `lib/zen_cex/adapters/binance/strategies.ex:898-920`
**Status:** Implemented balance percentage checks in `validate_position_limits/4` using `extract_account_balance/1` helper.

### ~~7. Binance Strategies - Unified Account View~~ ✅ COMPLETED
**Files:** `lib/zen_cex/adapters/binance/strategies.ex:550-591`
**Status:** Implemented `get_unified_usdm_positions/0` and `get_unified_coinm_positions/0` with proper account mode checking.

### ~~8. Clock Sync - Dynamic Host Configuration~~ ✅ COMPLETED
**File:** `lib/zen_cex/safety/clock_sync.ex:435-447`
**Status:** Implemented `get_deribit_base_url/0` with dynamic environment-based configuration.

### ~~9. WebSocket Implementation~~ ✅ COMPLETED
**Files:** `lib/zen_cex/adapters/binance/websocket.ex`, `lib/zen_cex/adapters/bybit/websocket.ex`
**Status:** Fully implemented using zen_websocket library (v0.1.3) with Gun transport. Both Binance and Bybit adapters are operational with ETS caching.

## Remaining Tasks

## 1. Market Analysis - Additional Exchange Support
**Files:** `lib/zen_cex/analysis/market.ex:470,532`
**Task:** Add funding rate fetching for Kraken, Deribit, and OKX perpetuals. Create new adapter modules following existing Binance/Bybit patterns.
**Current TODOs in code:**
- Line 470: `# TODO: Add support for additional exchanges - Kraken (futures), Deribit (perpetuals), OKX (perpetuals)`
- Line 532: `# TODO: Add historical funding rate support for additional exchanges - Kraken, Deribit, OKX`

## 2. Core Registry - New Exchange Adapters
**Files:** `lib/zen_cex/core/registry.ex:35-36`
**Task:** Implement Kraken and Deribit adapters with basic spot/futures functionality. Start with market data endpoints.
**Current TODOs in code:**
- Line 35: `# kraken: ZenCex.Adapters.Kraken.Endpoints,  # TODO: Implement Kraken`
- Line 36: `# deribit: ZenCex.Adapters.Deribit.Endpoints  # TODO: Implement Deribit`

## 3. Integration Case - Testnet Enforcement
**Files:** `test/support/integration_case.ex:215,224`
**Task:** Add testnet URL enforcement for Kraken and Deribit once adapters are implemented.
**Current TODOs in code:**
- Line 215: `# TODO: Implement Kraken testnet enforcement when Kraken adapter is added`
- Line 224: `# TODO: Implement Deribit testnet enforcement when Deribit adapter is added`

## 4. WebSocket Connection Registry Enhancement
**File:** `lib/zen_cex/websocket/connection_registry.ex`
**Task:** Extract streams from client metadata if available for better connection tracking.
**Current TODO in code:**
- `# TODO: Extract streams from client metadata if available`

## Priority Order
1. **Tasks 1-2**: New exchange support (Kraken, Deribit, OKX) - Expand platform coverage
2. **Task 3**: Testnet enforcement - Complete testing infrastructure for new exchanges
3. **Task 4**: WebSocket registry enhancement - Nice-to-have improvement

## Notes
- All critical order safety and portfolio management tasks have been completed
- WebSocket implementation is fully operational with zen_websocket library
- Focus has shifted to expanding exchange support and completing test infrastructure