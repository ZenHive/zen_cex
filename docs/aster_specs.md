# Aster Exchange Integration Specification

This document contains numbered tasks for implementing Aster exchange support in ZenCex.

## Status: PENDING

---

## 🔄 CONTINUATION PROMPT (Update at end of each session)

**Last Updated**: 2025-10-05 (Session 0)

**For next session, start with**:
```
Continue implementing Aster exchange support from docs/aster_specs.md.

Current status: Not started. Specification updated with market data tasks.
Next: Task 0 (API verification and testnet access).

Key points:
- Aster uses Binance-compatible API structure (HMAC SHA256)
- Base URLs: https://fapi.asterdex.com (REST), wss://fstream.asterdex.com (WebSocket)
- Can reuse ~90% of Binance patterns
- Rate limits: 2400 weight/min, 1200 orders/min
- Web3 auth is for deposits/withdrawals (out of scope)
- Market data integration: 4-layer architecture (MarketData → WebSocket → Cache.Market → OrderSafety)
- New tasks added: 1.5 (MarketData), 6.5 (WebSocket cache), 6.6 (ConnectionRegistry), 7.5 (OrderSafety)

Begin: "Starting Aster integration from docs/aster_specs.md - Task 0..."
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
- [ ] `/fapi/v1/ping` returns `{}`
- [ ] `/fapi/v1/time` returns `%{"serverTime" => <unix_timestamp>}`
- [ ] `/fapi/v1/exchangeInfo` has `symbols` array with symbol details
- [ ] `/fapi/v1/ticker/price` returns `%{"symbol" => "BTCUSDT", "price" => "..."}`
- [ ] Response headers include rate limit info (`X-MBX-*` headers)
- [ ] Response formats match Binance exactly

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
   - [ ] `/fapi/v2/balance` returns account balances
   - [ ] `/fapi/v4/account` returns account information
   - [ ] `/fapi/v2/positionRisk` returns positions
   - [ ] Signature validation succeeds
   - [ ] Timestamp validation works (±5000ms window)

**Document Findings**:
- Testnet availability: ✅/❌
- Response format compatibility: ✅/❌ (note differences)
- Rate limit headers: `X-MBX-USED-WEIGHT-1M`, `X-MBX-ORDER-COUNT-1M`
- HMAC-SHA256 compatibility: ✅/❌
- Any API quirks or differences from Binance

---

## Task 1: Create Core Aster Modules Structure

[D:3/B:7 → Priority:2.33] 🚀

**Purpose**: Set up basic module structure for Aster adapter

**Files to create**:
```
lib/zen_cex/adapters/aster/
├── aster.ex              # Main module with documentation
├── auth.ex               # HMAC SHA256 authentication (may reuse Binance.Auth)
├── endpoints.ex          # Endpoint definitions
├── rate_limiter.ex       # Rate limiting (2400/min weight, 1200/min orders)
├── parser.ex             # Response parsing (check if Binance parser works)
└── websocket.ex          # WebSocket streams (using zen_websocket)
```

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
     Uses HMAC SHA256 signatures (compatible with Binance auth).

     ## Rate Limits
     - Request Weight: 2400/minute
     - Order Limit: 1200/minute
     - IP-based rate limiting

     ## Modules
     - `Aster.UsdmFutures` - Perpetual futures trading
     - `Aster.WebSocket` - Real-time market data streams
     """

     @base_url "https://fapi.asterdex.com"
     @ws_url "wss://fstream.asterdex.com"

     def base_url, do: @base_url
     def websocket_url, do: @ws_url
   end
   ```

2. **Check if we can reuse**:
   - `Binance.Auth` module (likely compatible)
   - `Binance.Parser` logic (needs testing)
   - Req middleware pattern

3. **Endpoints structure**:
   - Use `@endpoints` macro pattern
   - Define futures endpoints
   - Register with `Core.Registry`

**Verification**:
- `mix compile` succeeds
- Modules are accessible in IEx
- Registry recognizes `:aster` exchange

---

## Task 1.5: Create Aster MarketData Module

[D:2/B:7 → Priority:3.5] 🎯

**Purpose**: Implement public market data endpoints module

**File**: `lib/zen_cex/adapters/aster/market_data.ex`

