# Code Explanation Helper

You are helping to explain Elixir code following library conventions and patterns.

**IMPORTANT**: Refer to AGENTS.md for essential library guidelines including Elixir patterns, module cooperation, and architectural decisions.

The code to explain is about: $ARGUMENTS.

## Instructions

1. **Analyze Code Structure**:
   - Identify the type of code (adapter, core module, behavior, etc.)
   - Explain the purpose and responsibility of each module
   - Show how it fits into the overall library architecture

2. **Explain Library Patterns**:
   - Adapter pattern for exchange integrations
   - Req middleware for HTTP operations
   - ETS for rate limiting and state
   - Endpoint registry pattern for API discovery
   - Error handling with {:ok, _} / {:error, _} tuples

3. **Break Down Complex Code**:
   - Explain function purpose and parameters
   - Show data flow through the library
   - Highlight important business logic
   - Explain error handling patterns

4. **ZenCex-Specific Patterns**:

### **Adapter Architecture**
```elixir
# Explain how exchange adapters work
defmodule ZenCex.Adapters.Binance.Endpoints do
  # Router module that delegates to API-specific modules
  # based on function prefixes (spot_, margin_, usdm_, etc.)
end
```

### **Req Middleware Pattern**
```elixir
# Explain how Req steps are used for auth and rate limiting
defmodule ZenCex.Core.HTTP do
  # Configures Req with custom middleware steps
  # Leverages Req's built-in features instead of reimplementing
end
```

### **Rate Limiting with ETS**
```elixir
# Explain ETS-based rate limiting
defmodule ZenCex.Adapters.Binance.RateLimiter do
  # Uses ETS atomic operations for stateless rate limiting
  # No GenServer needed - works with Req's pipeline
end
```

### **Endpoint Registry Pattern**
```elixir
# Explain code generation from endpoint definitions
defmodule ZenCex.EndpointRegistry do
  # Generates functions from @endpoints declarations
  # Provides runtime discovery and documentation
end
```

5. **Explain Key Concepts**:

### **Error Handling**
- Using `{:ok, result}` and `{:error, reason}` tuples
- Pass raw errors without wrapping
- Pattern matching for different outcomes

### **Testing Against Real APIs**
- Testnet-only integration tests
- No mocks without real API testing first
- Document actual API responses

### **Clock Synchronization**
- Time sync with exchange servers
- Critical for authenticated requests
- Per-API-type synchronization

### **Security Considerations**
- API key management
- Request signing (HMAC-SHA256)
- Rate limit compliance
- Testnet vs production safety

6. **Performance Implications**:
   - Connection pooling via Finch
   - ETS atomic operations
   - Req's retry and backoff
   - Telemetry for monitoring

7. **Testing Strategies**:
   - Unit tests for pure functions
   - Integration tests against testnet
   - Performance benchmarks
   - Debug module for troubleshooting

## Example Usage

Paste the code you want explained, and I'll provide:
- Overall purpose and architecture
- Line-by-line explanation of complex parts
- How it fits into ZenCex library patterns
- Security and performance considerations
- Testing recommendations
- Common patterns and anti-patterns
- Integration best practices

I'll tailor explanations to your experience level and focus on the most important concepts for understanding the ZenCex cryptocurrency exchange library.