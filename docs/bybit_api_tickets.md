# Bybit v5 REST API Implementation Tickets

## Pass 1: Core Infrastructure (Pure Functions & ETS Tables)

### ✅ Ticket #1: Bybit Signer Module (HMAC-SHA256)
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/signer.ex`
- HMAC-SHA256 signature generation (similar to Binance)
- Sign with timestamp + api_key + recv_window + query_string pattern
- Pure function: `sign(query_string, secret, timestamp, recv_window, api_key)`
- Test with known test vectors from Bybit docs

### ✅ Ticket #2: Bybit Parameter Builder
**Size:** 2 hours  
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/parameter_builder.ex`
- Handle unified v5 API parameter structure
- Add `category` parameter for product types (spot, linear, inverse, option)
- Timestamp and recv_window handling
- Parameter ordering for signature generation

### ✅ Ticket #3: Bybit Parser Module  
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/parser.ex`
- Response normalization for v5 unified responses
- Error code mapping (10001-80014 range)
- Unified parsing for spot/derivatives/options
- Handle retCode/retMsg/result structure

### ✅ Ticket #4: ETS-based Rate Limiter
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/rate_limiter.ex`
- 600 requests per 5-second window per IP
- ETS table: `Elixir.ZenCex.Adapters.Bybit.RateLimiter.Table`
- Atomic counters with 5-second windows
- Emergency bypass for cancel operations
- Reserved capacity (10% for emergency ops)

## Pass 2: Request Infrastructure

### ✅ Ticket #5: Bybit Auth Module (Req Step)
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/auth.ex`
- Implement as Req request step
- Add headers: X-BAPI-API-KEY, X-BAPI-TIMESTAMP, X-BAPI-SIGN, X-BAPI-RECV-WINDOW
- Coordinate with Signer and ParameterBuilder
- Support testnet/production environment switching

### ✅ Ticket #6: Request Helper Module
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/request_helper.ex`
- URL construction for v5 endpoints
- Base URLs: api.bybit.com (prod), api-testnet.bybit.com (test)
- Operation type detection
- Integrate with Core.HTTP

### ✅ Ticket #7: Common Endpoints Module
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/common.ex`
- Server time endpoint: GET /v5/market/time
- Announcement endpoint: GET /v5/announcements/index
- Use EndpointRegistry macro
- No auth required endpoints

## Pass 3: Trading Endpoints (Using EndpointRegistry)

### ✅ Ticket #8: Spot Trading Module
**Size:** 4 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/spot.ex`
- Define @endpoints for spot operations
- GET /v5/account/wallet-balance (get_balances)
- POST /v5/order/create (place_order)
- POST /v5/order/cancel (cancel_order)
- GET /v5/order/realtime (get_open_orders)
- Use EndpointRegistry macro for generation

### ✅ Ticket #9: Linear Futures Module (USDT-margined)
**Size:** 4 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/linear_futures.ex`
- Define @endpoints for linear futures
- GET /v5/position/list (get_positions)
- POST /v5/order/create with category=linear
- POST /v5/position/set-leverage
- GET /v5/account/wallet-balance with accountType=CONTRACT

### ✅ Ticket #10: Inverse Futures Module (Coin-margined)
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/inverse_futures.ex`
- Define @endpoints for inverse futures
- Similar to linear but category=inverse
- Handle coin-margined position calculations
- Different margin requirements

## Pass 4: Router & Registration

### ✅ Ticket #11: Main Endpoints Router
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/endpoints.ex`
- Router pattern like Binance
- Prefix-based delegation: spot_*, linear_*, inverse_*
- Register with Core.Registry
- Implement discovery functions

### ✅ Ticket #12: Endpoint Loader & Generated Files
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/endpoint_loader.ex`
- Generate: generated_spot_endpoints.ex, generated_linear_endpoints.ex, generated_inverse_endpoints.ex
- Macro-based endpoint generation
- Operation name mapping

## Pass 5: Integration & Testing

### ✅ Ticket #13: Integration Case Setup
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Update `test/support/integration_case.ex` for Bybit
- Testnet URL enforcement: api-testnet.bybit.com
- Environment variable setup: BYBIT_TESTNET_API_KEY, BYBIT_TESTNET_API_SECRET
- Add Bybit-specific test helpers

### ✅ Ticket #14: Core Integration Tests
**Size:** 4 hours
**Status:** TODO
**Implementation:**
- Create spot_integration_test.exs
- Create linear_futures_integration_test.exs
- Test against REAL testnet API
- Document actual API responses
- No mocks, only real API calls

### ✅ Ticket #15: Clock Synchronization
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Update `ZenCex.Safety.ClockSync` for Bybit
- Add Bybit server time endpoint
- Support unified API (single sync for all products)
- Test time window handling

## Pass 6: Advanced Features

### ✅ Ticket #16: Options Trading Module (Optional)
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/options.ex` 
- category=option for options trading
- Greeks calculations if needed
- Lower priority - implement if needed

### ✅ Ticket #17: Institutional Rate Limits (Optional)
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Add institutional tier support
- POST /v5/apilimit/set endpoint
- GET /v5/apilimit/query endpoint
- UID-based rate limit management

## Implementation Order

1. **Core Infrastructure First** (Tickets 1-4): Pure functions and ETS tables
2. **Request Layer** (Tickets 5-7): Auth and HTTP integration  
3. **Basic Trading** (Tickets 8-10): Spot and futures endpoints
4. **Router Setup** (Tickets 11-12): Connect everything
5. **Testing** (Tickets 13-15): Real API integration tests
6. **Optional Features** (Tickets 16-17): If needed

## Key Architecture Notes

- **Unified v5 API**: Single set of endpoints for all products (spot/derivatives/options)
- **Category Parameter**: Distinguishes product types in same endpoint
- **Rate Limits**: 600 requests per 5-second window (different from Binance's per-minute)
- **Testnet**: api-testnet.bybit.com for all testing
- **No WebSocket**: REST only, following ZenCex philosophy
- **Req-centric**: Leverage Req's capabilities, no custom HTTP logic
- **ETS over GenServers**: For stateless rate limiting
- **Real API Testing**: No mocks, test against testnet only

## Success Criteria

- [ ] All core endpoints working with testnet
- [ ] Rate limiting prevents 403 errors
- [ ] Auth signatures match Bybit's requirements
- [ ] Integration tests pass against real API
- [ ] Router properly delegates to sub-modules
- [ ] Telemetry events emitted correctly
- [ ] Clock sync handles time drift
- [ ] Emergency operations bypass rate limits