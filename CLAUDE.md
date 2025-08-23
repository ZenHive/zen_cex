# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## IMPORTANT: Date Awareness

**Always check today's date** from the environment context (`<env>` section) when:
- Working with dates, timestamps, or time-based operations
- Calculating date ranges or intervals
- Referencing "recent" or "current" documentation
- Searching for the latest version of documentation or APIs
- Creating or updating date-sensitive code

**For Web Searches**:
- **NEVER use "2024" when searching for current/latest documentation**
- **ALWAYS use the current year from the `<env>` section (e.g., if today is 2025-08-17, use "2025")**
- Examples:
  - ❌ BAD: "Binance API rate limits 2024 documentation"
  - ✅ GOOD: "Binance API rate limits 2025 documentation" (when in 2025)
  - ✅ GOOD: "Binance API rate limits latest documentation"

The current date is provided in the `<env>` section as "Today's date: YYYY-MM-DD". Use this for all date-related operations and searches.

## Project Overview

**IMPORTANT: This library is not in your training data. Please do not assume you know how it works - make yourself familiar with it by reading the codebase.**

ZenCex is an Elixir library for centralized cryptocurrency exchange (CEX) REST API integrations, extracted from the BlockWatch Phoenix application. It provides a unified interface for interacting with cryptocurrency exchanges through their REST APIs with a focus on reliable position management and trading operations.

**Implementation Status**: See `docs/AI-IMPLEMENTATION.md` for current task progress and implementation status.

**IMPORTANT SCOPE**:
- **REST APIs ONLY** - No WebSocket implementation planned or desired
- **NOT for HFT** - This library is explicitly not for high-frequency trading
- **Focus on Reliability** - Prioritizes fault-tolerance over microsecond latency
- **Regular Trading Operations** - Position management, order execution, account queries

**Relationship to BlockWatch**: This library was extracted to be a standalone, reusable package for CEX integrations across the Elixir ecosystem. The parent BlockWatch application (../blockwatch) is a Phoenix LiveView app for monitoring DeFi positions.

## Development Commands

### Core Commands
```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix test --cover
mix coveralls.html  # Generate HTML coverage report

# Run a specific test file
mix test test/zen_cex/exchange/http_test.exs

# Run a specific test at a line number
mix test test/zen_cex/exchange/http_test.exs:42

# Run previously failed tests
mix test --failed

# Format code
mix format

# Check formatting without changes
mix format --check-formatted

# Run static analysis
mix credo --strict

# Run dialyzer type checking
mix dialyzer

# Check documentation coverage and specs
mix doctor              # Analyze docs, typespecs, and module health
mix doctor --full       # Detailed report for each module
mix doctor --summary    # Summary statistics only
mix doctor --failed     # Show only failed modules

# Generate documentation
mix docs

# Start interactive shell
iex -S mix

# Clean dependencies (rarely needed)
mix deps.clean --all  # Avoid unless necessary
```

### Test Categories
The test suite is organized into three categories:
- **Unit tests**: `*_test.exs` - Test individual functions and modules
- **Integration tests**: `*_integration_test.exs` - Test against real exchange APIs
- **Performance tests**: `*_performance_test.exs` - Benchmark high-load scenarios

## Tidewave MCP (Model Context Protocol)

Tidewave provides an MCP server for enhanced Elixir development capabilities. It allows Claude Code to directly interact with your Elixir project through specialized tools.

### Starting Tidewave

```bash
# Start Tidewave server on port 4000
# BUT CHECK FIRST IF IT IS RUNNING ALWAYS
mix tidewave

# The server runs continuously - keep it running during development
```

### Available MCP Tools

When Tidewave is running, Claude Code has access to these `mcp__tidewave__` prefixed tools:

1. **`mcp__tidewave__project_eval`** - Execute Elixir code in project context
   - Runs code with full project dependencies loaded
   - Returns both the result and any IO output
   - Includes IEx helpers (e.g., `exports(Module)`)
   - Supports timeout configuration
   - **PREFER THIS over shell commands for Elixir evaluation**

2. **`mcp__tidewave__get_docs`** - Get documentation for modules/functions
   - Works for project modules and dependencies
   - Accepts Module, Module.function, or Module.function/arity
   - Returns formatted documentation with examples

3. **`mcp__tidewave__get_source_location`** - Find source code locations
   - Returns file path and line number for any reference
   - Works for project code and dependencies
   - Useful for navigating to implementation details

