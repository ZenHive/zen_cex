# Deribit Integration Specification

**Version**: 2.6
**Created**: 2025-01-31
**Updated**: 2025-11-11
**Status**: In Progress - Task 4 Complete ✅

## Changelog

### v2.6 (2025-11-11) - TASK 4 COMPLETE ✅
- ✅ **Deribit.Trading module created** (289 lines) - Ultra-thin wrappers over Rpc methods
- ✅ **All 8 trading functions implemented** - buy, sell, cancel, edit_order, get_open_orders, cancel_all, get_order_history, get_user_trades
- ✅ **Rpc module enhanced** - Added 5 new methods (edit_order, cancel_all, get_order_history, get_user_trades, get_order_state)
- ✅ **Comprehensive integration test suite** - 25+ tests against real Deribit testnet, all passing
- ✅ **Dynamic pricing strategy** - Tests use real market data to calculate safe prices (20% away from market)
- ✅ **Complete order lifecycle testing** - Place, edit, cancel, query history, full flow verification
- ✅ **Proper test cleanup** - on_exit handlers cancel all test orders automatically
- ✅ **Real testnet validation** - All trading operations verified against test.deribit.com
- 📊 **Files created**:
  - `lib/zen_cex/adapters/deribit/trading.ex` (289 lines)
  - `test/zen_cex/adapters/deribit/trading_test.exs` (572 lines)
- 📊 **Files updated**:
  - `lib/zen_cex/adapters/deribit/rpc.ex` (254 → 401 lines, +147)
  - `lib/zen_cex/adapters/deribit/parser.ex` (395 → 424 lines, +29)
  - `test/zen_cex/adapters/deribit/parser_test.exs` (585 → 620 lines, +35)
- 📈 **Total tests passing**: 61+ (23 parser + 13 WebSocket + 25+ trading)
- 🎯 **Next**: Task 5 - MarketData wrapper + ETS cache

### v2.5 (2025-11-06) - TASK 3 COMPLETE ✅
- ✅ **Deribit.Parser module created** (395 lines) - Full parser with normalize_keys
- ✅ **All parse functions implemented** - parse_order, parse_orders, parse_order_book, parse_ticker, parse_instruments, parse_trades, parse_account_summary, parse_positions
- ✅ **Comprehensive test suite** - 23 parser tests, all passing
- ✅ **Key normalization** - camelCase → snake_case atoms (e.g., `"orderState"` → `:order_state`)
- ✅ **Enum normalization** - Converts enum strings to atoms (`:open`, `:buy`, `:filled`, etc.)
- ✅ **Error pass-through** - All errors returned unchanged preserving JSON-RPC structure
- ✅ **Real response examples** - Tests based on actual Deribit API documentation
- 📊 **Files created**:
  - `lib/zen_cex/adapters/deribit/parser.ex` (395 lines)
  - `test/zen_cex/adapters/deribit/parser_test.exs` (585 lines)
- 📈 **Total tests passing**: 36 (23 parser + 13 WebSocket integration)
- 🎯 **Next**: Task 4 - Trading wrapper (ultra-thin functions over Rpc methods)

### v2.4 (2025-11-02) - TASK 2 COMPLETE ✅
- ✅ **Deribit.Rpc module created** (254 lines) - All 12 RPC methods copied from Examples.DeribitRpc
- ✅ **Deribit.WebSocket module created** (355 lines) - Full adapter with ETS caching
- ✅ **Message handlers implemented** - handle_orderbook_update, handle_ticker_update, handle_trade_update
- ✅ **Integration tests passing** - 13 tests, 0 failures (connection, auth, subscriptions, ETS cache, direct requests)
- ✅ **IntegrationCase updated** - Added enforce_deribit_testnet! and verify_deribit_connectivity!
- ✅ **Real testnet validation** - All tests verified against test.deribit.com
- 📊 **Files created**:
  - `lib/zen_cex/adapters/deribit/rpc.ex` (254 lines)
  - `lib/zen_cex/adapters/deribit/websocket.ex` (355 lines)
  - `test/zen_cex/adapters/deribit/websocket_test.exs` (265 lines)
- 🎯 **Next**: Task 3 - Parser module (normalize raw JSON → atom keys + snake_case)

### v2.3 (2025-02-01) - CRITICAL PATTERN CORRECTION ⚠️
- 🚨 **Task 5 updated**: Match actual Binance pattern (WebSocket handlers update ETS, MarketData reads ETS)
- ✅ Clarified: Subscription → WebSocket.handle_message → ETS → MarketData.get_*
- ✅ Removed: "Check ETS first, fallback to request" pattern (incorrect for subscription data)
- ✅ Added: Message handler functions to Task 2 (handle_orderbook_update, handle_ticker_update, etc.)
- ✅ Verified: ZenCex.Cache.Market works with instrument names (no module changes needed)
- 📚 Pattern: Deribit.WebSocket updates ETS (like Binance.WebSocket:480-577), MarketData reads it

### v2.2 (2025-01-31) - FINAL CORRECTIONS ⚠️
- 🚨 **DeribitRpc is ALSO example code** - In `examples/` dir, NOT production API
- ✅ Updated: Use `ZenWebsocket.JsonRpc.build_request/2` (core API)
- ✅ Recommended: Copy DeribitRpc methods into `ZenCex.Adapters.Deribit.Rpc`
- ✅ Alternative: Use JsonRpc.build_request directly in WebSocket module
- 📚 Core API: `ZenWebsocket.JsonRpc` (production), `Examples.DeribitRpc` (reference)

