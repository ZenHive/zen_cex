# Example Modules & Tests Implementation Tickets

This document tracks remaining tasks for implementing example modules and tests to verify all documentation claims in README.md, usage-rules.md, and CHANGELOG.md.

## Status: IN PROGRESS

**Last Updated**: 2025-01-05 (Session 8)

**Current Progress**:
- ✅ Completed: Tasks 0-7, 11-17 (all Binance modules + Bybit trading + all tests)
- ⏳ Remaining: 8 tasks (3 modules + 4 tests + config/verification)

**Next Task**: Task 8 (credential_management.ex) and Task 18 (credential_management_test.exs)

---

## 🔄 CONTINUATION PROMPT

**For next session, start with**:
```
Continue implementing example modules from docs/examples_specs.md.

Current status: Completed Tasks 0-7, 11-17 (all Binance modules + Bybit trading + all tests). Session 8 fixed all test failures.
Next: Task 8 (credential_management.ex) and Task 18 (credential_management_test.exs).

Key points:
- ALWAYS implement both module AND tests in the same session
- Bybit returns STRING keys, Binance returns ATOM keys (inconsistency documented)
- Use Cache.Market.get_ticker(:binance, symbol) for WebSocket cached data
- Use MarketData module for REST market data endpoints
- All functions need @spec, @doc, @moduledoc
- Run tests after creating them
- Update this file's continuation prompt when done
- ALWAYS pass auth_credentials in opts for authenticated operations
- Handle exchange-specific error codes (Binance: -2019, -4013; Bybit: 110101, 170140)

Begin: "Continuing from docs/examples_specs.md - implementing Task 8..."
```

---

## Remaining Tasks

### Example Modules (lib/examples/)

#### Task 8: Create credential_management.ex

**File**: `lib/examples/credential_management.ex`

**Purpose**: Demonstrate authentication patterns from README.md:99-184

**Requirements**:
- Environment variable pattern
- Per-request credentials
- Multi-account management
- Credential rotation pattern
- Show both keyword list and map options

**Functions to implement**:
```elixir
def use_environment_credentials()
def use_custom_credentials(api_key, api_secret)
def manage_multiple_accounts(account_credentials_list)
def rotate_credentials_on_error(params, get_credentials_fn)
```

**Documentation refs**:
- README.md:99-184
- usage-rules.md:116-169

---

#### Task 9: Create debug_troubleshooting.ex

**File**: `lib/examples/debug_troubleshooting.ex`

**Purpose**: Demonstrate debug mode from README.md:386-407

**Requirements**:
- Enable debug mode
- Make failing request
- Get curl command
- Get debug statistics
- Disable debug mode

**Functions to implement**:
```elixir
def enable_debug_mode()
def get_last_curl_command()
def get_debug_stats()
def disable_debug_mode()
def debug_failed_request(params)
```

**Documentation refs**:
- README.md:386-407
- lib/zen_cex/core/debug.ex

---

#### Task 10: Create endpoint_discovery.ex

**File**: `lib/examples/endpoint_discovery.ex`

**Purpose**: Demonstrate endpoint introspection from README.md:409-426

**Requirements**:
- List all endpoints
- List by API type
- Get endpoint details
- Show runtime discovery

**Functions to implement**:
```elixir
def list_all_endpoints()
def list_spot_endpoints()
def list_futures_endpoints()
def get_endpoint_details(operation, api_type)
```

**Documentation refs**:
- README.md:409-426
- lib/zen_cex/adapters/binance/endpoints.ex

---

### Test Suites (test/examples/)

#### Task 18: Create test suite for credential_management

**File**: `test/examples/credential_management_test.exs`

**Purpose**: Verify authentication patterns

**Requirements**:
- Test env variable pattern
- Test custom credentials
- Test multi-account workflow
- Mock credential rotation

**Tests needed**:
- `use_environment_credentials/0`
- `use_custom_credentials/2`
- `manage_multiple_accounts/1`
- `rotate_credentials_on_error/2`

---

#### Task 19: Create test suite for debug_troubleshooting

**File**: `test/examples/debug_troubleshooting_test.exs`

**Purpose**: Verify debug mode examples

**Requirements**:
- Test debug enable/disable
- Verify curl export
- Check stats collection

**Tests needed**:
- `enable_debug_mode/0`
- `get_last_curl_command/0`
- `get_debug_stats/0`
- `disable_debug_mode/0`
- `debug_failed_request/1`

---

#### Task 20: Create test suite for endpoint_discovery

**File**: `test/examples/endpoint_discovery_test.exs`

**Purpose**: Verify endpoint introspection

**Requirements**:
- Test endpoint listing
- Verify endpoint details structure
- No auth required

**Tests needed**:
- `list_all_endpoints/0`
- `list_spot_endpoints/0`
- `list_futures_endpoints/0`
- `get_endpoint_details/2`

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
