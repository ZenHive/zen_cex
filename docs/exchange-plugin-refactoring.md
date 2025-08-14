# Exchange Plugin Architecture Refactoring Plan

## Executive Summary

This document outlines the refactoring plan to transform ZenCex from a monolithic exchange integration library into a plugin-based architecture. The refactoring will extract exchange-specific logic from core modules into self-contained adapter modules, improving maintainability, testability, and extensibility.

**Timeline**: 3-4 weeks  
**Risk Level**: Low-Medium (with phased approach)  
**Breaking Changes**: None (backward compatibility maintained)

## Problem Statement

### Current Issues

1. **Tight Coupling**: Exchange-specific logic is hardcoded throughout core modules
   - 50+ case statements in `auth.ex`
   - 166 lines of endpoint definitions in `endpoints.ex`
   - Exchange-specific rate limiting logic scattered in `rate_limit.ex`

2. **Violation of SOLID Principles**
   - **Open/Closed**: Adding exchanges requires modifying core modules
   - **Single Responsibility**: Core modules handle multiple exchange concerns
   - **Dependency Inversion**: Core modules depend on concrete implementations

3. **Maintenance Burden**
   - Adding a new exchange requires changes to 5+ files
   - Testing requires mocking all exchanges even when testing one
   - Exchange-specific bugs affect the entire codebase

4. **Scalability Limitations**
   - Cannot load exchanges dynamically
   - All exchange code loaded even if using only one
   - Difficult to implement exchange-specific optimizations

## Proposed Architecture

### Core Design Principles

1. **Plugin Pattern**: Each exchange is a self-contained plugin
2. **Behavior Contracts**: Well-defined interfaces for exchange implementations
3. **Registry Pattern**: Dynamic discovery and registration of exchanges
4. **Facade Pattern**: Maintain backward compatibility
5. **Dependency Injection**: Core modules depend on abstractions

### Directory Structure

```
lib/zen_cex/
├── exchange/
│   ├── adapters/                    # Exchange implementations
│   │   ├── binance/
│   │   │   ├── adapter.ex          # Main adapter module
│   │   │   ├── auth.ex             # Authentication logic
│   │   │   ├── endpoints.ex        # Endpoint definitions
│   │   │   ├── rate_limiter.ex     # Rate limiting logic
│   │   │   ├── parser.ex           # Response parsing
│   │   │   └── config.ex           # Configuration
│   │   ├── binance_futures/
│   │   │   └── ...                 # Same structure
│   │   ├── kraken/
│   │   │   └── ...
│   │   └── deribit/
│   │       └── ...
│   ├── behaviours/                  # Contract definitions
│   │   ├── adapter.ex              # Main adapter behavior
│   │   ├── auth_provider.ex        # Authentication contract
│   │   ├── endpoint_provider.ex    # Endpoint contract
│   │   ├── rate_limiter.ex         # Rate limiting contract
│   │   └── parser.ex               # Response parsing contract
│   ├── core/                        # Core modules (simplified)
│   │   ├── http.ex                 # Generic HTTP client
│   │   ├── auth.ex                 # Auth facade
│   │   ├── rate_limit.ex           # Rate limit facade
│   │   └── endpoints.ex            # Endpoint facade
│   ├── registry.ex                  # Adapter registry
│   ├── factory.ex                   # Adapter factory
│   └── utils/                       # Shared utilities
│       ├── crypto.ex                # HMAC, signatures
│       ├── time.ex                  # Time utilities
│       └── telemetry.ex             # Telemetry helpers
```

## Implementation Phases

### Phase 1: Foundation (Week 1)

#### 1.1 Create Behavior Contracts
```elixir
# lib/zen_cex/exchange/behaviours/adapter.ex
defmodule ZenCex.Exchange.Behaviours.Adapter do
  @callback name() :: atom()
  @callback base_url(env :: atom()) :: String.t()
  @callback auth_provider() :: module()
  @callback endpoint_provider() :: module()
  @callback rate_limiter() :: module()
  @callback parser() :: module()
end

# lib/zen_cex/exchange/behaviours/auth_provider.ex
defmodule ZenCex.Exchange.Behaviours.AuthProvider do
  @callback sign_request(request :: map(), keys :: map(), opts :: keyword()) :: 
    {:ok, map()} | {:error, term()}
  @callback get_credentials() :: {:ok, map()} | {:error, term()}
  @callback validate_timestamp(timestamp :: integer(), window :: integer()) :: 
    :ok | {:error, atom()}
end
```

