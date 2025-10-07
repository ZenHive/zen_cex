# Aster Exchange Integration Specification

This document contains numbered tasks for implementing Aster exchange support in ZenCex.

## Status: PENDING

---

## 🔄 CONTINUATION PROMPT (Update at end of each session)

**Last Updated**: 2025-10-06 (Session 1)

**For next session, start with**:
```
Continue implementing Aster exchange support from docs/aster_specs.md.

Current status: Task 0 COMPLETED ✅ - API verification successful.
Next: Task 1 (Create core Aster modules structure).

Key findings from Task 0:
- ✅ 100% Binance-compatible API (identical response formats)
- ✅ Binance.Auth works perfectly without modification
- ✅ All public endpoints verified (ping, time, exchangeInfo, ticker, depth, 24hr)
- ✅ All authenticated endpoints verified (balance, account, positionRisk)
- ✅ 186 trading symbols, 32 margin assets available
- ✅ Clock sync within 416ms (well within ±5000ms window)
- ✅ No API quirks or differences detected

Implementation approach:
- Delegate to Binance.Auth for authentication (100% compatible)
- Reuse Binance.Parser for response parsing (verify during implementation)
- Custom rate limiter (2400 weight/min, 1200 orders/min)
- WebSocket likely compatible with Binance pattern

Begin: "Starting Task 1: Create core Aster modules structure..."
```

**What to update at end of each session**:
1. Update "Last Updated" date and session number
2. Update "Current status" with completed tasks
3. Update "Next" with the next task number and name
4. If all tasks done, change Status to "COMPLETED"

---

## Overview

**Exchange**: Aster Perpetual Pro (DEX)
**API Docs**: https://docs.asterdex.com/product/aster-perpetual-pro/api/api-documentation
**GitHub**: https://github.com/asterdex/api-docs

**⚠️ IMPORTANT: Manual Endpoint Pattern**

Aster has **no OpenAPI or Postman specs** available for code generation, so this implementation uses **manual endpoint definitions** (unlike Binance/Bybit which use generated endpoints from OpenAPI specs). Key differences:

1. **Endpoints Module**: Registry/discovery ONLY (no endpoint implementations)
   - Provides: `auth()`, `rate_limiter()`, `parser()`, `get_module()`, `list_api_types()`
   - Uses `ZenCex.Adapters.BaseEndpoints` for environment detection

2. **MarketData Module**: 16 public endpoints (manually defined functions)
   - Direct function definitions (no EndpointLoader/generation)
   - Simpler and more explicit than macro-based generation

3. **UsdmFutures Module**: 24 authenticated endpoints (manually defined functions)
   - Direct function definitions (no EndpointRegistry macro)
   - Follows same pattern as MarketData for consistency

This approach is **correct and appropriate** for smaller APIs (~40 total endpoints) where manual definitions are simpler than setting up a generation pipeline.

**What is Aster?**
Aster is a **decentralized exchange (DEX)** offering perpetual futures trading with two API versions:
1. **Standard API** - Traditional REST API with HMAC-SHA256 authentication (zen_cex implements this)
2. **V3 API** - Web3 wallet-based authentication using Keccak + ECDSA signatures (out of scope)

**API Compatibility**: Binance-compatible Standard API
- HMAC SHA256 authentication (identical to Binance)
- Same endpoint structure (`/fapi/v1/*`, `/fapi/v2/*`, `/fapi/v4/*`)
- `X-MBX-APIKEY` header for API key
- Similar rate limiting model (request weight system)
- Response formats match Binance Futures

**Base URLs**:
- REST: `https://fapi.asterdex.com`
- WebSocket: `wss://fstream.asterdex.com`

**Rate Limits**:
- Request Weight: 2400/min
- Order Limit: 1200/min
- IP-based rate limiting
- 429 status code for violations
- Potential IP ban for repeated violations

**Scope for zen_cex**:
- Perpetual futures trading (similar to Binance USD-M Futures)
- Standard API only (not V3 Web3 wallet API)
- ~40 REST endpoints across market data, account, and trading
- Market data (ticker, orderbook, trades, klines, funding rates)
- WebSocket streams (Binance-compatible stream formats)
- Position and leverage management
- Multi-assets mode and hedge mode support

---

## Task 0: API Verification and Testnet Access

[D:2/B:8 → Priority:4.0] 🎯

**Purpose**: Verify Aster API structure and obtain testnet credentials

**Public Endpoints to Test** (no auth required):
```elixir
# Use Tidewave to test these endpoints
alias ZenCex.Core.HTTP

# 1. Test connectivity
HTTP.request(%{method: :get, path: "/fapi/v1/ping", base_url: "https://fapi.asterdex.com"}, %{}, skip_auth: true)

# 2. Check server time (verify timestamp format)
HTTP.request(%{method: :get, path: "/fapi/v1/time", base_url: "https://fapi.asterdex.com"}, %{}, skip_auth: true)

# 3. Get exchange info (verify response structure matches Binance)
HTTP.request(%{method: :get, path: "/fapi/v1/exchangeInfo", base_url: "https://fapi.asterdex.com"}, %{}, skip_auth: true)

# 4. Get ticker price (test BTCUSDT)
HTTP.request(%{method: :get, path: "/fapi/v1/ticker/price", base_url: "https://fapi.asterdex.com"}, %{symbol: "BTCUSDT"}, skip_auth: true)

# 5. Get order book depth
HTTP.request(%{method: :get, path: "/fapi/v1/depth", base_url: "https://fapi.asterdex.com"}, %{symbol: "BTCUSDT", limit: 10}, skip_auth: true)

# 6. Get 24hr ticker stats
HTTP.request(%{method: :get, path: "/fapi/v1/ticker/24hr", base_url: "https://fapi.asterdex.com"}, %{symbol: "BTCUSDT"}, skip_auth: true)
```

**Verification Checklist**:
- [x] `/fapi/v1/ping` returns `{}`
- [x] `/fapi/v1/time` returns `%{"serverTime" => <unix_timestamp>}` - Server time within 416ms of local time
- [x] `/fapi/v1/exchangeInfo` has `symbols` array with symbol details - 186 symbols, identical structure to Binance
- [x] `/fapi/v1/ticker/price` returns `%{"symbol" => "BTCUSDT", "price" => "...", "time" => <timestamp>}`
- [x] `/fapi/v1/depth` returns order book with `bids`, `asks`, `lastUpdateId`, `E`, `T` fields
- [x] `/fapi/v1/ticker/24hr` returns 24hr stats with 16 fields (identical to Binance)
- [x] Response formats match Binance exactly - 100% compatible

**Authentication Testing** (if credentials available):
1. **Get testnet credentials**:
   - Register at Aster testnet (check if available)
   - Set environment variables:
     ```bash
     export ASTER_TESTNET_API_KEY="your_key"
     export ASTER_TESTNET_API_SECRET="your_secret"
     ```

