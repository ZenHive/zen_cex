# AGENTS.md - ZenCex Library Guidelines

This document provides essential guidelines for AI agents working with the ZenCex library. It focuses on Elixir patterns and library-specific requirements that must be followed.

## Critical: This is NOT a Phoenix Application

ZenCex is a **standalone Elixir library** for cryptocurrency exchange REST APIs:
- **No Phoenix framework** - Pure Elixir/OTP application
- **No LiveView** - Command-line and programmatic usage only
- **No web interface** - Library consumers build their own UIs
- **No routing** - Direct function calls to adapter modules
- **No templates** - API responses only

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
lib/zen_cex/adapters/{exchange}/
├── endpoints.ex         # Main entry point (router)
├── auth.ex             # Authentication (HMAC, OAuth, etc.)
├── rate_limiter.ex     # Rate limiting with ETS
├── parser.ex           # Response normalization
└── generated_*.ex      # Auto-generated from @endpoints
```

### Endpoint Registry Pattern

Use the declarative `@endpoints` pattern for standard operations:
```elixir
@endpoints [
  get_balances: [
    method: :get,
    path: "/api/v3/account",
    auth: :required,
    weight: 10
  ]
]
```

Hand-code complex operations that need special logic.

### Testing Requirements

**CRITICAL: Test against REAL TESTNET APIs only**
- **NO mocks or fixtures** - Use real exchange testnets
- **NO production APIs** in tests
- **FAIL loudly** if testnet credentials missing
- **Document actual API responses** from testnets

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

When calling `ZenCex.Adapters.Binance.Endpoints.spot_get_balances/1`:
1. Router module delegates based on prefix
2. Core.HTTP creates Req request with middleware
3. Auth module signs request (HMAC-SHA256 for Binance)
4. RateLimiter checks and updates limits via ETS
5. Parser normalizes response format
6. Telemetry events emitted at each stage

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

- This is a **library**, not an application
- Consumers integrate this into their own apps (Phoenix, LiveView, etc.)
- Focus on the API client functionality, not UI concerns
- Keep dependencies minimal - only what's needed for REST APIs
- Performance matters but reliability matters more
- Always check `docs/AI-IMPLEMENTATION.md` for current task status