4. **`mcp__tidewave__search_package_docs`** - Search Hex documentation
   - Searches documentation for project dependencies
   - Useful for finding usage examples and API details
   - Can filter by specific packages

5. **`mcp__tidewave__get_package_location`** - Get dependency locations
   - Returns file paths for installed dependencies
   - Helps locate dependency source code

6. **`mcp__tidewave__get_logs`** - View application logs
   - Filter by log level (debug, info, warning, error, etc.)
   - Tail recent log entries
   - Excludes logs from other tool calls

7. **`mcp__tidewave__list_liveview_pages`** - List active LiveViews
   - Shows currently connected LiveView sessions
   - Useful for Phoenix LiveView development

### Development Workflow with Tidewave

**IMPORTANT**: When Tidewave is available, prefer using MCP tools over starting the Phoenix server:

```elixir
# Instead of: iex -S mix or mix phx.server
# Use: mcp__tidewave__project_eval to test code

# Example: Test a module function
mcp__tidewave__project_eval(code: """
  ZenCex.Core.Registry.list_exchanges()
""")

# Example: Inspect module exports
mcp__tidewave__project_eval(code: """
  exports(ZenCex.Core.HTTP)
""")

# Example: Test with specific timeout
mcp__tidewave__project_eval(
  code: "Process.sleep(1000); :ok",
  timeout: 2000
)
```

### Benefits of Using Tidewave

1. **No Manual Server Management** - No need to start/stop IEx sessions
2. **Direct Code Execution** - Test functions without creating temporary files
3. **Full Project Context** - All dependencies and modules available
4. **Integrated Documentation** - Access docs without leaving the development flow
5. **Real-time Logs** - Monitor application behavior during testing
6. **Faster Iteration** - Immediate feedback without server restarts

### Common Tidewave Patterns

```elixir
# Check module compilation
mcp__tidewave__project_eval(code: "Code.ensure_loaded?(ZenCex.Core.HTTP)")

# Inspect ETS tables
mcp__tidewave__project_eval(code: ":ets.all() |> Enum.map(&:ets.info(&1, :name))")

# Test rate limiter
mcp__tidewave__project_eval(code: """
  alias ZenCex.Adapters.Binance.RateLimiter
  RateLimiter.check_and_increment(:spot_request)
""")

# Check application environment
mcp__tidewave__project_eval(code: "Application.get_all_env(:zen_cex)")
```

### Troubleshooting Tidewave

If Tidewave connection issues occur:
1. Ensure Tidewave is running: `mix tidewave`
2. Check for port conflicts on 4000
3. Verify dependencies with `mix deps.get`
4. Check logs with `mcp__tidewave__get_logs(tail: 20, level: "error")`

## Architecture

### Req-Centric REST Architecture Overview

**CRITICAL DESIGN**: This library is built entirely around Req's capabilities - we don't reimplement what Req already provides.

- **No custom HTTP client logic** - Req handles pooling (Finch), retry, telemetry
- **Middleware as Req steps** - Auth and rate limiting are just request/response steps
- **ETS over GenServers** - Atomic counters work better with Req's stateless pipeline
- **Minimal supervision** - Only OAuth tokens need state (when implemented)
- **Let Req handle complexity** - We just configure and compose

### Core Module Structure

1. **Application** (`lib/zen_cex/application.ex`)
   - Initializes ETS tables for rate limiting
   - Starts Finch for Req's connection pooling
   - Only supervises OAuth GenServers when needed (future Deribit implementation)

2. **Core.Registry** (`lib/zen_cex/core/registry.ex`)
   - Maps exchange names to endpoint modules
   - Runtime validation and loading
   - Exchange listing and capability queries
   - Currently only Binance is fully registered

3. **Core.HTTP** (`lib/zen_cex/core/http.ex`)
   - Configures Req's built-in features: pooling, retry, telemetry
   - Adds auth and rate limiting as Req request/response steps
   - Leverages Req's middleware pipeline instead of custom coordination

4. **Safety.ClockSync** (`lib/zen_cex/safety/clock_sync.ex`)
   - Synchronizes local time with exchange servers
   - Supports per-API-type synchronization (e.g., Binance spot vs futures)
   - Critical for exchanges requiring precise timestamps
   - ETS-based offset storage for performance

### Adapter Structure

Each exchange adapter in `ZenCex.Adapters.{Exchange}.*` consists of these cooperating modules:

#### Binance Adapter (Fully Implemented)
The Binance adapter is the most complete implementation supporting multiple API types:

1. **Router Module** (`endpoints.ex`) - Main entry point that delegates based on function prefixes
2. **API Type Modules** - Each handles specific trading types:
   - `spot.ex` - Spot trading
   - `margin.ex` - Cross and isolated margin
   - `usdm_futures.ex` - USD-M futures/USDT-margined
   - `coinm_futures.ex` - COIN-M futures/coin-margined
   - `portfolio_margin.ex` - Portfolio margin
   - `common.ex` - Shared endpoints like server_time
3. **Generated Endpoint Modules** - Auto-generated from endpoint definitions:
   - `generated_endpoints.ex` - Spot trading endpoints
   - `generated_margin_endpoints.ex` - Margin trading endpoints
   - `generated_usdm_endpoints.ex` - USD-M futures endpoints
   - `generated_coinm_endpoints.ex` - COIN-M futures endpoints
   - `generated_portfolio_endpoints.ex` - Portfolio margin endpoints
4. **Supporting Modules**:
   - `auth.ex` - HMAC-SHA256 authentication
   - `rate_limiter.ex` - Multi-API rate limiting with ETS
   - `parser.ex` - Response normalization
   - `signer.ex` - Request signing logic
   - `parameter_builder.ex` - Parameter construction
   - `request_helper.ex` - Request utilities
   - `endpoint_loader.ex` - Dynamic endpoint loading
   - `product_detector.ex` - API type detection
   - `strategies.ex` - Trading strategy helpers

#### Other Exchange Adapters
- **Bybit, Kraken, Deribit**: Not yet implemented
- See `docs/AI-IMPLEMENTATION.md` for implementation roadmap

### Why "Adapters" Namespace?

The `Adapters` namespace accurately describes the role of these modules:
- They **adapt** external exchange APIs to ZenCex's unified interface
- Each adapter is a **collection of modules** working together (not just endpoints)
- The pattern follows the Adapter design pattern from software architecture
- Future protocol support (if added) would still fit logically under this namespace

### Supervision Tree (Minimal - Leveraging Req)

```
ZenCex.Application
├── Finch (named: ZenCex.Finch)  # Req's connection pooling
└── (Future: OAuth GenServers when needed)

# No supervision needed for:
# - Rate limiters (ETS tables with atomic ops)
# - Auth modules (stateless Req steps)
# - HTTP operations (Req handles retry, telemetry)
```

### Key Design Patterns (Req-Powered REST)

1. **Req does the heavy lifting**: We configure, not reimplement - pooling, retry, telemetry all from Req
2. **Steps over GenServers**: Auth/rate-limiting as Req steps, not separate processes
3. **ETS for stateless ops**: Rate limit counters via ETS atomic ops fit Req's model
4. **Supervision only when needed**: OAuth tokens will need GenServer (future implementations)
5. **REST-Only by design**: No WebSocket complexity - Req excels at REST
6. **Leverage, don't build**: If Req has it, we use it; if not, we question if we need it

## Exchange-Specific Implementation Details

### Binance (Fully Implemented)

#### Architecture
- **Router Pattern**: Main `Endpoints` module delegates to API-specific modules based on function prefixes
- **Function Prefixes**: `spot_*`, `margin_*`, `usdm_*`, `coinm_*`, `portfolio_*` for clarity
- **Generated + Manual**: Combines macro-generated standard endpoints with hand-written complex operations

#### Endpoint Discovery
```elixir
# List all available endpoints
Endpoints.list_available_endpoints()

# List endpoints by API type
Endpoints.list_available_endpoints(:spot)
Endpoints.list_available_endpoints(:margin)
Endpoints.list_available_endpoints(:usdm_futures)

# Get detailed endpoint information
Endpoints.get_endpoint_info(:spot_get_balances)
# => Returns map with method, path, auth requirements, rate limits, etc.
```

#### Technical Details
- Requires `timestamp` and `recvWindow` parameters for authenticated requests
- Signature goes in query string as last parameter
- Uses `X-MBX-APIKEY` header for API key
- Rate limit weights reported in `x-mbx-used-weight-1m` header
- Separate rate limits maintained per API type
- ClockSync handles time synchronization per API type

### Other Exchanges
For planned exchange implementations and their technical requirements, see `docs/AI-IMPLEMENTATION.md`.

## Environment Variables

Required for authenticated operations:
```bash
# Binance
BINANCE_API_KEY=your_key
BINANCE_API_SECRET=your_secret

# Other exchanges (when implemented)
# See docs/AI-IMPLEMENTATION.md for required environment variables
```

