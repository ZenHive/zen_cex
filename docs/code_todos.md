# Code TODOs - ZenCex

## Authentication & Debug
1. **Remove debug logging from auth modules** - Remove debug logs from `binance/auth.ex:55` and `bybit/auth.ex:30` once stable

## Exchange Implementations
2. **[OUT OF SCOPE] Implement Kraken adapter** - Add full Kraken support (`core/registry.ex:35`, `integration_case.ex:201,158`)
3. **[OUT OF SCOPE] Implement Deribit adapter** - Add full Deribit support (`core/registry.ex:36`, `integration_case.ex:210,167`, `clock_sync.ex:428`)
4. **Complete Bybit category injection** - Finish implementation in `bybit/endpoint_loader.ex:115`
5. **Add Bybit rate limit headers** - Monitor docs and implement official headers (`bybit/rate_limiter.ex:181`)

## Trading Features
6. **Implement batch order cancellation** - Add batch cancel for Spot (`binance/spot.ex:257`)
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
18. **Add ISO date format support** - Implement YYYY-MM-DD format (`basis.ex:449`)
19. **[OUT OF SCOPE] Extend exchange support for funding rates** - Add Kraken, Deribit, OKX (`market.ex:470,532`)
20. **Add central config management** - For backward compatibility (`market.ex:619`)

## Testing
21. **Fix auth break test** - Restore auth after testing error formatting (`spot_integration_test.exs:664`, `endpoints_integration_test.exs:312`)
22. **Implement get_ticker_price in Spot** - Add missing method (`strategies_integration_test.exs:317`)
23. **Add production rate limit warnings** - Log when approaching limits (`usdm_futures_integration_test.exs:144`)

## Minor Fixes
24. **Remove HTTP debug logging** - Clean up `core/http.ex:225`
25. **Adjust clock sync tolerance** - Review 5ms tolerance (`clock_sync_test.exs:444`)
26. **Get contract sizes from exchange info** - Replace hardcoded values (`strategies.ex:529`)
27. **Handle portfolio margin 404s properly** - Improve error handling (`portfolio_margin_404_test.exs:215,228`)