2. **Test HMAC-SHA256 signature** (use Binance.Auth):
   ```elixir
   # Test if Binance auth works with Aster
   api_key = System.get_env("ASTER_TESTNET_API_KEY")
   api_secret = System.get_env("ASTER_TESTNET_API_SECRET")

   request = Req.new(url: "https://fapi.asterdex.com/fapi/v2/balance")
   signed = ZenCex.Adapters.Binance.Auth.sign_request(request, api_key, api_secret)
   {:ok, response} = Req.request(signed)
   ```

3. **Verify authenticated endpoints**:
   - [x] `/fapi/v2/balance` returns account balances - Returns array of 32 assets with balance details
   - [x] `/fapi/v4/account` returns account information - Includes canTrade, canDeposit, assets, positions
   - [x] `/fapi/v2/positionRisk` returns positions - 186 positions (matching all symbols)
   - [x] Signature validation succeeds - Binance.Auth works perfectly with Aster
   - [x] Timestamp validation works (±5000ms window) - Clock sync compatible

**Document Findings**:
- Testnet availability: ✅ VERIFIED - Credentials working, API fully accessible
- Response format compatibility: ✅ 100% BINANCE-COMPATIBLE
- Rate limit headers: Not yet verified (need to check response headers in next test)
- HMAC-SHA256 compatibility: ✅ PERFECT - Binance.Auth works without modification
- API quirks or differences: NONE DETECTED - Identical to Binance USD-M Futures API

**Key Findings**:
1. **Authentication**: `Binance.Auth` works perfectly with Aster (100% compatible)
2. **Response Structure**: Identical field names, data types, and formats to Binance
3. **Endpoints**: All tested endpoints (`/fapi/v1/*`, `/fapi/v2/*`, `/fapi/v4/*`) work as expected
4. **Clock Sync**: Server time within 416ms of local time (well within ±5000ms window)
5. **Data Quality**: 186 trading symbols, 32 margin assets, comprehensive market data
6. **Account Structure**: Same fields as Binance (canTrade, canDeposit, feeTier, balances, positions)

