# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ZenCex is an Elixir library for centralized cryptocurrency exchange (CEX) integrations, extracted from the BlockWatch Phoenix application. It provides a unified interface for interacting with multiple exchanges (Binance, Kraken, Deribit) through REST APIs, with planned WebSocket support for real-time market data.

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

### Core Module Structure

The library is organized around the `ZenCex.Exchange` namespace with specialized modules for different concerns:

1. **HTTP Client Layer** (`lib/zen_cex/exchange/http.ex`)
   - Built on REQ with Finch for connection pooling
   - Implements exponential backoff with jitter: `min(2^n * 1000, 60000) + random(0-500)ms`
   - Middleware pipeline for request/response processing
   - Operation-specific timeouts (trading: 2s, market: 5s, historical: 30s)

2. **Authentication** (`lib/zen_cex/exchange/auth.ex`)
   - Binance: HMAC-SHA256 signatures with timestamp/recvWindow
   - Kraken: HMAC-SHA512 with atomic nonce generation via ETS
   - Deribit: OAuth2 with automatic token refresh (120s buffer)
   - Environment-based credential management

3. **Rate Limiting** (`lib/zen_cex/exchange/rate_limit.ex`)
   - Atomic ETS counters for lock-free concurrent access
   - True sliding window for Binance (60 per-second buckets)
   - Per-exchange limits: Binance (1200/min), Binance Futures (2400/min), Kraken (15/sec), Deribit (20/sec)
   - Automatic cleanup of expired windows every 60 seconds
   - Header-based reconciliation for server-reported weights

4. **Health Monitoring** (`lib/zen_cex/exchange/health/`)
   - Clock sync validation with configurable thresholds (300ms warning, 500ms critical)
   - Multi-exchange consensus detection using median drift
   - Startup health checks via `Health.Startup` GenServer
   - Periodic monitoring via `Health.Monitor` GenServer

5. **Caching** (`lib/zen_cex/exchange/cache.ex`)
   - TTL-based ETS caching with automatic cleanup
   - Separate tables for positions, balances, and market data
   - Public tables for concurrent read access
   - Memory statistics via `get_stats/0`

6. **Telemetry** (`lib/zen_cex/exchange/telemetry.ex`)
   - Comprehensive event emission for monitoring
   - Attached handlers for rate limiting and health events
   - Integration points for external monitoring systems

### Supervision Tree

```
ZenCex.Application
├── Finch (named: ZenCex.Finch)
├── ZenCex.RateLimit
├── ZenCex.Health.Monitor
└── ZenCex.Health.Startup
```

### Key Design Patterns

1. **Atomic Operations**: Rate limiting uses ETS atomic counters instead of GenServer state to avoid bottlenecks
2. **Single-Flight Protection**: OAuth token refresh uses in-flight tracking to prevent concurrent token requests
3. **Middleware Architecture**: REQ request/response steps for cross-cutting concerns
4. **Table Partitioning**: Separate ETS tables per exchange for optimal concurrent access
5. **Public ETS Tables**: Direct ETS access for read operations, GenServer only for cleanup/management

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

### Completed Modules (62.5%)
- ✅ Exchange.HTTP - REQ-based HTTP client with middleware
- ✅ Exchange.Auth - Multi-exchange authentication strategies  
- ✅ Exchange.RateLimit - Atomic rate limiting with sliding windows
- ✅ Exchange.Health - Clock sync and consensus monitoring
- ✅ Exchange.Cache - TTL-based caching with cleanup

### Pending Modules
- ⏳ Exchange.MarketData - WebSocket support for real-time data
- ⏳ Exchange.Parser - Response normalization across exchanges
- ⏳ Exchange.Client - Unified orchestration layer

## Important Implementation Notes

### From Task Documentation (docs/cex-implementation-tasks.md)
- Overall completion: 62.5% (5/8 modules)
- Average quality rating: 4.6/5 for completed modules
- Timeline estimate: 4 days total (Day 1 REST APIs completed)
- WebSocket implementation (Day 2) not yet started

### Key Architectural Decisions
- **WebSocket for public market data, REST for authenticated operations**
- **Atomic ETS over GenServer state** for rate limiting (lock-free concurrency)
- **Single-flight protection** for OAuth token refresh
- **True sliding window** for Binance rate limits (60 per-second buckets)
- **Median-based consensus** for multi-exchange health monitoring

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
- `HTTP` module depends on `RateLimit` for pre-request checking
- `Auth.DeribitOAuth` is a separate GenServer for token management
- `Health.Monitor` depends on `Endpoints` for time endpoint definitions
- All modules emit telemetry events via `Telemetry` module
- `ReqHelpers` provides utilities for REQ private data management

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