#### 1.2 Implement Registry Pattern
```elixir
# lib/zen_cex/exchange/registry.ex
defmodule ZenCex.Exchange.Registry do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def register(exchange_id, adapter_module) do
    GenServer.call(__MODULE__, {:register, exchange_id, adapter_module})
  end
  
  def get_adapter(exchange_id) do
    GenServer.call(__MODULE__, {:get_adapter, exchange_id})
  end
  
  def list_exchanges() do
    GenServer.call(__MODULE__, :list_exchanges)
  end
end
```

#### 1.3 Extract Shared Utilities
- Move HMAC functions to `utils/crypto.ex`
- Move time functions to `utils/time.ex`
- Move telemetry helpers to `utils/telemetry.ex`

**Deliverables**:
- [ ] Behavior definitions complete
- [ ] Registry implementation with tests
- [ ] Shared utilities extracted
- [ ] Documentation for behaviors

### Phase 2: Binance Adapter (Week 1-2)

#### 2.1 Implement Binance Adapter
```elixir
# lib/zen_cex/exchange/adapters/binance/adapter.ex
defmodule ZenCex.Exchange.Adapters.Binance.Adapter do
  @behaviour ZenCex.Exchange.Behaviours.Adapter
  
  @impl true
  def name(), do: :binance
  
  @impl true
  def base_url(:prod), do: "https://api.binance.com"
  def base_url(:test), do: "https://testnet.binance.vision"
  
  @impl true
  def auth_provider(), do: __MODULE__.Auth
  
  @impl true
  def endpoint_provider(), do: __MODULE__.Endpoints
  
  @impl true
  def rate_limiter(), do: __MODULE__.RateLimiter
end
```

#### 2.2 Extract Binance-Specific Logic
- Move `sign_binance_request/2` to `binance/auth.ex`
- Move `@binance_endpoints` to `binance/endpoints.ex`
- Move sliding window logic to `binance/rate_limiter.ex`

#### 2.3 Create Binance Tests
- Unit tests for each module
- Integration tests with test API
- Performance benchmarks

**Deliverables**:
- [ ] Binance adapter fully implemented
- [ ] Binance Futures adapter implemented
- [ ] All Binance tests passing
- [ ] Performance benchmarks documented

### Phase 3: Remaining Adapters (Week 2)

#### 3.1 Implement Kraken Adapter
- Extract nonce generation logic
- Move HMAC-SHA512 signing
- Implement form-encoded body handling

#### 3.2 Implement Deribit Adapter  
- Extract OAuth2 logic (keep DeribitOAuth GenServer)
- Move JSON-RPC handling
- Implement token refresh logic

**Deliverables**:
- [ ] Kraken adapter complete with tests
- [ ] Deribit adapter complete with tests
- [ ] All existing tests still passing

### Phase 4: Facade Implementation (Week 2-3)

#### 4.1 Create Backward-Compatible Facades
```elixir
# lib/zen_cex/exchange/core/auth.ex
defmodule ZenCex.Auth do
  @moduledoc """
  Backward-compatible facade for authentication.
  Delegates to exchange adapters while maintaining existing API.
  """
  
  # Keep existing public API
  def sign_request(exchange, request, opts \\ []) do
    with {:ok, adapter} <- Registry.get_adapter(exchange) do
      adapter.auth_provider().sign_request(request, get_api_keys(exchange), opts)
    else
      {:error, :not_registered} ->
        # Fall back to legacy implementation during transition
        legacy_sign_request(exchange, request, opts)
    end
  end
  
  # Maintain existing functions
  def get_api_keys(exchange), do: # delegate to adapter
  def hmac_sha256(secret, message, format), do: Utils.Crypto.hmac_sha256(secret, message, format)
end
```

#### 4.2 Update HTTP Module
- Remove exchange-specific URL mappings
- Use registry to get base URLs
- Simplify to generic HTTP operations

#### 4.3 Update Rate Limit Module
- Remove exchange-specific logic
- Delegate to adapter rate limiters
- Maintain global cleanup process

**Deliverables**:
- [ ] All facades implemented
- [ ] Existing API fully compatible
- [ ] Integration tests passing
- [ ] Performance regression tests passing

### Phase 5: Migration & Cleanup (Week 3)

