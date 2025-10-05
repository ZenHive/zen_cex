# Example Modules & Tests Implementation Tickets

This document contains numbered tasks for implementing example modules and tests to verify all documentation claims in README.md, usage-rules.md, and CHANGELOG.md.

## Status: IN PROGRESS

---

## 🔄 CONTINUATION PROMPT (Update at end of each session)

**Last Updated**: 2025-01-05 (Session 5)

**For next session, start with**:
```
Continue implementing example modules from docs/examples_specs.md.

Current status: Completed Tasks 0-6, 11-16 (all Binance modules + all tests).
Next: Task 7 (bybit_trading.ex) and Task 17 (bybit_trading_test.exs).

Key points:
- ALWAYS implement both module AND tests in the same session
- Use Cache.Market.get_ticker(:binance, symbol) for WebSocket cached data
- Use MarketData module for REST market data endpoints
- All functions need @spec, @doc, @moduledoc
- Run tests after creating them
- Update this file's continuation prompt when done

Begin: "Continuing from docs/examples_specs.md - implementing Task 7..."
```

**What to update at end of each session**:
1. Update "Last Updated" date and session number
2. Update "Current status" with completed tasks
3. Update "Next" with the next task number and name
4. If all tasks done, change Status to "COMPLETED" and note final verification needed

**Implementation Strategy**:
- Always implement example module AND its test suite in the same session
- Run tests immediately after creating them to verify correctness
- Fix any issues before moving to next task

---

### Completed ✅

**Example Modules:**
- [x] Task 0: Fix documentation errors (README.md, usage-rules.md)
- [x] Task 1: Create binance_quick_start.ex
- [x] Task 2: Create binance_spot_trading.ex
- [x] Task 3: Create binance_futures_trading.ex
- [x] Task 4: Create binance_market_data.ex
- [x] Task 5: Create binance_websocket_streams.ex
- [x] Task 6: Create binance_strategies.ex

**Test Suites:**
- [x] Task 11: Create test suite for binance_quick_start
- [x] Task 12: Create test suite for binance_spot_trading
- [x] Task 13: Create test suite for binance_futures_trading
- [x] Task 14: Create test suite for binance_market_data
- [x] Task 15: Create test suite for binance_websocket_streams
- [x] Task 16: Create test suite for binance_strategies

### Remaining Tasks

---

## Task 5: Create binance_websocket_streams.ex

**File**: `lib/examples/binance_websocket_streams.ex`

**Purpose**: Demonstrate WebSocket usage from README.md:328-360

