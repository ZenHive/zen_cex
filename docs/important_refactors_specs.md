# Important Refactors Specification

This document tracks important refactoring tasks that improve consistency and maintainability across the ZenCex library.

---

## Status: PENDING

---

## Refactor 1: Extract Shared Parser Key Normalization

### Priority: High
**[D:2/B:9 → Priority:4.5] 🎯 Exceptional ROI**

**Impact**: Eliminates code duplication, ensures consistency for all current and future exchanges

### Problem

The library has **duplicated key normalization logic** and **inconsistent response formats**:

- **Binance Parser** (886 lines): Manually normalizes all responses to **atom keys**
  ```elixir
  # 50+ lines per function doing manual key mapping
  %{
    order_id: extract_field(response, ["orderId"], :string),
    client_order_id: extract_field(response, ["clientOrderId"], :string),
    symbol: extract_field(response, ["symbol"], :string),
    # ... 20+ more fields per function
  }
  ```

- **Bybit Parser** (410 lines): Returns **string keys** as-is from API
  ```elixir
  # No normalization - raw API response
  {:ok, %{"orderId" => "123", "symbol" => "BTCUSDT"}}
  ```

- **Aster** (future): Will need the same normalization logic again

### Impact

**Code Duplication Issues**:
1. **800+ lines of duplicated key mapping** across parsers
2. Each new exchange needs to reimplement normalization
3. Inconsistent behavior: Binance returns atoms, Bybit returns strings
4. Pattern matching breaks when switching exchanges

**User Experience Issues**:
```elixir
# Works with Binance (atom keys)
{:ok, %{server_time: time}} = Binance.Common.get_server_time()

# Breaks with Bybit (string keys) - user expects consistency
{:ok, %{server_time: time}} = Bybit.Common.get_server_time()  # MatchError!
```

**Maintenance Burden**:
- Tests must handle different key formats per exchange
- Example code documents the inconsistency (see `lib/examples/bybit_trading.ex`)
- Future exchanges (Aster, etc.) will repeat the same duplication
- Users must write exchange-specific code

### Root Cause

**No shared key normalization utility**:
- `ParserMacros` has decimal/field extraction utilities but NOT key normalization
- Binance manually converts: `"orderId"` → `:order_id` (50+ lines per function)
- Bybit returns raw: `%{"orderId" => "123"}` unchanged
- Each parser duplicates or omits normalization logic

**File comparison**:
```elixir
# Binance.Parser:360 - Manual normalization (repeated 15+ times)
def parse_server_time(response) when is_map(response) do
  time -> {:ok, %{server_time: time}}  # ← Manual atom key
end

# Bybit.Parser:118 - No normalization
defp handle_bybit_response(%{"retCode" => 0, "result" => result}, _status, _response) do
  {:ok, result}  # ← Raw string keys
end
```

### Solution

**Approach**: Extract shared `normalize_keys/1` function to `ParserMacros`

**Decision**: Use `String.to_atom/1` (SAFE for exchange responses)

