# CLAUDE.md

Guidance for Claude Code when working with the ZenCex library.

## 🛑 STOP: MINIMALIST APPROACH FIRST

**DO EXACTLY WHAT IS ASKED - NOTHING MORE, NOTHING LESS**
- **NO** proactive features or improvements unless explicitly requested
- **NO** additional error handling beyond what's needed
- **NO** extra validation or checks unless asked
- **NO** refactoring unless specifically requested
- **NO** no extra documentation files unless asked
- **ONLY** implement the exact feature/fix requested
- **ALWAYS** ask before adding anything not explicitly mentioned
- **IF UNCLEAR**: Ask "Should I also do X?" before proceeding

## 🚨 CRITICAL: NEVER HIDE TEST FAILURES

**See global CLAUDE.md for comprehensive test error handling rules.**

**Project-specific addition**: When unsure what errors to expect from exchange APIs, use Tidewave MCP tools (`mcp__tidewave__project_eval`) to explore actual API behavior before writing assertions.

## Prerequisites
- **Read AGENTS.md first** - Contains Elixir patterns, testing requirements, and module cooperation patterns
- **Date Awareness**: Always use current year from `<env>` section for searches (e.g., "Binance API 2025" not "2024")

## Project Overview

ZenCex - Elixir library for crypto exchange APIs (REST + WebSocket via zen_websocket).

