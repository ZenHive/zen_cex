# Example Modules & Tests Implementation Tickets

This document tracks remaining tasks for implementing example modules and tests to verify all documentation claims in README.md, usage-rules.md, and CHANGELOG.md.

## Status: IN PROGRESS

**Last Updated**: 2025-01-05 (Session 10)

**Current Progress**:
- ✅ Completed: Tasks 0-10, 11-20 (all modules + all tests completed!)
- ⏳ Remaining: 3 tasks (2 tests + config/verification)

**Next Task**: Task 21 (documentation_examples_test.exs) - Parse and validate README/docs code examples

---

## 🔄 CONTINUATION PROMPT

**For next session, start with**:
```
Continue implementing example modules from docs/examples_specs.md.

Current status: Completed Tasks 0-10, 11-20 (all modules + tests completed!). Session 10 implemented endpoint_discovery module with comprehensive introspection examples.
Next: Task 21 (documentation_examples_test.exs) - Create validation test that parses README.md and usage-rules.md code examples.

Key points:
- ALWAYS implement both module AND tests in the same session
- Task 21 is a meta-test that validates documentation code examples
- Extract all Elixir code blocks from markdown files
- Verify module references exist and functions are exported
- Check for outdated patterns (Cache.Market vs MarketData corrections already applied)
- Use @moduletag :documentation for this test
- All functions need @spec, @doc, @moduledoc
- Run tests after creating them
- Update this file's continuation prompt when done

Begin: "Continuing from docs/examples_specs.md - implementing Task 21..."
```

---

## Remaining Tasks

### Example Modules (lib/examples/)

#### ✅ Task 8: Create credential_management.ex (COMPLETED - Session 9)

**File**: `lib/examples/credential_management.ex`

**Purpose**: Demonstrate authentication patterns from README.md:99-184

**Implementation Notes**:
- ✅ Created 4 functions with full @spec, @doc, @moduledoc
- ✅ CRITICAL: Made clear library NEVER reads ENV - only calling code does
- ✅ Shows explicit credential passing (PRIMARY pattern)
- ✅ Shows calling code reading ENV then passing to library
- ✅ Multi-account management with explicit credentials
- ✅ Credential rotation pattern with get_credentials function
- ✅ All tests pass (12 tests, 0 failures)

**Functions implemented**:
```elixir
def use_explicit_credentials(api_key, api_secret, opts \\ [])
def use_credentials_from_env()
def manage_multiple_accounts(account_credentials_list)
def rotate_credentials_on_error(params, get_credentials_fn)
```

**Documentation refs**:
- README.md:99-184
- usage-rules.md:116-169

---

#### ✅ Task 9: Create debug_troubleshooting.ex (COMPLETED - Session 9)

**File**: `lib/examples/debug_troubleshooting.ex`

**Purpose**: Demonstrate debug mode from README.md:386-407

**Implementation Notes**:
- ✅ Created 5 functions with full @spec, @doc, @moduledoc
- ✅ Comprehensive workflow: enable → fail → get curl → stats → disable
- ✅ Integration with ZenCex.Core.Debug module
- ✅ Security warnings about production usage
- ✅ All tests pass (16 tests, 0 failures)

**Functions implemented**:
```elixir
def enable_debug_mode() :: :ok
def disable_debug_mode() :: :ok
def get_last_curl_command() :: {:ok, String.t()} | {:error, :not_found}
def get_debug_stats() :: map()
def debug_failed_request(params :: map()) :: {:error, term()}
```

**Documentation refs**:
- README.md:386-407
- lib/zen_cex/core/debug.ex

---

#### ✅ Task 10: Create endpoint_discovery.ex (COMPLETED - Session 10)

**File**: `lib/examples/endpoint_discovery.ex`

**Purpose**: Demonstrate endpoint introspection from README.md:409-426

**Implementation Notes**:
- ✅ Created 4 functions with full @spec, @doc, @moduledoc
- ✅ Demonstrates runtime endpoint discovery across all API types
- ✅ Shows listing endpoints (all, spot, futures)
- ✅ Shows getting detailed endpoint information
- ✅ All tests pass (23 tests, 0 failures)

**Functions implemented**:
```elixir
def list_all_endpoints() :: {:ok, [atom()]}
def list_spot_endpoints() :: {:ok, [atom()]}
def list_futures_endpoints() :: {:ok, [atom()]}
def get_endpoint_details(atom(), atom()) :: {:ok, map()} | {:error, :not_found}
```

**Documentation refs**:
- README.md:409-426
- lib/zen_cex/adapters/binance/endpoints.ex

---

### Test Suites (test/examples/)

#### ✅ Task 18: Create test suite for credential_management (COMPLETED - Session 9)

**File**: `test/examples/credential_management_test.exs`

**Purpose**: Verify authentication patterns

**Implementation Notes**:
- ✅ Created comprehensive test suite with 12 tests
- ✅ All tests pass (12 tests, 0 failures)
- ✅ Tests verify ENV reading happens in calling code, not library
- ✅ Tests verify explicit credential passing
- ✅ Tests verify multi-account management
- ✅ Tests verify credential rotation logic
- ✅ Uses IntegrationCase for real testnet API calls
- ✅ Properly handles Binance atom key responses

**Tests implemented**:
- `use_explicit_credentials/3` (3 tests)
- `use_credentials_from_env/0` (2 tests)
- `manage_multiple_accounts/1` (4 tests)
- `rotate_credentials_on_error/2` (2 tests)
- Integration patterns (1 test)

---

#### ✅ Task 19: Create test suite for debug_troubleshooting (COMPLETED - Session 9)