**Implementation Impact**:
- Can reuse `Binance.Auth` module directly (delegate pattern)
- Can likely reuse `Binance.Parser` for response parsing
- EndpointRegistry pattern will work identically
- Rate limiter needs custom limits (2400/min vs Binance's limits)
- WebSocket likely compatible (same `/stream` format expected)

**Next Steps**:
- Proceed with Task 1: Create core Aster modules structure
- No blockers identified - API is production-ready

---

## Task 1: Create Core Aster Modules Structure

[D:3/B:7 → Priority:2.33] 🚀

**Purpose**: Set up basic module structure for Aster adapter

**Files to create**:
```
lib/zen_cex/adapters/aster/
├── aster.ex              # Main module with documentation
├── endpoints.ex          # Registry module (auth, rate_limiter, parser, base_url)
├── auth.ex               # Delegates to Binance.Auth (100% compatible)
├── rate_limiter.ex       # Rate limiting (2400/min weight, 1200/min orders)
├── parser.ex             # Response parsing (delegates to Binance.Parser if compatible)
├── market_data.ex        # Public endpoints (manual definitions - no OpenAPI spec)
├── usdm_futures.ex       # Authenticated endpoints (manual definitions)
└── websocket.ex          # WebSocket streams (using zen_websocket)
```

**Architecture Note**:
Since Aster has **no OpenAPI/Postman specs**, we use **manual endpoint definitions** (unlike Binance/Bybit which have generated endpoints). This is simpler for small APIs (~40 endpoints total).

**Requirements**:
1. **lib/zen_cex/adapters/aster/aster.ex**:
   ```elixir
   defmodule ZenCex.Adapters.Aster do
     @moduledoc """
     Aster Perpetual Pro exchange adapter.

     Provides access to Aster's Binance-compatible perpetual futures API.

     ## Base URLs
     - REST: https://fapi.asterdex.com
     - WebSocket: wss://fstream.asterdex.com

     ## Authentication
     Uses HMAC SHA256 signatures (100% compatible with Binance auth).

     ## Rate Limits
     - Request Weight: 2400/minute
     - Order Limit: 1200/minute
     - IP-based rate limiting

     ## Modules
     - `Aster.Endpoints` - Registry/discovery (no endpoint implementations)
     - `Aster.MarketData` - Public market data endpoints
     - `Aster.UsdmFutures` - Perpetual futures trading
     - `Aster.WebSocket` - Real-time market data streams

     ## Implementation Notes
     - Endpoints are manually defined (no OpenAPI spec available)
     - Auth delegates to Binance.Auth (100% compatible)
     - Parser may delegate to Binance.Parser (needs verification)
     """

     @base_url "https://fapi.asterdex.com"
     @ws_url "wss://fstream.asterdex.com"

     def base_url, do: @base_url
     def websocket_url, do: @ws_url
   end
   ```

2. **lib/zen_cex/adapters/aster/endpoints.ex** (Registry only - no endpoint implementations):
   ```elixir
   defmodule ZenCex.Adapters.Aster.Endpoints do
     @moduledoc """
     Registry and discovery module for Aster exchange endpoints.

     This module provides registry functions for Core.Registry and endpoint discovery,
     but does NOT contain any actual endpoint implementations. Use the specific
     API modules directly for calling endpoints.

     ## Architecture

     This is a REGISTRY/DISCOVERY module only. All endpoints are implemented in:
     - `Aster.MarketData` - Public market data endpoints (16 endpoints)
     - `Aster.UsdmFutures` - Authenticated trading endpoints (24 endpoints)

     Since Aster has no OpenAPI/Postman specs, endpoints are manually defined
     in their respective modules (unlike Binance/Bybit which use generated endpoints).
     """

     use ZenCex.Adapters.BaseEndpoints,
       exchange: :aster,
       prod_url: "https://fapi.asterdex.com",
       test_url: "https://fapi.asterdex.com"  # TODO: Update if testnet becomes available

     alias ZenCex.Adapters.Aster.{MarketData, UsdmFutures, RateLimiter, Parser}
     alias ZenCex.Adapters.Binance.Auth  # Delegate to Binance (100% compatible)

     @doc "Returns the auth module (delegates to Binance.Auth)"
     @spec auth() :: module()
     def auth, do: Auth

     @doc "Returns the rate limiter module"
     @spec rate_limiter() :: module()
     def rate_limiter, do: RateLimiter

     @doc "Returns the parser module"
     @spec parser() :: module()
     def parser, do: Parser

     @doc "Returns the API module for a given type"
     @spec get_module(atom()) :: module() | nil
     def get_module(api_type) do
       case api_type do
         :market_data -> MarketData
         :usdm_futures -> UsdmFutures
         _ -> nil
       end
     end

     @doc "Returns all available API types"
     @spec list_api_types() :: [atom()]
     def list_api_types do
       [:market_data, :usdm_futures]
     end
   end
   ```

**Testing**:
Create `test/zen_cex/adapters/aster/aster_test.exs`:
```elixir
defmodule ZenCex.Adapters.AsterTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Aster

  @moduletag :aster

  test "base_url/0 returns Aster REST URL" do
    assert Aster.base_url() == "https://fapi.asterdex.com"
  end

  test "websocket_url/0 returns Aster WebSocket URL" do
    assert Aster.websocket_url() == "wss://fstream.asterdex.com"
  end
end
```

**Testing**: Create `test/zen_cex/adapters/aster/aster_test.exs` - test base_url/0 and websocket_url/0

**Verification**:
- `mix compile` succeeds
- Tests pass
- Registry recognizes `:aster` exchange

---

## Task 1.5: Create Aster MarketData Module

[D:2/B:7 → Priority:3.5] 🎯

**Purpose**: Implement public market data endpoints module

**File**: `lib/zen_cex/adapters/aster/market_data.ex`

**Pattern**: Manual endpoint definitions (Aster has no OpenAPI/Postman specs to generate from)

**Why Manual Pattern?**
- Aster provides no OpenAPI or Postman collections for code generation
- Manual definitions are simpler for small APIs (16 public endpoints)
- Binance/Bybit use generated endpoints because they have 100+ endpoints
- This approach is explicit, maintainable, and easier to customize

**Implementation**:
```elixir
defmodule ZenCex.Adapters.Aster.MarketData do
  @moduledoc """
  Market data endpoints for Aster Perpetual API.

  This module provides access to all Aster market data endpoints which are
  public and don't require authentication. These endpoints provide real-time
  and historical market information for perpetual futures trading.

  ## Available Endpoints

  ### Price Data
  - `get_ticker_price/1` - Current price for symbol(s)
  - `get_ticker_24hr/1` - 24hr ticker statistics
  - `get_order_book/1` - Order book depth
  - `get_recent_trades/1` - Recent trades list

  ### Historical Data
  - `get_klines/1` - Candlestick/OHLCV data
  - `get_mark_price/1` - Mark price and funding
  - `get_funding_rate/1` - Funding rate history
  - `get_open_interest/1` - Open interest

  ### Reference Data
  - `get_exchange_info/0` - Trading rules and symbols

  ## Usage

  Market data endpoints don't require authentication:

      # Get ticker price
      MarketData.get_ticker_price(%{symbol: "BTCUSDT"})

      # Get order book
      MarketData.get_order_book(%{symbol: "BTCUSDT", limit: 100})

      # Get klines
      MarketData.get_klines(%{
        symbol: "BTCUSDT",
        interval: "1h",
        limit: 100
      })
  """

  alias ZenCex.Adapters.Aster.Parser
  alias ZenCex.Core.HTTP

  @base_url "https://fapi.asterdex.com"

  # ============================================================================
  # System Endpoints
  # ============================================================================

  @doc "Test connectivity to the REST API"
  def ping(opts \\ []) do
    request(:get, "/fapi/v1/ping", %{}, opts)
  end

  @doc "Check server time (for timestamp validation)"
  def get_server_time(opts \\ []) do
    request(:get, "/fapi/v1/time", %{}, opts)
  end

  @doc "Current exchange trading rules and symbol information"
  def get_exchange_info(opts \\ []) do
    request(:get, "/fapi/v1/exchangeInfo", %{}, opts)
  end

  # ============================================================================
  # Price & Ticker Data
  # ============================================================================

  @doc "Current price for a symbol or all symbols"
  def get_ticker_price(params \\ %{}, opts \\ []) do
    request(:get, "/fapi/v1/ticker/price", params, opts)
  end

  @doc "24hr ticker price change statistics"
  def get_ticker_24hr(params \\ %{}, opts \\ []) do
    request(:get, "/fapi/v1/ticker/24hr", params, opts)
  end

  @doc "Best price/qty on the order book"
  def get_book_ticker(params \\ %{}, opts \\ []) do
    request(:get, "/fapi/v1/ticker/bookTicker", params, opts)
  end

  # ============================================================================
  # Order Book & Trades
  # ============================================================================

  @doc "Order book depth"
  def get_order_book(params, opts \\ []) do
    request(:get, "/fapi/v1/depth", params, opts)
  end

  @doc "Recent trades list"
  def get_recent_trades(params, opts \\ []) do
    request(:get, "/fapi/v1/trades", params, opts)
  end

  @doc "Old trade lookup (MARKET_DATA)"
  def get_historical_trades(params, opts \\ []) do
    request(:get, "/fapi/v1/historicalTrades", params, opts)
  end

  @doc "Compressed/aggregate trades list"
  def get_agg_trades(params, opts \\ []) do
    request(:get, "/fapi/v1/aggTrades", params, opts)
  end

  # ============================================================================
  # Klines (Candlestick Data)
  # ============================================================================

  @doc "Kline/candlestick bars for a symbol"
  def get_klines(params, opts \\ []) do
    request(:get, "/fapi/v1/klines", params, opts)
  end

  @doc "Index price kline/candlestick data"
  def get_index_price_klines(params, opts \\ []) do
    request(:get, "/fapi/v1/indexPriceKlines", params, opts)
  end

  @doc "Mark price kline/candlestick data"
  def get_mark_price_klines(params, opts \\ []) do
    request(:get, "/fapi/v1/markPriceKlines", params, opts)
  end

  # ============================================================================
  # Futures-Specific Data
  # ============================================================================

  @doc "Mark price and funding rate"
  def get_mark_price(params \\ %{}, opts \\ []) do
    request(:get, "/fapi/v1/premiumIndex", params, opts)
  end

  @doc "Funding rate history"
  def get_funding_rate(params, opts \\ []) do
    request(:get, "/fapi/v1/fundingRate", params, opts)
  end

  @doc "Funding rate config/info"
  def get_funding_info(params \\ %{}, opts \\ []) do
    request(:get, "/fapi/v1/fundingInfo", params, opts)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp request(method, path, params, opts) do
    endpoint_config = %{
      method: method,
      path: path,
      base_url: @base_url
    }

    # Market data is always public
    opts = Keyword.put(opts, :skip_auth, true)

    HTTP.request(endpoint_config, params, opts)
    |> Parser.parse_response()
  end
end
```

**Note**: Since Aster doesn't have OpenAPI/Postman specs, endpoints are **manually defined** as individual functions. This is simpler and more explicit than Binance's EndpointLoader approach, and works well for smaller APIs (16 public endpoints).

**Testing**: Create `test/zen_cex/adapters/aster/market_data_test.exs` - test endpoint functions are defined

**Verification**:
- Tests pass
- Public endpoints work without auth (verify with Tidewave)
- Returns normalized data (atom keys)

---

## Task 2: Implement Authentication

[D:2/B:6 → Priority:3.0] 🎯

**Purpose**: Implement HMAC SHA256 authentication for Aster

**File**: `lib/zen_cex/adapters/aster/auth.ex`

**Authentication Method**: HMAC-SHA256 (identical to Binance)
- Algorithm: HMAC SHA256
- Header: `X-MBX-APIKEY` (same as Binance)
- Timestamp parameter: `timestamp` (Unix milliseconds)
- Receive window: `recvWindow` (default 5000ms, max 60000ms)
- Signature parameter: `signature` (hex-encoded HMAC SHA256)

**Signature Process** (from Aster docs):
1. Create query string with all parameters (including timestamp)
2. Sign the query string: `signature = hex(HMAC_SHA256(api_secret, query_string))`
3. Append signature to query string
4. Add `X-MBX-APIKEY` header with API key

**Expected Approach**: Reuse `Binance.Auth` (100% compatible)

### Implementation (Recommended):
```elixir
defmodule ZenCex.Adapters.Aster.Auth do
  @moduledoc """
  HMAC SHA256 authentication for Aster (Binance-compatible).

  Aster uses the exact same authentication method as Binance Futures:
  - HMAC SHA256 signature algorithm
  - X-MBX-APIKEY header for API key
  - timestamp and signature query parameters
  - 5000ms default receive window

  Since the authentication is identical, we delegate to Binance.Auth.
  """

  defdelegate sign_request(request, api_key, api_secret),
    to: ZenCex.Adapters.Binance.Auth
end
```

**Testing with Tidewave**:
```elixir
# Test if Binance auth works with Aster
alias ZenCex.Adapters.Binance.Auth

api_key = System.get_env("ASTER_TESTNET_API_KEY")
api_secret = System.get_env("ASTER_TESTNET_API_SECRET")

# Create test request for account endpoint
request = Req.new(
  url: "https://fapi.asterdex.com/fapi/v2/balance",
  method: :get
)

# Sign with Binance auth
signed = Auth.sign_request(request, api_key, api_secret)

# Execute and verify
case Req.request(signed) do
  {:ok, %{status: 200, body: body}} ->
    IO.puts("✅ Authentication successful!")
    IO.inspect(body, label: "Response")

  {:ok, %{status: status, body: body}} ->
    IO.puts("❌ Authentication failed: #{status}")
    IO.inspect(body, label: "Error")

  {:error, reason} ->
    IO.puts("❌ Request failed")
    IO.inspect(reason)
end
```

**Testing**: Create `test/zen_cex/adapters/aster/auth_test.exs` - verify delegation works

**Verification**: Tests pass (auth already verified in Task 0)

**Notes**:
- Aster documentation confirms 100% Binance-compatible authentication
- No differences in signature algorithm, headers, or parameters
- Using delegation keeps code DRY and maintains consistency
- If signature fails, check:
  1. API key/secret are correct
  2. Timestamp is synchronized (use Safety.ClockSync)
  3. Query parameter ordering (should be handled by Binance.Auth)

---

## Task 3: Implement Rate Limiter

[D:3/B:6 → Priority:2.0] 🚀

**Purpose**: Implement rate limiting for Aster API

**File**: `lib/zen_cex/adapters/aster/rate_limiter.ex`

**Requirements**:
- 2400 request weight per minute
- 1200 orders per minute
- IP-based tracking
- Weight calculation from response headers

**Pattern to follow**: Copy from `Binance.RateLimiter` and adjust limits

```elixir
defmodule ZenCex.Adapters.Aster.RateLimiter do
  @moduledoc """
  Rate limiter for Aster API.

  Limits:
  - 2400 request weight per minute
  - 1200 orders per minute
  - IP-based rate limiting
  """

  @request_weight_limit 2400
  @order_limit 1200
  @window_ms 60_000

  # ETS table initialization
  # Request checking logic
  # Response header parsing
  # Weight tracking
end
```

**Testing**: Create `test/zen_cex/adapters/aster/rate_limiter_test.exs` - test weight tracking, limits, ETS operations

**Verification**: Tests pass, rate limits enforced, telemetry works

---

## Task 4: Implement UsdmFutures Module (Authenticated Endpoints)

[D:4/B:8 → Priority:2.0] 🚀

**Purpose**: Create main trading module with authenticated endpoints

**File**: `lib/zen_cex/adapters/aster/usdm_futures.ex`

**Pattern**: Manual endpoint definitions (like MarketData, since no OpenAPI spec)

**Total Authenticated Endpoints**: 24 (from Standard API documentation)

**Endpoint Categories**:
1. **Account Management** (9 endpoints)
2. **Trading Operations** (10 endpoints)
3. **Position Management** (5 endpoints)

**Implementation**:

```elixir
defmodule ZenCex.Adapters.Aster.UsdmFutures do
  @moduledoc """
  Aster Perpetual Futures trading interface.

  Provides all authenticated endpoints for perpetual futures trading on Aster.
  All endpoints require API credentials passed via the `auth_credentials` option.

  ## Usage

      alias ZenCex.Adapters.Aster.UsdmFutures

      # Account information
      UsdmFutures.get_balance(%{}, [
        auth_credentials: %{
          api_key: "...",
          api_secret: "..."
        }
      ])

      # Place order
      UsdmFutures.place_order(
        %{symbol: "BTCUSDT", side: "BUY", type: "LIMIT", quantity: "0.01", price: "50000"},
        [auth_credentials: %{api_key: "...", api_secret: "..."}]
      )

  ## Authentication

  All endpoints require HMAC-SHA256 authentication. Credentials are passed via options:
  - `api_key` - API key from Aster
  - `api_secret` - API secret for signing requests
  - `testnet` - (optional) Set to `true` for testnet endpoints

  ## Endpoint Categories

  ### Account Management (9 endpoints)
  - `get_balance/2` - Get futures account balance
  - `get_account/2` - Get account information
  - `get_positions/2` - Get current positions
  - `get_user_trades/2` - Get user trades
  - `get_income/2` - Get income history
  - `get_leverage_bracket/2` - Get leverage brackets
  - `get_adl_quantile/2` - Get ADL quantile
  - `get_force_orders/2` - Get force orders (liquidations)
  - `get_commission_rate/2` - Get commission rate

  ### Trading Operations (10 endpoints)
  - `place_order/2` - Place a new order
  - `place_batch_orders/2` - Place multiple orders
  - `cancel_order/2` - Cancel an existing order
  - `cancel_all_orders/2` - Cancel all open orders
  - `cancel_batch_orders/2` - Cancel multiple orders
  - `cancel_all_and_place/2` - Cancel all and place atomically
  - `get_order/2` - Query order status
  - `get_open_orders/2` - Get all open orders
  - `get_all_orders/2` - Get all orders (history)
  - `transfer_wallet/2` - Transfer between wallets

  ### Position & Leverage Management (5 endpoints)
  - `set_position_mode/2` - Change position mode
  - `get_position_mode/2` - Get current position mode
  - `set_multi_assets_mode/2` - Change multi-assets mode
  - `get_multi_assets_mode/2` - Get current multi-assets mode
  - `set_leverage/2` - Change leverage
  - `set_margin_type/2` - Change margin type
  - `modify_isolated_position_margin/2` - Modify isolated margin
  - `get_position_margin_history/2` - Get margin change history
  """

  alias ZenCex.Adapters.Aster.Parser
  alias ZenCex.Core.HTTP

  @base_url "https://fapi.asterdex.com"

  # ============================================================================
  # Account Management (9 endpoints)
  # ============================================================================

  @doc "Get futures account balance (USER_DATA)"
  def get_balance(params \\ %{}, opts) do
    request(:get, "/fapi/v2/balance", params, opts)
  end

  @doc "Get account information including balances and positions (USER_DATA)"
  def get_account(params \\ %{}, opts) do
    request(:get, "/fapi/v4/account", params, opts)
  end

  @doc "Get current position information (USER_DATA)"
  def get_positions(params \\ %{}, opts) do
    request(:get, "/fapi/v2/positionRisk", params, opts)
  end

  @doc "Get trades for a specific account and symbol (USER_DATA)"
  def get_user_trades(params, opts) do
    request(:get, "/fapi/v1/userTrades", params, opts)
  end

  @doc "Get income history (funding fees, realized PNL, etc.) (USER_DATA)"
  def get_income(params \\ %{}, opts) do
    request(:get, "/fapi/v1/income", params, opts)
  end

  @doc "Get notional and leverage brackets (USER_DATA)"
  def get_leverage_bracket(params \\ %{}, opts) do
    request(:get, "/fapi/v1/leverageBracket", params, opts)
  end

  @doc "Get quantitative rules for ADL (Auto-Deleveraging) (USER_DATA)"
  def get_adl_quantile(params \\ %{}, opts) do
    request(:get, "/fapi/v1/adlQuantile", params, opts)
  end

  @doc "Get user's force orders (liquidations) (USER_DATA)"
  def get_force_orders(params \\ %{}, opts) do
    request(:get, "/fapi/v1/forceOrders", params, opts)
  end

  @doc "Get current commission rate (USER_DATA)"
  def get_commission_rate(params, opts) do
    request(:get, "/fapi/v1/commissionRate", params, opts)
  end

  # ============================================================================
  # Trading Operations (10 endpoints)
  # ============================================================================

  @doc "Place a new order (TRADE)"
  def place_order(params, opts) do
    request(:post, "/fapi/v1/order", params, opts)
  end

  @doc "Place multiple orders (up to 5 orders) (TRADE)"
  def place_batch_orders(params, opts) do
    request(:post, "/fapi/v1/batchOrders", params, opts)
  end

  @doc "Cancel an existing order (TRADE)"
  def cancel_order(params, opts) do
    request(:delete, "/fapi/v1/order", params, opts)
  end

  @doc "Cancel all open orders on a symbol (TRADE)"
  def cancel_all_orders(params, opts) do
    request(:delete, "/fapi/v1/allOpenOrders", params, opts)
  end

  @doc "Cancel multiple orders (TRADE)"
  def cancel_batch_orders(params, opts) do
    request(:delete, "/fapi/v1/batchOrders", params, opts)
  end

  @doc "Cancel all orders and place new batch orders atomically (TRADE)"
  def cancel_all_and_place(params, opts) do
    request(:post, "/fapi/v1/countdownCancelAll", params, opts)
  end

  @doc "Query order status (USER_DATA)"
  def get_order(params, opts) do
    request(:get, "/fapi/v1/order", params, opts)
  end

  @doc "Get all open orders on a symbol (USER_DATA)"
  def get_open_orders(params \\ %{}, opts) do
    request(:get, "/fapi/v1/openOrders", params, opts)
  end

  @doc "Get all orders (active, canceled, filled) for a symbol (USER_DATA)"
  def get_all_orders(params, opts) do
    request(:get, "/fapi/v1/allOrders", params, opts)
  end

  @doc "Transfer between futures and spot wallet (USER_DATA)"
  def transfer_wallet(params, opts) do
    request(:post, "/fapi/v1/asset/wallet/transfer", params, opts)
  end

  # ============================================================================
  # Position & Leverage Management (5 endpoints)
  # ============================================================================

  @doc "Change position mode (Hedge Mode or One-way Mode) (TRADE)"
  def set_position_mode(params, opts) do
    request(:post, "/fapi/v1/positionSide/dual", params, opts)
  end

  @doc "Get current position mode (Hedge Mode or One-way Mode) (USER_DATA)"
  def get_position_mode(params \\ %{}, opts) do
    request(:get, "/fapi/v1/positionSide/dual", params, opts)
  end

  @doc "Change multi-assets mode (USER_DATA)"
  def set_multi_assets_mode(params, opts) do
    request(:post, "/fapi/v1/multiAssetsMargin", params, opts)
  end

  @doc "Get current multi-assets mode (USER_DATA)"
  def get_multi_assets_mode(params \\ %{}, opts) do
    request(:get, "/fapi/v1/multiAssetsMargin", params, opts)
  end

  @doc "Change initial leverage for a symbol (TRADE)"
  def set_leverage(params, opts) do
    request(:post, "/fapi/v1/leverage", params, opts)
  end

  @doc "Change margin type for a symbol (TRADE)"
  def set_margin_type(params, opts) do
    request(:post, "/fapi/v1/marginType", params, opts)
  end

  @doc "Modify isolated position margin (TRADE)"
  def modify_isolated_position_margin(params, opts) do
    request(:post, "/fapi/v1/positionMargin", params, opts)
  end

  @doc "Get position margin change history (TRADE)"
  def get_position_margin_history(params, opts) do
    request(:get, "/fapi/v1/positionMargin/history", params, opts)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp request(method, path, params, opts) do
    endpoint_config = %{
      method: method,
      path: path,
      base_url: @base_url
    }

    # Auth credentials must be passed via opts
    HTTP.request(endpoint_config, params, opts)
    |> Parser.parse_response()
  end
end
```

**Note**: Endpoints are manually defined (no OpenAPI spec). This pattern is simpler and more explicit for smaller APIs.

**Testing**: Create `test/zen_cex/adapters/aster/usdm_futures_test.exs`:
```elixir
defmodule ZenCex.Adapters.Aster.UsdmFuturesTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Aster.UsdmFutures

  @moduletag :aster

  describe "module exports" do
    test "defines all 24 endpoint functions" do
      assert function_exported?(UsdmFutures, :get_balance, 2)
      assert function_exported?(UsdmFutures, :place_order, 2)
      assert function_exported?(UsdmFutures, :get_positions, 2)
      # ... test other functions exist
    end
  end
end
```

**Registry Integration**:
Already handled by Task 1 - `Endpoints.get_module(:usdm_futures)` returns `UsdmFutures`

**Verification**:
- `mix compile` succeeds
- All 24 functions are defined
- Endpoints.get_module(:usdm_futures) returns correct module

---

## Task 5: Implement Response Parser

[D:3/B:5 → Priority:1.67] 🚀

**Purpose**: Parse Aster API responses

**File**: `lib/zen_cex/adapters/aster/parser.ex`

**Strategy**:
1. Test if Binance parser works as-is
2. If not, create Aster-specific parser
3. Normalize to atom keys (like Binance)

**Testing with Tidewave**:
```elixir
# Get raw response from Aster
{:ok, response} = Aster.UsdmFutures.get_ticker_price(%{symbol: "BTCUSDT"})

# Check structure
IO.inspect(response)

# Test with Binance parser
Binance.Parser.parse_ticker(response)
```

**Implementation options**:

### Option A: Delegate to Binance (if compatible)
```elixir
defmodule ZenCex.Adapters.Aster.Parser do
  defdelegate parse_ticker(response), to: ZenCex.Adapters.Binance.Parser
  defdelegate parse_order_book(response), to: ZenCex.Adapters.Binance.Parser
  # ... etc
end
```

### Option B: Custom parser (if needed)
```elixir
defmodule ZenCex.Adapters.Aster.Parser do
  def parse_ticker(response) when is_map(response) do
    # Normalize to atom keys
    # Extract fields
    # Return standardized format
  end
end
```

**Testing**: Create `test/zen_cex/adapters/aster/parser_test.exs` - test key normalization, error parsing

**Verification**: Tests pass, atom keys, proper error handling

---

## Task 6: Implement WebSocket Core

[D:5/B:7 → Priority:1.4] 📋

**Purpose**: Add WebSocket streaming for market data (core functionality)

**File**: `lib/zen_cex/adapters/aster/websocket.ex`

**Pattern to follow**: Copy from `Binance.WebSocket` structure

```elixir
defmodule ZenCex.Adapters.Aster.WebSocket do
  @moduledoc """
  Minimal Aster WebSocket adapter using zen_websocket directly.

  Provides a thin layer over zen_websocket for Aster-specific WebSocket handling.
  Data is automatically stored in ETS cache for fast access by other modules.

  ## Connection Management Architecture

  This module operates as part of a three-layer architecture:

  1. **Transport Layer (zen_websocket)**:
     - Maintains Gun connection ownership through the Client GenServer
     - Handles automatic reconnection with exponential backoff
     - Returns stable client structs that survive reconnections

  2. **Adapter Layer (this module)**:
     - Provides exchange-specific protocol handling
     - Creates new connections when called directly (by design)
     - Does NOT manage connection reuse - that's an application concern
     - Focuses on Aster-specific stream formats and message parsing

  3. **Application Layer (ConnectionRegistry + MarketData)**:
     - `ConnectionRegistry` tracks all active connections by `{exchange, symbol}`
     - `MarketData.ensure_websocket_connection/2` checks registry before creating
     - Implements actual connection reuse logic with application context

  ## Supported Streams

  Binance-compatible stream formats:
  - Trade streams: `<symbol>@trade`
  - Ticker streams: `<symbol>@ticker`
  - Order book: `<symbol>@depth` or `<symbol>@depth@100ms`
  - Book ticker: `<symbol>@bookTicker`
  - Kline/Candlestick: `<symbol>@kline_<interval>`

  ## Connection Modes

  ### Development Mode (Direct Connection)
      {:ok, client} = Aster.WebSocket.connect(["btcusdt@depth20", "ethusdt@trade"])

  ### Production Mode (Supervised Connection)
      {:ok, client} = Aster.WebSocket.connect(
        ["btcusdt@depth20", "btcusdt@ticker"],
        supervised: true
      )
  """

  require Logger
  alias ZenCex.Cache.Market

  @spot_base_url "wss://fstream.asterdex.com"

  # Main API functions (5 functions max)
  def connect(streams, opts \\ [])
  def subscribe(client, streams)
  def unsubscribe(client, streams)
  def close(client)
  def ensure_connection(exchange, symbol, opts \\ [])

  # Message handler callback
  def handle_message({:text, msg}, state) do
    # Parse JSON message
    # Extract stream type and symbol
    # Route to appropriate cache update
    # (Details in Task 6.5)
  end
end
```

**Testing**: Create `test/zen_cex/adapters/aster/websocket_test.exs` - test stream URLs, message parsing (async: false)

**Verification**: Tests pass, WebSocket connects, messages received

---

## Task 6.5: WebSocket Cache Integration

[D:3/B:8 → Priority:2.67] 🎯

**Purpose**: Integrate WebSocket data with Cache.Market for unified access

**File**: Update `lib/zen_cex/adapters/aster/websocket.ex` message handler

**Implementation**: Update `handle_message/2` to parse WebSocket events (24hrTicker, bookTicker, depthUpdate, trade) and call corresponding `Cache.Market` functions (put_ticker, put_book_ticker, put_orderbook, put_last_trade).

**Reference**: `lib/zen_cex/adapters/binance/websocket.ex` - identical message format

**Verification**: WebSocket messages update ETS cache, Cache.Market.get_* functions return fresh data

---

## Task 6.6: WebSocket ConnectionRegistry Integration

[D:2/B:6 → Priority:3.0] 🎯

**Purpose**: Register Aster WebSocket connections for reuse

**Implementation**: Add `ensure_connection/3` - check ConnectionRegistry, reuse healthy connections or create new. Build streams list for symbol (bookTicker, ticker, trade).

**Reference**: `lib/zen_cex/adapters/binance/websocket.ex` - identical pattern

**Verification**: Second call reuses connection, ConnectionRegistry tracks Aster connections

---

## Task 7: Add Integration Tests

[D:4/B:6 → Priority:1.5] 🚀

**Purpose**: Create integration tests for Aster adapter against real API

**Implementation**: Create `integration_test.exs` - test public endpoints, authenticated endpoints (@describetag :authenticated), trading operations (@describetag :write_operation). Add WebSocket integration tests.

**Reference**: `test/zen_cex/adapters/binance/integration_test.exs`

**Verification**: All tests pass with testnet credentials

---

## Task 7.5: Add Safety.OrderSafety.MarketData Support

[D:2/B:8 → Priority:4.0] 🎯

**Purpose**: Integrate Aster with the OrderSafety market data system

**Implementation**: Add `:aster` clauses to `fetch_symbol_info_from_exchange/2`, `fetch_price_from_exchange/2`, and `fetch_balance/3` in `lib/zen_cex/safety/order_safety/market_data.ex`.

**Reference**: Existing `:binance` implementations in same file

**Verification**: Test with Tidewave - fetch_symbol_info, fetch_current_price work, WebSocket fallback works after Task 6.5/6.6

---

## Task 8: Create Example Module

[D:3/B:5 → Priority:1.67] 🚀

**Purpose**: Create usage examples for Aster

**Implementation**: Create `lib/examples/aster_trading.ex` with demo functions: check_connectivity, get_btc_price, get_account_info, connect_market_stream, get_cached_data.

**Reference**: `lib/examples/binance_trading.ex`

**Verification**: All examples work with testnet credentials

---

## Task 9: Update Documentation

[D:2/B:6 → Priority:3.0] 🎯

**Purpose**: Add Aster to project documentation

**Files to update**:

1. **README.md**:
   ```markdown
   ## Supported Exchanges

   - ✅ **Binance** - Spot, Margin, USD-M Futures, COIN-M Futures, Portfolio Margin
   - ✅ **Bybit** - Unified Trading (V5)
   - ✅ **Aster** - Perpetual Futures (Binance-compatible)

   ### Aster Perpetual Pro

   ```elixir
   alias ZenCex.Adapters.Aster.UsdmFutures

   # Market data
   {:ok, ticker} = UsdmFutures.get_ticker_price(%{symbol: "BTCUSDT"})

   # Account & positions
   {:ok, positions} = UsdmFutures.get_positions(%{}, [
     auth_credentials: %{
       api_key: System.get_env("ASTER_API_KEY"),
       api_secret: System.get_env("ASTER_API_SECRET")
     }
   ])

   # WebSocket streams
   {:ok, client} = Aster.WebSocket.connect(["btcusdt@trade"])
   ```
   ```

2. **usage-rules.md**:
   - Add Aster quick reference
   - Document endpoint patterns
   - Add WebSocket examples

3. **CHANGELOG.md**:
   ```markdown
   ## [Unreleased]

   ### Added
   - Aster Perpetual Pro exchange support
     - Binance-compatible API structure
     - HMAC SHA256 authentication
     - Perpetual futures trading
     - WebSocket market data streams
     - Rate limiting (2400/min weight, 1200/min orders)
   ```

4. **Environment variables** (README.md):
   ```bash
   # Aster
   ASTER_TESTNET_API_KEY=xxx
   ASTER_TESTNET_API_SECRET=xxx
   ```

**Verification**:
- Documentation builds correctly
- Examples are accurate
- All features documented

---

## Task 10: Final Integration and Testing

[D:3/B:7 → Priority:2.33] 🚀

**Purpose**: Complete integration and verify all features work

**Checklist**:

1. **Core Registry**:
   - [ ] `:aster` exchange registered
   - [ ] Module routing works
   - [ ] Discovery functions include Aster

2. **Clock Sync**:
   - [ ] Add Aster to `Safety.ClockSync`
   - [ ] Time offset calculated correctly
   - [ ] Timestamps are accurate

3. **Circuit Breaker**:
   - [ ] Circuit breaker configured for Aster
   - [ ] Failure threshold set
   - [ ] Recovery works

4. **Telemetry**:
   - [ ] Events emitted for requests
   - [ ] Rate limit events work
   - [ ] WebSocket events fire

5. **Testing**:
   ```bash
   # Run Aster tests
   mix test test/zen_cex/adapters/aster/ --include aster

   # Run integration tests
   mix test --only aster --only integration

   # Run WebSocket tests
   mix test --only aster --only websocket

   # Run example tests
   mix test test/examples/aster_trading_test.exs

   # Run market data tests
   mix test test/zen_cex/adapters/aster/market_data_test.exs
   mix test test/zen_cex/adapters/aster/market_data_integration_test.exs
   ```

6. **IEx Helpers**:
   - [ ] Add Aster aliases to `.iex.exs`
   - [ ] Test helpers work
   - [ ] Credentials helper includes Aster

7. **Documentation**:
   - [ ] `mix docs` includes Aster modules
   - [ ] Examples appear in docs
   - [ ] README updated

8. **Quality Checks**:
   ```bash
   mix format
   mix credo
   mix dialyzer
   mix doctor
   ```

**Final verification**:
- [ ] All tests pass
- [ ] No dialyzer warnings
- [ ] Documentation is complete
- [ ] Examples work end-to-end
- [ ] Rate limiting enforced
- [ ] WebSocket streaming works
- [ ] Authentication successful
- [ ] Market data module works (public endpoints)
- [ ] WebSocket cache integration working
- [ ] ConnectionRegistry tracks Aster connections
- [ ] Safety.OrderSafety.MarketData supports Aster
- [ ] Price fetching works (REST + WebSocket fallback)
- [ ] Symbol info caching works
- [ ] `Cache.Market.get_ticker(:aster, "BTCUSDT")` returns data

---

## Notes

### Standard API vs V3 API Comparison

Aster offers two distinct API versions for different use cases:

| Aspect | Standard API | V3 API |
|--------|-------------|--------|
| **Authentication** | HMAC-SHA256 (API key + secret) | Web3 Wallet (Keccak + ECDSA) |
| **Credentials** | API Key + API Secret | Wallet Address + Private Key |
| **Required Headers** | `X-MBX-APIKEY` | Custom Web3 signature headers |
| **Signature Algorithm** | HMAC SHA256 | ABI encoding → Keccak hash → ECDSA |
| **Use Case** | Trading bots, server-side automation | DeFi frontends, wallet integrations |
| **Dependencies** | Standard HTTP libraries (Req, Finch) | Web3 libraries (ethers.js, web3.py, etc.) |
| **Target Users** | Algorithmic traders, market makers | Wallet users, DeFi protocols |
| **zen_cex Support** | ✅ **Implementing** (Tasks 0-10) | ❌ **Out of scope** |
| **Total Endpoints** | ~40 (16 market data + 24 account/trading) | ~6 (subset for Web3 use cases) |
| **Binance Compatible** | ✅ Yes (identical structure) | ❌ No (custom Web3 format) |
| **WebSocket Support** | ✅ Yes (Binance-compatible streams) | Unknown (not documented) |

**Why Standard API for zen_cex?**
1. **Compatibility**: Reuses existing Binance.Auth, parser patterns, and HTTP infrastructure
2. **Simplicity**: No Web3 dependencies (ethers.js, web3.py, etc.)
3. **Scope**: zen_cex focuses on trading APIs, not on-chain deposits/withdrawals
4. **Use Case**: Algorithmic trading and market making (not wallet-based DeFi)

**V3 API Details** (for reference):
- **Authentication**: Uses Ethereum ABI parameter encoding, Keccak hashing, and ECDSA signatures
- **Endpoints**: Limited to balance transfers and account queries
- **Purpose**: On-chain asset management and wallet-based trading
- **Excluded from zen_cex**: Requires different paradigm (Web3) and is out of scope for traditional trading APIs

### Market Data Architecture (4 Layers)

The market data system in zen_cex uses a 4-layer architecture:

1. **MarketData Module** (`Aster.MarketData`):
   - Public REST endpoints (no authentication)
   - Provides: tickers, orderbook, klines, funding rates, etc.
   - Uses manual function definitions (no OpenAPI spec for generation)
   - Sets `skip_auth: true` for all requests

2. **WebSocket Adapter** (`Aster.WebSocket`):
   - Real-time market data streams
   - Automatically updates ETS cache via `Cache.Market`
   - Binance-compatible stream formats (e.g., `btcusdt@ticker`)
   - Uses zen_websocket Client for connection management

3. **Cache.Market** (Unified Cache Layer):
   - ETS-based caching with TTLs
   - Functions: `get_ticker/2`, `get_orderbook/2`, `get_book_ticker/2`, `put_ticker/3`, etc.
   - WebSocket data uses `:infinity` TTL (continuously updated)
   - REST data uses shorter TTLs (15-60 seconds)

4. **Safety.OrderSafety.MarketData** (High-level API):
   - Used by OrderSafety for validation
   - Prefers WebSocket data (if fresh)
   - Falls back to REST if WebSocket unavailable/stale
   - Caches symbol info and prices

**Data Flow**:
```
WebSocket Stream → Aster.WebSocket → Cache.Market (ETS)
                                           ↓
User Code → Safety.OrderSafety.MarketData → Cache.Market → WebSocket or REST
```

### Reusable Components
Since Aster is Binance-compatible, we can likely reuse:
- ✅ `Binance.Auth` - HMAC SHA256 signing
- ✅ Req middleware pattern
- ✅ Endpoint registry pattern
- ✅ WebSocket message handling
- ✅ Cache.Market integration (exchange-agnostic)
- ⚠️ `Binance.Parser` - needs verification
- ⚠️ Response normalization - verify atom keys

### Unique Aspects
- Different base URLs
- Different rate limits (2400/min vs Binance)
- May have different response formats (needs testing)
- Different WebSocket URL
- Futures-only (no spot market)

### Environment Variables
```bash
# Testnet (if available)
export ASTER_TESTNET_API_KEY="your_key"
export ASTER_TESTNET_API_SECRET="your_secret"

# Production (separate test account with minimal funds)
export ASTER_API_KEY="your_key"
export ASTER_API_SECRET="your_secret"
```

### Web3 Integration (Out of Scope)
The Web3 wallet authentication found in GitHub repo is for:
- Deposits (on-chain)
- Withdrawals (on-chain)
- Asset transfers (on-chain)

**Not needed for trading API**, which uses standard API key/secret.

---

## Task 11: Review Exchange Adapter Pattern

[D:2/B:8 → Priority:4.0] 🎯

**Purpose**: Evaluate if a formal `ExchangeAdapter` behavior should be introduced

**Context**: After implementing Aster (3rd exchange), we have enough data points to decide whether to formalize the exchange adapter pattern as a behavior.

**Current Pattern** (Informal):
```elixir
# All exchange Endpoints modules implement:
def auth() :: module()
def rate_limiter() :: module()
def parser() :: module()
def base_url(...) :: String.t()  # Signature varies!
def get_module(atom()) :: module() | nil
def list_api_types() :: [atom()]
```

**Review Questions**:
1. Do all 3 exchanges (Binance, Bybit, Aster) implement identical signatures?
2. Are there exchange-specific extensions that required signature variations?
3. Would a formal behavior have prevented any bugs during Aster implementation?
4. Does the informal pattern cause maintainability issues?

**Decision Criteria**:

**Introduce `ZenCex.Behaviors.ExchangeAdapter` IF**:
- ✅ All 3 exchanges have identical function signatures
- ✅ No exchange needed signature variations
- ✅ Behavior would provide compile-time safety value

**Keep Informal Protocol IF**:
- ✅ Exchanges have different base_url signatures (Binance vs Bybit)
- ✅ Some exchanges skip certain functions
- ✅ Current pattern works without issues

**Philosophy Check** (CLAUDE.md):
- "Create abstractions only with proven need - Need 3+ use cases" → ✅ Now have 3
- "Simplicity First" → Only add if proven necessary

**Outcome**: Document decision in `docs/architecture/exchange-adapter-pattern.md`

---

## 📝 Session Notes (Append after each session)

### Session 0: 2025-10-05
**Completed**:
- Created specification document
- Researched Aster API documentation
- Verified Binance compatibility
- Identified reusable components

**Findings**:
- Aster uses Binance-compatible API structure
- HMAC SHA256 authentication (same as Binance)
- Endpoint paths match Binance futures (`/fapi/v1/*`)
- Rate limits: 2400 weight/min, 1200 orders/min
- Web3 auth is separate (deposits/withdrawals only)

**Next session**: Task 0 (API verification with Tidewave)

### Session 1: 2025-10-06
**Completed**:
- Reviewed and verified spec accuracy against existing Binance/Bybit patterns
- Corrected architecture to follow proper registry/endpoint separation
- Updated specs to use manual endpoint pattern (no OpenAPI generation)

**Changes Made**:
1. **Task 1**: Added `BaseEndpoints` usage and Endpoints registry pattern
2. **Task 1.5**: Clarified manual pattern for MarketData (no map-based generation)
3. **Task 4**: Split into Endpoints (registry) and UsdmFutures (implementations)
4. **Overview**: Added section explaining manual vs generated pattern choice

**Key Architectural Decisions**:
- **Endpoints module**: Registry/discovery ONLY (matches Binance/Bybit pattern)
- **Manual definitions**: Direct function definitions in MarketData/UsdmFutures
- **No EndpointLoader**: Appropriate for small APIs (~40 endpoints total)
- **Code reuse**: Binance.Auth delegation, Binance.Parser verification needed

**Findings**:
- Manual pattern is **correct** for APIs without OpenAPI/Postman specs
- Simpler and more explicit than macro-based generation for small APIs
- Maintains architectural consistency (registry vs implementation separation)
- Follows same patterns as Binance/Bybit where applicable

**Next session**: Begin Task 1 implementation (create core module structure)

---

_Add new session notes above this line_