**Pattern to follow**: Copy from `Binance.MarketData` or `Bybit.MarketData`

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

  alias ZenCex.Adapters.Aster.Auth
  alias ZenCex.Adapters.Aster.Parser
  alias ZenCex.Core.HTTP

  # Market data endpoints - manually defined since no OpenAPI spec available
  # Total: 16 public endpoints from Standard API
  @market_data_endpoints %{
    # System Endpoints
    ping: %{
      method: :get,
      path: "/fapi/v1/ping",
      auth: false,
      doc: "Test connectivity to the REST API"
    },
    get_server_time: %{
      method: :get,
      path: "/fapi/v1/time",
      auth: false,
      doc: "Check server time (for timestamp validation)"
    },
    get_exchange_info: %{
      method: :get,
      path: "/fapi/v1/exchangeInfo",
      auth: false,
      doc: "Current exchange trading rules and symbol information"
    },

    # Price & Ticker Data
    get_ticker_price: %{
      method: :get,
      path: "/fapi/v1/ticker/price",
      auth: false,
      doc: "Current price for a symbol or all symbols"
    },
    get_ticker_24hr: %{
      method: :get,
      path: "/fapi/v1/ticker/24hr",
      auth: false,
      doc: "24hr ticker price change statistics"
    },
    get_book_ticker: %{
      method: :get,
      path: "/fapi/v1/ticker/bookTicker",
      auth: false,
      doc: "Best price/qty on the order book"
    },

    # Order Book & Trades
    get_order_book: %{
      method: :get,
      path: "/fapi/v1/depth",
      auth: false,
      doc: "Order book depth"
    },
    get_recent_trades: %{
      method: :get,
      path: "/fapi/v1/trades",
      auth: false,
      doc: "Recent trades list"
    },
    get_historical_trades: %{
      method: :get,
      path: "/fapi/v1/historicalTrades",
      auth: false,
      doc: "Old trade lookup (MARKET_DATA)"
    },
    get_agg_trades: %{
      method: :get,
      path: "/fapi/v1/aggTrades",
      auth: false,
      doc: "Compressed/aggregate trades list"
    },

    # Klines (Candlestick Data)
    get_klines: %{
      method: :get,
      path: "/fapi/v1/klines",
      auth: false,
      doc: "Kline/candlestick bars for a symbol"
    },
    get_index_price_klines: %{
      method: :get,
      path: "/fapi/v1/indexPriceKlines",
      auth: false,
      doc: "Index price kline/candlestick data"
    },
    get_mark_price_klines: %{
      method: :get,
      path: "/fapi/v1/markPriceKlines",
      auth: false,
      doc: "Mark price kline/candlestick data"
    },

    # Futures-Specific Data
    get_mark_price: %{
      method: :get,
      path: "/fapi/v1/premiumIndex",
      auth: false,
      doc: "Mark price and funding rate"
    },
    get_funding_rate: %{
      method: :get,
      path: "/fapi/v1/fundingRate",
      auth: false,
      doc: "Funding rate history"
    },
    get_funding_info: %{
      method: :get,
      path: "/fapi/v1/fundingInfo",
      auth: false,
      doc: "Funding rate config/info"
    }
  }

  # Generate functions for each endpoint
  for {operation, config} <- @market_data_endpoints do
    @doc config.doc
    def unquote(operation)(params \\ %{}, opts \\ []) do
      endpoint_config = %{
        method: unquote(config.method),
        path: unquote(config.path),
        base_url: "https://fapi.asterdex.com"
      }

      # Market data is always public
      opts = Keyword.put(opts, :skip_auth, true)

      HTTP.request(endpoint_config, params, opts)
      |> Parser.parse_response()
    end
  end
