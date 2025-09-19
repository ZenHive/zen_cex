# Code TODOs - ZenCex

## ✅ Completed (2025-09-19)
1. ~~**Remove debug logging from auth modules**~~ - Removed debug logs from `binance/auth.ex:55`, `bybit/auth.ex:30`, and `core/http.ex:225`
4. ~~**Complete Bybit category injection**~~ - Implemented in `bybit/endpoint_loader.ex:115`
18. ~~**Add ISO date format support**~~ - Already implemented in `basis.ex:449`, just removed TODO comment
22. ~~**Implement get_ticker_price in Spot**~~ - Added delegation to MarketData in `binance/spot.ex`
24. ~~**Remove HTTP debug logging**~~ - Cleaned up `core/http.ex:225`
25. ~~**Adjust clock sync tolerance**~~ - Reviewed 5ms tolerance in `clock_sync_test.exs:444` (keeping as-is, tests passing)
21. ~~**Fix auth break test**~~ - Auth restoration handled by `with_env` macro's after block (`spot_integration_test.exs:664`, `endpoints_integration_test.exs:312`)
23. ~~**Add production rate limit warnings**~~ - Already implemented in `check_and_log_usage/3` (`usdm_futures_integration_test.exs:144`)
6. ~~**Implement batch order cancellation**~~ - `cancel_all_orders/1` auto-generated from `:delete_openOrders` endpoint (`binance/spot.ex`)

## Exchange Implementations
1. **[OUT OF SCOPE] Implement Kraken adapter** - Add full Kraken support (`core/registry.ex:35`, `integration_case.ex:201,158`)
2. **[OUT OF SCOPE] Implement Deribit adapter** - Add full Deribit support (`core/registry.ex:36`, `integration_case.ex:210,167`, `clock_sync.ex:428`)
3. **Add Bybit rate limit headers** - Monitor docs and implement official headers (`bybit/rate_limiter.ex:181`)

## Trading Features
7. **Implement COIN-M order placement** - Complete COIN-M futures orders (`binance/strategies.ex:677`)
8. **Implement portfolio rebalancing** - Add rebalancing strategy (`binance/strategies.ex:223`)

## Price & Market Data
9. **Replace placeholder prices with real ticker data** - Multiple locations need real price fetching (`strategies.ex:321,354,357,759-764`)
10. **Add WebSocket market data parsing** - Deferred to WebSocket phase (`binance/parser.ex:337`)
11. **Implement proper market price estimation** - Replace stub (`order_safety.ex:722`)

## Order Safety & Validation
12. **Connect order safety to real exchange APIs** - Replace stubs with actual calls (`order_safety.ex:482,556,843-856`)
13. **Fetch real symbol info and minimums** - Use exchange APIs instead of defaults (`order_safety.ex:691,750,760`)
14. **Add balance percentage checks** - Implement when account balance available (`strategies.ex:24,588`)

## Portfolio Margin
15. **Properly combine UM and CM positions** - Improve position aggregation (`portfolio_margin.ex:305`)
16. **Use unified portfolio view endpoints** - Replace workarounds (`strategies.ex:302,309`)
17. **Validate portfolio margin responses** - Add proper validation for production (`portfolio_margin_404_test.exs:242-243`)

## Market Analysis
19. **[OUT OF SCOPE] Extend exchange support for funding rates** - Add Kraken, Deribit, OKX (`market.ex:470,532`)
20. **Add central config management** - For backward compatibility (`market.ex:619`)

## Minor Fixes
26. **Get contract sizes from exchange info** - Replace hardcoded values (`strategies.ex:529`)
27. **Handle portfolio margin 404s properly** - Improve error handling (`portfolio_margin_404_test.exs:215,228`)