## AI-Assisted Development Workflow

This project uses structured task management for development:
- **Task Tracking**: See `docs/AI-IMPLEMENTATION.md` for current tasks and progress
- **Review Process**: See `docs/AI-REVIEW.md` for validation checklists
- **Implementation Status**: Check AI-IMPLEMENTATION.md Phase sections for completed/pending work

### Documentation Writing Guidelines

When writing or updating docs/* files:
- **Be concise**: Use bullet points and short sentences
- **Avoid repetition**: Reference other docs instead of duplicating
- **Task updates only**: Update task status with single line (e.g., "✅ Task #10 COMPLETED")
- **No verbose explanations**: State facts, skip lengthy justifications
- **Use tables**: For comparisons and quick reference data
- **Minimal examples**: 3-5 lines max, only when essential
- **Skip preambles**: Get straight to the point
- **No redundant sections**: If it's in CLAUDE.md, don't repeat in docs/
- **Trust the AI Expert Developer**: It knows how to write software - skip HOW-to explanations, focus on WHAT is needed

## Important Implementation Notes

### Endpoint Registry Pattern

The library uses a sophisticated declarative endpoint registry pattern:

#### How It Works
1. **Endpoint Definition**: Each API module defines `@endpoints` with endpoint specifications
2. **Code Generation**: `EndpointRegistry` macro generates functions at compile time
3. **Router Delegation**: Main `Endpoints` module routes prefixed functions to appropriate modules
4. **Runtime Discovery**: Built-in functions for endpoint exploration and documentation

#### Key Features
- **Automatic Function Generation**: Standard operations generated from declarations
- **Manual Override**: Complex operations can be hand-written in the same module
- **Compile-time Validation**: Prevents dangerous patterns (e.g., retries on order placement)
- **Multi-Arity Support**: Generated functions support 0, 1, and 2 argument versions
- **Endpoint Discovery**: Runtime introspection of available endpoints and their details

#### Generated Files Pattern
Binance uses a dual-file approach:
- **API Module** (e.g., `spot.ex`): Contains endpoint definitions and complex operations
- **Generated Module** (e.g., `generated_endpoints.ex`): Auto-generated standard operations

This separation keeps the main modules focused while avoiding code duplication.

#### Debug Mode
```elixir
use ZenCex.EndpointRegistry, :debug  # Prints generated AST during compilation
```

### Trading Strategies Module

The Binance adapter includes a `Strategies` module with pre-built trading strategies:
- **`auto_hedge_spot_positions/2`** - Automatically hedge spot positions
- **`hedge_with_paxg_long/1`** - Hedge using PAXG (gold-backed token) long positions
- **`rebalance_paxg_perp_to_spot/1`** - Rebalance between PAXG perpetual and spot
- **`rebalance_portfolio/2`** - General portfolio rebalancing

These are high-level trading operations that coordinate multiple endpoints.

### Current Features
For current implementation status and completed features, see:
- **Implementation Progress**: `docs/AI-IMPLEMENTATION.md` (Phase sections)
- **Available Exchanges**: Currently only Binance is fully implemented
- **Core Features**: Req-centric architecture, endpoint discovery, multi-API support, clock sync
- **Safety Features**: Order validation, rate limiting with emergency bypass, idempotency protection

### Key Architectural Decisions
- **Req-centric EVERYTHING**: If Req can do it, we don't build it
- **Stateless by default**: OAuth tokens only exception (future implementations)
- **ETS + Req steps**: Rate limiting via atomic ops, not processes
- **No custom supervision**: Finch (via Req) manages connections
- **REST-only focus**: Req is built for REST, so are we
- **Reliability over speed**: Not for HFT, built for correctness
- **Code generation**: Macros eliminate boilerplate without runtime overhead

### Req HTTP Client Best Practices (from latest docs)

#### Step Implementation Patterns
Req uses a composable step-based middleware system. Steps must follow these signatures:

1. **Request Steps**: Take a request, return modified request OR `{request, response}` or `{request, exception}` to short-circuit
   ```elixir
   def my_request_step(request) do
     # Normal flow: modify and return request
     request
     |> Req.Request.put_header("x-custom", "value")

     # OR halt with error
     # Req.Request.halt(request, {:error, :my_error})

     # OR short-circuit with response
     # {request, %Req.Response{status: 200, body: "cached"}}
   end
   ```

2. **Response Steps**: Take `{request, response}`, return `{request, response}` or `{request, exception}`
   ```elixir
   def my_response_step({request, response}) do
     # Parse and return modified response
     {request, %{response | body: Jason.decode!(response.body)}}
   end
   ```

3. **Error Steps**: Take `{request, exception}`, return `{request, exception}` or `{request, response}`
   ```elixir
   def my_error_step({request, exception}) do
     # Convert error to response or propagate
     {request, %Req.Response{status: 503, body: "Service unavailable"}}
   end
   ```

#### Built-in Features to Leverage
- **Authentication**: Use `auth: {:bearer, token}` or `auth: fn -> {:bearer, get_token()} end` for dynamic tokens
- **Retry**: Built-in `:safe_transient` retry (GET/HEAD only) or custom retry functions
- **Finch Pooling**: Automatic connection pooling via `:finch` option
- **Telemetry**: Automatic telemetry events, hook into `[:req, :request, :*]` events
- **Compression**: Automatic gzip/deflate handling
- **JSON**: Automatic encoding/decoding with `:json` option

#### Private Field Usage
Use `request.private` for passing data between steps (reserved for libraries/frameworks):
```elixir
request
|> Req.Request.put_private(:exchange, :binance)
|> Req.Request.put_private(:zen_cex_operation, :place_order)
```

#### Step Ordering
- Use `append_request_steps/2` to add steps at the end (common case)
- Use `prepend_request_steps/2` to add steps before built-in steps
- Order matters: auth → rate limit → retry → telemetry

#### Error Handling with Req.Request.halt/2
Use `halt/2` to stop pipeline execution:
```elixir
def circuit_breaker_step(request) do
  if CircuitBreaker.open?(request.private[:exchange]) do
    Req.Request.halt(request, {:error, :circuit_breaker_open})
  else
    request
  end
end
```

#### Performance Considerations
- Steps should be lightweight and non-blocking
- Use ETS for shared state (rate limits, circuit breakers)
- Leverage Req's built-in features instead of reimplementing
- Configure Finch pools appropriately for your load:
  ```elixir
  finch_options: [
    conn_opts: [transport_opts: [timeout: 5_000]],
    pool_timeout: 5_000,
    receive_timeout: 15_000
  ]
  ```

## Testing Strategy: Real APIs Only (TESTNET ONLY)

### Simple Rule: ALL Tests Must Use Real TESTNET APIs

We test against real exchange testnet/sandbox APIs. Period.
No mocks. No fixtures. No simulation. Just real testnet APIs.
**NEVER use production APIs in tests.**

### Test Categories

1. **Unit Tests** (`*_test.exs`)
   - Test pure functions only (parsers, calculations)
   - No API calls needed

2. **Integration Tests** (`*_integration_test.exs`)
   - Test against REAL testnet/sandbox APIs only
   - Tag with `@tag :integration`
   - **FAIL if credentials missing** - Don't skip/hide missing tests
   - **FAIL if not using testnet** - Prevent production API calls
   - Must document actual API responses

### Testnet URLs (ENFORCED IN TESTS)

```elixir
# These are the ONLY allowed URLs in test environment
# Currently only Binance is implemented:
@test_hosts %{
  binance: "testnet.binance.vision"
  # Future implementations will add:
  # bybit: "api-testnet.bybit.com"
  # kraken: "api.kraken.com"
  # deribit: "test.deribit.com"
}

# Tests MUST verify testnet usage - use the adapter's current_env() method
alias ZenCex.Adapters.Binance.Endpoints
assert Endpoints.current_env() == :test
assert Endpoints.base_url() == "https://testnet.binance.vision"
```

### Running Tests

```bash
# Run unit tests only (fast, no API)
mix test --exclude integration

# Run ALL tests including real API tests (requires TESTNET credentials)
BINANCE_TESTNET=true BINANCE_TESTNET_API_KEY=xxx BINANCE_TESTNET_API_SECRET=yyy mix test

# Run specific exchange integration tests
mix test --only integration:binance

# Check what integration tests exist (should FAIL without credentials)
mix test --only integration
```

**Note: First Test Run Behavior**
When running tests that connect to real testnet APIs, some tests may fail on the first run due to initial connection setup and synchronization. This is expected behavior. To ensure all tests pass:
1. Run `mix test` (some tests may fail initially)
2. Run `mix test --failed --trace` to re-run only the failed tests with detailed output
3. Failed tests should pass on the second run once connections are established

### Writing Integration Tests

**Integration tests follow a consistent pattern** for testing against real testnet APIs:

```elixir
defmodule ZenCex.Adapters.BinanceIntegrationTest do
  # The IntegrationCase handles all testnet enforcement automatically
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot
  
  alias ZenCex.Adapters.Binance.Spot

  test "get_balances returns real testnet balances" do
    # This calls the REAL Binance testnet API
    assert {:ok, balances} = Spot.get_balances()
    assert is_list(balances)
    
    # Document actual response structure from TESTNET
    # Binance testnet returns: [%{"asset" => "BTC", "free" => "0.0", "locked" => "0.0"}, ...]
  end

  test "place_order with invalid symbol returns real error" do
    # This gets REAL error from Binance TESTNET
    assert {:error, reason} = Spot.place_order(%{
      symbol: "INVALID",
      side: "BUY",
      quantity: "1"
    })

    # Document what Binance TESTNET actually returns
    # Binance testnet error: {"code": -1121, "msg": "Invalid symbol."}
    assert reason =~ "Invalid symbol" or reason == {:invalid_symbol, _}
  end
  
  # Use the with_env macro for testing env variable changes
  test "authentication errors are properly formatted" do
    with_env [{"BINANCE_TESTNET_API_KEY", "invalid_key"}] do
      assert {:error, _} = Spot.get_balances()
    end
  end
end
```

Integration tests must:
- Verify testnet URL in setup/setup_all
- Document actual API responses from testnet
- Fail loudly if credentials are missing
- Never skip tests - fail fast to ensure visibility
- Use `@tag :integration` for test filtering

### Benefits

- **Dead simple rule**: Real testnet APIs or no test
- **No bad mocks**: Can't mock what you haven't seen
- **Self-documenting**: Tests show real behavior
- **Forces integration testing**: Tests fail loudly without credentials
- **Production safety**: Tests fail if not using testnet
- **Fast local dev**: `--exclude integration` for unit tests only

### Environment Variable Naming

**CRITICAL**: Use `_TESTNET_` in environment variable names to prevent confusion:

```bash
# GOOD - Clear these are testnet credentials
BINANCE_TESTNET_API_KEY=xxx
BINANCE_TESTNET_API_SECRET=yyy
KRAKEN_TESTNET_API_KEY=xxx
DERIBIT_TESTNET_CLIENT_ID=xxx

# BAD - Ambiguous, could be production
BINANCE_API_KEY=xxx  # NEVER use in tests
BINANCE_SECRET=yyy   # NEVER use in tests
```

### CI Configuration

```yaml
# For CI: Either provide TESTNET credentials or explicitly exclude integration tests
- name: Run tests
  env:
    MIX_ENV: test
    BINANCE_TESTNET_API_KEY: ${{ secrets.BINANCE_TESTNET_KEY }}
    BINANCE_TESTNET_API_SECRET: ${{ secrets.BINANCE_TESTNET_SECRET }}
  run: |
    # Option 1: With testnet credentials (recommended)
    mix test
    
    # Option 2: Unit tests only (explicit choice)
    mix test --exclude integration
```

### Production Safety Checklist

- [ ] All integration tests verify testnet URL in setup
- [ ] Environment variables include `_TESTNET_` in name
- [ ] Config files set testnet URLs for test environment
- [ ] Tests fail loudly if production URL detected
- [ ] No production credentials in test fixtures or examples

### Coverage Targets
- Overall: 80% minimum
- Critical paths: 95% minimum
- GenServer modules: 100% with proper error handling tests

## Module Dependencies

Critical internal dependencies to be aware of:
- **Registry Pattern**: Endpoints modules (main adapter entry points) register with `Core.Registry` at compile time
- **Delegation Chain**: `Core.HTTP` → `Core.Registry` → `Adapters.{Exchange}.Endpoints` → specific adapter modules
- **Stateful Components**: OAuth GenServers will be used when needed (future implementations)
- **Rate Limiting**: Each adapter's RateLimiter manages its own ETS tables independently
- **Telemetry**: All modules emit telemetry events for monitoring and debugging

### Module Cooperation Example

When calling `Binance.Endpoints.get_balances/1`:
1. The Endpoints module defines the operation via `@endpoints`
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

Following BlockWatch's Elixir best practices:

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
Following BlockWatch's philosophy:
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

Following BlockWatch's testing policy:
```
[!] TESTING POLICY [!]
--------------------------------------------------
ALWAYS test against REAL APIs first to understand behavior.
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