#### 5.1 Add Feature Flags
```elixir
# config/config.exs
config :zen_cex,
  use_plugin_architecture: true,
  legacy_fallback: true
```

#### 5.2 Parallel Testing
- Run tests with both architectures
- Compare performance metrics
- Validate behavior consistency

#### 5.3 Remove Legacy Code
- Delete old private functions
- Remove hardcoded case statements
- Clean up module attributes

#### 5.4 Test Migration and Cleanup

**Tests to Migrate:**
```bash
# Current monolithic test files to be refactored
test/zen_cex/exchange/auth_test.exs                    # Split into adapter-specific tests
test/zen_cex/exchange/auth_integration_test.exs         # Split by exchange
test/zen_cex/exchange/endpoints_test.exs                # Move to adapter tests
test/zen_cex/exchange/rate_limit_test.exs              # Split by rate limit strategy
test/zen_cex/exchange/rate_limit_integration_test.exs   # Split by exchange
test/zen_cex/exchange/http_test.exs                    # Keep core HTTP tests only
test/zen_cex/exchange/http_rate_limit_integration_test.exs # Split by exchange
```

**New Test Structure:**
```
test/
├── zen_cex/
│   ├── exchange/
│   │   ├── adapters/
│   │   │   ├── binance/
│   │   │   │   ├── adapter_test.exs
│   │   │   │   ├── auth_test.exs
│   │   │   │   ├── endpoints_test.exs
│   │   │   │   ├── rate_limiter_test.exs
│   │   │   │   └── integration_test.exs
│   │   │   ├── kraken/
│   │   │   │   └── ... (same structure)
│   │   │   └── deribit/
│   │   │       └── ... (same structure)
│   │   ├── core/
│   │   │   ├── http_test.exs          # Generic HTTP tests only
│   │   │   ├── auth_facade_test.exs   # Facade compatibility tests
│   │   │   └── registry_test.exs      # Registry functionality
│   │   └── behaviours/
│   │       └── adapter_behaviour_test.exs  # Contract tests
│   └── compatibility/
│       ├── api_compatibility_test.exs  # Ensure old API still works
│       └── performance_test.exs        # Performance regression tests
```

**Test Migration Steps:**

1. **Extract Exchange-Specific Tests**
   ```elixir
   # Before: In auth_test.exs
   describe "Binance authentication" do
     test "signs request with HMAC-SHA256" do
       # test code
     end
   end
   
   # After: In adapters/binance/auth_test.exs
   defmodule ZenCex.Exchange.Adapters.Binance.AuthTest do
     test "signs request with HMAC-SHA256" do
       # same test code, but isolated
     end
   end
   ```

2. **Delete Redundant Tests**
   - Remove tests that duplicate exchange-specific logic
   - Delete mock-heavy tests that will be replaced with adapter tests
   - Remove integration tests that test multiple exchanges together

3. **Create Adapter Contract Tests**
   ```elixir
   # test/zen_cex/exchange/behaviours/adapter_behaviour_test.exs
   defmodule ZenCex.Exchange.Behaviours.AdapterTest do
     @adapters [
       ZenCex.Exchange.Adapters.Binance.Adapter,
       ZenCex.Exchange.Adapters.Kraken.Adapter,
       ZenCex.Exchange.Adapters.Deribit.Adapter
     ]
     
     for adapter <- @adapters do
       test "#{adapter} implements all required callbacks" do
         assert function_exported?(unquote(adapter), :name, 0)
         assert function_exported?(unquote(adapter), :base_url, 1)
         assert function_exported?(unquote(adapter), :auth_provider, 0)
       end
     end
   end
   ```

**Files to Delete After Migration:**
```bash
# Complete deletion list
rm test/zen_cex/exchange/auth_test.exs
rm test/zen_cex/exchange/auth_integration_test.exs  
rm test/zen_cex/exchange/auth/deribit_oauth_test.exs  # Moved to adapter
rm test/zen_cex/exchange/cache_test.exs  # If cache becomes adapter-specific
rm test/zen_cex/exchange/endpoints_test.exs
rm test/zen_cex/exchange/health/health_check_test.exs
rm test/zen_cex/exchange/health/health_consensus_test.exs
rm test/zen_cex/exchange/health/health_integration_test.exs
rm test/zen_cex/exchange/health/health_monitor_test.exs
rm test/zen_cex/exchange/health_test.exs
rm test/zen_cex/exchange/rate_limit_test.exs
rm test/zen_cex/exchange/rate_limit_integration_test.exs
rm test/zen_cex/exchange/rate_limit_performance_test.exs

# Keep but refactor
# test/zen_cex/exchange/http_test.exs - Keep only generic HTTP tests
# test/zen_cex/exchange/http_rate_limit_integration_test.exs - Split by exchange
```

