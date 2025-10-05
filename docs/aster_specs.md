# Aster Exchange Integration Specification

This document contains numbered tasks for implementing Aster exchange support in ZenCex.

## Status: PENDING

---

## 🔄 CONTINUATION PROMPT (Update at end of each session)

**Last Updated**: 2025-10-05 (Session 0)

**For next session, start with**:
```
Continue implementing Aster exchange support from docs/aster_specs.md.

Current status: Not started.
Next: Task 0 (API verification and testnet access).

Key points:
- Aster uses Binance-compatible API structure (HMAC SHA256)
- Base URLs: https://fapi.asterdex.com (REST), wss://fstream.asterdex.com (WebSocket)
- Can reuse ~90% of Binance patterns
- Rate limits: 2400 weight/min, 1200 orders/min
- Web3 auth is for deposits/withdrawals (out of scope)

Begin: "Starting Aster integration from docs/aster_specs.md - Task 0..."
```

**What to update at end of each session**:
1. Update "Last Updated" date and session number
2. Update "Current status" with completed tasks
3. Update "Next" with the next task number and name
4. If all tasks done, change Status to "COMPLETED"

---

## Overview

**Exchange**: Aster Perpetual Pro
**API Docs**: https://docs.asterdex.com/product/aster-perpetual-pro/api/api-documentation
**GitHub**: https://github.com/asterdex/api-docs

**API Compatibility**: Binance-compatible
- HMAC SHA256 authentication (same as Binance)
- Same endpoint structure (`/fapi/v1/*`)
- `X-MBX-APIKEY` header for API key
- Similar rate limiting model

**Base URLs**:
- REST: `https://fapi.asterdex.com`
- WebSocket: `wss://fstream.asterdex.com`

**Rate Limits**:
- Request Weight: 2400/min
- Order Limit: 1200/min
- IP-based rate limiting

**Scope**:
- Perpetual futures trading (similar to Binance USD-M Futures)
- Market data (ticker, orderbook, trades, klines)
- WebSocket streams (same as Binance futures streams)

---

## Task 0: API Verification and Testnet Access

[D:2/B:8 → Priority:4.0] 🎯

**Purpose**: Verify Aster API structure and obtain testnet credentials

**Actions**:
1. **Verify API compatibility**:
   - Check if Aster has testnet environment
   - Test public endpoints (ping, server time, ticker)
   - Verify authentication method (HMAC SHA256)
   - Compare response formats with Binance

2. **Get testnet credentials** (if available):
   - Register for testnet access
   - Set environment variables:
     - `ASTER_TESTNET_API_KEY`
     - `ASTER_TESTNET_API_SECRET`

3. **Test authenticated endpoints**:
   - Account information
   - Open orders
   - Positions

4. **Document findings**:
   - Testnet availability (yes/no)
   - Response format differences vs Binance
   - Rate limit headers
   - Any API quirks or differences

**Tools to use**:
- `mcp__tidewave__project_eval` - Test API calls
- WebFetch - Check documentation
- Bash - curl commands for API testing

**Expected output**: Verification report with:
- ✅/❌ Testnet availability
- Example API responses
- Any differences from Binance API
- Credential setup instructions

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

## Task 2: Implement Authentication

[D:2/B:6 → Priority:3.0] 🎯

**Purpose**: Implement HMAC SHA256 authentication for Aster

**File**: `lib/zen_cex/adapters/aster/auth.ex`

**Options**:

### Option A: Reuse Binance.Auth (if compatible)
```elixir
defmodule ZenCex.Adapters.Aster.Auth do
  @moduledoc """
  HMAC SHA256 authentication for Aster (Binance-compatible).
  Delegates to Binance.Auth implementation.
  """

  defdelegate sign_request(request, api_key, api_secret),
    to: ZenCex.Adapters.Binance.Auth
end
```

### Option B: Custom implementation (if differences found)
```elixir
defmodule ZenCex.Adapters.Aster.Auth do
  @moduledoc """
  HMAC SHA256 authentication for Aster.
  """

  def sign_request(%Req.Request{} = request, api_key, api_secret) do
    # Implement signature logic
    # Add X-MBX-APIKEY header
    # Add timestamp
    # Generate HMAC SHA256 signature
  end
end
```

