# CLAUDE.md

Guidance for Claude Code when working with the ZenCex library.

## Prerequisites
- **Read AGENTS.md first** - Contains Elixir patterns, testing requirements, and module cooperation patterns
- **Date Awareness**: Always use current year from `<env>` section for searches (e.g., "Binance API 2025" not "2024")

## Project Overview

ZenCex - Elixir library for crypto exchange REST APIs (Binance & Bybit).

**Scope**: REST-only, 30s-5min intervals, not for HFT
**Design**: Req-centric HTTP, ETS state, minimal supervision

**Use Cases**:
- Position monitoring & exposure calculation
- Portfolio hedging & rebalancing
- Subaccount risk isolation
- Market data collection
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

## Tidewave MCP

Start with `mix tidewave` (port 4001). Use MCP tools for testing:
- `mcp__tidewave__project_eval` - Execute code in project context
- `mcp__tidewave__get_docs` - Get module/function docs
- `mcp__tidewave__get_source_location` - Find source locations
- `mcp__tidewave__search_package_docs` - Search Hex docs
- `mcp__tidewave__get_logs` - View application logs

## Debug Module

Enable with `ZenCex.Core.Debug.enable()` to export failed requests as curl commands:
- `get_last_curl()` - Get last failed request as curl
- `get_recent_curls(n)` - Get n recent failures
- `stats()` - Debug statistics
- `clear()` - Clear debug data

## Architecture

### Core Modules
- **Application**: ETS tables, Finch pooling
- **Core.Registry**: Exchange → module mapping
- **Core.HTTP**: Req configuration with auth/rate-limit steps
- **Safety.ClockSync**: Time sync with exchanges

### Adapters

**Binance** (complete):
- Direct module usage: `Spot`, `Margin`, `UsdmFutures`, `CoinmFutures`, `PortfolioMargin`
- Supporting: `Auth`, `RateLimiter`, `Parser`, `Strategies`

**Bybit** (trading complete):
- Direct module usage: `Unified`, `Common`, `MarketData`
- Market data pending

### Design Patterns
- Req middleware for everything (auth, rate-limiting)
- ETS for state (rate limits, clock sync)
- Minimal supervision (only OAuth needs GenServer)

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

## Testing

**RULE: Test against REAL testnet APIs only. No mocks without real API testing first.**
** You can TEST with Tidewave first to understand behavior. **

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

### HTTP Client
- **Always use Req** for HTTP requests - It's the preferred client
- **Avoid** HTTPoison, Tesla, and :httpc

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

### Testing Philosophy
```
[!] TESTING POLICY [!]
--------------------------------------------------
ALWAYS test against REAL APIs first to understand behavior.
You can TEST with Tidewave first to understand behavior.
NEVER create mocks without first testing real APIs.
Document actual API responses and edge cases from real testing.
Mocks must exactly match observed real API behavior.
This ensures reliable, production-ready code.
--------------------------------------------------
```

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