**Test Migration Checklist:**
- [ ] Create adapter test directories
- [ ] Migrate Binance-specific tests
- [ ] Migrate Kraken-specific tests  
- [ ] Migrate Deribit-specific tests
- [ ] Create behavior contract tests
- [ ] Create compatibility test suite
- [ ] Update test_helper.exs for new structure
- [ ] Delete old monolithic test files
- [ ] Verify test coverage maintained >80%
- [ ] Document new test patterns

**Deliverables**:
- [ ] Feature flags implemented
- [ ] Parallel testing complete
- [ ] Legacy code removed
- [ ] Old tests migrated and deleted
- [ ] New test structure documented
- [ ] Test coverage report showing maintained/improved coverage

### Phase 6: Documentation & Training (Week 3-4)

#### 6.1 Update Documentation
- Update README with new architecture
- Create adapter development guide
- Document migration process

#### 6.2 Create Examples
- Example: Adding a new exchange
- Example: Customizing an adapter
- Example: Using the registry

#### 6.3 Performance Documentation
- Benchmark results
- Memory usage comparison
- Latency measurements

**Deliverables**:
- [ ] README updated
- [ ] Developer guide complete
- [ ] Examples created
- [ ] Performance report

## Testing Strategy

### Test Categories

1. **Unit Tests** (per adapter)
   - Authentication logic
   - Endpoint definitions
   - Rate limiting logic
   - Response parsing

2. **Integration Tests** (per exchange)
   - Real API calls (test environment)
   - End-to-end workflows
   - Error handling

3. **Compatibility Tests**
   - Existing API compatibility
   - Behavior consistency
   - Performance regression

4. **System Tests**
   - Multi-exchange scenarios
   - Registry functionality
   - Dynamic loading

### Test Execution Plan

```bash
# Run all tests with coverage
mix test --cover

# Run adapter-specific tests
mix test test/adapters/binance/
mix test test/adapters/kraken/

# Run compatibility tests
mix test --only compatibility

# Run performance benchmarks
mix run benchmarks/adapter_performance.exs
```

## Risk Management

### Identified Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking API changes | Low | High | Facade pattern, extensive testing |
| Performance regression | Medium | Medium | Benchmarking, profiling |
| OAuth token management issues | Low | High | Keep existing DeribitOAuth GenServer |
| ETS table conflicts | Low | Low | Namespace tables by adapter |
| Increased complexity | Medium | Low | Clear documentation, examples |

### Rollback Plan

1. **Feature Flags**: Can disable plugin architecture instantly
2. **Legacy Fallback**: Original code remains during transition
3. **Gradual Rollout**: Test with one exchange first
4. **Version Tags**: Tag releases before major changes

## Success Metrics

### Code Quality Metrics

- [ ] **Cyclomatic complexity** reduced from ~15 to <5 in core modules
- [ ] **Module cohesion** increased (single responsibility)
- [ ] **Test coverage** maintained at >80%
- [ ] **Documentation coverage** 100% for public APIs

### Performance Metrics

- [ ] **Request latency** within 5% of current
- [ ] **Memory usage** increase <10%
- [ ] **Test suite runtime** reduced by 20%
- [ ] **Startup time** within 10% of current

### Maintainability Metrics

- [ ] **Time to add new exchange** reduced from days to hours
- [ ] **Lines changed per feature** reduced by 50%
- [ ] **Bug isolation** improved (exchange-specific)
- [ ] **Developer onboarding** simplified

## Migration Checklist

### Pre-Migration
- [ ] All tests passing on main branch
- [ ] Performance baseline recorded
- [ ] Team briefed on new architecture
- [ ] Feature flags configured

### During Migration
- [ ] Phase 1: Foundation complete
- [ ] Phase 2: Binance adapter complete
- [ ] Phase 3: All adapters complete
- [ ] Phase 4: Facades implemented
- [ ] Phase 5: Legacy code removed
- [ ] Phase 6: Documentation complete

