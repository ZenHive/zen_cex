# Code TODOs

Actionable tasks extracted from codebase TODOs, organized for AI-assisted implementation.

## ~~1. Bybit Rate Limiter Headers~~ ✅ COMPLETED
**File:** `lib/zen_cex/adapters/bybit/rate_limiter.ex:181`
**Status:** Implemented support for `X-Bapi-Limit`, `X-Bapi-Limit-Status`, and `X-Bapi-Limit-Reset-Timestamp` headers.

## ~~2. Order Safety - Replace Stub Implementations~~ ✅ COMPLETED
**Files:** `lib/zen_cex/safety/order_safety.ex:843-856`
**Status:** Replaced stubs with real API calls using Binance.MarketData and Bybit.MarketData for symbol info, Binance.Spot and Bybit.Unified for balances.

## ~~3. Order Safety - Market Price Estimation~~ ✅ COMPLETED
**File:** `lib/zen_cex/safety/order_safety.ex:722`
**Status:** Implemented `fetch_current_price/2` using ticker APIs from both exchanges.

## ~~4. Order Safety - Dynamic Min Order Values~~ ✅ COMPLETED
**File:** `lib/zen_cex/safety/order_safety.ex:760`
**Status:** Modified `get_min_notional/2` to extract minimum values from exchange symbol filters.

## 5. Portfolio Margin Position Consolidation
**File:** `lib/zen_cex/adapters/binance/portfolio_margin.ex:305`
**Task:** Properly combine USDM and COINM futures positions with correct aggregation logic for total exposure calculation.

## 6. Binance Strategies - Balance Percentage Validation
**Files:** `lib/zen_cex/adapters/binance/strategies.ex:42,884`
**Task:** Add balance percentage checks for order validation once account balance is available from margin_info response.

## 7. Binance Strategies - Unified Account View
**Files:** `lib/zen_cex/adapters/binance/strategies.ex:551,558`
**Task:** Replace temporary Portfolio Margin endpoint usage with proper unified account data aggregation across spot/margin/futures.

## 8. Clock Sync - Dynamic Host Configuration
**File:** `lib/zen_cex/safety/clock_sync.ex:428`
**Task:** Use adapter's `base_url/1` method to get correct host for test/prod environments instead of hardcoded URL.

## 9. Market Analysis - Additional Exchange Support
**Files:** `lib/zen_cex/analysis/market.ex:470,532`
**Task:** Add funding rate fetching for Kraken, Deribit, and OKX perpetuals. Create new adapter modules following existing Binance/Bybit patterns.

## 10. Core Registry - New Exchange Adapters
**Files:** `lib/zen_cex/core/registry.ex:35-36`
**Task:** Implement Kraken and Deribit adapters with basic spot/futures functionality. Start with market data endpoints.

## 11. Integration Case - Testnet Enforcement
**Files:** `test/support/integration_case.ex:158,167`, `lib/zen_cex/test_utilities/integration_case.ex:201,210`
**Task:** Add testnet URL enforcement for Kraken and Deribit once adapters are implemented.

## 12. WebSocket Implementation
**File:** `lib/zen_cex/adapters/binance/parser.ex:337`
**Task:** Design and implement WebSocket support for real-time market data. Consider using `WebSockex` or `gun` library.

## Priority Order
1. Tasks 2-4: Critical for order safety in production
2. Tasks 5-7: Important for accurate portfolio tracking
3. Task 1,8: Improve existing functionality
4. Tasks 9-11: New exchange support
5. Task 12: Future enhancement for real-time data