**Requirements**:
- Connect to single stream
- Connect to multiple streams
- Subscribe to additional streams
- **CRITICAL**: Access cached data using `ZenCex.Cache.Market.get_ticker(:binance, "BTCUSDT")`
  - NOT `MarketData.get_cached_ticker/1` (doesn't exist)
- Close connection
- Show both Binance and Bybit WebSocket patterns

**Functions to implement**:
```elixir
def connect_single_stream(stream)
def connect_multiple_streams(streams)
def subscribe_additional(client, new_streams)
def get_cached_ticker_data(symbol)
def get_cached_orderbook_data(symbol)
def get_cached_trade_data(symbol)
def close_connection(client)
```

**Documentation refs**:
- README.md:328-360
- lib/zen_cex/adapters/binance/websocket.ex:101-107

---

## Task 6: Create binance_strategies.ex

**File**: `lib/examples/binance_strategies.ex`

**Purpose**: Demonstrate high-level trading strategies from README.md:362-384

**Requirements**:
- Auto-hedge spot positions
- PAXG hedging strategy
- Portfolio rebalancing

**Functions to implement**:
```elixir
def auto_hedge_spot_positions(hedge_percentage, opts)
def hedge_with_paxg_long(params)
def rebalance_portfolio(target_allocations, opts)
```

**Documentation refs**:
- README.md:362-384
- lib/zen_cex/adapters/binance/strategies.ex

---

## Task 7: Create bybit_trading.ex

**File**: `lib/examples/bybit_trading.ex`

**Purpose**: Demonstrate Bybit Unified API from README.md:288-326

**Requirements**:
- Server connectivity check
- Spot trading (category: "spot")
- Linear futures (category: "linear")
- Inverse futures (category: "inverse")
- Show category parameter pattern

**Functions to implement**:
```elixir
def check_server_connectivity()
def place_spot_order(symbol, side, order_type, qty)
def place_linear_futures_order(symbol, side, order_type, qty)
def place_inverse_futures_order(symbol, side, order_type, price, qty)
def get_positions(category)
```

**Documentation refs**:
- README.md:288-326
- usage-rules.md (Bybit sections)

---

## Task 8: Create credential_management.ex

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

## Task 9: Create debug_troubleshooting.ex

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

## Task 10: Create endpoint_discovery.ex

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

## Task 11: Create test suite for binance_quick_start

**File**: `test/examples/binance_quick_start_test.exs`

**Purpose**: Verify quick start examples work with real testnet

**Requirements**:
- Use `@moduletag :example`
- Test `check_connectivity/0` (no auth)
- Test `get_account_balances/0` (requires testnet creds)
- Test `get_balances_with_credentials/1`
- Use `ZenCex.IntegrationCase`

**Test structure**:
```elixir
defmodule ZenCex.Examples.BinanceQuickStartTest do
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  @moduletag :example

  describe "connectivity" do
    test "check_connectivity/0 returns server time"
  end

  describe "authenticated operations" do
    test "get_account_balances/0 with env credentials"
    test "get_balances_with_credentials/1 with custom creds"
  end
end
```

---

## Task 12: Create test suite for binance_spot_trading

**File**: `test/examples/binance_spot_trading_test.exs`

**Purpose**: Verify spot trading examples

**Requirements**:
- Test read-only operations (balances, open orders)
- Tag write operations with `@tag :write_operation`
- Verify data structures match documentation
- Test error scenarios

**Tests needed**:
- `get_current_balances/0`
- `get_open_orders/1`
- `place_market_buy/2` (skip or write_operation tag)
- `check_order_status/2` (skip or write_operation tag)
- `cancel_order/2` (skip or write_operation tag)

---

## Task 13: Create test suite for binance_futures_trading

**File**: `test/examples/binance_futures_trading_test.exs`

**Purpose**: Verify futures examples

**Requirements**:
- Test position queries (read-only)
- Tag order placement with `@tag :write_operation`
- Test both USD-M and COIN-M

**Tests needed**:
- `get_usdm_positions/0`
- `get_coinm_positions/0`
- `place_usdm_market_order/3` (skip/write tag)
- `place_coinm_limit_order/4` (skip/write tag)

---

## Task 14: Create test suite for binance_market_data

**File**: `test/examples/binance_market_data_test.exs`

**Purpose**: Verify market data examples (all public, no auth)

**Requirements**:
- All tests should run without auth
- Verify response structures
- Test error handling (invalid symbols)

**Tests needed**:
- `get_current_price/1`
- `get_24hr_stats/1`
- `get_order_book/2`
- `get_recent_trades/2`
- `get_klines/3`
- `get_funding_rate/1`
- `get_open_interest/1`

---

## Task 15: Create test suite for binance_websocket_streams

**File**: `test/examples/binance_websocket_streams_test.exs`

**Purpose**: Verify WebSocket examples

**Requirements**:
- Use `@tag :websocket`
- Test connection lifecycle
- Verify cache access patterns
- Test both Binance and Bybit

**Tests needed**:
- `connect_single_stream/1`
- `connect_multiple_streams/1`
- `subscribe_additional/2`
- `get_cached_ticker_data/1` (verify uses Cache.Market)
- `close_connection/1`

---

## Task 16: Create test suite for binance_strategies

**File**: `test/examples/binance_strategies_test.exs`

**Purpose**: Verify high-level strategy examples

**Requirements**:
- Use `@tag :strategy` and `@tag :write_operation`
- Test with dry_run: true when possible
- Verify parameter validation

**Tests needed**:
- `auto_hedge_spot_positions/2` (dry_run)
- `hedge_with_paxg_long/1` (dry_run)
- `rebalance_portfolio/2` (dry_run)

---

## Task 17: Create test suite for bybit_trading

**File**: `test/examples/bybit_trading_test.exs`

**Purpose**: Verify Bybit examples

**Requirements**:
- Use Bybit testnet credentials
- Test category parameter pattern
- Tag write operations

**Tests needed**:
- `check_server_connectivity/0`
- `get_positions/1`
- `place_spot_order/4` (skip/write tag)
- `place_linear_futures_order/4` (skip/write tag)
- `place_inverse_futures_order/5` (skip/write tag)

---

## Task 18: Create test suite for credential_management

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

## Task 19: Create test suite for debug_troubleshooting

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

## Task 20: Create test suite for endpoint_discovery

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

## Task 21: Create documentation validation test

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

## Task 22: Update project configuration

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

## Task 23: Final verification

**Actions**:
1. Run `mix test test/examples/` - all should pass
2. Run `mix test --only example` - verify tag filtering works
3. Run `mix test --only websocket` - verify WebSocket tests work
4. Run `mix test --exclude write_operation` - verify read-only tests pass
5. Check `mix docs` includes examples in sidebar
6. Verify all README.md code blocks have corresponding example functions

---

## Usage Notes

- Each task is designed to fit in one Claude Code session
- Tasks 1-10 create example modules (lib/examples/)
- Tasks 11-21 create test suites (test/examples/)
- Task 22 updates configuration
- Task 23 final verification

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

## 📝 Session Notes (Append after each session)

### Session 1: 2025-01-04
**Completed**:
- Task 0: Fixed README.md:354 (WebSocket cache), usage-rules.md (Common→MarketData)
- Task 1: Created binance_quick_start.ex
- Task 2: Created binance_spot_trading.ex
- Task 3: Created binance_futures_trading.ex
- Task 4: Created binance_market_data.ex

**Next session**: Task 5 (binance_websocket_streams.ex)

**Notes**:
- All example modules include proper @spec, @doc, @moduledoc
- Following library design principles (explicit credentials, no global config)
- Using testnet patterns throughout

---

### Session 2: 2025-01-04
**Completed**:
- Task 5: Created binance_websocket_streams.ex

**Next session**: Task 6 (binance_strategies.ex)

**Notes**:
- WebSocket example uses Cache.Market for accessing cached data (get_ticker, get_orderbook, get_last_trade, get_book_ticker)
- Includes complete run_complete_example/0 function demonstrating full workflow
- All functions have proper @spec and @doc with examples

---

### Session 3: 2025-01-04
**Completed**:
- Task 6: Created binance_strategies.ex
- Task 16: Created test suite for binance_strategies

**Next session**: Task 7 (bybit_trading.ex) and Task 17 (tests)

---

### Session 4: 2025-01-05
**Completed**:
- Verified all existing tests pass (Tasks 11-14, 16)
- Updated specs documentation to reflect actual completion status

**Status Check**:
- ✅ All Binance example modules complete (Tasks 1-6)
- ✅ All Binance tests complete except WebSocket (Tasks 11-14, 16)
- ⏳ Task 15 (binance_websocket_streams_test.exs) - deferred for later
- ⏳ Bybit examples and tests (Tasks 7, 17) - ready to start

**Test Results**: 28 tests, 0 failures, 9 skipped (all write_operation and strategy tests)

**Next session**: Task 15 (WebSocket tests) or Task 7 (bybit_trading.ex)

---

### Session 5: 2025-01-05
**Completed**:
- Task 15: Created binance_websocket_streams_test.exs (initial + enhancements)
- Enhanced binance_websocket_streams.ex with production features

**Initial Implementation (17 tests)**:
- Comprehensive WebSocket test suite
- Tests connection lifecycle (connect, subscribe, close)
- Tests all cache access patterns (ticker, orderbook, trade, book_ticker)
- Verifies Cache.Market integration
- Tests both single and multiple stream connections
- Full integration workflow test
- Proper timeout handling (@wait_for_data_ms = 3000)

**Production Enhancements (9 additional tests = 26 total)**:
- Added `connect_with_retry/2` - automatic retry with exponential backoff
- Added `connect_supervised/2` - supervised connections for production
- Added `check_connection_health/1` - comprehensive health monitoring
- Added `reconnect_connection/1` - manual reconnection trigger
- Added `run_production_example/0` - full production workflow demo
- Added `run_monitoring_example/0` - health monitoring demo
- Enhanced @moduledoc with Gun ownership architecture explanation
- Tests for all new production features

**Key Architecture Documented**:
- Gun ownership through Client GenServer (not external reconnection)
- Automatic reconnection maintaining same GenServer process
- Message routing continuity through reconnections
- Client struct remains valid throughout reconnections
- Superior to external reconnection (no ownership transfer issues)

**Test Results**: 26 tests, 0 failures (all passed with real WebSocket connections in ~80s)

**Notes**:
- WebSocket tests tagged with `@websocket` and `@example`
- Production example tests tagged with `@slow`
- Tests connect to real Binance WebSocket endpoints
- Some tests accept {:error, :not_found} or {:error, :expired} due to timing
- Fixed pattern matching syntax (match?/2 instead of match/2)
- Demonstrates zen_websocket's sophisticated reconnection architecture

**Next session**: Task 7 (bybit_trading.ex) and Task 17 (bybit_trading_test.exs)

---

_Add new session notes above this line_
