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

## Prerequisites
- **Read AGENTS.md first** - Contains Elixir patterns, testing requirements, and module cooperation patterns
- **Date Awareness**: Always use current year from `<env>` section for searches (e.g., "Binance API 2025" not "2024")

## Project Overview

ZenCex - Elixir library for crypto exchange APIs (REST + WebSocket via zen_websocket).

**Scope**:
- REST for trading operations (30s-5min intervals)
- WebSocket for real-time market data via [zen_websocket](https://github.com/ZenHive/zen_websocket)
**Design**: Req-centric HTTP, ETS state, minimal supervision, Gun-based WebSocket

**zen_websocket Access**: The zen_websocket library code is available via symlink at `./zen_websocket/` for reference and understanding of WebSocket implementation details.

**Use Cases**:
- Real-time market data streaming (order books, trades, tickers)
- Position monitoring & exposure calculation
- Portfolio hedging & rebalancing
- Subaccount risk isolation
- Trade execution on signals

## Commands

```bash
mix deps.get              # Install dependencies
mix test                  # Run all tests
mix test --exclude integration  # Unit tests only
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

## Environment Variables

```bash
# Binance (spot/futures have separate testnets!)
BINANCE_TESTNET_API_KEY=xxx       # testnet.binance.vision
BINANCE_FUTURES_TEST_API_KEY=xxx  # testnet.binancefuture.com

# Bybit
BYBIT_TESTNET_API_KEY=xxx         # api-testnet.bybit.com
```


## Key Implementation Notes

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

**Source Access**: Full zen_websocket source code available at `./zen_websocket/` (symlink to `/Users/efries/_DATA/code/zen_websocket`).
- Main modules: `./zen_websocket/lib/zen_websocket/*.ex`
- Tests for reference: `./zen_websocket/test/*.exs`
- **Examples**: `./zen_websocket/test/zen_websocket/examples/` - Comprehensive usage examples including:
  - `basic_usage_test.exs` - Simple connection and messaging
  - `supervised_client_test.exs` - Production supervision patterns
  - `subscription_management_test.exs` - Channel subscription patterns
  - `error_handling_test.exs` - Error recovery strategies
  - `rate_limiting_test.exs` - Rate limit handling
  - `platform_adapter_template_test.exs` - Exchange adapter patterns
- Documentation: `./zen_websocket/README.md` and `./zen_websocket/CLAUDE.md`

**Core API** (5 functions only):
- `connect/2` - Establish WebSocket connection
- `send/2` - Send messages to server
- `subscribe/2` - Subscribe to data channels
- `state/1` - Check connection state
- `close/1` - Close connection

**Usage Patterns**:
```elixir
# Development - Direct connection
{:ok, ws} = ZenWebsocket.connect("wss://stream.binance.com:9443/ws", [])
:ok = ZenWebsocket.subscribe(ws, "btcusdt@trade")

# Production - Supervised connection
children = [
  {ZenWebsocket.ClientSupervisor, name: :market_data_supervisor},
  {Binance.WebSocket.MarketData, symbol: "BTCUSDT"}
]
```

**Design Rules** (from zen_websocket):
- Start simple: Direct connections for development
- Add supervision only for production
- Always test against real WebSocket endpoints
- Use built-in retry and heartbeat mechanisms
- Maximum 5 public functions per WebSocket module
- Leverage telemetry for monitoring

**Market Data Caching**:
- Store latest tickers/orderbooks in ETS
- Update via WebSocket callbacks
- REST fallback for initial state
- TTL-based cache invalidation

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