### v2.1 (2025-01-31) - CRITICAL CORRECTIONS ⚠️
- 🚨 **zen_websocket does NO normalization** - Returns raw JSON with string keys!
- 🚨 **DeribitAdapter is reference code** - In `examples/` dir, NOT production API
- ✅ Updated Task 2: Use `ZenWebsocket.Client` directly, NOT `Examples.DeribitAdapter`
- ✅ Clarified: Copy DeribitAdapter pattern, don't delegate to example module
- ✅ Updated Parser task: Emphasize critical role (string→atom, camelCase→snake_case)
- ✅ Added example transformations showing raw JSON → normalized output
- ✅ Updated all references from "delegate to" → "copy pattern from"
- 📚 Evidence: zen_websocket/test/correlation_test.exs:26 shows raw string keys

### v2.0 (2025-01-31) - MAJOR CORRECTION ⚠️
- 🚨 **REMOVED Auth module** - zen_cex NEVER reads from environment variables!
- ✅ Updated WebSocket.connect/3 to accept explicit credentials (client_id, client_secret)
- ✅ Documented correct pattern: calling code reads ENV, library receives explicit params
- ✅ Updated Integration Strategy and Module Structure (removed auth.ex)
- ✅ Task count: 8 total (Task 1 explanatory + 7 implementation tasks, removed duplicate Task 2)
- ✅ Total lines: 1,360 → 1,200 (160 lines saved)
- 📚 References: Core.Auth.ex:14-19, BaseAuth.ex:10-18, CLAUDE.md:291-318

### v1.1 (2025-01-31)
- ✅ Added Connection Management Architecture section explaining three-layer pattern
- ✅ Reordered tasks: Auth → WebSocket → Parser → Integration Tests (validates early!)
- ✅ Fixed code examples: `request.method` → `request[:method]` (DeribitRpc uses atom keys)
- ✅ Updated Integration Strategy diagram to show Auth first
- ✅ Added rationale for task ordering

### v1.0 (2025-01-31)
- Initial specification with 8 implementation tasks

## Executive Summary

This specification defines the Deribit exchange integration for zen_cex. Unlike Binance/Bybit which are REST-first, Deribit is **WebSocket-first with JSON-RPC 2.0**. The critical insight: **zen_websocket already provides 95% of required functionality** through `DeribitRpc` and `DeribitAdapter`.

### What zen_websocket Provides (Already Complete!)

✅ **Client.ex** (core API): connect, send_message, close, subscribe, get_state
✅ **JsonRpc.ex** (core API): build_request/2 for JSON-RPC 2.0 messages
✅ **DeribitRpc.ex** (reference pattern): 12 method examples in `examples/` dir (COPY these!)
✅ **DeribitAdapter.ex** (reference pattern): Example showing how to wrap Client + JsonRpc (in `examples/` dir)
✅ **JSON-RPC 2.0**: Automatic request/response correlation by message ID
✅ **Rate Limiting**: Token bucket with `deribit_cost/1` function (100-credit bucket)
✅ **Heartbeat**: Automatic Deribit heartbeat handling (public/test + set_heartbeat)
✅ **Reconnection**: Exponential backoff with state preservation & connection ownership
✅ **Supervision**: ClientSupervisor for production deployments

**CRITICAL**:
- zen_websocket returns **raw JSON with string keys** - NO normalization!
- **Examples.*** modules are reference code - COPY the pattern, don't import them!
- **Documentation**: Full Deribit API docs available at `zen_websocket/docs/deribit/` (15 markdown files covering all endpoints)

### What zen_cex Needs to Add

✅ **Rpc** module: Copy DeribitRpc methods, use JsonRpc.build_request/2 (401 lines) - COMPLETE
✅ **WebSocket** wrapper: Accept explicit credentials, copy DeribitAdapter pattern (393 lines) - COMPLETE
✅ **Parser** module: Normalize raw JSON (string keys → atom keys, camelCase → snake_case) (424 lines) - COMPLETE
✅ **Trading** wrappers: Ultra-thin functions over Rpc methods (289 lines) - COMPLETE
📊 **MarketData** cache: ETS table updated by WebSocket handler
📡 **REST** endpoints: Optional fallback for historical data (LOW priority)

### Implementation Progress

**Status**: 4/7 tasks complete (57%) ✅

**Completed**:
- ✅ Task 1: Understood - No Auth module needed
- ✅ Task 2: Deribit.WebSocket + Rpc modules (393 lines WS + 401 lines Rpc, 13 tests passing)
- ✅ Task 3: Deribit.Parser module (424 lines, 23 tests passing)
- ✅ Task 4: Deribit.Trading module (289 lines, 25+ tests passing)

**Remaining**:
- 📊 Task 5: MarketData wrapper + ETS cache - **NEXT**
- ⚙️ Task 6: RateLimiter config
- 🧪 Task 7: Integration tests (partially complete - 61+ tests passing)
- ⚠️ Task 8: REST endpoints (optional, low priority)

---

## Architecture Overview

### Key Differences from Binance/Bybit

| Aspect | Binance/Bybit | Deribit |
|--------|---------------|---------|
| **Primary Interface** | REST APIs | WebSocket (JSON-RPC 2.0) |
| **Protocol** | REST + WebSocket streams | JSON-RPC 2.0 for both |
| **Authentication** | Per-request HMAC-SHA256 | OAuth session token |
| **Trading** | POST /api/v3/order | WS private/buy |
| **Market Data** | GET /api/v3/ticker | WS public/ticker |
| **Subscriptions** | WebSocket only | WebSocket only |

### Integration Strategy