**Testing with Tidewave**:
```elixir
# Test if Binance auth works with Aster
alias ZenCex.Adapters.{Binance, Aster}

# Create test request
request = Req.new(url: "#{Aster.base_url()}/fapi/v1/account")

# Try Binance auth
signed = Binance.Auth.sign_request(request, api_key, api_secret)

# Execute and verify
{:ok, response} = Req.request(signed)
```

**Verification**:
- Authenticated requests succeed
- Signature is accepted by Aster API
- Error responses are meaningful

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

**Endpoints to implement** (based on Binance futures):

```elixir
defmodule ZenCex.Adapters.Aster.Endpoints do
  @moduledoc """
  Endpoint definitions for Aster Perpetual API.
  """

  @endpoints [
    # Market Data
    {:get_server_time, :get, "/fapi/v1/time", :none},
    {:get_ticker_price, :get, "/fapi/v1/ticker/price", :none},
    {:get_ticker_24hr, :get, "/fapi/v1/ticker/24hr", :none},
    {:get_order_book, :get, "/fapi/v1/depth", :none},
    {:get_recent_trades, :get, "/fapi/v1/trades", :none},
    {:get_klines, :get, "/fapi/v1/klines", :none},
    {:get_funding_rate, :get, "/fapi/v1/fundingRate", :none},
    {:get_open_interest, :get, "/fapi/v1/openInterest", :none},

    # Account & Trading
    {:get_account, :get, "/fapi/v1/account", :signed},
    {:get_balance, :get, "/fapi/v1/balance", :signed},
    {:get_positions, :get, "/fapi/v2/positionRisk", :signed},
    {:place_order, :post, "/fapi/v1/order", :signed},
    {:cancel_order, :delete, "/fapi/v1/order", :signed},
    {:get_order, :get, "/fapi/v1/order", :signed},
    {:get_open_orders, :get, "/fapi/v1/openOrders", :signed},

    # Position & Leverage
    {:set_leverage, :post, "/fapi/v1/leverage", :signed},
    {:set_margin_type, :post, "/fapi/v1/marginType", :signed},
  ]

  # Use macro to generate functions (copy from Binance pattern)
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

## Task 6: Implement WebSocket Support

[D:5/B:7 → Priority:1.4] 📋

**Purpose**: Add WebSocket streaming for market data

**File**: `lib/zen_cex/adapters/aster/websocket.ex`

**Pattern to follow**: Copy from `Binance.WebSocket`

```elixir
defmodule ZenCex.Adapters.Aster.WebSocket do
  @moduledoc """
  WebSocket client for Aster real-time market data.

  Supports Binance-compatible stream formats:
  - Trade streams: `<symbol>@trade`
  - Ticker streams: `<symbol>@ticker`
  - Order book: `<symbol>@depth`
  - Kline/Candlestick: `<symbol>@kline_<interval>`
  """

  @base_url "wss://fstream.asterdex.com"

  def connect(streams, opts \\ []) do
    # Use zen_websocket.Client
    # Format stream URL
    # Handle callbacks
  end

  def subscribe(client, streams) do
    # Subscribe to additional streams
  end
end
```

**Stream formats** (same as Binance):
- Single stream: `wss://fstream.asterdex.com/ws/btcusdt@trade`
- Combined streams: `wss://fstream.asterdex.com/stream?streams=btcusdt@trade/btcusdt@ticker`

**Cache integration**:
```elixir
# Update Cache.Market for :aster exchange
def handle_message({:text, msg}, state) do
  data = Jason.decode!(msg)

  # Parse stream type and symbol
  # Update ETS cache
  Cache.Market.update(:aster, symbol, data)

  {:ok, state}
end
```

**Verification**:
- Connects to Aster WebSocket
- Receives market data
- Updates cache correctly
- `Cache.Market.get_ticker(:aster, "BTCUSDT")` works

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

---

## Notes

### Reusable Components
Since Aster is Binance-compatible, we can likely reuse:
- ✅ `Binance.Auth` - HMAC SHA256 signing
- ✅ Req middleware pattern
- ✅ Endpoint registry pattern
- ✅ WebSocket message handling
- ⚠️ `Binance.Parser` - needs verification
- ⚠️ Response normalization - verify atom keys

### Unique Aspects
- Different base URLs
- Different rate limits (2400/min vs Binance)
- May have different response formats (needs testing)
- Different WebSocket URL

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