**Scope**:
- REST for trading operations (30s-5min intervals)
- WebSocket for real-time market data via [zen_websocket](https://github.com/ZenHive/zen_websocket)
**Design**: Req-centric HTTP, ETS state, minimal supervision, Gun-based WebSocket

## Library Design Principles

**CRITICAL: ZenCex is a LIBRARY, not an APPLICATION**

### Configuration Management

**❌ NEVER use centralized Mix config (`Application.get_env(:zen_cex, ...)`):**
- **Namespace collision**: Multiple apps using zen_cex would conflict
- **No multi-instance support**: Can't connect to testnet + prod simultaneously
- **No multi-account support**: Can't use different API keys for different subaccounts
- **Forces config pattern**: Users may prefer database, vault, or per-request credentials
- **Hidden global state**: Violates functional programming principles
- **Testing complexity**: Hard to test with different configs in parallel

**✅ CORRECT patterns (used by zen_cex):**
1. **Explicit auth_credentials**: Always pass credentials explicitly via `auth_credentials` option
2. **No ENV fallback in library**: Library code never reads ENV variables for credentials
3. **Testnet flag in credentials**: `testnet: true/false` determines which environment to use
4. **ENV reading only in calling code**: Tests, scripts, and IEx helpers can read ENV, but pass explicitly

**Example:**
```elixir
# ❌ BAD: ENV fallback in library code
def get_balances(opts \\ []) do
  api_key = opts[:api_key] || System.get_env("BINANCE_API_KEY")  # Hidden fallback!
end

# ✅ GOOD: Explicit credentials required
# Calling code (tests, scripts) reads ENV and passes explicitly
api_key = System.get_env("BINANCE_TESTNET_API_KEY")
api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

Binance.Spot.get_balances(%{},
  auth_credentials: %{
    api_key: api_key,
    api_secret: api_secret,
    testnet: true
  }
)
```

**Note**: `.iex.exs` helper functions are fine for developer convenience, but they should NOT create library-level abstractions.

**zen_websocket Access**: The zen_websocket library code is available via symlink at `./zen_websocket/` for reference and understanding of WebSocket implementation details.

**Use Cases**:
- Real-time market data streaming (order books, trades, tickers)
- Position monitoring & exposure calculation
- Portfolio hedging & rebalancing
- Subaccount risk isolation
- Trade execution on signals

## Task Prioritization Framework (Standard for All Task Lists)

When creating any task list or TODO document, always include difficulty and benefit scores:

### Scoring Format
- **Format**: `[D:X/B:Y → Priority:Z]` where Priority = Benefit/Difficulty
- **Quick Scale**: Use 1-10 for both Difficulty and Benefit
- **Priority Interpretation**:
  - Priority > 2.0: 🎯 Exceptional ROI - do immediately
  - Priority 1.5-2.0: 🚀 High ROI - do soon
  - Priority 1.0-1.5: 📋 Good ROI - plan carefully
  - Priority < 1.0: ⚠️ Poor ROI - reconsider or defer

### Benefit Scoring Guidelines (1-10)
- **10**: Transforms entire system/workflow
- **8-9**: Major improvement to core functionality
- **6-7**: Significant quality of life improvement
- **4-5**: Moderate improvement, nice to have
- **2-3**: Minor improvement, cosmetic
- **1**: Minimal impact

### Difficulty Scoring Guidelines (1-10)
- **10**: Requires architectural changes, multiple weeks
- **8-9**: Complex implementation, 1-2 weeks
- **6-7**: Significant work, 2-5 days
- **4-5**: Moderate complexity, 1-2 days
- **2-3**: Simple changes, few hours
- **1**: Trivial, under 1 hour

### Exclusions (Don't Score These)
- 🐛 Critical bugs - always highest priority
- 🔒 Security issues - always highest priority
- 📝 Documentation of completed work - just do it
- ✅ Tasks already in progress - finish them first

### Example Task List
```markdown
## Development Tasks
- [ ] Add WebSocket reconnection logic [D:3/B:9 → Priority:3.0] 🎯
- [ ] Refactor parser modules [D:7/B:7 → Priority:1.0] 📋
- [ ] Update color scheme [D:2/B:3 → Priority:1.5] 🚀
- [ ] Rewrite entire auth system [D:9/B:8 → Priority:0.89] ⚠️
```

This system helps us focus on high-impact, low-effort wins first!

## Commands

```bash
mix deps.get              # Install dependencies
mix test --cover          # Run all tests (and with cover)
mix precommit             # Format, credo, dialyzer, tests
mix doctor                # Check docs and specs
iex -S mix                # Interactive shell
```

### Testing Approach
**Development Mode**: When implementing features from `docs/specs.md` or other task documents, run only specific tests as needed:
- `mix test test/path/to/test.exs` - Run specific test file
- `mix test --failed` - Re-run failed tests

**Code Review Mode**: Overall code quality checks (`mix precommit`, `mix credo`, `mix dialyzer`, `mix coveralls`) will be run in a separate dedicated session after implementation is complete.

## Tidewave MCP

Start with `mix tidewave` (port 4001). Use MCP tools for testing:
- `mcp__tidewave__project_eval` - Execute code in project context
- `mcp__tidewave__get_docs` - Get module/function docs
- `mcp__tidewave__get_source_location` - Find source locations
- `mcp__tidewave__search_package_docs` - Search Hex docs
- `mcp__tidewave__get_logs` - View application logs

## Implementation Rules

1. **Explore BEFORE coding** - Use `mcp__tidewave__project_eval` to explore API responses and data structures BEFORE writing any implementation. Understanding the actual response prevents incorrect assumptions.

2. **Verify with Tidewave first** - Before implementing parsers or data transformations, test the actual API calls with Tidewave to see real response structures, error formats, and edge cases.

3. **No assumptions about APIs** - Never assume what an API returns. Always verify the actual response structure, field names, data types, and error responses using Tidewave.

4. **Debug with real data** - When something doesn't work as expected, use Tidewave to inspect the actual data flow rather than adding debug prints or modifying code.

**Philosophy**: Understand reality before implementing against it. Tidewave is your exploration tool - use it liberally before and during development.

## Debug Module

Enable with `ZenCex.Core.Debug.enable()` to export failed requests as curl commands:
- `get_last_curl()` - Get last failed request as curl
- `get_recent_curls(n)` - Get n recent failures
- `stats()` - Debug statistics
- `clear()` - Clear debug data

## Architecture

### Core Modules
- **Application**: ETS tables, Finch pooling, WebSocket supervision
- **Core.Registry**: Exchange → module mapping
- **Core.HTTP**: Req configuration with auth/rate-limit steps
- **Safety.ClockSync**: Time sync with exchanges

### Adapters

**Binance** (complete):
- Direct module usage: `Spot`, `Margin`, `UsdmFutures`, `CoinmFutures`, `PortfolioMargin`
- Supporting: `Auth`, `RateLimiter`, `Parser`, `Strategies`
- WebSocket: `Binance.WebSocket` for market streams

**Bybit** (trading complete):
- Direct module usage: `Unified`, `Common`, `MarketData`
- WebSocket: `Bybit.WebSocket` for real-time data

**Deribit** (planned):
- **WebSocket-First Architecture**: Unlike Binance/Bybit, Deribit's preferred interface is WebSocket
- JSON-RPC 2.0 protocol for both WebSocket and REST
- WebSocket for trading operations AND market data (REST is fallback only)
- zen_websocket already has Deribit support (`heartbeat_config: %{type: :deribit}`)
- OpenAPI schema available at `github.com/deribit/deribit-api-clients` (reference only, may be auto-generated)
- See `docs/deribit_specs.md` for detailed implementation plan

**Aster** (planned):
- **Binance-Compatible DEX**: Perpetual futures with two API options
- Standard API: HMAC-SHA256 auth (identical to Binance Futures)
- V3 API: Web3 wallet authentication with ECDSA signatures
- Manual endpoint definitions (~40 endpoints total)
- See `docs/aster_specs.md` and `docs/aster_web3_specs.md` for details

### Design Patterns
- Req middleware for REST (auth, rate-limiting)
- Gun-based WebSocket via zen_websocket
- ETS for state (rate limits, clock sync, market data cache)
- Minimal supervision (OAuth and critical WebSocket connections)

## Exchange Details

### Binance
```elixir
alias ZenCex.Adapters.Binance.{Spot, UsdmFutures}
Spot.get_balances()
Spot.place_oco_order(%{symbol: "BTCUSDT", ...})
```
- HMAC-SHA256 auth, `X-MBX-APIKEY` header
- Per-API-type rate limits
- ClockSync for timestamps

### Bybit
```elixir
alias ZenCex.Adapters.Bybit.Unified
Unified.get_positions()
```
- Unified V5 API
- Single rate limit pool

### Deribit (Planned)
```elixir
alias ZenCex.Adapters.Deribit.WebSocket

# Primary interface: WebSocket with JSON-RPC 2.0
Deribit.WebSocket.place_order(%{instrument: "BTC-PERPETUAL", amount: 100, type: "limit", price: 45000})
Deribit.WebSocket.subscribe(["book.BTC-PERPETUAL.100ms", "trades.BTC-PERPETUAL.raw"])

# REST fallback (same JSON-RPC calls)
Deribit.Trading.place_order(%{...})
```

**Product Coverage**:
- **Spot Trading**: Zero-fee markets (launched 2023)
- **Options**: BTC/ETH/SOL options (90% market share)
- **Futures**: Perpetual and dated futures contracts
- **Perpetuals**: BTC-PERPETUAL, ETH-PERPETUAL, etc.

**Key Differences from Binance/Bybit**:
- **WebSocket-first**: Trading operations via WebSocket, not REST
- **JSON-RPC 2.0**: Both WebSocket and REST use JSON-RPC protocol
- **Single auth**: Authenticate once per WebSocket session, not per request
- **Subscriptions only via WebSocket**: Real-time data requires persistent connection
- **zen_websocket features**: JSON-RPC support, Deribit heartbeats, request/response correlation

**API Endpoints**:
- Production: `https://www.deribit.com/api/v2` (WebSocket: `wss://www.deribit.com/ws/api/v2`)
- Testnet: `https://test.deribit.com/api/v2` (WebSocket: `wss://test.deribit.com/ws/api/v2`)

**Authentication**:
- OAuth 2.0 client credentials flow
- Single authentication message for WebSocket session
- REST requires per-request OAuth or API key signing

### Aster (Planned)
```elixir
alias ZenCex.Adapters.Aster.{MarketData, UsdmFutures}

# Standard API - HMAC authentication (like Binance)
MarketData.get_ticker(%{symbol: "BTCUSDT"})
UsdmFutures.place_order(%{symbol: "BTCUSDT", side: "BUY", type: "LIMIT", ...},
  auth_credentials: %{api_key: "...", api_secret: "...", testnet: true})

# V3 API - Web3 wallet authentication (future)
UsdmFutures.place_order(%{...},
  auth_credentials: %{wallet_address: "0x...", private_key: "0x..."})
```

**Key Characteristics**:
- **Binance-Compatible**: Same endpoint structure (`/fapi/v1/*`), HMAC auth, response formats
- **DEX with CEX UX**: Decentralized exchange with traditional API interface
- **Dual Auth**: Standard HMAC (implemented first) + Web3 ECDSA signatures (future)
- **Perpetual Futures Only**: USD-margined contracts with multi-assets and hedge mode
- **Manual Endpoints**: ~40 endpoints defined manually (no OpenAPI spec available)

**Rate Limits**:
- Request weight: 2400/min
- Order limit: 1200/min
- IP-based with potential ban for violations

## Environment Variables

```bash
# Binance (spot/futures have separate testnets!)
BINANCE_TESTNET_API_KEY=xxx       # testnet.binance.vision
BINANCE_FUTURES_TEST_API_KEY=xxx  # testnet.binancefuture.com

# Bybit
BYBIT_TESTNET_API_KEY=xxx         # api-testnet.bybit.com

# Deribit (API key or OAuth client credentials)
DERIBIT_TESTNET_API_KEY=xxx       # test.deribit.com
DERIBIT_TESTNET_SECRET_KEY=xxx
DERIBIT_CLIENT_ID=xxx             # OAuth (same as API key for testnet)
DERIBIT_CLIENT_SECRET=xxx         # OAuth (same as secret key for testnet)

# Aster (Standard API or V3 Web3)
ASTER_API_KEY=xxx                 # fapi.asterdex.com (Standard API)
ASTER_API_SECRET=xxx
ASTER_WALLET_ADDRESS=xxx          # V3 Web3 API (future)
ASTER_PRIVATE_KEY=xxx
```


## Key Implementation Notes

### Parser Pattern (Standard for All Exchanges)

**Philosophy**: Parsers are the transport layer, not business logic. Return raw API values with normalized keys.

**Standard Pattern**:
```elixir
def parse_*(response) when is_map(response) do
  # 1. Normalize all keys (camelCase → snake_case atoms)
  normalized = normalize_keys(response)

  # 2. Optional: Validate required fields
  case normalized[:required_field] do
    nil -> {:error, :invalid_format}
    _ -> {:ok, normalized}
  end

  # 3. Optional: Add computed fields (enums only)
  normalized = Map.put(normalized, :side, normalize_enum_value(response["side"]))

  {:ok, normalized}
end
```

**DO** (Minimal Transformation):
- ✅ Normalize keys with `ParserMacros.normalize_keys/1` (camelCase → snake_case atoms)
- ✅ Return ALL API fields automatically (not just manually mapped ones)
- ✅ Validate required fields exist (return `{:error, :invalid_format}` if missing)
- ✅ Normalize enum values to atoms (e.g., `"BUY"` → `:buy`) using `normalize_enum_value/1`
- ✅ Keep numeric values as-is (strings, integers, floats from API)

**DON'T** (Business Logic):
- ❌ Never convert strings to Decimal (that's business logic)
- ❌ Never compute derived fields (like `total = free + locked`)
- ❌ Never filter data (like removing zero balances)
- ❌ Never create fake fields not in the API response
- ❌ Never wrap raw values in custom structs

**Examples**:

```elixir
# ✅ GOOD: Normalize keys, return raw values
def parse_balances(response) do
  balances = response["balances"] |> Enum.map(&normalize_keys/1)
  {:ok, %{balances: balances}}
  # Returns: %{balances: [%{asset: "BTC", free: "0.5", locked: "0.1"}]}
end

# ❌ BAD: Business logic in parser
def parse_balances(response) do
  balances = response["balances"]
    |> Enum.map(fn b ->
      %{
        asset: b["asset"],
        total: Decimal.add(Decimal.new(b["free"]), Decimal.new(b["locked"]))  # Business logic!
      }
    end)
    |> Enum.reject(&Decimal.equal?(&1.total, Decimal.new("0")))  # Filtering data!
  {:ok, balances}
end

# ✅ GOOD: User handles conversions
{:ok, %{balances: balances}} = parse_balances(response)
btc = Enum.find(balances, &(&1[:asset] == "BTC"))
total = Decimal.add(Decimal.new(btc[:free]), Decimal.new(btc[:locked]))
```

**Why This Matters**:
- **Consistency**: All exchanges return the same format (atom keys, raw values)
- **Completeness**: Users get ALL API fields, not just manually mapped ones
- **Flexibility**: Users choose Decimal/Float/Integer based on their needs
- **Simplicity**: Less code, fewer bugs, easier maintenance
- **Testability**: Tests verify raw API responses, not transformed data

**Breaking Changes**: When updating parsers to this pattern, note that:
- Numeric fields change from `Decimal` → strings/integers/floats
- Users must convert: `Decimal.new(value)` or `Decimal.div(value, 10000)` for basis points
- Field names match raw API (e.g., `:position_amt` not `:size`)

### Endpoint Registry Pattern
- `@endpoints` definitions → macro-generated functions
- Direct module usage (no delegation)
- Compile-time validation
- Runtime discovery via registry modules

### IEx Helpers
```elixir
H.env()           # Show environment
H.credentials()   # Check API credentials
H.rate_status()   # Rate limiter status
```

### Req Features We Leverage (Don't Reinvent!)

**Built-in Features**:
- **Authentication**: `auth: {:bearer, token}` or dynamic `auth: fn -> {:bearer, get_token()} end`
- **Retry**: `:safe_transient` (GET/HEAD) or custom retry functions
- **Pooling**: Automatic via Finch with `:finch` option
- **Telemetry**: Auto events on `[:req, :request, :*]`
- **Compression**: Automatic gzip/deflate
- **JSON**: Auto encode/decode with `:json` option

**Step Patterns**:
- Request steps: `request → request | {request, response/exception}`
- Response steps: `{request, response} → {request, response/exception}`
- Use `Req.Request.halt/2` to stop pipeline
- Use `request.private` for inter-step data
- Order: auth → rate limit → retry → telemetry

**What We Add (Not Reinvent)**:
- Exchange-specific auth (HMAC-SHA256) as Req step
- Rate limiting as Req step (ETS counters)
- Clock sync for timestamps
- Debug curl export on failures

### WebSocket Integration (zen_websocket)

**CRITICAL: zen_websocket is NOT in training data!** This library was private during training, so you CANNOT make ANY assumptions about its API or behavior. You MUST:
- Check `deps/zen_websocket/` for examples and documentation
- Use Tidewave MCP tools to explore and understand the actual API
- Never assume function signatures or behavior patterns
- Always verify against the actual source code

**Source Access**: Full zen_websocket source code available at `./zen_websocket/` (symlink).

**Connection Management Architecture**:

WebSocket connections in zen_cex use a three-layer architecture:

1. **Transport Layer (zen_websocket)**:
   - Returns stable client structs with `server_pid` that survives reconnections
   - Client GenServer owns Gun connection throughout lifecycle
   - Handles automatic reconnection with exponential backoff
   - Maintains message routing continuity through reconnects

2. **Adapter Layer (Binance.WebSocket, Bybit.WebSocket)**:
   - Exchange-specific protocol handling (streams, topics, ping/pong)
   - Always creates NEW connections when called directly (by design)
   - Does NOT implement connection reuse - that's an application concern
   - `ensure_connection/2` is just a convenience alias to `connect/2`

3. **Application Layer (ConnectionRegistry + MarketData)**:
   - `ConnectionRegistry` tracks all connections by `{exchange, symbol}`
   - `MarketData.ensure_websocket_connection/2` checks registry BEFORE creating
   - Implements actual connection reuse with application context
   - Makes decisions about connection grouping based on trading needs

**Why Connection Reuse is at Application Layer**:
- Adapters lack context about which symbols are traded together
- Connection grouping requires application-level knowledge
- Different use cases need different connection strategies
- Registry provides centralized connection tracking

**Key Point**: The TODOs in adapter files about "checking registry for existing connections" are intentionally NOT implemented. Connection reuse happens where it should - at the application layer with full context.

**Core Features**:
- **Gun Transport**: Battle-tested HTTP/2 & WebSocket client for production reliability
- **Automatic Reconnection**: Exponential backoff with state preservation & connection ownership
- **JSON-RPC 2.0**: Full protocol support with request/response correlation & notifications
- **Rate Limiting**: Token bucket algorithm with configurable costs per request type
- **Supervision**: Optional DynamicSupervisor for crash recovery & isolation
- **Connection Registry**: ETS-based tracking without GenServer overhead
- **Frame Handling**: Proper WebSocket frame encoding/decoding with text/binary support
- **Error Categorization**: Structured error handling with recovery strategies
- **Heartbeat Support**: Built-in ping/pong & platform-specific heartbeats (Deribit, Binance)
- **Message Correlation**: Track request/response pairs for async operations
- **Telemetry Integration**: Comprehensive event emission for monitoring

**Public API (Client module - 5 functions)**:
```elixir
# Connect with options
{:ok, client} = ZenWebsocket.Client.connect("wss://example.com", [
  timeout: 5000,
  retry_count: 3,
  retry_delay: 1000,
  max_backoff: 60_000,
  heartbeat_interval: 30_000,
  reconnect_on_error: true
])

# Send messages (text or binary)
{:ok, _} = ZenWebsocket.Client.send_message(client, "text message")
{:ok, _} = ZenWebsocket.Client.send_message(client, {:binary, <<1,2,3>>})

# Subscribe to channels (platform-specific)
{:ok, _} = ZenWebsocket.Client.subscribe(client, ["channel1", "channel2"])

# Get connection state
{:connected, info} = ZenWebsocket.Client.get_state(client)

# Close connection
:ok = ZenWebsocket.Client.close(client)
```

**Advanced Features**:

```elixir
# JSON-RPC Support (for Deribit, etc.)
use ZenWebsocket.JsonRpc
defrpc :authenticate, "public/auth"
{:ok, request} = authenticate(%{grant_type: "client_credentials"})

# Supervised Connections
{:ok, _} = ZenWebsocket.ClientSupervisor.start_link([])
{:ok, client} = ClientSupervisor.start_client("wss://example.com", [
  retry_count: 5,
  heartbeat_config: %{type: :deribit, interval: 30_000}
])

# Rate Limiting (prevent API violations)
config = %{
  tokens: 100,              # Max tokens in bucket
  refill_rate: 10,          # Tokens added per interval
  refill_interval: 1000,    # Refill every 1 second
  request_cost: fn         # Dynamic cost calculation
    %{method: "subscribe"} -> 5
    %{method: "order"} -> 10
    _ -> 1
  end
}
{:ok, limiter} = RateLimiter.init(:my_limiter, config)

# Platform Adapters (thin wrappers)
{:ok, adapter} = DeribitAdapter.connect(
  client_id: "...",
  client_secret: "...",
  test_mode: true
)
{:ok, adapter} = DeribitAdapter.authenticate(adapter)
{:ok, adapter} = DeribitAdapter.subscribe(adapter, ["book.BTC-PERPETUAL.raw"])
```

**Architecture Patterns**:
- **GenServer-based Client**: Owns Gun connection for message routing
- **Connection Ownership**: Client process maintains Gun ownership through reconnections
- **Modular Handlers**: Pluggable message, error, and connection handlers
- **ETS State Storage**: Rate limiting & connection registry use ETS for performance
- **Single-flight Protection**: Prevents duplicate operations during transitions

**Testing Utilities**:
```elixir
# Mix tasks for validation
mix zen_websocket.usage       # Show API usage examples
mix zen_websocket.validate    # Check adapter compliance
mix stability_test            # Long-running stability test
```

**Key Files for Reference**:
- `lib/zen_websocket/client.ex` - Main client implementation
- `lib/zen_websocket/examples/deribit_adapter.ex` - Complete platform adapter example
- `lib/zen_websocket/json_rpc.ex` - JSON-RPC protocol support
- `lib/zen_websocket/rate_limiter.ex` - Rate limiting implementation
- `test/zen_websocket/examples/*_test.exs` - Comprehensive usage examples

**Design Philosophy**:
- Start simple: Direct `Client.connect/2` for development
- Add supervision only when needed for production
- Test against real endpoints, not mocks
- Use platform adapters as thin wrappers (5 functions max)
- Leverage built-in features instead of reimplementing
- Message handling in caller process, not internal GenServer

**Market Data Integration Pattern**:
```elixir
# ETS table for latest market data
:ets.new(:market_data, [:set, :public, :named_table])

# WebSocket callback updates cache
def handle_message({:text, msg}, state) do
  data = Jason.decode!(msg)
  :ets.insert(:market_data, {data["symbol"], data})
  {:ok, state}
end

# REST fallback for initial load
def get_ticker(symbol) do
  case :ets.lookup(:market_data, symbol) do
    [] -> fetch_via_rest(symbol)
    [{_, data}] -> {:ok, data}
  end
end
```

## Testing

### Testing Rules

**CRITICAL: NEVER MAKE TEST FAILURES LOOK LIKE SUCCESS!** Tests that encounter errors must fail loudly and clearly. No `IO.puts("this is acceptable")`, no conditional logic to hide failures, no try/catch blocks that swallow errors. A failing test is valuable feedback - hiding it is dangerous.

1. **Tests should be deterministic** - A test either passes or fails, period. NEVER add logic like "if it fails, that's okay" or hide failures behind conditional checks or rescue blocks.

2. **Tests verify functionality, not configuration** - Tests should not check if API keys are configured. They should test that the code works correctly when called.

3. **No mocks for external APIs initially** - Test against REAL testnet/production APIs first. Document actual response formats. Mocks must exactly match observed real API behavior.

4. **Integration tests use real credentials** - When testing exchange integrations, use actual testnet or read-only production API keys to verify the code works with real API responses.

5. **Test the actual response structure** - Tests should assert on the real data structure returned by functions, not on simplified or mocked structures.

6. **Test against reality** - Use Tidewave first to understand behavior. Document actual API responses and edge cases from real testing.

**Philosophy**: Test against reality, not against idealized or mocked scenarios. Failed tests are valuable signals - NEVER suppress them.

### FORBIDDEN Test Patterns (NEVER WRITE THESE!)

**❌ NEVER use `assert true` to hide failures:**
```elixir
# ❌ WRONG - Makes ANY outcome pass silently!
case result do
  {:ok, _} -> assert true
  {:error, _} -> assert true  # Failure silently passes!
end

# ❌ WRONG - Hides errors with comments
{:error, _} ->
  # This is acceptable for testnet
  assert true  # NO! This makes the test ALWAYS PASS!

# ✅ CORRECT - Fail loudly on unexpected errors
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :expected_specific_error} -> :ok
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

**❌ NEVER return `:ok` on errors unless explicitly testing error handling:**
```elixir
# ❌ WRONG - Silently passes failures
{:error, _reason} ->
  # Other validation failures are acceptable
  :ok  # NO! This hides real bugs!

# ✅ CORRECT - Only pass on specific expected errors
{:error, :insufficient_balance} ->
  :ok  # This specific error is expected and valid
{:error, other} ->
  flunk("Expected :insufficient_balance, got #{inspect(other)}")
```

**❌ NEVER use comments like "acceptable", "okay", "expected to fail":**
```elixir
# ❌ WRONG - Comments don't make bad tests acceptable
{:error, reason} ->
  # Any error is acceptable on testnet
  assert true  # Test will ALWAYS pass!

# ❌ WRONG - Comment hiding bad logic
{:error, _} ->
  # Expected possible failures on testnet
  :ok  # Silently swallows all errors!

# ✅ CORRECT - Test specific behavior explicitly
test "returns not_found when account doesn't exist" do
  assert {:error, :not_found} = get_account("invalid_id")
end

test "returns data when account exists" do
  assert {:ok, %{balance: _}} = get_account("valid_id")
end
```

**❌ NEVER use `IO.puts` to document why a test passes:**
```elixir
# ❌ WRONG - Logging doesn't validate behavior
{:error, reason} ->
  IO.puts("Error may be normal for testnet: #{inspect(reason)}")
  assert true  # Still wrong!

# ✅ CORRECT - Either skip the test or assert specific behavior
@tag :skip  # If testnet is unreliable
test "testnet announcement endpoint" do
  # Test implementation
end

# OR test specific expected behavior:
test "announcement endpoint returns list or not_found" do
  case get_announcements() do
    {:ok, list} when is_list(list) -> :ok
    {:error, :not_found} -> :ok
    other -> flunk("Unexpected: #{inspect(other)}")
  end
end
```

**When in doubt: A test should FAIL if the code doesn't work as intended. Never write tests that silently pass on failures!**

```bash
mix test --exclude integration     # Unit tests only
mix test                          # All tests (needs testnet credentials)
mix test --only integration       # Integration tests only
mix test --failed --trace         # Retry failed tests and trace errors
```

- Unit tests: Pure functions only
- Integration tests: Real testnet APIs, fail if credentials missing
- First run may fail (connection setup), run `mix test --failed` to retry

### Integration Test Pattern
```elixir
use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

test "real testnet API call" do
  assert {:ok, balances} = Spot.get_balances()
  # Document actual testnet response format
end
```

### Production API Testing with Test Account

When testnet has IP restrictions or is unavailable, tests can fall back to production API with a dedicated test account:

```elixir
# In your test file
use ZenCex.IntegrationCase,
  exchange: :binance,
  api_type: :spot,
  use_production_for_test: true  # Enable production fallback
```

**Setup Requirements**:
1. Set `BINANCE_TESTNET_ALT_API_KEY` and `BINANCE_TESTNET_ALT_API_SECRET` in environment
2. These should point to a **production** account with **MINIMAL funds** for safety
3. Tests will show warnings when using production endpoints

**How It Works**:
- IntegrationCase first tries regular testnet credentials
- If unavailable or `use_production_for_test: true` is set, falls back to ALT credentials
- Credentials are injected via test context (`:api_key`, `:api_secret`)
- Tests use `context[:api_key]` instead of `System.get_env()`

**Safety Notes**:
- ⚠️ ONLY use accounts with MINIMAL funds (dust amounts)
- ⚠️ Tests will show clear warnings when using production
- ⚠️ Never run destructive operations in these tests
- ⚠️ Primarily for read-only operations and auth validation

### Test Error Handling
- **FAIL LOUDLY** - Never hide errors with `:ok`
- Test specific error conditions explicitly
- Separate success/error test cases
- Use `_TESTNET_` in env variable names

## Module Dependencies

Critical internal dependencies to be aware of:
- **Registry Pattern**: Endpoints modules provide discovery/registry functions for `Core.Registry`
- **Direct Usage**: `Core.HTTP` → `Core.Registry` → Direct API module calls (e.g., `Binance.Spot`)
- **Stateful Components**: OAuth GenServers will be used when needed (future implementations)
- **Rate Limiting**: Each adapter's RateLimiter manages its own ETS tables independently
- **Telemetry**: All modules emit telemetry events for monitoring and debugging

### Module Cooperation Example

When calling `Binance.Spot.get_balances/1`:
1. The Spot module defines the operation via `@endpoints`
2. Core.HTTP creates the Req request with middleware
3. Binance.Auth signs the request with HMAC-SHA256
4. Binance.RateLimiter checks and updates rate limits
5. Binance.Parser normalizes the response
6. Telemetry events are emitted at each stage

## Performance Characteristics

Based on benchmarks:
- Rate limiter handles 10,000 concurrent requests in ~50ms
- Memory growth <1MB under high load
- OAuth token refresh uses single-flight protection
- ETS cleanup runs every 60 seconds (configurable)
- Connection pooling via Finch with default pool sizes

## Elixir Guidelines

Core Elixir best practices for library development:

### Language Patterns
- **Lists don't support index access** - Use `Enum.at/2`, pattern matching, or `List` module instead
- **Variables are immutable but rebindable** - Bind expression results to use them:
  ```elixir
  # INVALID: rebinding inside expression doesn't work
  if condition do
    socket = assign(socket, :val, val)
  end

  # VALID: rebind the result
  socket =
    if condition do
      assign(socket, :val, val)
    end
  ```
- **Type check structs in function heads** - Use pattern matching for compile-time safety:
  ```elixir
  # GOOD: Compile-time struct validation
  def process_user(%User{} = user) do
    # user is guaranteed to be a User struct
  end

  # BETTER: Also extract fields if needed
  def process_user(%User{id: id, name: name} = user) do
    # user is guaranteed to be a User struct with id and name available
  end
  ```
- **Never nest multiple modules** in the same file (causes cyclic dependencies)
- **Never use map access syntax** on structs - Use dot notation (`struct.field`)
- **Never use `String.to_atom/1`** on user input (memory leak risk)
- **Predicate functions** should end with `?`, not start with `is_`
- **Use `Task.async_stream/3`** for concurrent enumeration with back-pressure

### HTTP/WebSocket Clients
- **REST**: Always use Req for HTTP requests - It's the preferred client
- **WebSocket**: Use zen_websocket (Gun-based) for all WebSocket connections
- **Avoid** HTTPoison, Tesla, :httpc, and raw Gun/WebSockex implementations

### Ecto Patterns (if used)
- Schema fields always use `:string` type, even for `:text` columns
- Use `Ecto.Changeset.get_field/2` to access changeset fields
- Preload associations in queries when they'll be accessed
- Programmatic fields (like `user_id`) must not be in `cast/3` calls

## Development Philosophy

### Simplicity Guidelines
- Code simplicity is a primary feature, not an afterthought
- Start simple and add complexity only when proven necessary
- **Target ~5-10 public functions per module** - Keep interfaces minimal
- **Function length guidelines**:
  - Pure business logic: aim for ~15 lines
  - GenServer callbacks: up to ~30 lines is acceptable
  - Complex pattern matching: up to ~25 lines
  - **Always prioritize readability** over arbitrary limits
- **Keep function call chains shallow** - 2-3 levels max
- **Use behaviors only when ≥2 implementations exist**
- **No custom error wrapping** - Pass raw errors through
- **Create abstractions only with proven need** - Need 3+ use cases


### Error Handling Philosophy

The library follows Elixir conventions:
- Returns `{:ok, result}` or `{:error, reason}` tuples
- Pass raw errors without wrapping in custom structs
- **Provide meaningful error context**: Instead of generic atoms like `:invalid_format`, return tuples with descriptive messages like `{:invalid_format, "Expected map with 'balances' key, got: #{inspect(response)}"}`
- Apply "let it crash" philosophy for unexpected errors
- Uses telemetry for error reporting
- Implements exponential backoff for transient failures
- Logs warnings for rate limits and critical errors for health issues

### TODO Comment Requirements

**CRITICAL**: All temporary implementations and production references MUST be marked with TODO:
- **Instead of**: "For now, we use...", "Currently...", "Temporarily..."
- **Write**: "TODO: For now, we use...", "TODO: Currently...", "TODO: Temporarily..."
- **Instead of**: "In production, this should...", "When deployed..."
- **Write**: "TODO: In production, this should...", "TODO: When deployed..."
- **Instead of**: "This is a workaround...", "Quick fix for..."
- **Write**: "TODO: This is a workaround...", "TODO: Quick fix for..."

This ensures `mix credo` can properly identify and track technical debt. Examples:
```elixir
# BAD: mix credo won't find this
# For now, we're using a hardcoded timeout
timeout = 5000

# GOOD: mix credo will track this
# TODO: For now, we're using a hardcoded timeout - should be configurable
timeout = 5000

# BAD: mix credo won't find this
# In production, this should use environment variables
api_key = "test_key"

# GOOD: mix credo will track this
# TODO: In production, this should use environment variables
api_key = "test_key"
```

### No Magic Numbers

**CRITICAL**: All numeric literals must be named constants or have explanatory comments:
- **Instead of**: `timeout = 5000`
- **Write**: `@default_timeout_ms 5000` or `timeout = 5000  # 5 seconds`
- **Instead of**: `if retries > 3`
- **Write**: `@max_retries 3` then `if retries > @max_retries`
- **Instead of**: `Process.sleep(100)`
- **Write**: `@backoff_delay_ms 100` then `Process.sleep(@backoff_delay_ms)`

Examples of values that need constants:
- Timeout values (milliseconds, seconds)
- Retry counts and backoff delays
- Buffer sizes and batch limits
- Port numbers and API versions
- Rate limit thresholds
- Any numeric value that could change or needs explanation

```elixir
# BAD: Magic numbers without explanation
def fetch_data do
  with {:error, _} <- attempt() do
    Process.sleep(1000)
    retry(3)
  end
end

# GOOD: Named constants with clear intent
@retry_delay_ms 1000
@max_retry_attempts 3

def fetch_data do
  with {:error, _} <- attempt() do
    Process.sleep(@retry_delay_ms)
    retry(@max_retry_attempts)
  end
end
```

## Common Issues and Solutions

### Test Failures
- **First run failures**: Some tests may fail on first run due to connection setup. Run `mix test --failed` to retry.
- **Missing credentials**: Tests will fail loudly if testnet API keys are not configured. This is intentional.
- **Rate limiting**: If you see rate limit errors, wait a minute or use `RateLimiter.reset(:spot)` in IEx.

### Authentication Issues
- **Invalid API key**: Ensure you're using testnet keys for tests, not production keys.
- **Timestamp errors**: The library handles clock sync automatically via `Safety.ClockSync`.
- **Signature errors**: Check that both API key and secret are correctly set in environment variables.

### Development Tips
- **Use IEx helpers**: The `.iex.exs` file provides convenient aliases and demos.
- **Check rate limits**: Use `H.rate_status()` in IEx to monitor rate limit usage.
- **Debug requests**: Enable debug mode with `ZenCex.Core.Debug.enable()` to export curl commands.
- **Tidewave for testing**: Use MCP tools for quick code testing without restarting the shell.