**Rationale**:
- ✅ Input from **trusted exchange APIs**, not user input
- ✅ Field names are **controlled vocabulary** (~50-100 unique keys per exchange)
- ✅ Exchange APIs are **stable** (don't add arbitrary new fields)
- ✅ Number of atoms is **bounded and small**
- ✅ Alternative (whitelisting) adds complexity without security benefit

#### Implementation: Add to ParserMacros

**File**: `lib/zen_cex/parser_macros.ex`

```elixir
@doc """
Normalizes string keys to atom keys with snake_case conversion.

Safe for exchange responses because field names are controlled by the exchange,
not user input. Uses String.to_atom/1 since we know the field vocabulary is bounded.

## Examples

    iex> normalize_keys(%{"orderId" => "123", "clientOrderId" => "abc"})
    %{order_id: "123", client_order_id: "abc"}

    iex> normalize_keys([%{"symbol" => "BTCUSDT"}])
    [%{symbol: "BTCUSDT"}]

    iex> normalize_keys(%{"nested" => %{"timeSecond" => "123"}})
    %{nested: %{time_second: "123"}}
"""
@spec normalize_keys(map() | list() | term()) :: map() | list() | term()
def normalize_keys(data) when is_map(data) do
  Enum.reduce(data, %{}, fn {key, value}, acc ->
    normalized_key =
      key
      |> to_string()
      |> Macro.underscore()
      |> String.to_atom()

    normalized_value = normalize_keys(value)
    Map.put(acc, normalized_key, normalized_value)
  end)
end

def normalize_keys(data) when is_list(data) do
  Enum.map(data, &normalize_keys/1)
end

def normalize_keys(data), do: data
```

#### Update Bybit Parser

**File**: `lib/zen_cex/adapters/bybit/parser.ex`

```elixir
import ZenCex.ParserMacros  # Add at top

defp handle_bybit_response(%{"retCode" => 0, "result" => result}, _status, _response) do
  # Normalize to atom keys for consistency with Binance
  normalized = normalize_keys(result)
  {:ok, normalized}
end
```

#### Optional: Simplify Binance Parser

**File**: `lib/zen_cex/adapters/binance/parser.ex`

```elixir
# BEFORE: Manual key mapping (50+ lines)
def parse_order(response) do
  %{
    order_id: extract_field(response, ["orderId", "id"], :string),
    client_order_id: extract_field(response, ["clientOrderId"], :string),
    symbol: symbol,
    side: side |> String.downcase() |> String.to_atom(),
    type: order_type |> String.downcase() |> String.to_atom(),
    # ... 15+ more manual field mappings
  }
end

# AFTER: Automatic normalization + computed fields only
def parse_order(response) do
  response
  |> normalize_keys()
  |> Map.merge(%{
    side: normalize_side(response["side"]),
    type: normalize_order_type(response["type"]),
    status: normalize_order_status(response["status"])
  })
  |> then(&{:ok, &1})
end
```

**Benefits**:
- ✅ **Eliminates 800+ lines of boilerplate** across parsers
- ✅ **Consistent atom keys** across all exchanges
- ✅ **Future-proof**: New exchanges auto-normalized
- ✅ **One place to fix** snake_case conversion
- ✅ **No security risk**: Trusted exchange APIs only

**Risks**:
- **Breaking change** for existing Bybit users
- Must update all tests that expect string keys

### Implementation Plan

**[D:2/B:9 → Priority:4.5] 🎯**

#### Step 1: Add normalize_keys/1 to ParserMacros (~30 min)

**File**: `lib/zen_cex/parser_macros.ex`

```elixir
@doc """
Normalizes string keys to atom keys with snake_case conversion.
"""
@spec normalize_keys(map() | list() | term()) :: map() | list() | term()
def normalize_keys(data) when is_map(data) do
  Enum.reduce(data, %{}, fn {key, value}, acc ->
    normalized_key =
      key
      |> to_string()
      |> Macro.underscore()
      |> String.to_atom()

    normalized_value = normalize_keys(value)
    Map.put(acc, normalized_key, normalized_value)
  end)
end

def normalize_keys(data) when is_list(data) do
  Enum.map(data, &normalize_keys/1)
end

def normalize_keys(data), do: data
```

Add tests in `test/zen_cex/parser_macros_test.exs`:
```elixir
test "normalize_keys converts camelCase to snake_case atoms" do
  input = %{"orderId" => "123", "clientOrderId" => "abc"}
  expected = %{order_id: "123", client_order_id: "abc"}
  assert normalize_keys(input) == expected
end

test "normalize_keys handles nested structures" do
  input = %{"result" => %{"timeSecond" => "123"}}
  expected = %{result: %{time_second: "123"}}
  assert normalize_keys(input) == expected
end

test "normalize_keys handles lists" do
  input = [%{"symbol" => "BTCUSDT"}]
  expected = [%{symbol: "BTCUSDT"}]
  assert normalize_keys(input) == expected
end
```

#### Step 2: Update Bybit Parser (~30 min)

**File**: `lib/zen_cex/adapters/bybit/parser.ex`

Add at top:
```elixir
import ZenCex.ParserMacros
```

Update `handle_bybit_response/3`:
```elixir
defp handle_bybit_response(%{"retCode" => 0, "result" => result}, _status, _response) do
  # Normalize to atom keys for consistency with Binance
  normalized = normalize_keys(result)
  {:ok, normalized}
end
```

#### Step 3: Update Bybit Tests (~45 min)

Update all Bybit tests to expect atom keys:

**Files to update**:
- `test/zen_cex/adapters/bybit/*_test.exs`
- `test/examples/bybit_trading_test.exs`

**Changes**:
```elixir
# BEFORE (string keys)
assert Map.has_key?(response, "list")
positions = response["list"]

# AFTER (atom keys)
assert Map.has_key?(response, :list)
positions = response[:list]
```

#### Step 4: Update Documentation (~15 min)

1. Remove string key warnings from `lib/examples/bybit_trading.ex`
2. Update CHANGELOG.md:
   ```markdown
   ### Changed
   - **BREAKING**: Bybit parser now returns atom keys (consistent with Binance)
     - All response keys normalized to snake_case atoms
     - Update code: `response["orderId"]` → `response[:order_id]`
   ```

3. Add to CLAUDE.md policy:
   ```markdown
   ## Response Key Normalization Policy
   - All exchange parsers MUST return atom keys
   - Use `ParserMacros.normalize_keys/1` for automatic conversion
   - camelCase → snake_case → atom (e.g., "orderId" → :order_id)
   - Safe for exchange APIs (controlled vocabulary)
   ```

#### Step 5: Optional - Simplify Binance Parser (~1-2 hours)

Consider refactoring Binance parser to use `normalize_keys/1` where beneficial.
This step can be deferred - focus on Bybit consistency first.

#### Step 6: Verification (~15 min)

```bash
mix test                    # All tests pass
mix dialyzer               # No warnings
mix credo                  # Clean
mix format                 # Formatted
```

### Total Time: ~2-3 hours

**Before Aster Integration**: Complete this refactor so Aster can use `normalize_keys/1` from day one.

### Breaking Change Notes

**For existing Bybit users**:

```elixir
# BEFORE (string keys)
{:ok, response} = Bybit.Unified.get_position_list(%{category: "linear"})
positions = response["list"]  # String key access
order_id = positions[0]["orderId"]

# AFTER (atom keys)
{:ok, response} = Bybit.Unified.get_position_list(%{category: "linear"})
positions = response[:list]  # Atom key access
order_id = positions[0][:order_id]
```

**Migration is simple**: Just change string key access to atom key access.

---

## Refactor 2: (Future) Simplify Binance Parser Using normalize_keys/1

### Priority: Low
**[D:4/B:6 → Priority:1.5] 📋**

**Impact**: Reduces Binance parser code duplication after Refactor 1 is complete

### Problem

After implementing shared `normalize_keys/1`, Binance parser still has manual key mapping:

```elixir
# Current: Manual field-by-field mapping
def parse_order(response) do
  %{
    order_id: extract_field(response, ["orderId", "id"], :string),
    client_order_id: extract_field(response, ["clientOrderId"], :string),
    symbol: extract_field(response, ["symbol"], :string),
    # ... 20+ more manual mappings
  }
end
```

### Solution

Use `normalize_keys/1` for base normalization, only manually map computed fields:

```elixir
def parse_order(response) do
  response
  |> normalize_keys()
  |> Map.merge(%{
    side: normalize_side(response["side"]),
    type: normalize_order_type(response["type"]),
    status: normalize_order_status(response["status"])
  })
  |> then(&{:ok, &1})
end
```

**Benefits**:
- Reduces ~50 lines per function to ~10 lines
- Maintains custom logic for enums/computed fields
- More maintainable

**Defer until**: After Refactor 1 is stable and Aster integration complete

---

## Session Notes

### 2025-01-05: Initial Specification

**Completed**:
- Documented atom vs string key inconsistency issue
- Designed shared `normalize_keys/1` solution
- Created implementation plan with 6 steps
- Estimated 2-3 hours total implementation time
- Decision: Use `String.to_atom/1` (safe for exchange APIs)

**Next Steps**:
- Implement Refactor 1 before Aster integration
- Aster can use shared normalization from day one
- Defer Binance simplification (Refactor 2) until later

---

_End of document_