end
```

**Note**: Since Aster doesn't have OpenAPI/Postman specs, endpoints are **manually defined** in the module using a simple map + macro pattern. This is simpler than Binance's EndpointLoader approach and works well for smaller APIs.

**Verification**:
- All market data functions compile
- Public endpoints work without auth
- Returns normalized data (atom keys)
- Compatible with Cache.Market

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

**Verification Checklist**:
- [ ] Binance.Auth successfully signs Aster requests
- [ ] `X-MBX-APIKEY` header is added correctly
- [ ] Timestamp is within ±5000ms of server time
- [ ] Signature is accepted by Aster API
- [ ] Authenticated endpoints return 200 status
- [ ] Error responses (401/403) are meaningful
- [ ] No need for custom Aster auth implementation

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

**Integration**:
- Add as Req middleware step
- Track via ETS (`:aster_rate_limits` table)
- Emit telemetry events

**Verification**:
- Rate limits are enforced
- Headers are parsed correctly
- Telemetry events fire
- Status check works: `Aster.RateLimiter.status()`

---

## Task 4: Implement Endpoints and UsdmFutures Module

[D:4/B:8 → Priority:2.0] 🚀

**Purpose**: Define endpoints and create main trading module

**File**: `lib/zen_cex/adapters/aster/endpoints.ex`

**Total Authenticated Endpoints**: 24 (from Standard API documentation)

**Endpoint Categories**:
1. **Account Management** (9 endpoints)
2. **Trading Operations** (10 endpoints)
3. **Position Management** (5 endpoints)

```elixir
defmodule ZenCex.Adapters.Aster.Endpoints do
  @moduledoc """
  Endpoint definitions for Aster Perpetual API.

  Total: 24 authenticated endpoints from Standard API.
  All endpoints require HMAC-SHA256 authentication via Binance.Auth.
  """

  alias ZenCex.Adapters.Aster.Auth
  alias ZenCex.Adapters.Aster.Parser
  alias ZenCex.Core.HTTP

  @base_url "https://fapi.asterdex.com"

  # Helper to make authenticated requests
  defp request(method, path, params, opts) do
    endpoint_config = %{
      method: method,
      path: path,
      base_url: @base_url
    }

    HTTP.request(endpoint_config, params, opts)
    |> Parser.parse_response()
  end

  # ==================== ACCOUNT MANAGEMENT ====================

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

  # ==================== TRADING OPERATIONS ====================

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

  # ==================== POSITION & LEVERAGE MANAGEMENT ====================

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

  # ==================== REGISTRY FUNCTIONS ====================

  def auth, do: Auth
  def base_url, do: @base_url

  def list_operations do
    [
      # Account
      :get_balance, :get_account, :get_positions, :get_user_trades,
      :get_income, :get_leverage_bracket, :get_adl_quantile,
      :get_force_orders, :get_commission_rate,
      # Trading
      :place_order, :place_batch_orders, :cancel_order, :cancel_all_orders,
      :cancel_batch_orders, :cancel_all_and_place, :get_order,
      :get_open_orders, :get_all_orders, :transfer_wallet,
      # Position/Leverage
      :set_position_mode, :get_position_mode, :set_multi_assets_mode,
      :get_multi_assets_mode, :set_leverage, :set_margin_type,
      :modify_isolated_position_margin, :get_position_margin_history
    ]
  end
end
```

**File**: `lib/zen_cex/adapters/aster/usdm_futures.ex`

```elixir
defmodule ZenCex.Adapters.Aster.UsdmFutures do
  @moduledoc """
  Aster Perpetual Futures trading interface.

  Binance-compatible API for perpetual futures trading.
  """

  alias ZenCex.Adapters.Aster.Endpoints

  # Import all endpoint functions
  # Add convenience wrappers
  # Add proper @spec and @doc
end
```

**Registry Integration**:
```elixir
# In Core.Registry
defp init_registry do
  # ...
  {:aster, :usdm_futures} => ZenCex.Adapters.Aster.UsdmFutures,
  # ...
end
```

**Verification**:
- All endpoints compile
- Functions are accessible
- Registry lookup works
- Public endpoints work without auth

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

**Requirements**:
- Return atom keys (consistency with Binance)
- Handle errors properly
- Normalize field names

**Verification**:
- Parser handles all response types
- Returns atom keys consistently
- Error responses are parsed correctly

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

**Stream URL formats** (same as Binance):
- Single stream: `wss://fstream.asterdex.com/ws/btcusdt@trade`
- Combined streams: `wss://fstream.asterdex.com/stream?streams=btcusdt@trade/btcusdt@ticker`

**Verification**:
- Connects to Aster WebSocket
- Receives raw market data messages
- Message handler is called correctly
- Can subscribe/unsubscribe to streams

---

## Task 6.5: WebSocket Cache Integration

[D:3/B:8 → Priority:2.67] 🎯

