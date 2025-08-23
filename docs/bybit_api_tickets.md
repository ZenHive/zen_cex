# Bybit v5 REST API Implementation Tickets

## Architecture Decision: Unified Approach
Bybit v5 provides a unified API where the same endpoints serve spot, derivatives, and options - distinguished only by a `category` parameter. We'll mirror this design with a single unified module while providing category-prefixed helper functions for user convenience.

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
- Auto-inject `category` parameter based on operation prefix
- Timestamp and recv_window handling
- Parameter ordering for signature generation

### ✅ Ticket #3: Bybit Parser Module  
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/parser.ex`
- Response normalization for v5 unified responses
- Error code mapping (10001-80014 range)
- Single parser handles all product types
- Handle retCode/retMsg/result structure

### ✅ Ticket #4: ETS-based Rate Limiter
**Size:** 3 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/rate_limiter.ex`
- 600 requests per 5-second window per IP
- Single ETS table: `Elixir.ZenCex.Adapters.Bybit.RateLimiter.Table`
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

## Pass 3: Unified Endpoints Module (Using EndpointRegistry)

### ✅ Ticket #8: Unified Endpoints Module
**Size:** 6 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/endpoints.ex`
- Single module for ALL v5 endpoints
- Define @endpoints with unified paths:
  - GET /v5/account/wallet-balance
  - POST /v5/order/create
  - POST /v5/order/cancel
  - GET /v5/order/realtime
  - GET /v5/position/list
  - POST /v5/position/set-leverage
- Use EndpointRegistry macro for base functions
- Add category-prefixed helpers:
  ```elixir
  def spot_place_order(params), do: place_order(Map.put(params, :category, "spot"))
  def linear_place_order(params), do: place_order(Map.put(params, :category, "linear"))
  def inverse_place_order(params), do: place_order(Map.put(params, :category, "inverse"))
  ```
- Register with Core.Registry
- Implement discovery functions

### ✅ Ticket #9: Generated Endpoints File
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Create `lib/zen_cex/adapters/bybit/generated_endpoints.ex`
- Single generated file for all endpoints
- EndpointLoader adapts to unified structure
- Category parameter handling in macro

## Pass 4: Integration & Testing

### ✅ Ticket #10: Integration Case Setup
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Update `test/support/integration_case.ex` for Bybit
- Testnet URL enforcement: api-testnet.bybit.com
- Environment variable setup: BYBIT_TESTNET_API_KEY, BYBIT_TESTNET_API_SECRET
- Add Bybit-specific test helpers

### ✅ Ticket #11: Unified Integration Tests
**Size:** 4 hours
**Status:** TODO
**Implementation:**
- Create `endpoints_integration_test.exs`
- Test spot operations with category="spot"
- Test linear futures with category="linear"
- Test inverse futures with category="inverse"
- Test against REAL testnet API
- Document actual API responses
- No mocks, only real API calls

### ✅ Ticket #12: Clock Synchronization
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Update `ZenCex.Safety.ClockSync` for Bybit
- Add Bybit server time endpoint
- Single sync for unified API (no per-product sync needed)
- Test time window handling

## Pass 5: Advanced Features (Optional)

### ✅ Ticket #13: Options Trading Support
**Size:** 2 hours
**Status:** TODO
**Implementation:**
- Add options-specific helpers to endpoints.ex
- `def option_place_order(params), do: place_order(Map.put(params, :category, "option"))`
- Greeks calculations if needed
- Lower priority - implement if needed

### ✅ Ticket #14: Institutional Rate Limits
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
3. **Unified Endpoints** (Tickets 8-9): Single module for all products
4. **Testing** (Tickets 10-12): Real API integration tests
5. **Optional Features** (Tickets 13-14): If needed

## Key Architecture Notes

### Unified Design Benefits
- **Single Module**: One `Bybit.Endpoints` module mirrors v5 unified API
- **Category Helpers**: Prefixed functions (spot_*, linear_*, inverse_*) for discoverability
- **Shared Infrastructure**: One rate limiter, one parser, one auth module
- **Simpler Testing**: Single integration test file with category-based test groups
- **Less Code**: ~40% less code than separated approach

### Technical Details
- **Category Parameter**: Distinguishes product types in same endpoint
- **Rate Limits**: 600 requests per 5-second window (vs Binance's per-minute)
- **Testnet**: api-testnet.bybit.com for all testing
- **Headers**: X-BAPI-* prefix (vs Binance's X-MBX-*)
- **No WebSocket**: REST only, following ZenCex philosophy
- **Req-centric**: Leverage Req's capabilities, no custom HTTP logic
- **ETS over GenServers**: For stateless rate limiting
- **Real API Testing**: No mocks, test against testnet only

## Success Criteria

- [ ] Unified endpoints module handles all product types
- [ ] Category-prefixed helpers provide clear API
- [ ] Rate limiting prevents 403 errors
- [ ] Auth signatures match Bybit's requirements
- [ ] Integration tests pass for spot/linear/inverse
- [ ] Telemetry events emitted correctly
- [ ] Clock sync handles time drift
- [ ] Emergency operations bypass rate limits