### Post-Migration
- [ ] All tests passing
- [ ] Performance validated
- [ ] Documentation published
- [ ] Team trained
- [ ] Monitoring in place

## Example: Adding a New Exchange

After refactoring, adding a new exchange (e.g., Coinbase) becomes straightforward:

### Step 1: Create Adapter Structure
```bash
mkdir -p lib/zen_cex/exchange/adapters/coinbase
```

### Step 2: Implement Adapter
```elixir
# lib/zen_cex/exchange/adapters/coinbase/adapter.ex
defmodule ZenCex.Exchange.Adapters.Coinbase.Adapter do
  @behaviour ZenCex.Exchange.Behaviours.Adapter
  
  @impl true
  def name(), do: :coinbase
  
  @impl true
  def base_url(:prod), do: "https://api.coinbase.com"
  
  # ... implement other callbacks
end
```

### Step 3: Implement Providers
```elixir
# lib/zen_cex/exchange/adapters/coinbase/auth.ex
defmodule ZenCex.Exchange.Adapters.Coinbase.Auth do
  @behaviour ZenCex.Exchange.Behaviours.AuthProvider
  
  @impl true
  def sign_request(request, keys, _opts) do
    # Coinbase-specific signing logic
  end
end
```

### Step 4: Register Adapter
```elixir
# In application startup or config
Registry.register(:coinbase, ZenCex.Exchange.Adapters.Coinbase.Adapter)
```

### Step 5: Use It
```elixir
# No changes needed to client code!
{:ok, response} = ZenCex.HTTP.get(:coinbase, "/accounts")
```

## Conclusion

This refactoring transforms ZenCex from a monolithic library into a flexible, maintainable plugin architecture. The phased approach ensures zero downtime and maintains backward compatibility while delivering significant improvements in code quality, testability, and extensibility.

The investment in this refactoring will pay dividends through:
- Faster development of new exchange integrations
- Easier maintenance and debugging
- Better performance through exchange-specific optimizations
- Improved developer experience

## Appendix A: File Mapping

### Production Code Migration

| Current File | Refactored Location |
|--------------|-------------------|
| `auth.ex#sign_binance_request/2` | `adapters/binance/auth.ex` |
| `auth.ex#sign_kraken_request/2` | `adapters/kraken/auth.ex` |
| `auth.ex#sign_deribit_request/2` | `adapters/deribit/auth.ex` |
| `endpoints.ex#@binance_endpoints` | `adapters/binance/endpoints.ex` |
| `endpoints.ex#@kraken_endpoints` | `adapters/kraken/endpoints.ex` |
| `rate_limit.ex#binance_sliding_window/3` | `adapters/binance/rate_limiter.ex` |

### Test File Migration and Deletion

| Current Test File | Action | New Location |
|-------------------|--------|--------------|
| `auth_test.exs` | Split & Delete | `adapters/{exchange}/auth_test.exs` |
| `auth_integration_test.exs` | Split & Delete | `adapters/{exchange}/integration_test.exs` |
| `auth/deribit_oauth_test.exs` | Move & Delete | `adapters/deribit/oauth_test.exs` |
| `cache_test.exs` | Refactor or Delete | `core/cache_test.exs` or per-adapter |
| `endpoints_test.exs` | Split & Delete | `adapters/{exchange}/endpoints_test.exs` |
| `health/health_check_test.exs` | Delete | Functionality moved to adapters |
| `health/health_consensus_test.exs` | Delete | Functionality moved to adapters |
| `health/health_integration_test.exs` | Delete | Split into adapter tests |
| `health/health_monitor_test.exs` | Delete | Functionality moved to adapters |
| `health_test.exs` | Delete | Split into adapter tests |
| `rate_limit_test.exs` | Split & Delete | `adapters/{exchange}/rate_limiter_test.exs` |
| `rate_limit_integration_test.exs` | Split & Delete | `adapters/{exchange}/integration_test.exs` |
| `rate_limit_performance_test.exs` | Split & Delete | `adapters/{exchange}/performance_test.exs` |
| `http_test.exs` | Partial Keep | `core/http_test.exs` (generic only) |
| `http_rate_limit_integration_test.exs` | Split & Delete | `adapters/{exchange}/integration_test.exs` |

## Appendix B: Behavior Specifications

[Detailed behavior specifications and type specs would be included here]

## Appendix C: Performance Benchmarks

[Baseline and target performance metrics would be included here]