**Purpose**: Integrate WebSocket data with Cache.Market for unified access

**File**: Update `lib/zen_cex/adapters/aster/websocket.ex` message handler

**Pattern**: Follow `Binance.WebSocket` and `Bybit.WebSocket` cache integration

**Implementation**:
```elixir
defp handle_message({:text, msg}, state) do
  case Jason.decode(msg) do
    {:ok, %{"e" => event_type, "s" => symbol} = data} ->
      update_cache_from_event(event_type, symbol, data, state)

    {:ok, %{"stream" => stream, "data" => data}} ->
      # Combined streams format
      update_cache_from_stream(stream, data, state)

    {:error, reason} ->
      Logger.warning("Failed to parse WebSocket message: #{inspect(reason)}")
      {:ok, state}
  end
end

defp update_cache_from_event("24hrTicker", symbol, data, state) do
  ticker = %{
    symbol: symbol,
    price: data["c"],
    volume: data["v"],
    price_change_percent: data["P"],
    timestamp: System.system_time(:millisecond)
  }
  Market.put_ticker(:aster, symbol, ticker)
  {:ok, state}
end

defp update_cache_from_event("bookTicker", symbol, data, state) do
  book_ticker = %{
    symbol: symbol,
    bid_price: data["b"],
    bid_qty: data["B"],
    ask_price: data["a"],
    ask_qty: data["A"],
    timestamp: System.system_time(:millisecond)
  }
  Market.put_book_ticker(:aster, symbol, book_ticker)
  {:ok, state}
end

defp update_cache_from_event("depthUpdate", symbol, data, state) do
  orderbook = %{
    symbol: symbol,
    bids: data["b"],
    asks: data["a"],
    last_update_id: data["u"],
    timestamp: System.system_time(:millisecond)
  }
  # Use :infinity TTL since WebSocket data is continuously updated
  Market.put_orderbook(:aster, symbol, orderbook, :infinity)
  {:ok, state}
end

defp update_cache_from_event("trade", symbol, data, state) do
  trade = %{
    symbol: symbol,
    price: data["p"],
    quantity: data["q"],
    time: data["T"],
    is_buyer_maker: data["m"]
  }
  Market.put_last_trade(:aster, symbol, trade)
  {:ok, state}
end
```

**Cache functions to use**:
- `Market.put_ticker/3` - 30 second TTL (continuously updated)
- `Market.put_book_ticker/3` - :infinity TTL (continuously updated)
- `Market.put_orderbook/4` - :infinity TTL for WebSocket data
- `Market.put_last_trade/3` - :infinity TTL (always latest)
- `Market.put_24hr_stats/3` - 60 second TTL

**Verification**:
- WebSocket messages update ETS cache
- `Cache.Market.get_ticker(:aster, "BTCUSDT")` returns fresh data
- `Cache.Market.get_book_ticker(:aster, "BTCUSDT")` works
- `Cache.Market.get_orderbook(:aster, "BTCUSDT")` returns depth data
- Timestamp fields are added to cached data

---

## Task 6.6: WebSocket ConnectionRegistry Integration

[D:2/B:6 → Priority:3.0] 🎯

**Purpose**: Register Aster WebSocket connections for reuse

**Files**:
- Update `lib/zen_cex/adapters/aster/websocket.ex`
- Ensure `lib/zen_cex/websocket/connection_registry.ex` supports `:aster`

**Implementation in Aster.WebSocket**:
```elixir
def ensure_connection(exchange, symbol, opts \\ []) do
  alias ZenCex.Websocket.ConnectionRegistry

  case ConnectionRegistry.get(exchange, symbol) do
    {:ok, client} ->
      # Check if connection is still healthy
      case ZenWebsocket.Client.get_state(client) do
        :connected ->
          Logger.debug("Reusing WebSocket connection for #{exchange}:#{symbol}")
          {:ok, client}

        _ ->
          # Connection not healthy, create new one
          Logger.info("Connection unhealthy, creating new connection for #{exchange}:#{symbol}")
          create_and_register_connection(exchange, symbol, opts)
      end

    {:error, :not_found} ->
      # No existing connection, create new one
      create_and_register_connection(exchange, symbol, opts)
  end
end

defp create_and_register_connection(exchange, symbol, opts) do
  # Determine streams based on symbol and exchange
  streams = build_streams_for_symbol(symbol)

  # Connect to WebSocket
  case connect(streams, opts) do
    {:ok, client} ->
      # Register the connection
      :ok = ConnectionRegistry.register(exchange, symbol, client)
      Logger.info("Registered new WebSocket connection for #{exchange}:#{symbol}")
      {:ok, client}

    error ->
      error
  end
end

defp build_streams_for_symbol(symbol) do
  symbol_lower = String.downcase(symbol)
  [
    "#{symbol_lower}@bookTicker",
    "#{symbol_lower}@ticker",
    "#{symbol_lower}@trade"
  ]
end
```

