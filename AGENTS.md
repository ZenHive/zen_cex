# AGENTS.md - ZenCex Library Guidelines

This document provides essential guidelines for AI agents working with the ZenCex library. It focuses on Elixir patterns and library-specific requirements that must be followed.

## Critical: Library Scope and Focus

ZenCex is an **Elixir library** for cryptocurrency exchange REST APIs:
- **Binance & Bybit only** - Two exchanges covering 80%+ of volume
- **REST APIs only** - Perfect for position monitoring and hedging
- **Market data + Trading** - Prices, order books, positions, orders
- **NOT for HFT** - Designed for 30s-5min intervals, not microseconds
- **No WebSocket** - REST-only by design, no streaming

## Elixir Language Guidelines

### Core Language Patterns

- **Lists don't support index access** - Use `Enum.at/2`, pattern matching, or `List` module
  ```elixir
  # INVALID
  mylist[0]
  
  # VALID
  Enum.at(mylist, 0)
  [first | _rest] = mylist
  ```

- **Variables are immutable but rebindable** - Bind expression results to use them:
  ```elixir
  # INVALID: rebinding inside expression doesn't work
  if condition do
    state = Map.put(state, :key, value)
  end

  # VALID: rebind the result
  state =
    if condition do
      Map.put(state, :key, value)
    else
      state
    end
  ```

- **Never nest multiple modules** in the same file (causes cyclic dependencies)
- **Never use map access syntax** on structs - Use dot notation (`struct.field`)
- **Never use `String.to_atom/1`** on user input (memory leak risk)
- **Predicate functions** should end with `?`, not start with `is_`
- **Use `Task.async_stream/3`** for concurrent operations with back-pressure

### HTTP Client Requirements

- **ALWAYS use Req** for HTTP requests - It's the only HTTP client in this library
- **NEVER use** HTTPoison, Tesla, or :httpc
- **Leverage Req's built-in features**:
  - Connection pooling via Finch
  - Retry logic for safe operations
  - Telemetry integration
  - Request/response steps for middleware

## Library-Specific Patterns

### Module Structure

Each exchange adapter consists of cooperating modules:
```
lib/zen_cex/adapters/binance/ 
lib/zen_cex/adapters/bybit/
```

### Endpoint Registry Pattern

Use the declarative `@endpoints` pattern:
```elixir
# Define endpoints
@endpoints [
  get_ticker_price: [
    method: :get,
    path: "/api/v3/ticker/price",
    auth: false,
    weight: 2,
    category: :market_data
  ],
  get_balances: [
    method: :get,
    path: "/api/v3/account",
    auth: :required,
    weight: 10,
    category: :spot
  ]
]
```

### Authentication Options

Endpoints support custom credentials via options (keyword list or map):
```elixir
# Using environment variables (default)
{:ok, data} = Exchange.spot_get_balances()

# Using custom credentials as keyword list
opts = [auth_credentials: %{api_key: "key", api_secret: "secret"}]
{:ok, data} = Exchange.spot_get_balances(%{}, opts)

# Using custom credentials as map
opts = %{auth_credentials: %{api_key: "key", api_secret: "secret"}}
{:ok, data} = Exchange.spot_get_balances(%{}, opts)
```

### Testing Requirements

**CRITICAL: Test against REAL TESTNET APIs only**
- **Binance testnet**: `testnet.binance.vision`
- **Bybit testnet**: `api-testnet.bybit.com`
- **NO mocks or fixtures** - Use real exchange testnets
- **NO production APIs** in tests
- **FAIL loudly** if testnet credentials missing
- **Document actual API responses** from testnets

```bash
# Required for integration tests
export BINANCE_TESTNET_API_KEY="your_testnet_key"
export BINANCE_TESTNET_API_SECRET="your_testnet_secret"
export BYBIT_TESTNET_API_KEY="your_testnet_key"
export BYBIT_TESTNET_API_SECRET="your_testnet_secret"
```

### Error Handling

- Return `{:ok, result}` or `{:error, reason}` tuples
- **Pass raw errors without wrapping** in custom structs
- Apply "let it crash" philosophy for unexpected errors
- Use telemetry for error reporting
- **Never rescue exceptions** unless absolutely necessary

### Development Commands

```bash
# Essential commands
mix deps.get           # Install dependencies
mix test              # Run tests
mix test --cover      # Coverage report
mix format            # Format code
mix credo --strict    # Static analysis
mix dialyzer          # Type checking
mix doctor            # Module health check
mix precommit         # Run all checks

# Testing
mix test --exclude integration    # Unit tests only
mix test --only integration       # Integration tests only
```

## Common Pitfalls to Avoid

1. **Creating Phoenix-like patterns** - This isn't a web framework
2. **Adding web dependencies** - No Phoenix, Plug, or web servers
3. **Using GenServers for everything** - Prefer ETS for stateless operations
4. **Mock-heavy testing** - Test against real testnet APIs
5. **Custom HTTP logic** - Use Req's built-in capabilities
6. **Deep module nesting** - Keep module hierarchy shallow
7. **Overly complex abstractions** - Start simple, add complexity only when proven necessary

## Key Architectural Decisions

- **Req-centric**: If Req can do it, we don't build it
- **ETS over GenServers**: For rate limiting and caching
- **Minimal supervision**: Only OAuth tokens need GenServers (future)
- **REST-only focus**: No WebSocket complexity
- **Declarative endpoints**: Macro-generated standard operations
- **Testnet-first testing**: Real APIs or no test

## Module Cooperation Example

When calling `ZenCex.Adapters.Binance.Endpoints.spot_get_ticker_price/1`:
1. **Router delegation** - `Endpoints` module routes to `Spot` module
2. **Request creation** - Core.HTTP builds Req request
3. **Rate limiting** - Check/update ETS counters
4. **Authentication** - Add API key/signature if needed
5. **Response parsing** - Normalize exchange format
6. **Telemetry** - Events at each stage for monitoring

## Documentation Standards

- **Module documentation**: Every module needs @moduledoc
- **Function documentation**: Public functions need @doc
- **Type specifications**: All public functions need @spec
- **Examples in docs**: Show actual usage, not theoretical
- **NO IO operations in @doc examples** - Just show the API:
  ```elixir
  # BAD in @doc
  IO.puts("Balance: #{balance}")
  
  # GOOD in @doc
  {:ok, balances} = Binance.Endpoints.spot_get_balances()
  ```

## Important Reminders

- **Two exchanges only** - Binance and Bybit with comprehensive support
- **REST-only** - Perfect for position monitoring, not for HFT
- **Market data + Trading** - Both public and authenticated endpoints
- Keep dependencies minimal - only what's needed for REST APIs
- Performance matters but reliability matters more
- Check `docs/refactoring_sessions.md` for implementation roadmap

## Perfect Use Cases

This library excels at:
- **Position monitoring** - Check balances/positions every 30s-5min
- **Portfolio hedging** - Calculate exposure and place hedge orders
- **Subaccount management** - Transfer funds for risk isolation
- **Automated trading** - Execute trades based on signals
- **Market data collection** - Fetch prices, order books, klines

NOT suitable for:
- High-frequency trading (need WebSocket/FIX)
- Market making with <100ms latency
- Real-time order book streaming
- Arbitrage requiring instant updates