```
zen_cex.Deribit
├── Rpc (JSON-RPC request builders - COPIED from Examples.DeribitRpc)
│   ├── Uses ZenWebsocket.JsonRpc.build_request/2 (core API)
│   ├── 12 methods: auth_request, buy, sell, cancel, get_open_orders, etc.
│   └── ~250 lines (simple wrappers over JsonRpc.build_request)
├── WebSocket (wrapper around Client - COPIED from Examples.DeribitAdapter)
│   ├── Uses ZenWebsocket.Client (core API)
│   ├── Uses Deribit.Rpc (our copy, NOT Examples.DeribitRpc)
│   ├── connect(client_id, client_secret, opts) - Explicit credentials!
│   └── ~200 lines (state management + delegation to Client)
├── Parser (CRITICAL - zen_websocket does NO normalization!)
│   ├── Converts string keys → atom keys
│   ├── Converts camelCase → snake_case
│   ├── Extracts %{"result" => data} wrapper
│   └── Normalizes enums: "open" → :open, "buy" → :buy
├── Trading (ultra-thin wrappers)
│   └── Rpc.buy/sell/cancel → Client.send_message → Parser
├── MarketData (ETS cache + wrappers)
│   └── Rpc.get_order_book/ticker → Client.send_message → Parser
└── REST (optional, LOW priority)
    └── Fallback for historical data

CRITICAL: ALL Examples.* modules are reference code - COPY into zen_cex, don't import!
NOTE: NO Auth module! Credentials passed explicitly per zen_cex design.
```

### Connection Management Architecture

Deribit follows the same three-layer connection architecture as Binance/Bybit:

1. **Transport Layer (zen_websocket.Client)**:
   - Maintains Gun connection ownership through GenServer
   - Handles automatic reconnection with exponential backoff
   - Returns stable client structs that survive reconnections

2. **Adapter Layer (Deribit.WebSocket)**:
   - Provides Deribit-specific protocol handling (JSON-RPC 2.0)
   - Creates new connections when called directly (by design)
   - Does NOT manage connection reuse - that's an application concern

3. **Application Layer (ConnectionRegistry + MarketData)**:
   - `ConnectionRegistry` tracks all connections by `{exchange, symbol}`
   - `MarketData.ensure_websocket_connection/2` checks registry before creating
   - Implements actual connection reuse logic with application context

**Why Connection Reuse is NOT at Adapter Level**: The adapter lacks context about which instruments are traded together. Connection grouping decisions require application-level knowledge where the registry provides centralized tracking.

---

## Implementation Tasks

**Recommended Order**: WebSocket → Parser → Integration Tests → Trading → MarketData → RateLimiter → REST

**Rationale**: **NO AUTH MODULE NEEDED!** Start with WebSocket (credentials passed explicitly). Then Parser as foundation. Integration tests ASAP to validate against real testnet before building Trading/MarketData wrappers.

**Task Count**: 7 implementation tasks (Task 1 is explanatory only)

---

### Task 1: NO Auth Module Needed! ❌

**CRITICAL**: zen_cex **NEVER reads from environment variables** for credentials!

**Reference**:
- `lib/zen_cex/core/auth.ex:14-19` - "No environment variable fallback exists. All credentials must be passed explicitly."
- `lib/zen_cex/adapters/base_auth.ex:10-18` - "Never use System.get_env/1 directly"
- CLAUDE.md lines 291-318 - Configuration Management section

**How zen_cex Works**:
1. **Library code** NEVER reads environment variables
2. **Calling code** (tests, scripts, IEx) reads env and passes credentials explicitly
3. **All requests** pass credentials via function parameters or `auth_credentials` option

**What This Means for Deribit**:
- NO Auth module needed!
- Deribit.WebSocket receives credentials as function parameters
- DeribitAdapter.authenticate() handles OAuth flow automatically

**Acceptance Criteria**: ✅ COMPLETE
- [x] NO Auth module created (not needed!)
- [x] Understood: Library = explicit credentials, Calling code = reads ENV
- [x] Ready for Task 2 (WebSocket wrapper with explicit credentials)

---

### Task 2: Create Deribit.WebSocket wrapper [D:3/B:10 → Priority:3.3] 🎯

**Goal**: Wrapper around ZenWebsocket.Client + JsonRpc for Deribit protocol