**Verification**:
- `Aster.WebSocket.ensure_connection(:aster, "BTCUSDT")` creates connection
- Second call reuses existing connection
- `ConnectionRegistry.get(:aster, "BTCUSDT")` returns client
- `ConnectionRegistry.list_all()` includes Aster connections
- `ConnectionRegistry.check_health(:aster, "BTCUSDT")` works

---

## Task 7: Add Integration Tests

[D:4/B:6 → Priority:1.5] 🚀

**Purpose**: Create integration tests for Aster adapter

**File**: `test/zen_cex/adapters/aster/integration_test.exs`

**Requirements**:
```elixir
defmodule ZenCex.Adapters.Aster.IntegrationTest do
  use ZenCex.IntegrationCase, exchange: :aster, api_type: :usdm_futures

  @moduletag :aster
  @moduletag :integration

  alias ZenCex.Adapters.Aster.UsdmFutures

  describe "public endpoints (no auth)" do
    test "get_server_time/0" do
      assert {:ok, %{server_time: time}} = UsdmFutures.get_server_time()
      assert is_integer(time)
    end

    test "get_ticker_price/1" do
      assert {:ok, %{symbol: "BTCUSDT", price: price}} =
        UsdmFutures.get_ticker_price(%{symbol: "BTCUSDT"})
      assert is_number(price)
    end
  end

  describe "authenticated endpoints" do
    @describetag :authenticated

    test "get_account/0", %{api_key: key, api_secret: secret} do
      opts = [auth_credentials: %{api_key: key, api_secret: secret}]
      assert {:ok, account} = UsdmFutures.get_account(%{}, opts)
      assert is_map(account)
    end
  end

  describe "trading operations" do
    @describetag :write_operation

    test "place_order/2" do
      # Skip or implement with testnet
    end
  end
end
```

**WebSocket tests**:
```elixir
defmodule ZenCex.Adapters.Aster.WebSocketTest do
  use ExUnit.Case

  @moduletag :aster
  @moduletag :websocket

  describe "market data streams" do
    test "connects and receives trade data" do
      {:ok, client} = Aster.WebSocket.connect(["btcusdt@trade"])
      Process.sleep(2000)

      assert {:ok, data} = Cache.Market.get_last_trade(:aster, "BTCUSDT")
      assert is_map(data)

      Aster.WebSocket.close(client)
    end
  end
end
```

**Verification**:
- All tests pass with testnet
- Public endpoints work without auth
- Authenticated endpoints require credentials
- WebSocket streams update cache

---

## Task 7.5: Add Safety.OrderSafety.MarketData Support

[D:2/B:8 → Priority:4.0] 🎯

**Purpose**: Integrate Aster with the OrderSafety market data system

**File**: `lib/zen_cex/safety/order_safety/market_data.ex`

**Changes required**:

### 1. Add Aster symbol info fetching:

```elixir
defp fetch_symbol_info_from_exchange(:aster, symbol) do
  alias ZenCex.Adapters.Aster.MarketData

  case MarketData.get_exchange_info() do
    {:ok, %{symbols: symbols}} ->
      case Enum.find(symbols, fn s -> s[:symbol] == symbol end) do
        nil -> {:error, :symbol_not_found}
        symbol_info -> {:ok, symbol_info}
      end

    error ->
      error
  end
end
```

### 2. Add Aster price fetching:

```elixir
defp fetch_price_from_exchange(:aster, symbol) do
  alias ZenCex.Adapters.Aster.MarketData

  case MarketData.get_ticker_price(%{symbol: symbol}) do
    {:ok, %{price: price_str}} ->
      DecimalUtils.safe_parse_decimal(price_str)

    error ->
      error
  end
end
```

