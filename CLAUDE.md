# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZenCex is an Elixir library for centralized cryptocurrency exchange (CEX) REST API integrations, extracted from the BlockWatch Phoenix application. It provides a unified interface for interacting with multiple exchanges (Binance, Kraken, Deribit) through their REST APIs with a focus on trading operations.

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

## Architecture

### Req-Centric Architecture Overview

The library leverages **Req's built-in capabilities** instead of custom OTP supervision:

- **Core Modules** (`ZenCex.Core.*`): Thin coordination layer using Req middleware
- **Behaviors** (`ZenCex.Behaviors.*`): Contracts for Req-based adapters
- **Adapters** (`ZenCex.Adapters.{Binance,Kraken,Deribit}.*`): Stateless modules (except Deribit OAuth)

### Core Module Structure

1. **Application** (`lib/zen_cex/application.ex`)
   - Initializes ETS tables for rate limiting
   - Starts Finch for Req's connection pooling
   - Only supervises Deribit.Auth GenServer (OAuth state)

2. **Core.Registry** (`lib/zen_cex/core/registry.ex`)
   - Compile-time validation of adapters
   - Runtime adapter lookup and validation
   - Exchange listing and capability queries

3. **Core.HTTP** (`lib/zen_cex/core/http.ex`)
   - Configures Req's built-in features: pooling, retry, telemetry
   - Adds auth and rate limiting as Req request/response steps
   - Leverages Req's middleware pipeline instead of custom coordination

### Adapter Components

Each exchange adapter implements these modules:

1. **Adapter Module** (`lib/zen_cex/adapters/{exchange}/adapter.ex`)
   - Entry point implementing `Behaviors.Adapter`
   - Coordinates all exchange-specific functionality
   - Returns child specs for supervision

2. **Auth Module** (`lib/zen_cex/adapters/{exchange}/auth.ex`)
   - Implements `Behaviors.Auth` behavior
   - Exchange-specific authentication (HMAC, OAuth, etc.)
   - Credential management from environment

3. **RateLimiter** (`lib/zen_cex/adapters/{exchange}/rate_limiter.ex`)
   - Implements `Behaviors.RateLimiter` behavior
   - Exchange-specific rate limiting logic
   - ETS-based atomic counters for performance

4. **WebSocket** (`lib/zen_cex/adapters/{exchange}/websocket.ex`)
   - Implements `Behaviors.WebSocket` behavior
   - Public market data streams only
   - Exchange-specific frame handling

### Supervision Tree (Minimal - Leveraging Req)

```
ZenCex.Application
├── Finch (named: ZenCex.Finch)  # Req's connection pooling
└── ZenCex.Adapters.Deribit.Auth  # Only stateful component (OAuth)

# No supervision needed for:
# - Rate limiters (ETS tables with atomic ops)
# - Auth modules (stateless Req steps)
# - HTTP operations (Req handles retry, telemetry)
```

### Key Design Patterns (Req-Powered)

1. **Req's Built-in Features**: Connection pooling (Finch), retry logic, telemetry - no custom implementation needed
2. **Req Middleware Steps**: Auth and rate limiting as composable request/response steps
3. **ETS Without GenServers**: Atomic counters for rate limiting work better with Req's pipeline
4. **Single-Flight Protection**: OAuth token refresh (only stateful operation)
5. **WebSocket Separation**: zen_websocket for streams (Req doesn't support WebSocket)
6. **Minimal Supervision**: Only Deribit OAuth needs a process - everything else is stateless

## Exchange-Specific Implementation Details

### Binance
- Requires `timestamp` and `recvWindow` parameters for authenticated requests
- Signature goes in query string as last parameter
- Uses `X-MBX-APIKEY` header for API key
- Rate limit weights reported in `x-mbx-used-weight-1m` header

### Kraken
- Uses nonce-based authentication (microseconds + counter)
- All private endpoints use POST with `application/x-www-form-urlencoded`
- API secret is base64-encoded (library handles both encoded and raw for testing)
- Rate limits based on verification tier

### Deribit
- OAuth2 with client credentials flow
- Tokens cached with automatic refresh 120 seconds before expiry
- JSON-RPC style API (even for REST endpoints)
- Separate test environment at test.deribit.com

## Environment Variables

Required for authenticated operations:
```bash
# Binance
BINANCE_API_KEY=your_key
BINANCE_API_SECRET=your_secret

# Kraken  
KRAKEN_API_KEY=your_key
KRAKEN_API_SECRET=your_secret

# Deribit
DERIBIT_CLIENT_ID=your_client_id
DERIBIT_CLIENT_SECRET=your_secret
DERIBIT_HOST=test.deribit.com  # or www.deribit.com for production
```

## Current Implementation Status

### Completed Components
- ✅ Core.Registry - Adapter registration and lookup
- ✅ Binance.RateLimiter - ETS tables with atomic operations
- ✅ Binance.Auth - HMAC-SHA256 as Req step
- ✅ Initial test coverage for core modules

### In Progress
- 🔄 Removing Core.Supervisor (Task #2) - Use Req's features instead
- 🔄 Refactoring to Req middleware steps
- 🔄 Remaining exchange adapters (Kraken, Deribit)
- 🔄 Integration tests leveraging Req.Test

### Documentation  
- **docs/AI-IMPLEMENTATION.md** - Single source of truth for AI coders (283 lines)
  - Combines all previous docs (was 2,346 lines across 4 files)
  - One-task-per-session rule with current task tracking
  - Essential patterns with minimal code examples
  - Common AI coder mistakes and solutions
  - Validation checklists and performance targets

## Important Implementation Notes

### Current Status
- Req-centric architecture leveraging built-in features
- Removing redundant OTP supervision (Task #2 in progress)
- Binance adapter being refactored to use Req steps
- Focus on utilizing Req's capabilities instead of reimplementing

### Key Architectural Decisions
- **Req-centric design**: Leverage built-in pooling, retry, telemetry instead of custom OTP
- **Stateless adapters**: Only Deribit OAuth needs GenServer for token state
- **ETS with Req middleware**: Rate limiting as request steps with atomic counters
- **No Core.Supervisor**: Req's Finch handles connection lifecycle
- **Minimal processes**: Let Req handle complexity, we just configure it

## Testing Approach

The codebase follows Test-Driven Development (TDD) with three test categories:

1. **Unit Tests**: Pure functions, no external dependencies
2. **Integration Tests**: Real API calls with test credentials (PREFERRED)
3. **Performance Tests**: Load testing and benchmarking

When adding new features:
1. Write failing tests first
2. Implement minimal code to pass tests
3. Refactor while keeping tests green
4. Add integration tests for real API validation
5. Only add mocks after validating against real APIs

### Coverage Targets
- Overall: 80% minimum
- Critical paths: 95% minimum  
- GenServer modules: 100% with proper error handling tests

## Module Dependencies

Critical internal dependencies to be aware of:
- Adapters register with `Core.Registry` at compile time
- `Core.HTTP` delegates to adapter-specific implementations
- `Deribit.Auth` runs as a GenServer for OAuth token management
- Each adapter's RateLimiter manages its own ETS tables
- All modules emit telemetry events for monitoring

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
PREFER REAL APIs over mocks whenever possible.
Test against real exchange APIs when available.
Mocks should only be used for truly external dependencies.
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