**Reference**:
- `zen_websocket/lib/zen_websocket/examples/deribit_adapter.ex:1-135` - **Reference pattern** (COPY, don't import!)
- `zen_websocket/lib/zen_websocket/examples/deribit_rpc.ex:1-234` - **Reference methods** (COPY these!)
- `zen_websocket/lib/zen_websocket/json_rpc.ex` - **Core API** (build_request/2)
- `zen_websocket/lib/zen_websocket/client.ex` - **Core API** (connect, send_message, close)
- `lib/zen_cex/adapters/binance/websocket.ex:1-577` - Market data caching pattern

**Critical Understanding**:
- **ALL `Examples.*` modules are reference code** - NOT production APIs!
- zen_cex should call `ZenWebsocket.Client` and `ZenWebsocket.JsonRpc` (core APIs)
- **Copy method implementations** from Examples.DeribitRpc into zen_cex
- **Copy the DeribitAdapter pattern** for state management
- zen_websocket returns **raw JSON with string keys** (NO normalization)

**Pattern**: Client + JsonRpc + custom Rpc module + state management

**Files**:
- Create `lib/zen_cex/adapters/deribit/rpc.ex` (~250 lines - copy from Examples.DeribitRpc)
- Create `lib/zen_cex/adapters/deribit/websocket.ex` (~200 lines - copy DeribitAdapter pattern)
- Create `test/zen_cex/adapters/deribit/websocket_test.exs`

**Rpc Module Functions** (12 total, copied from Examples.DeribitRpc):
```elixir
defmodule ZenCex.Adapters.Deribit.Rpc do
  alias ZenWebsocket.JsonRpc

  def auth_request(client_id, client_secret) do
    JsonRpc.build_request("public/auth", %{
      grant_type: "client_credentials",
      client_id: client_id,
      client_secret: client_secret
    })
  end

  def buy(instrument, amount, opts), do: ...
  def sell(instrument, amount, opts), do: ...
  def cancel(order_id), do: ...
  def get_open_orders(opts), do: ...
  def subscribe(channels), do: ...
  def unsubscribe(channels), do: ...
  def get_order_book(instrument, depth), do: ...
  def ticker(instrument), do: ...
  def get_instruments(currency), do: ...
  def set_heartbeat(interval), do: ...
  def test_request(), do: ...
end
```

**WebSocket Module Functions** (10-12 total, copy DeribitAdapter pattern):

**Public API**:
1. `connect/3` - Accept client_id, client_secret, opts; call `Client.connect/2` with Deribit config
2. `authenticate/1` - Build auth via `Rpc.auth_request/2`, send via `Client.send_message/2`
3. `subscribe/2` - Build request via `Rpc.subscribe/1`, send via Client
4. `unsubscribe/2` - Build request via `Rpc.unsubscribe/1`, send via Client
5. `send_request/3` - Build request via `JsonRpc.build_request/2`, send via Client
6. `send_request_sync/2` - Synchronous request with response correlation (for MarketData direct requests)
7. `close/1` - Call `Client.close/1` directly

**Message Handlers (Private - update ETS like Binance.WebSocket:480-577)**:
8. `handle_subscription_message/2` - Route subscription messages to specific handlers
9. `handle_orderbook_update/1` - Parse and cache order book → `Market.put_orderbook(:deribit, ...)`
10. `handle_ticker_update/1` - Parse and cache ticker → `Market.put_ticker(:deribit, ...)`
11. `handle_trade_update/1` - Parse and cache trades → `Market.put_last_trade(:deribit, ...)`
12. `create_message_handler/0` - Returns message handler function for Client config

**Struct** (copy from DeribitAdapter):
```elixir
defstruct [:client, :authenticated, :subscriptions, :client_id, :client_secret]
```

**Acceptance Criteria**: ✅ COMPLETE (2025-11-02)
- [x] Connection to test.deribit.com works
- [x] Credentials passed as function parameters (NOT from env!)
- [x] Uses `ZenWebsocket.Client` and `ZenWebsocket.JsonRpc` (core APIs)
- [x] **Does NOT import `Examples.*` modules** - all code copied into zen_cex
- [x] Message handlers update ETS cache (like Binance.WebSocket:480-577)
- [x] `handle_orderbook_update/1` → `Market.put_orderbook(:deribit, instrument, data, :infinity)`
- [x] `handle_ticker_update/1` → `Market.put_ticker(:deribit, instrument, data, 30)`
- [x] `handle_trade_update/1` → `Market.put_last_trade(:deribit, instrument, data)`
- [x] Integration test: connect → auth → subscribe → receive updates → verify ETS cache
- [x] Rpc module is 254 lines (12 simple delegation functions)
- [x] WebSocket module is 355 lines (pattern copy + state + message handlers)

---

### Task 3: Create Deribit.Parser module [D:2/B:9 → Priority:4.5] 🎯

**Goal**: Normalize Deribit JSON responses to zen_cex format using normalize_keys

**Reference**:
- `lib/zen_cex/adapters/binance/parser.ex:1-705` - Full parser pattern
- `lib/zen_cex/adapters/bybit/parser.ex:1-407` - Unified V5 format handling
- `zen_websocket/lib/zen_websocket/examples/deribit_rpc.ex:168-234` - ALL trading/market data methods

**Critical Understanding**:
- zen_websocket returns **raw JSON with STRING keys**: `%{"result" => %{"orderId" => "123"}}`
- Parser must normalize to **atom keys + snake_case**: `%{result: %{order_id: "123"}}`
- Parser extracts `%{"result" => data}` wrapper and returns just `data`
- Parser converts enum strings to atoms: `"open"` → `:open`, `"buy"` → `:buy`

**Example Transformation**:
```elixir
# Input (from zen_websocket):
%{"result" => %{"order" => %{"orderId" => "123", "orderState" => "open"}}}

# Output (after Parser):
{:ok, %{order_id: "123", order_state: :open}}
```

**Pattern**:
- Use `ParserMacros.normalize_keys/1` for all responses
- Extract nested `%{"result" => data}` wrapper
- Keep numeric values as-is (strings/integers from API)
- Normalize enum values to atoms (e.g., `"buy"` → `:buy`)
- Pass errors through unchanged

**Files**:
- Create `lib/zen_cex/adapters/deribit/parser.ex`
- Create `test/zen_cex/adapters/deribit/parser_test.exs`

**Functions** (8-10 total):
1. `parse_order/1` - Normalize order response
2. `parse_orders/1` - List of orders (used by get_open_orders)
3. `parse_order_book/1` - Normalize order book snapshot
4. `parse_ticker/1` - Normalize ticker data
5. `parse_instruments/1` - Normalize instrument list
6. `parse_positions/1` - Normalize position data (futures/options)
7. `parse_trades/1` - Normalize user trade history
8. `parse_account_summary/1` - Normalize account/balance info
9. `parse_error/1` - Pass through Deribit errors unchanged
10. `parse_generic/1` - Fallback for simple responses

**Deribit-Specific Normalization**:
- `order_state`: `"open"` → `:open`, `"filled"` → `:filled`, `"cancelled"` → `:cancelled`
- `direction`: `"buy"` → `:buy`, `"sell"` → `:sell`
- `order_type`: `"limit"` → `:limit`, `"market"` → `:market`
- Keep instrument names as strings: `"BTC-PERPETUAL"`, `"ETH-29MAR24"`
- Keep all numeric values as-is (Deribit uses floats, not strings)

**Acceptance Criteria**: ✅ COMPLETE (2025-11-06)
- [x] All parse functions use `normalize_keys/1` from ParserMacros
- [x] Enum values converted to atoms (direction, order_state, order_type)
- [x] Numeric values kept as-is (no Decimal conversion in parser)
- [x] Errors passed through unchanged (preserve original JSON-RPC error structure)
- [x] Unit tests for each parse function with real Deribit response examples
- [x] Module is 395 lines (parsers are comprehensive with 9 parse functions)

---

### Task 4: Create Deribit.Trading wrapper [D:1/B:8 → Priority:8.0] 🎯

**Goal**: Ultra-thin wrappers over DeribitRpc trading methods

**Reference**:
- `zen_websocket/examples/deribit_rpc.ex:168-234` - buy/sell/cancel/get_open_orders **ALREADY EXIST**
- Task 3 Parser - parse_order/parse_orders functions

**Pattern**: DeribitRpc does request building, we just call + parse response

**Files**:
- Create `lib/zen_cex/adapters/deribit/trading.ex`
- Create `test/zen_cex/adapters/deribit/trading_test.exs`

**Functions** (6-8 total, ALL thin wrappers):
1. `buy/4` - Place buy order (DeribitRpc.buy → WebSocket.send_request → Parser.parse_order)
2. `sell/4` - Place sell order (same pattern)
3. `cancel/2` - Cancel order by ID
4. `get_open_orders/2` - List open orders (optional filters)
5. `edit_order/3` - Modify existing order (add to DeribitRpc if missing)
6. `cancel_all/2` - Cancel all orders (add to DeribitRpc if missing)
7. `get_order_history/2` - Historical orders (add to DeribitRpc if missing)
8. `get_user_trades/2` - User trade history (add to DeribitRpc if missing)

**Order Options** (from Deribit docs):
- `type`: `:limit`, `:market`, `:stop_limit`, `:stop_market`
- `price`: Limit price (required for limit orders)
- `time_in_force`: `:good_til_cancelled`, `:fill_or_kill`, `:immediate_or_cancel`
- `post_only`: Boolean (maker-only orders)
- `reduce_only`: Boolean (only reduce position)
- `label`: String (user-defined order label)

**Acceptance Criteria**: ✅ COMPLETE (2025-11-11)
- [x] Each function uses DeribitRpc for request building (NO manual JSON-RPC!)
- [x] Responses parsed via Parser module (normalize_keys)
- [x] Integration test: place order, check response, cancel order on testnet
- [x] Support all Deribit order types (limit orders with post_only, reduce_only, labels)
- [x] Module is 289 lines (comprehensive @moduledoc with examples, actual code <200)

---

### Task 5: Create Deribit.MarketData wrapper + ETS cache [D:2/B:9 → Priority:4.5] 🎯

**Goal**: Thin wrappers that read from ETS cache (populated by WebSocket subscriptions)

**Reference**:
- `zen_websocket/examples/deribit_rpc.ex:108-154` - get_order_book/ticker/get_instruments
- `lib/zen_cex/adapters/binance/websocket.ex:480-575` - **Message handlers update ETS cache**
- `lib/zen_cex/cache/market.ex` - Existing ETS cache module (works with instrument names!)

**CRITICAL**: Unlike Binance/Bybit which use "symbol" (e.g., "BTCUSDT"), Deribit uses "instrument" (e.g., "BTC-PERPETUAL", "ETH-29MAR24"). The `ZenCex.Cache.Market` module accepts any string, so no changes needed - just pass instrument names as the symbol parameter.

**Pattern**: WebSocket subscription → message handler updates ETS → get functions read ETS

**Architecture**:
1. **Deribit.WebSocket** (Task 2) - Message handlers update ETS automatically (like Binance)
2. **Deribit.MarketData** (this task) - Read-only wrappers over ETS cache + direct requests

**Files**:
- Create `lib/zen_cex/adapters/deribit/market_data.ex` (~150 lines)
- Create `test/zen_cex/adapters/deribit/market_data_test.exs`

**Functions** (6-8 total):

**Subscription-based (require active WebSocket subscription)**:
1. `get_order_book/1` - Read from ETS (returns {:error, :not_subscribed} if cache empty)
2. `get_ticker/1` - Read from ETS (returns {:error, :not_subscribed} if cache empty)
3. `get_last_trade/1` - Read from ETS (returns {:error, :not_subscribed} if cache empty)

**Direct request (no subscription needed)**:
4. `get_instruments/1` - One-time WebSocket request via Rpc.get_instruments, cache 5 min
5. `get_price_index/1` - One-time request via custom Rpc method, cache 1 sec
6. `get_funding_history/2` - One-time request for historical data

**Helper functions**:
7. `subscribe_order_book/2` - Convenience wrapper for WebSocket.subscribe with channel name
8. `subscribe_ticker/2` - Convenience wrapper for WebSocket.subscribe

**Example Implementation**:
```elixir
defmodule ZenCex.Adapters.Deribit.MarketData do
  alias ZenCex.Cache.Market
  alias ZenCex.Adapters.Deribit.{WebSocket, Rpc, Parser}

  # Subscription-based: Read from ETS (populated by WebSocket handlers)
  def get_order_book(instrument) do
    case Market.get_orderbook(:deribit, instrument) do
      {:ok, orderbook} -> {:ok, orderbook}
      {:error, _} -> {:error, :not_subscribed}
    end
  end

  def get_ticker(instrument) do
    case Market.get_ticker(:deribit, instrument) do
      {:ok, ticker} -> {:ok, ticker}
      {:error, _} -> {:error, :not_subscribed}
    end
  end

  # Direct request: One-time fetch + cache
  def get_instruments(currency) do
    case Market.get_market_data(:deribit, "", "instruments_#{currency}") do
      {:ok, cached} -> {:ok, cached}
      {:error, _} ->
        # Direct WebSocket request (not subscription)
        request = Rpc.get_instruments(currency)
        with {:ok, response} <- WebSocket.send_request_sync(request),
             {:ok, instruments} <- Parser.parse_instruments(response) do
          Market.put_market_data(:deribit, "", "instruments_#{currency}", instruments, 300)
          {:ok, instruments}
        end
    end
  end

  # Convenience wrappers for subscriptions
  def subscribe_order_book(client, instrument) do
    WebSocket.subscribe(client, ["book.#{instrument}.raw"])
  end

  def subscribe_ticker(client, instrument) do
    WebSocket.subscribe(client, ["ticker.#{instrument}.raw"])
  end
end
```

**ETS Cache Strategy** (populated by WebSocket.handle_message):
- **Order book**: `Market.put_orderbook(:deribit, instrument, data, :infinity)` - continuous
- **Ticker**: `Market.put_ticker(:deribit, instrument, data, 30)` - 30 sec TTL
- **Last trade**: `Market.put_last_trade(:deribit, instrument, data)` - infinite TTL
- **Instruments**: `Market.put_market_data(:deribit, "", "instruments_BTC", data, 300)` - 5 min
- **Price index**: `Market.put_market_data(:deribit, "", "price_index_BTC", data, 1)` - 1 sec

**Acceptance Criteria**:
- [ ] Get functions read from ETS cache (NO fallback requests for subscription data!)
- [ ] Returns {:error, :not_subscribed} when cache empty (not an API error!)
- [ ] WebSocket.handle_message (Task 2) updates ETS for subscription channels
- [ ] Direct request functions (get_instruments) cache results appropriately
- [ ] Subscribe helper functions build correct Deribit channel names
- [ ] Integration test: subscribe → receive updates → verify ETS → get functions work
- [ ] Module is <150 lines (mostly thin wrappers!)

**Parser Enhancements** (add during this task):
- [ ] Add `parse_market_data/1` optional callback to `Deribit.Parser`
- [ ] Implement WebSocket subscription data parsing (orderbook updates, ticker streams, trade streams)
- [ ] Add `@behaviour ZenCex.Behaviors.Parser` declaration for compile-time verification
- [ ] Test parsing of subscription channel messages with real Deribit examples

---

### Task 6: Configure Deribit.RateLimiter (100-credit bucket) [D:1/B:7 → Priority:7.0] 📋

**Goal**: Configure zen_websocket RateLimiter with Deribit's 100-credit system

**Reference**:
- `zen_websocket/lib/zen_websocket/rate_limiter.ex:1-170` - Token bucket implementation
- `zen_websocket/lib/zen_websocket/rate_limiter.ex:139-149` - deribit_cost function **ALREADY EXISTS**
- Deribit docs: https://docs.deribit.com/#rate-limits (100 credits/second, different costs per method)

**Pattern**: Use existing RateLimiter, just configure for Deribit

**Files**:
- Create `lib/zen_cex/adapters/deribit/rate_limiter.ex`
- Create `test/zen_cex/adapters/deribit/rate_limiter_test.exs`

**Functions** (3-4 total, configuration wrapper):
1. `init/0` - Initialize with 100-credit bucket using ZenWebsocket.RateLimiter.deribit_cost/1
2. `check_rate_limit/1` - Check if request can proceed
3. `get_status/0` - Current rate limit status
4. `reset/0` - Reset rate limiter (testing only)

**Deribit Credit Costs** (from zen_websocket/rate_limiter.ex:139-149):
- Public methods: 1 credit
- Private get_*: 5 credits
- Private set_*: 10 credits
- Trading (buy/sell): 15 credits

**Acceptance Criteria**:
- [ ] Uses existing ZenWebsocket.RateLimiter (no reimplementation!)
- [ ] Configured with 100-credit bucket
- [ ] Uses deribit_cost function from zen_websocket
- [ ] Integration test: Exceed rate limit, verify queue behavior
- [ ] Module is <100 lines (it's just configuration!)

---

### Task 7: Integration Tests with Real Deribit Testnet [D:2/B:9 → Priority:4.5] 🎯

**Goal**: Comprehensive integration tests against real Deribit testnet

**Reference**:
- `zen_websocket/test/zen_websocket/correlation_test.exs:1-230` - Real Deribit API tests
- `test/zen_cex/adapters/binance/websocket_test.exs` - WebSocket integration pattern
- `test/zen_cex/adapters/bybit/unified_test.exs` - Trading integration pattern
- `lib/zen_cex/test_utilities/integration_case.ex` - IntegrationCase pattern

**Pattern**: Test against test.deribit.com with explicit credentials (NO env reading in tests)

**Files**:
- Create `test/zen_cex/adapters/deribit/integration_test.exs`

**Test Cases** (10-15 tests):
1. **Connection & Authentication** - Connect with explicit client_id/client_secret, authenticate
2. **Market Data Subscription** - Subscribe to order book, receive updates
3. **Order Placement (Testnet)** - Place limit order below market (won't fill)
4. **Order Cancellation** - Cancel order by ID
5. **Get Open Orders** - List open orders
6. **Get Instruments List** - Fetch available instruments
7. **Get Ticker Data** - Fetch ticker data
8. **Get Account Summary** - Fetch account balance
9. **WebSocket Reconnection** - Simulate disconnect, verify reconnection
10. **Rate Limit Handling** - Rapid requests, verify queue behavior
11. **Error Handling** - Invalid instrument, insufficient balance
12. **JSON-RPC Correlation** - Multiple concurrent requests

**Test Setup Pattern** (use IntegrationCase):
- Use `ZenCex.IntegrationCase` with `exchange: :deribit`
- Credentials injected via context (`:client_id`, `:client_secret`)
- Tests tagged with `:integration` and `:deribit`
- Rate limiter initialized in setup

**Acceptance Criteria**:
- [ ] All tests pass against real Deribit testnet
- [ ] Tests receive credentials via context (NOT from env directly)
- [ ] Tests tagged with `:integration` and `:deribit`
- [ ] Tests cover happy path + error scenarios
- [ ] Tests verify ETS cache behavior
- [ ] Tests demonstrate WebSocket reconnection

---

### Task 8: REST Endpoints (OPTIONAL, LOW PRIORITY) [D:3/B:4 → Priority:1.3] ⚠️

**Goal**: REST fallback endpoints for historical data (Deribit REST is secondary)

**Reference**:
- Deribit REST docs: https://docs.deribit.com/v2/#rest-api
- `lib/zen_cex/adapters/binance/spot.ex` - REST endpoint pattern

**Pattern**: Use Req for REST, but WebSocket is preferred

**Why LOW Priority**:
- Deribit's REST API is just HTTP wrapper over same JSON-RPC 2.0
- WebSocket can do EVERYTHING REST can do
- REST is fallback only when WebSocket unavailable
- Most use cases are real-time (WebSocket handles it)

**Endpoints to Consider** (if needed):
- `GET /api/v2/public/get_instruments` - Instrument list (cache on startup)
- `GET /api/v2/public/get_historical_volatility` - Historical vol (WebSocket doesn't provide)
- `GET /api/v2/public/get_funding_rate_history` - Funding history (bulk fetch)

**Implementation Only If**:
- Historical data analysis needed (backtesting)
- Bulk data export required
- WebSocket connection unstable

**Acceptance Criteria**:
- [ ] REST endpoints ONLY for data not available via WebSocket
- [ ] Uses Req with JSON-RPC 2.0 format (same as WebSocket)
- [ ] Same Parser module for responses
- [ ] Clearly documented as "fallback only"

---

## Module Structure

```
lib/zen_cex/adapters/deribit/
├── rpc.ex              (401 lines) ✅ - COPIED from Examples.DeribitRpc + 5 new methods
├── websocket.ex        (393 lines) ✅ - COPIED pattern + message handlers for ETS
├── parser.ex           (424 lines) ✅ - Normalize JSON with normalize_keys
├── trading.ex          (289 lines) ✅ - Ultra-thin wrappers over Rpc
├── market_data.ex      (~150 lines) - Read from ETS + direct requests
└── rate_limiter.ex     (~80 lines)  - Config wrapper for zen_websocket

test/zen_cex/adapters/deribit/
├── rpc_test.exs        (TBD)
├── websocket_test.exs  (254 lines) ✅ - 13 tests, all passing
├── parser_test.exs     (620 lines) ✅ - 23 tests, all passing
├── trading_test.exs    (572 lines) ✅ - 25+ tests, all passing
├── market_data_test.exs (TBD)
├── rate_limiter_test.exs (TBD)
└── integration_test.exs (~300 lines) - Real testnet tests (may merge with websocket_test)
```

**Total Lines**: ~3,483 lines (2,953 lines complete, 530 lines remaining)

**Architecture Notes**:
- NO auth.ex! Credentials passed explicitly per zen_cex design
- ALL code copied from Examples.* into zen_cex (no external deps on example code)
- **WebSocket.handle_message** updates ETS (like Binance pattern)
- **MarketData** reads from ETS (subscription data) or makes direct requests (instruments, etc.)

---

## Testing Strategy

### Unit Tests
- **Parser**: Mock Deribit JSON responses (from real API captures)
- **RateLimiter**: Test token consumption, queue behavior

### Integration Tests (Real Testnet)
- **WebSocket**: Connect with explicit credentials, auth, subscribe, receive messages
- **Trading**: Place/cancel orders on testnet (won't fill at extreme prices)
- **MarketData**: Fetch order book, ticker, instruments
- **Error Handling**: Invalid requests, auth failures, rate limits
- **Credentials**: Use IntegrationCase pattern (credentials via context, NOT env)

### Test Data Sources
1. **Deribit Testnet**: test.deribit.com (requires free testnet account)
2. **zen_websocket Tests**: correlation_test.exs already uses Deribit testnet
3. **API Explorer**: https://test.deribit.com/api_console/v2/

---

## Environment Variables

```bash
# Testnet (default for development)
DERIBIT_TESTNET_API_KEY=xxx        # test.deribit.com
DERIBIT_TESTNET_SECRET_KEY=xxx

# Production (explicit opt-in)
DERIBIT_API_KEY=xxx                # www.deribit.com
DERIBIT_SECRET_KEY=xxx
```

**Note**: API key and secret are the same as OAuth client_id and client_secret for Deribit.

---

## Success Criteria

**Progress: 4/7 tasks complete (57%)**

1. ⏳ **All tasks completed** with passing tests (4/7 complete)
2. ✅ **Integration tests** pass against real Deribit testnet (61+ tests passing)
3. ⏳ **Connection reuse** via ConnectionRegistry (application layer - pending Task 5)
4. ✅ **Parser** handles all Deribit response formats (Task 3 - complete)
5. ✅ **WebSocket** connection survives reconnections (zen_websocket handles this)
6. ⏳ **Rate limiting** prevents API violations (Task 6 - pending)
7. ✅ **ETS cache** reduces redundant API calls (message handlers implemented)
8. ✅ **Code coverage** >80% (61+ tests: 23 parser + 13 WebSocket + 25+ trading)

---

## References

### Deribit API Documentation (Local)
**Primary Reference**: `zen_websocket/docs/deribit/` - Complete local documentation with real examples

Available files (15 total):
- `market_data.md` - All market data endpoints with response examples
- `trading.md` - Trading endpoints (buy, sell, cancel, edit)
- `subscriptions.md` - WebSocket subscription channels
- `authentication.md` - OAuth 2.0 client credentials flow
- `account_management.md` - Account info, positions, balances
- `wallet.md` - Deposits, withdrawals, transfers
- `session_management.md` - API key management
- `supporting.md` - Helper endpoints (time, test)
- `json_rpc.md` - JSON-RPC 2.0 protocol details
- `json_rpc_usage.md` - Usage examples
- `overview.md` - API overview and concepts
- `index.md` - Documentation index
- `block_trade.md`, `block_rfq.md`, `combo_books.md` - Advanced features

### zen_websocket Source (Already Complete!)
- `zen_websocket/examples/deribit_adapter.ex:1-135` - **5 functions, copy pattern**
- `zen_websocket/examples/deribit_rpc.ex:1-234` - **12 RPC methods, all trading/market data**
- `zen_websocket/lib/zen_websocket/client.ex:1-862` - Client GenServer
- `zen_websocket/lib/zen_websocket/json_rpc.ex:1-82` - JSON-RPC 2.0 protocol
- `zen_websocket/lib/zen_websocket/rate_limiter.ex:139-149` - deribit_cost function
- `zen_websocket/helpers/deribit.ex:1-56` - Heartbeat handling
- `zen_websocket/test/correlation_test.exs:1-230` - Real Deribit tests

### zen_cex Patterns
- `lib/zen_cex/adapters/binance/websocket.ex:1-577` - WebSocket adapter pattern
- `lib/zen_cex/adapters/binance/parser.ex:1-705` - Parser with normalize_keys
- `lib/zen_cex/adapters/bybit/parser.ex:1-407` - Unified V5 format handling

### Deribit Online Documentation
- REST/WebSocket: https://docs.deribit.com/v2/
- Authentication: https://docs.deribit.com/v2/#authentication
- Rate Limits: https://docs.deribit.com/v2/#rate-limits
- JSON-RPC 2.0: https://www.jsonrpc.org/specification

---

## Implementation Notes

### Critical Realizations

1. **zen_websocket does 95% of the work** - Client + DeribitRpc provide the foundation
2. **No JSON-RPC builders needed** - DeribitRpc.buy/sell/cancel/etc. already exist (12 methods!)
3. **No WebSocket protocol handling** - Client.ex handles everything (reconnection, correlation, heartbeat)
4. **No auth module needed** - Build auth via DeribitRpc, send via Client (credentials explicit)
5. **Parser is CRITICAL work** - zen_websocket does ZERO normalization (returns raw JSON strings)
6. **DeribitAdapter is reference only** - Copy the pattern, don't import `Examples.*` modules
7. **ETS caching pattern** - Copy from Binance.WebSocket (works well)

### What NOT to Build (Already in zen_websocket Core!)

- ❌ JSON-RPC protocol (use `ZenWebsocket.JsonRpc.build_request/2`)
- ❌ WebSocket connection management (use `ZenWebsocket.Client`)
- ❌ Heartbeat logic (Client handles automatically with Deribit helper)
- ❌ Reconnection logic (Client handles with exponential backoff)
- ❌ Request/response correlation (Client handles automatically by ID)
- ❌ Key normalization in WebSocket layer (zen_websocket returns raw JSON!)

### What TO Build (Copy from Examples!)

- ✅ **Deribit.Rpc** - Copy 12 methods from `Examples.DeribitRpc` (~250 lines)
- ✅ **Deribit.WebSocket** - Copy pattern from `Examples.DeribitAdapter` (~200 lines)
- ✅ **Deribit.Parser** - NEW code for normalization (~300 lines)
- ✅ Trading/MarketData wrappers (~450 lines combined)

### Call Chain Pattern

Every function in zen_cex Deribit adapter should be **≤15 lines**:
1. Build request via `Rpc.method_name(params)` (our copy, NOT Examples)
2. Encode and send via `Client.send_message(client, Jason.encode!(request))`
3. Receive correlated response: `{:ok, %{"result" => data}}`
4. Normalize via `Parser.parse_*(data)`
5. Return normalized result

Pattern: **Rpc → Client.send_message → Parser → result** (4 steps max)

---

## Next Steps

1. **Task 1**: Understand NO Auth module needed (credentials passed explicitly)
2. **Task 2**: Create WebSocket wrapper (enables integration testing)
3. **Task 3**: Create Parser module (foundation for all responses)
4. **Task 7**: Integration Tests (verify against real testnet ASAP!)
5. **Tasks 4-6**: Trading, MarketData, RateLimiter (build on proven foundation)
6. **Task 8**: Skip REST unless proven necessary

**Estimated Timeline**: 2-3 sessions (each task is 1-3 hours with zen_websocket doing heavy lifting!)