### 3. Add Aster balance fetching (if needed):

```elixir
defp fetch_balance(:aster, asset, opts) do
  alias ZenCex.Adapters.Aster.UsdmFutures

  # Aster is futures-only, balances are in USDT
  case UsdmFutures.get_balance(%{}, opts) do
    {:ok, balances} when is_list(balances) ->
      case Enum.find(balances, fn b -> b[:asset] == asset end) do
        nil -> {:ok, Decimal.new("0")}
        balance -> DecimalUtils.safe_parse_decimal(balance[:balance])
      end

    error ->
      error
  end
end
```

### 4. Ensure WebSocket integration:

The existing `fetch_price_from_websocket/2` should work automatically once:
- `Cache.Market` is updated by `Aster.WebSocket` (Task 6.5)
- `ConnectionRegistry` tracks Aster connections (Task 6.6)

No changes needed to the WebSocket fallback logic - it will work once cache is populated.

**Verification**:
```elixir
# Test with Tidewave
alias ZenCex.Safety.OrderSafety.MarketData

# Symbol info
{:ok, info} = MarketData.fetch_symbol_info(:aster, "BTCUSDT")
assert info[:symbol] == "BTCUSDT"
assert info[:status] == "TRADING"

# Price fetching (REST)
{:ok, price} = MarketData.fetch_current_price(:aster, "BTCUSDT")
assert Decimal.gt?(price, Decimal.new("0"))

# WebSocket price (after WebSocket is running)
Aster.WebSocket.ensure_connection(:aster, "BTCUSDT")
Process.sleep(2000)  # Wait for data
{:ok, price} = MarketData.fetch_current_price(:aster, "BTCUSDT")
# Should come from WebSocket cache, not REST
```

**Integration points**:
- Used by `ZenCex.Safety.OrderSafety` for order validation
- Provides symbol filters (min_notional, price_precision, etc.)
- Supports both REST and WebSocket data sources
- Caches data to reduce API calls

---

## Task 8: Create Example Module

[D:3/B:5 → Priority:1.67] 🚀

**Purpose**: Create usage examples for Aster

**File**: `lib/examples/aster_trading.ex`

```elixir
defmodule ZenCex.Examples.AsterTrading do
  @moduledoc """
  Example usage of Aster Perpetual Pro API.

  Demonstrates:
  - Market data access
  - Account information
  - Order placement
  - Position management
  - WebSocket streams
  """

  alias ZenCex.Adapters.Aster.{UsdmFutures, WebSocket}
  alias ZenCex.Cache.Market

  @doc """
  Check Aster server connectivity.

  ## Example
      iex> AsterTrading.check_connectivity()
      {:ok, %{server_time: 1704470400000}}
  """
  def check_connectivity do
    UsdmFutures.get_server_time()
  end

  @doc """
  Get current BTCUSDT price.
  """
  def get_btc_price do
    UsdmFutures.get_ticker_price(%{symbol: "BTCUSDT"})
  end

  @doc """
  Get account balances and positions.
  """
  def get_account_info do
    # Get from environment or pass explicitly
    api_key = System.get_env("ASTER_TESTNET_API_KEY")
    api_secret = System.get_env("ASTER_TESTNET_API_SECRET")

    opts = [
      auth_credentials: %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: true
      }
    ]

    with {:ok, account} <- UsdmFutures.get_account(%{}, opts),
         {:ok, positions} <- UsdmFutures.get_positions(%{}, opts) do
      {:ok, %{account: account, positions: positions}}
    end
  end

  @doc """
  Connect to real-time market data stream.
  """
  def connect_market_stream(symbol) do
    streams = [
      "#{String.downcase(symbol)}@trade",
      "#{String.downcase(symbol)}@ticker"
    ]

    WebSocket.connect(streams)
  end

  @doc """
  Get cached market data from WebSocket.
  """
  def get_cached_data(symbol) do
    %{
      ticker: Market.get_ticker(:aster, symbol),
      last_trade: Market.get_last_trade(:aster, symbol)
    }
  end
end
```

**Verification**:
- All examples work
- Documentation is clear
- Testnet examples included

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
   - Uses `EndpointRegistry` macro for auto-generated functions
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

---

_Add new session notes above this line_