**File**: `test/examples/debug_troubleshooting_test.exs`

**Purpose**: Verify debug mode examples

**Implementation Notes**:
- ✅ Created comprehensive test suite with 16 tests
- ✅ All tests pass (16 tests, 0 failures)
- ✅ Tests verify enable/disable, curl export, stats collection
- ✅ Integration tests verify actual debug capture workflow
- ✅ Proper setup/teardown to clear debug state between tests
- ✅ Uses ExUnit.Case (no auth needed for debug module)

**Tests implemented**:
- `enable_debug_mode/0` (2 tests)
- `disable_debug_mode/0` (3 tests)
- `get_last_curl_command/0` (3 tests)
- `get_debug_stats/0` (4 tests)
- `debug_failed_request/1` (3 tests)
- Full workflow integration (1 test)

---

#### ✅ Task 20: Create test suite for endpoint_discovery (COMPLETED - Session 10)

**File**: `test/examples/endpoint_discovery_test.exs`

**Purpose**: Verify endpoint introspection

**Implementation Notes**:
- ✅ Created comprehensive test suite with 23 tests
- ✅ All tests pass (23 tests, 0 failures)
- ✅ Tests verify endpoint listing (all, spot, futures)
- ✅ Tests verify endpoint details structure and metadata
- ✅ Tests verify sorting, uniqueness, and subset relationships
- ✅ Integration tests verify cross-API type comparison
- ✅ Uses ExUnit.Case (no auth needed for discovery operations)

**Tests implemented**:
- `list_all_endpoints/0` (4 tests)
- `list_spot_endpoints/0` (4 tests)
- `list_futures_endpoints/0` (5 tests)
- `get_endpoint_details/2` (8 tests)
- Integration examples (2 tests)

---

#### Task 21: Create documentation validation test

**File**: `test/examples/documentation_examples_test.exs`

**Purpose**: Parse README.md and usage-rules.md to verify all code examples are valid

**Requirements**:
- Extract all Elixir code blocks from markdown
- Verify all module references exist
- Verify all function calls exist
- Flag outdated examples
- Check corrected patterns (Cache.Market vs MarketData)

**Test structure**:
```elixir
defmodule ZenCex.Examples.DocumentationExamplesTest do
  use ExUnit.Case

  @moduletag :documentation

  describe "README.md examples" do
    test "all module references are valid"
    test "all function calls exist"
    test "WebSocket cache examples use Cache.Market"
    test "market data examples use MarketData module"
  end

  describe "usage-rules.md examples" do
    test "all Quick Reference functions exist"
    test "Common module only used for server_time"
  end
end
```

---

### Configuration & Verification

#### Task 22: Update project configuration

**File**: Mix and formatter updates

**Actions**:
1. Add to `.formatter.exs`:
   ```elixir
   inputs: [
     # ... existing ...
     "lib/examples/**/*.{ex,exs}",
     "test/examples/**/*.exs"
   ]
   ```

2. Add to `mix.exs` docs config:
   ```elixir
   docs: [
     # ... existing ...
     extras: [
       "README.md",
       "CHANGELOG.md",
       "docs/TELEMETRY.md",
       "docs/examples_specs.md"  # Add this
     ],
     groups_for_extras: [
       "Examples": ~r/examples/
     ]
   ]
   ```

3. Run `mix format` on all example files
4. Run `mix docs` to verify examples appear

---

#### Task 23: Final verification

**Actions**:
1. Run `mix test test/examples/` - all should pass
2. Run `mix test --only example` - verify tag filtering works
3. Run `mix test --only websocket` - verify WebSocket tests work
4. Run `mix test --exclude write_operation` - verify read-only tests pass
5. Check `mix docs` includes examples in sidebar
6. Verify all README.md code blocks have corresponding example functions

---

## Critical Corrections Applied

✅ README.md:354 - Fixed WebSocket cache access:
- OLD: `MarketData.get_cached_ticker("BTCUSDT")`
- NEW: `Market.get_ticker(:binance, "BTCUSDT")`

✅ usage-rules.md:39,66-85 - Fixed module references:
- OLD: `Common.get_ticker_price/1`
- NEW: `MarketData.get_ticker_price/1`

✅ Common module only has: `get_server_time/0`
✅ MarketData module has: ticker, order book, klines, etc.
✅ Cache.Market module has: get_ticker/2, get_orderbook/2, get_last_trade/2

---

## Testing Guidelines

### CRITICAL: NEVER HIDE TEST FAILURES

**TESTS THAT HIDE ERRORS ARE WORSE THAN NO TESTS AT ALL**

```elixir
# ❌ FORBIDDEN - Makes ANY outcome pass
case result do
  {:ok, _} -> assert true
  {:error, _} -> assert true  # Hides all failures!
end

# ✅ CORRECT - Fail loudly on unexpected errors
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :specific_expected_error} -> :ok
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

### Key Testing Rules

1. **Tests should be deterministic** - A test either passes or fails, period
2. **No mocks for external APIs initially** - Test against REAL testnet/production APIs first
3. **Integration tests use real credentials** - Use actual testnet or read-only production API keys
4. **Test the actual response structure** - Assert on real data structures, not mocked ones
5. **ALWAYS pass auth_credentials in opts** for authenticated operations
6. **Match response key format to exchange parser** - Binance uses atoms, Bybit uses strings

---

## Implementation History

See [examples_implementation_log.md](./examples_implementation_log.md) for:
- Completed task details
- Session-by-session notes
- Implementation discoveries
- Architecture decisions
