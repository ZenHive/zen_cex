# TypeSpec Generation for Mix Task Generators

Auto-generate `@spec` annotations from OpenAPI schemas to enable compile-time type checking with Dialyzer.

## Status: PENDING

---

## 🔄 CONTINUATION PROMPT (Update at end of each session)

**Last Updated**: 2025-10-27 (Task 3 Complete)

**For next session, start with**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 3 COMPLETED ✅ - Binance Spot types verified with Dialyzer
Next: Task 4 (Update Binance Futures Generator)

Task 3 verification results:
- Test fix: Updated optional field syntax test (38/38 passing)
- Dialyzer: 0 typespec-related errors (16 pre-existing errors in other modules)
- Type coverage: 96.8% (329/340 endpoints with detailed types)
- Complex types: All working (nested objects, enums, optional fields)
- EndpointRegistry: Already complete (ahead of schedule - extracts specs and generates AST)
- Module compilation: Clean, no warnings

Begin: "Starting Task 4: Updating Binance Futures generator with type generation..."
```

**What to update at end of each session**:
1. Update "Last Updated" date
2. Update "Current status" with completed tasks
3. Update "Next" with the next task number and name
4. If all tasks done, change Status to "COMPLETED"

---

## Overview

**Goal**: Auto-generate `@spec` type annotations from OpenAPI schemas in all mix task generators.

**Why**: Enable Dialyzer to catch type errors at compile time, improve IDE autocomplete, and provide better developer experience.

**Scope**: 6 generators totaling ~2,183 lines of code:
1. Binance Spot (303 lines) - `zen_cex.generate_endpoints.ex`
2. Binance Futures (309 lines) - `zen_cex.generate_futures_endpoints.ex`
3. Binance Margin (301 lines) - `zen_cex.generate_margin_endpoints.ex`
4. Binance Market Data (268 lines) - `zen_cex.generate_binance_market_data.ex`
5. Bybit Endpoints (448 lines) - `zen_cex.generate_bybit_endpoints.ex`
6. Bybit Market Data (254 lines) - `zen_cex.generate_bybit_market_data.ex`

**Approach**: Create shared type generation module, then update generators incrementally.

---

## Architecture

### Shared Type Module

**File**: `lib/mix/tasks/helpers/type_generator.ex`

**Responsibilities**:
- Parse OpenAPI parameter schemas → Elixir types
- Parse OpenAPI response schemas → Elixir types
- Resolve `$ref` references to component schemas
- Generate `@spec` annotation syntax
- Handle edge cases (oneOf, anyOf, allOf, etc.)

**Public API**:
```elixir
TypeGenerator.extract_param_types(endpoint_spec, components) :: [{atom(), type_ast()}]
TypeGenerator.extract_response_type(endpoint_spec, components) :: type_ast()
TypeGenerator.generate_spec(operation_name, param_types, response_type) :: String.t()
```

### Integration Points

Each generator will call TypeGenerator functions in their existing parsing pipeline:

```elixir
# Current: Just extract operation metadata
defp map_to_endpoint_format(openapi_spec) do
  paths = openapi_spec["paths"]

  for {path, operations} <- paths do
    %{operation: ..., method: ..., path: ...}
  end
end

# Enhanced: Also extract type information
defp map_to_endpoint_format(openapi_spec) do
  paths = openapi_spec["paths"]
  components = openapi_spec["components"]  # NEW

  for {path, operations} <- paths do
    %{
      operation: ...,
      method: ...,
      path: ...,
      # NEW: Type information
      param_types: TypeGenerator.extract_param_types(spec, components),
      response_type: TypeGenerator.extract_response_type(spec, components),
      spec_annotation: TypeGenerator.generate_spec(operation, params, response)
    }
  end
end
```

### Output Format

**Current generated_endpoints.ex** (no types):
```elixir
[
  %{
    operation: :get_server_time,
    method: :get,
    path: "/api/v3/time"
  }
]
```

**Enhanced generated_endpoints.ex** (with types):
```elixir
[
  %{
    operation: :get_server_time,
    method: :get,
    path: "/api/v3/time",
    # NEW: Type metadata
    param_types: [],
    response_type: "%{server_time: integer()}",
    spec: "@spec get_server_time(keyword()) :: {:ok, %{server_time: integer()}} | {:error, term()}"
  }
]
```

---

## Task 0: Research & Design

**[D:2/B:9 → Priority:4.5] 🎯**

**Purpose**: Understand OpenAPI schema structure and design type mapping system.

**Estimated Time**: 1.5-2 hours

**Prerequisites**: None

**Implementation Steps**:

1. **Explore OpenAPI Schema Structure** (30 min):
   - Download Binance OpenAPI spec
   - Examine parameter schemas (path params, query params, body)
   - Examine response schemas (200, 400, etc.)
   - Check component schemas and `$ref` usage
   - Document common patterns

2. **Design Type Mapping Table** (30 min):
   - Map OpenAPI types → Elixir types
   - Handle primitive types (integer, string, boolean, number)
   - Handle complex types (array, object)
   - Handle enums and constants
   - Document edge cases (oneOf, anyOf, allOf, nullable)

3. **Design Shared Module API** (30 min):
   - Define function signatures for TypeGenerator
   - Design internal data structures
   - Plan error handling strategy
   - Document assumptions and limitations

4. **Create Examples** (15 min):
   - Show sample OpenAPI schema → Elixir type conversions
   - Document expected output for common cases
   - List unsupported features (for Phase 2)

**Verification Criteria**:
- [ ] Downloaded and examined OpenAPI spec
- [ ] Created type mapping table (15+ type conversions)
- [ ] Designed TypeGenerator API (3-5 public functions)
- [ ] Documented 5+ example conversions
- [ ] Listed known limitations

**Output**: Updated this spec document with Research Findings section.

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 0 COMPLETED ✅ - Research and design finished
Next: Task 1 (Create Shared Type Module)

Key findings from Task 0:
- OpenAPI type mapping: [summary]
- $ref resolution strategy: [approach]
- Edge cases to handle: [list]

Begin: "Starting Task 1: Creating shared TypeGenerator module..."
```

---

## Task 1: Create Shared Type Module

**[D:4/B:9 → Priority:2.25] 🚀**

**Purpose**: Implement reusable type generation helpers that all generators can use.

**Estimated Time**: 2-3 hours

**Prerequisites**: Task 0 completed

**File**: `lib/mix/tasks/helpers/type_generator.ex`

**Implementation Steps**:

1. **Create Module Structure** (15 min):
   ```elixir
   defmodule Mix.Tasks.Helpers.TypeGenerator do
     @moduledoc """
     Shared utilities for generating Elixir type specifications from OpenAPI schemas.
     """

     # Public API functions
     # Private helper functions
   end
   ```

2. **Implement Type Mapping** (45 min):
   ```elixir
   defp openapi_type_to_elixir(%{"type" => "integer"})
   defp openapi_type_to_elixir(%{"type" => "string"})
   defp openapi_type_to_elixir(%{"type" => "array", "items" => items})
   defp openapi_type_to_elixir(%{"type" => "object", "properties" => props})
   # ... etc
   ```

3. **Implement $ref Resolution** (30 min):
   ```elixir
   defp resolve_ref({"$ref" => ref_path}, components)
   defp resolve_ref(schema, _components) when is_map(schema)
   ```

4. **Implement Parameter Extraction** (30 min):
   ```elixir
   def extract_param_types(endpoint_spec, components) do
     params = endpoint_spec["parameters"] || []

     Enum.map(params, fn param ->
       resolved = resolve_ref(param, components)
       {
         String.to_atom(resolved["name"]),
         openapi_type_to_elixir(resolved["schema"])
       }
     end)
   end
   ```

5. **Implement Response Extraction** (30 min):
   ```elixir
   def extract_response_type(endpoint_spec, components) do
     responses = endpoint_spec["responses"]
     success_response = responses["200"] || responses["201"]

     schema = get_in(success_response, ["content", "application/json", "schema"])
     openapi_type_to_elixir(resolve_ref(schema, components))
   end
   ```

6. **Implement Spec Generation** (30 min):
   ```elixir
   def generate_spec(operation_name, param_types, response_type) do
     param_spec = if Enum.empty?(param_types) do
       "map(), keyword()"
     else
       # Build typed param map
       "..."
     end

     "@spec #{operation_name}(#{param_spec}) :: {:ok, #{response_type}} | {:error, term()}"
   end
   ```

7. **Add Tests** (30 min):
   - Create `test/mix/tasks/helpers/type_generator_test.exs`
   - Test primitive type conversions
   - Test array/object conversions
   - Test $ref resolution
   - Test spec generation

**Verification Criteria**:
- [ ] Module compiles without errors
- [ ] All public functions implemented
- [ ] Handles primitive types (integer, string, boolean, number)
- [ ] Handles complex types (array, object)
- [ ] Resolves $ref references
- [ ] Generates valid @spec syntax
- [ ] All tests pass

**Testing Commands**:
```bash
mix compile
mix test test/mix/tasks/helpers/type_generator_test.exs
```

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 1 COMPLETED ✅ - Shared TypeGenerator module created
Next: Task 2 (Update Binance Spot Generator - Proof of Concept)

Key implementation notes:
- TypeGenerator location: lib/mix/tasks/helpers/type_generator.ex
- Public API: extract_param_types/2, extract_response_type/2, generate_spec/3
- Supported types: [list what works]
- Known limitations: [list what doesn't work yet]

Begin: "Starting Task 2: Updating Binance Spot generator as proof of concept..."
```

---

## Task 2: Update Binance Spot Generator (Proof of Concept)

**[D:3/B:8 → Priority:2.67] 🎯**

**Purpose**: Integrate TypeGenerator into one generator to validate the approach.

**Estimated Time**: 2-3 hours

**Prerequisites**: Task 1 completed

**File**: `lib/mix/tasks/zen_cex.generate_endpoints.ex`

**Implementation Steps**:

1. **Import TypeGenerator** (5 min):
   ```elixir
   alias Mix.Tasks.Helpers.TypeGenerator
   ```

2. **Update `map_to_endpoint_format/1`** (30 min):
   ```elixir
   defp map_to_endpoint_format(openapi_spec) do
     paths = openapi_spec["paths"] || %{}
     components = openapi_spec["components"] || %{}  # NEW

     Enum.flat_map(paths, fn {path, operations} ->
       Enum.map(operations, fn {method, spec} ->
         %{
           # Existing fields...
           operation: derive_operation_name(method, path, spec),
           method: String.to_atom(method),
           path: path,

           # NEW: Type information
           param_types: TypeGenerator.extract_param_types(spec, components),
           response_type: TypeGenerator.extract_response_type(spec, components),
           spec_annotation: TypeGenerator.generate_spec(
             derive_operation_name(method, path, spec),
             TypeGenerator.extract_param_types(spec, components),
             TypeGenerator.extract_response_type(spec, components)
           )
         }
       end)
     end)
   end
   ```

3. **Update `format_endpoint/1`** (30 min):
   ```elixir
   defp format_endpoint(endpoint) do
     # Existing formatting...

     # NEW: Add type information to output
     "  %{\n" <>
       "    operation: #{inspect(endpoint.operation)},\n" <>
       # ... existing fields ...
       "    param_types: #{inspect(endpoint.param_types)},\n" <>
       "    response_type: #{inspect(endpoint.response_type)},\n" <>
       "    spec: #{inspect(endpoint.spec_annotation)}\n" <>
       "  }"
   end
   ```

4. **Test Generation** (30 min):
   ```bash
   # Backup current generated file
   cp lib/zen_cex/adapters/binance/generated_endpoints.ex \
      lib/zen_cex/adapters/binance/generated_endpoints.ex.backup

   # Generate with types
   mix zen_cex.generate_endpoints binance

   # Check output
   head -50 lib/zen_cex/adapters/binance/generated_endpoints.ex
   ```

5. **Fix Issues** (45 min):
   - Handle errors in type extraction
   - Fix type conversion edge cases
   - Improve error messages
   - Add fallbacks for missing schemas

6. **Document Findings** (15 min):
   - Note which endpoints work well
   - Note which endpoints have issues
   - List improvements needed in TypeGenerator
   - Update spec with learnings

**Verification Criteria**:
- [ ] Generation completes without errors
- [ ] Generated file includes type information
- [ ] At least 50% of endpoints have valid types
- [ ] Complex types (arrays, objects) work correctly
- [ ] Generated code compiles

**Testing Commands**:
```bash
mix zen_cex.generate_endpoints binance
mix compile
grep "spec:" lib/zen_cex/adapters/binance/generated_endpoints.ex | head -5
```

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 2 COMPLETED ✅ - Binance Spot generator updated
Next: Task 3 (Test & Verify Binance Spot Types)

Generated endpoints with types: [count successful]
Issues encountered: [list problems]
TypeGenerator improvements needed: [list enhancements]

Begin: "Starting Task 3: Testing and verifying Binance Spot types..."
```

---

## Task 3: Test & Verify Binance Spot Types

**[D:2/B:9 → Priority:4.5] 🎯**

**Purpose**: Validate that generated types work correctly with Dialyzer and in actual code.

**Estimated Time**: 1.5-2 hours

**Prerequisites**: Task 2 completed

**Implementation Steps**:

1. **Update EndpointLoader to Use Specs** (45 min):

   **File**: `lib/zen_cex/adapters/binance/endpoint_loader.ex`

   ```elixir
   defmacro load_endpoints(file, transform_fn \\ nil) do
     endpoints = # Read file...

     for endpoint <- endpoints do
       # NEW: Inject @spec if present
       if spec_string = endpoint[:spec_annotation] do
         # Convert string to code and inject
         Code.eval_string(spec_string, [], __ENV__)
       end

       # Generate function (existing code)
       def unquote(endpoint.operation)(params \\ %{}, opts \\ []) do
         execute_endpoint_request(config, params, opts)
       end
     end
   end
   ```

2. **Run Dialyzer** (30 min):
   ```bash
   # This will take time on first run
   mix dialyzer

   # Look for type errors in generated specs
   # Should see no errors related to Spot module functions
   ```

3. **Manual Testing** (30 min):
   ```elixir
   # In IEx
   alias ZenCex.Adapters.Binance.Spot

   # Check if types are working
   # Dialyzer should catch type mismatches
   {:ok, result} = Spot.get_server_time()
   result.server_time + 1000  # Should type-check
   ```

4. **Fix Type Issues** (30 min):
   - Adjust TypeGenerator for Dialyzer errors
   - Fix incorrect type conversions
   - Handle missing/optional fields
   - Update generated file and re-test

5. **Document Success Metrics** (15 min):
   - Count endpoints with valid specs
   - Count Dialyzer errors (goal: 0)
   - List endpoints with complex types that work
   - Note any remaining issues

**Verification Criteria**:
- [ ] Dialyzer runs without errors on Spot module
- [ ] At least 80% of endpoints have working specs
- [ ] Complex types (arrays, nested objects) work
- [ ] Manual testing in IEx confirms types
- [ ] No type-related compilation warnings

**Testing Commands**:
```bash
mix compile --force
mix dialyzer --format dialyzer
mix test test/zen_cex/adapters/binance/spot_test.exs
```

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 3 COMPLETED ✅ - Binance Spot types verified
Next: Task 4 (Update Binance Futures Generator)

Dialyzer results: [X errors, Y warnings]
Type coverage: [X%] of endpoints have valid specs
Known issues: [list any problems]

Begin: "Starting Task 4: Updating Binance Futures generator..."
```

---

## Task 4: Update Binance Futures Generator

**Status**: ✅ COMPLETED

**[D:2/B:7 → Priority:3.5] 🎯**

**Purpose**: Apply learnings from Spot generator to Futures generator.

**Estimated Time**: 1-1.5 hours

**Prerequisites**: Task 3 completed

**File**: `lib/mix/tasks/zen_cex.generate_futures_endpoints.ex`

**Implementation Steps**:

1. **Copy Pattern from Task 2** (30 min):
   - Import TypeGenerator
   - Update map_to_endpoint_format/1
   - Update format_endpoint/1
   - Apply any fixes discovered in Task 3

2. **Test Generation** (20 min):
   ```bash
   mix zen_cex.generate_futures_endpoints
   head -50 lib/zen_cex/adapters/binance/generated_futures_endpoints.ex
   ```

3. **Quick Verification** (20 min):
   - Check generated file has types
   - Spot-check a few endpoints
   - Run quick compile test

**Verification Criteria**:
- [x] Generation completes successfully
- [x] Types present in generated file
- [x] No new errors introduced
- [x] Compiles cleanly

**Completion Notes**:
- Updated `lib/mix/tasks/zen_cex.generate_futures_endpoints.ex` with TypeGenerator import
- Added generic types (`map()` for params, `term()` for responses) since Postman collections lack schema info
- Successfully regenerated all three futures endpoint files:
  - `generated_usdm_endpoints.ex` (46 endpoints)
  - `generated_coinm_endpoints.ex` (34 endpoints)
  - `generated_portfolio_endpoints.ex` (98 endpoints)
- All generated files include `param_types`, `response_type`, and `spec` fields
- Compilation successful with no errors
- Type specs follow pattern: `@spec operation_name(map(), keyword()) :: {:ok, term()} | {:error, term()}`

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 4 COMPLETED ✅ - Binance Futures generator updated
Next: Task 5 (Update Binance Margin Generator)

Begin: "Starting Task 5: Updating Binance Margin generator..."
```

---

## Task 5: Update Binance Margin Generator

**[D:2/B:7 → Priority:3.5] 🎯**

**Purpose**: Continue applying type generation to remaining Binance generators.

**Estimated Time**: 1-1.5 hours

**Prerequisites**: Task 4 completed

**File**: `lib/mix/tasks/zen_cex.generate_margin_endpoints.ex`

**Implementation Steps**: Same as Task 4

**Verification Criteria**: Same as Task 4

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 5 COMPLETED ✅ - Binance Margin generator updated
Next: Task 6 (Update Binance Market Data Generator)

Begin: "Starting Task 6: Updating Binance Market Data generator..."
```

---

## Task 6: Update Binance Market Data Generator

**[D:2/B:6 → Priority:3.0] 🎯**

**Purpose**: Update market data generator (may have different schema structure).

**Estimated Time**: 1-2 hours

**Prerequisites**: Task 5 completed

**File**: `lib/mix/tasks/zen_cex.generate_binance_market_data.ex`

**Implementation Steps**:

1. **Check Schema Differences** (15 min):
   - Market data endpoints may have different response formats
   - Check if OpenAPI spec is structured differently
   - Note any special cases

2. **Apply Type Generation** (45 min):
   - Same pattern as previous tasks
   - Handle any market-data-specific edge cases

3. **Test & Verify** (30 min):
   - Generate endpoints
   - Check output
   - Quick compile test

**Verification Criteria**: Same as Task 4

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 6 COMPLETED ✅ - Binance Market Data generator updated
Next: Task 7 (Update Bybit Endpoints Generator)

All Binance generators now have type generation ✅

Begin: "Starting Task 7: Updating Bybit Endpoints generator..."
```

---

## Task 7: Update Bybit Endpoints Generator

**[D:3/B:7 → Priority:2.33] 🚀**

**Purpose**: Adapt type generation for Bybit's API structure.

**Estimated Time**: 2-2.5 hours

**Prerequisites**: Task 6 completed

**File**: `lib/mix/tasks/zen_cex.generate_bybit_endpoints.ex`

**Implementation Steps**:

1. **Analyze Bybit OpenAPI Structure** (30 min):
   - Bybit may use Postman collections instead of OpenAPI
   - Schema structure may differ from Binance
   - Identify differences in type definitions

2. **Adapt TypeGenerator if Needed** (45 min):
   - Add Bybit-specific type handling
   - May need different schema parsing logic
   - Keep backward compatibility with Binance

3. **Update Generator** (45 min):
   - Apply type generation pattern
   - Handle Bybit-specific cases
   - Test output

4. **Verify** (30 min):
   - Generate endpoints
   - Check types look correct
   - Quick compile test

**Verification Criteria**:
- [ ] Generation works for Bybit structure
- [ ] Types present and look reasonable
- [ ] No breaking changes to Binance generators
- [ ] Compiles cleanly

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 7 COMPLETED ✅ - Bybit Endpoints generator updated
Next: Task 8 (Update Bybit Market Data Generator)

Bybit-specific handling: [note any special cases]

Begin: "Starting Task 8: Updating Bybit Market Data generator..."
```

---

## Task 8: Update Bybit Market Data Generator

**[D:2/B:6 → Priority:3.0] 🎯**

**Purpose**: Complete type generation for all generators.

**Estimated Time**: 1-1.5 hours

**Prerequisites**: Task 7 completed

**File**: `lib/mix/tasks/zen_cex.generate_bybit_market_data.ex`

**Implementation Steps**: Same pattern as Task 7, but faster since Bybit approach is established.

**Verification Criteria**: Same as Task 7

**Continuation Prompt**:
```
Continue TypeSpec generation from docs/typespec_generation_spec.md.

Current status: Task 8 COMPLETED ✅ - Bybit Market Data generator updated
Next: Task 9 (Final Testing & Documentation)

All 6 generators now have type generation! ✅

Begin: "Starting Task 9: Final testing and documentation..."
```

---

## Task 9: Final Testing & Documentation

**[D:3/B:8 → Priority:2.67] 🎯**

**Purpose**: Comprehensive testing, documentation, and cleanup.

**Estimated Time**: 2-3 hours

**Prerequisites**: Task 8 completed

**Implementation Steps**:

1. **Regenerate All Endpoints** (30 min):
   ```bash
   mix zen_cex.generate_endpoints binance
   mix zen_cex.generate_futures_endpoints
   mix zen_cex.generate_margin_endpoints
   mix zen_cex.generate_binance_market_data
   mix zen_cex.generate_bybit_endpoints
   mix zen_cex.generate_bybit_market_data
   ```

2. **Run Full Test Suite** (30 min):
   ```bash
   mix compile --force
   mix test
   mix dialyzer
   ```

3. **Update Documentation** (45 min):
   - Update README.md with type generation info
   - Add examples showing typed endpoints
   - Document mix task usage
   - Update CHANGELOG.md

4. **Create Usage Examples** (30 min):
   - Show before/after with types
   - Demonstrate Dialyzer catching type errors
   - Show IDE autocomplete improvements

5. **Final Review** (30 min):
   - Check all generated files
   - Verify no regressions
   - Count type coverage metrics
   - Document known limitations

**Verification Criteria**:
- [ ] All 6 generators work
- [ ] All tests pass
- [ ] Dialyzer shows 0 errors (or acceptable count)
- [ ] Documentation updated
- [ ] Examples added

**Deliverables**:
- 6 updated generators with type generation
- 1 shared TypeGenerator module
- Updated documentation
- Usage examples

**Success Metrics**:
- [ ] 100% of generators have type generation
- [ ] 80%+ of endpoints have valid @spec annotations
- [ ] Dialyzer catches type errors in test code
- [ ] IDE autocomplete shows typed returns

**Continuation Prompt**:
```
TypeSpec generation project COMPLETED! ✅

All 6 generators now auto-generate @spec annotations from OpenAPI schemas.

Summary:
- Generators updated: 6/6
- Type coverage: [X%]
- Dialyzer errors: [count]
- Documentation: Updated

Next steps (future enhancements):
- Support oneOf/anyOf/allOf schemas
- Generate separate Types modules
- Add runtime validation
```

---

## Research Findings (Updated by Task 0)

### OpenAPI Spec Structure Analysis

**Spec Source**: `https://raw.githubusercontent.com/binance/binance-api-swagger/master/spot_api.yaml`
- **Size**: 30,229 lines
- **Format**: OpenAPI 3.0.2 (YAML)
- **Structure**: Standard `paths` → `operations` → `parameters` + `responses`

### OpenAPI Type Mapping Table

| OpenAPI Type | Format | Elixir Type | Notes |
|--------------|--------|-------------|-------|
| `integer` | `int32` | `integer()` | Standard Elixir integer |
| `integer` | `int64` | `integer()` | Elixir integers are arbitrary precision |
| `number` | `double` | `float()` | IEEE 754 double precision |
| `number` | `float` | `float()` | Same as double |
| `string` | (none) | `String.t()` | UTF-8 string |
| `string` | `date-time` | `String.t()` | Keep as string, don't convert to DateTime |
| `boolean` | (none) | `boolean()` | true/false |
| `array` | (items) | `list(item_type())` | Recursive type for items |
| `object` | (properties) | `%{atom() => type()}` | Map with atom keys |
| `object` | (required) | `%{required(:key) => type(), optional(:key) => type()}` | Required/optional keys |
| `enum` | (values) | `:atom \| :atom \| ...` | Convert strings to atoms |

**Type Priority**:
1. If `enum` present → union of atoms
2. If `$ref` present → resolve reference
3. If `type` present → use mapping table
4. If missing → `term()`

### $ref Resolution Strategy

**Pattern**: `#/components/parameters/symbol` or `#/components/schemas/order`

**Resolution Steps**:
1. Split ref path: `["#", "components", "parameters", "symbol"]`
2. Navigate OpenAPI spec: `spec["components"]["parameters"]["symbol"]`
3. Recursively resolve if result contains another `$ref`
4. Cache resolved refs to avoid cycles (use agent state or process dict)

**Example**:
```elixir
# Input: {"$ref" => "#/components/parameters/symbol"}
# Navigate: openapi_spec["components"]["parameters"]["symbol"]
# Result: %{
#   "name" => "symbol",
#   "in" => "query",
#   "required" => true,
#   "schema" => %{"type" => "string"}
# }
# Final type: String.t()
```

### Edge Cases Discovered

1. **oneOf/anyOf/allOf** (15 occurrences in Binance spec):
   - Used for polymorphic responses (ticker vs tickerList)
   - Used for mixed type arrays (integer | string)
   - **Phase 1 Strategy**: Map to `term()` as fallback
   - **Phase 2**: Generate union types or separate functions

2. **Inline Schemas vs References**:
   - Some parameters have inline schemas
   - Others use `$ref` to components
   - **Strategy**: Handle both uniformly in type extraction

3. **Required vs Optional Parameters**:
   - Parameters have `required: true/false` field
   - Schema properties have `required: [field1, field2]` array
   - **Strategy**: Use `optional(key)` syntax for Dialyzer

4. **Numeric String Types**:
   - Binance uses `type: string` for decimal numbers (e.g., prices, quantities)
   - **Strategy**: Keep as `String.t()`, not `Decimal.t()` (parser layer responsibility)

5. **Missing Types**:
   - Some schemas have properties without type definitions
   - **Strategy**: Default to `term()` for untyped fields

### Example Conversions

#### Example 1: Simple Endpoint (GET /api/v3/time)
```yaml
responses:
  '200':
    content:
      application/json:
        schema:
          type: object
          properties:
            serverTime:
              type: integer
              format: int64
          required:
            - serverTime
```
**Generated Type**: `%{server_time: integer()}`
**Generated Spec**: `@spec get_server_time(keyword()) :: {:ok, %{server_time: integer()}} | {:error, term()}`

#### Example 2: Endpoint with Parameters (GET /api/v3/order)
```yaml
parameters:
  - $ref: '#/components/parameters/symbol'    # type: string, required
  - $ref: '#/components/parameters/orderId'   # type: integer, optional
responses:
  '200':
    schema:
      $ref: '#/components/schemas/orderDetails'
```
**Parameter Types**: `[symbol: String.t(), order_id: integer()]`
**Response Type**: `%{symbol: String.t(), order_id: integer(), status: String.t(), ...}` (from resolved schema)
**Generated Spec**: `@spec query_order(map(), keyword()) :: {:ok, order_details()} | {:error, term()}`

#### Example 3: Array Response (GET /api/v3/account)
```yaml
properties:
  balances:
    type: array
    items:
      type: object
      properties:
        asset:
          type: string
        free:
          type: string
        locked:
          type: string
```
**Generated Type**: `%{balances: list(%{asset: String.t(), free: String.t(), locked: String.t()})}`

#### Example 4: Enum Type (side parameter)
```yaml
parameters:
  - name: side
    schema:
      type: string
      enum: [BUY, SELL]
```
**Generated Type**: `:buy | :sell`
**Note**: Convert enum strings to lowercase atoms

#### Example 5: oneOf (Ticker Response) - Phase 2
```yaml
schema:
  oneOf:
    - $ref: '#/components/schemas/ticker'
    - $ref: '#/components/schemas/tickerList'
```
**Phase 1 Type**: `term()` (fallback)
**Phase 2 Type**: `ticker() | list(ticker())` (union type)

### TypeGenerator Module API Design

**File**: `lib/mix/tasks/helpers/type_generator.ex`

```elixir
defmodule Mix.Tasks.Helpers.TypeGenerator do
  @moduledoc """
  Generates Elixir type specifications from OpenAPI schemas.

  This module provides utilities for converting OpenAPI type definitions
  into Elixir @spec annotations for use in generated endpoint modules.
  """

  # ============================================================================
  # Public API (4 functions)
  # ============================================================================

  @doc """
  Extracts parameter types from an OpenAPI endpoint specification.

  Returns list of {param_name_atom, type_string} tuples.
  """
  @spec extract_param_types(map(), map()) :: [{atom(), String.t()}]
  def extract_param_types(endpoint_spec, components)

  @doc """
  Extracts response type from an OpenAPI endpoint specification.

  Looks for 200/201 success responses and generates type from schema.
  Returns type string like "%{field: String.t()}" or "term()" if unknown.
  """
  @spec extract_response_type(map(), map()) :: String.t()
  def extract_response_type(endpoint_spec, components)

  @doc """
  Generates complete @spec annotation string for a function.

  Combines parameter types and response type into valid Elixir spec.
  """
  @spec generate_spec(atom(), [{atom(), String.t()}], String.t()) :: String.t()
  def generate_spec(operation_name, param_types, response_type)

  @doc """
  Resolves a $ref reference to its actual schema definition.

  Handles both parameter refs and schema refs.
  """
  @spec resolve_ref(String.t() | map(), map()) :: map()
  def resolve_ref(ref_or_schema, components)

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Convert OpenAPI type object to Elixir type string
  defp openapi_type_to_elixir(schema) :: String.t()

  # Handle primitive types
  defp type_integer(schema), do: "integer()"
  defp type_number(schema), do: "float()"
  defp type_string(schema), do: handle_string_type(schema)
  defp type_boolean(schema), do: "boolean()"

  # Handle complex types
  defp type_array(schema, components), do: "list(#{item_type})"
  defp type_object(schema, components), do: generate_map_type(schema)

  # Handle enums
  defp handle_enum(values), do: Enum.map_join(values, " | ", &":#{downcase}")

  # Handle string subtypes
  defp handle_string_type(%{"format" => "date-time"}), do: "String.t()"
  defp handle_string_type(%{"enum" => values}), do: handle_enum(values)
  defp handle_string_type(_), do: "String.t()"

  # Generate map type with required/optional keys
  defp generate_map_type(schema) do
    properties = schema["properties"] || %{}
    required = schema["required"] || []
    # Build %{required(:key) => type(), optional(:key) => type()}
  end

  # Navigate ref path like "#/components/parameters/symbol"
  defp navigate_ref_path(path, components) :: map()

  # Convert camelCase to snake_case for field names
  defp to_snake_case_atom(string) :: atom()
end
```

### Implementation Notes

1. **Keep It Simple**: Start with primitive types, arrays, and objects. Defer oneOf/anyOf to Phase 2.

2. **Error Handling**: If type extraction fails, return `"term()"` instead of crashing. Log warning for debugging.

3. **Caching**: Don't implement caching in Phase 1. Profile first, optimize later if needed.

4. **String Formatting**: Generate human-readable type strings, not AST. Easier to debug and inspect.

5. **Integration Point**: Generators call `TypeGenerator` functions in existing `map_to_endpoint_format/1`, adding 3 new fields to endpoint map:
   - `param_types: [{:symbol, "String.t()"}, ...]`
   - `response_type: "%{server_time: integer()}"`
   - `spec_annotation: "@spec get_server_time(...) :: ..."`

### Known Limitations (Phase 1)

1. **No oneOf/anyOf/allOf support** → Falls back to `term()`
2. **No discriminators** → Can't generate tagged unions
3. **No custom type definitions** → Inline types only
4. **No validation** → Types are for Dialyzer only, no runtime checks
5. **No nested $ref optimization** → May generate verbose types
6. **No type aliases** → Every occurrence generates full inline type

### Success Metrics for Task 0

- [x] Downloaded and examined Binance OpenAPI spec (30K lines)
- [x] Created type mapping table (11 type conversions)
- [x] Designed TypeGenerator API (4 public functions)
- [x] Documented 5 example conversions
- [x] Listed 6 known limitations

---

## Notes

### Out of Scope (Phase 2)

These features are explicitly **not** included in this initial implementation:

1. **Separate Types Modules**: Not generating `ZenCex.Adapters.Binance.Types` module yet
2. **Runtime Validation**: No parameter validation at runtime (just compile-time types)
3. **oneOf/anyOf/allOf**: Complex schema composition not supported initially
4. **Discriminators**: Polymorphic types not handled
5. **Custom Type Guards**: No `when` clauses in generated specs

### Philosophy

Following CLAUDE.md principles:
- **Simple First**: Start with basic types, add complexity only when proven necessary
- **Pragmatic Simplicity**: Cover 80% of cases with 20% of the complexity
- **Explicit over Implicit**: Generate readable type annotations, not clever abstractions
- **No Magic Numbers**: All type conversion decisions are documented

### Success Criteria

This implementation is successful if:
1. ✅ Dialyzer catches real type errors in development
2. ✅ IDE autocomplete improves for generated functions
3. ✅ Types work for 80%+ of endpoints
4. ✅ No performance impact on generation time
5. ✅ Easy to maintain and update

---

## Session Notes

### Session 1: 2025-10-06

**Completed**: Task 0 - Research & Design

**Time**: ~1.5 hours

**Findings**:
- Binance OpenAPI spec is comprehensive (30K lines) with standard structure
- Type mapping is straightforward for 80% of cases (primitives, arrays, objects)
- Main complexity comes from $ref resolution and oneOf/anyOf/allOf (15 occurrences)
- Binance uses `type: string` for numeric values (prices, quantities) - keep as strings in types
- 4-function public API is sufficient: extract_param_types, extract_response_type, generate_spec, resolve_ref
- Can defer complex schema composition (oneOf/anyOf/allOf) to Phase 2 with `term()` fallback
- Estimated 80%+ type coverage achievable with simple implementation

**Key Decisions**:
1. Generate type strings (not AST) for easier debugging
2. Default to `term()` on errors instead of crashing
3. No caching in Phase 1 - optimize later if needed
4. Keep numeric strings as `String.t()` (parser layer handles Decimal conversion)
5. Support both inline schemas and $ref uniformly

**Next**: Task 1 - Create Shared TypeGenerator Module

### Session 2: 2025-10-07

**Completed**: Task 1 - Create Shared Type Module

**Time**: ~2 hours

**Implementation**:
- Created `lib/mix/tasks/helpers/type_generator.ex` with 260 lines
- Created `test/mix/tasks/helpers/type_generator_test.exs` with 38 tests
- All tests passing

**Public API Functions**:
1. `extract_param_types/2` - Extracts parameter types from endpoint spec
2. `extract_response_type/2` - Extracts response type from 200/201 responses
3. `generate_spec/3` - Generates @spec annotation string
4. `resolve_ref/2` - Resolves $ref references to actual schemas
5. `openapi_type_to_elixir/2` - Converts OpenAPI types to Elixir types (exposed for testing)

**Type Coverage**:
- ✅ Primitives: integer, number, string, boolean
- ✅ Complex: array, object with required/optional fields
- ✅ Enums: converted to atom unions
- ✅ $ref resolution: navigates component paths correctly
- ✅ Nested types: arrays of objects, nested objects
- ⚠️  Edge cases: oneOf/anyOf/allOf fall back to `term()`

**Key Implementation Details**:
1. $ref resolution builds full spec structure (`%{"components" => components}`) before navigating
2. Parameter names converted to snake_case atoms (`recvWindow` → `:recv_window`)
3. Missing parameter names default to `:unknown_param`
4. Object fields use required/optional syntax: `%{field: type(), optional(field) => type()}`
5. All functions take `(map(), keyword())` signature for consistency

**Issues Fixed**:
- $ref navigation needed full spec structure, not just components
- Parameter name nil guard added
- Made `openapi_type_to_elixir/2` public for testing

**Next**: Task 2 - Update Binance Spot Generator (Proof of Concept)

### Session 3: 2025-10-07

**Completed**: Task 2 - Update Binance Spot Generator (Proof of Concept)

**Time**: ~1.5 hours

**Changes Made**:
1. Updated `lib/mix/tasks/zen_cex.generate_endpoints.ex`:
   - Added `alias Mix.Tasks.Helpers.TypeGenerator` (line 23)
   - Updated `map_to_endpoint_format/1` to extract components and generate types (lines 118-150)
   - Updated `format_endpoint/1` to include type fields in output (lines 297-316)

2. Generated 340 Binance Spot endpoints with full type annotations
3. Verified compilation (successful, no errors)
4. File size: 7,026 lines

**Type Coverage Examples**:
- ✅ Primitive types: `integer()`, `String.t()`, `float()`, `boolean()`
- ✅ Enums: `:true | :false`, `:buy | :sell`
- ✅ Arrays: `list(%{asset: String.t(), free: String.t(), locked: String.t()})`
- ✅ Nested objects: Multi-level object nesting with required/optional fields
- ✅ Optional fields: `%{optional(key) => type()}`
- ✅ Complex nested arrays: Arrays of objects containing arrays

**Key Findings**:
1. TypeGenerator handles 100% of endpoints successfully
2. Approximately 95% have detailed type information, 5% fall back to `term()` for complex schemas
3. All type conversions working correctly:
   - CamelCase → snake_case for field names (recvWindow → recv_window)
   - $ref resolution navigating component schemas
   - Deep nesting support (objects in arrays in objects)
4. No compilation errors introduced
5. Generated specs follow pattern: `@spec operation(map(), keyword()) :: {:ok, type()} | {:error, term()}`

**Issues/Notes**:
- As expected, oneOf/anyOf/allOf schemas fall back to `term()` (Phase 2 feature)
- Some endpoints have very long type strings (e.g., get_account has 15+ fields)
- Type strings are human-readable and match OpenAPI schemas accurately

**Next**: Task 3 - Test & Verify Binance Spot Types with Dialyzer

### Session 4: 2025-10-27

**Completed**: Task 3 - Test & Verify Binance Spot Types

**Time**: ~1 hour

**Changes Made**:
1. Fixed test in `test/mix/tasks/helpers/type_generator_test.exs`:
   - Updated optional field syntax expectation: `optional(order_id)` → `optional(:order_id)`
   - All 38 tests now passing ✅

2. Discovered EndpointRegistry integration already complete:
   - `lib/zen_cex/core/endpoint_registry.ex` already extracts spec strings
   - Already generates @spec AST for both arity-1 and arity-2 functions
   - Smart fallback to `term()` on parse errors
   - This work was completed ahead of schedule!

**Dialyzer Results**:
- ✅ **Zero typespec-related errors**
- 16 pre-existing errors in other modules (not related to our work):
  - Pattern matching warnings in examples
  - Unused functions
  - Test utility functions (ExUnit)
- No errors in:
  - `type_generator.ex`
  - `generated_endpoints.ex`
  - `endpoint_registry.ex`
  - Generator tasks

**Success Metrics**:
```
Total endpoints: 340
Endpoints with @spec: 340 (100%)
Endpoints with detailed types: 329
Endpoints with term() fallback: 11
Type coverage: 96.8%

Complex types verified:
✅ Nested objects in arrays
✅ Enum types (unions)
✅ Optional fields
```

**Verification Criteria Results**:
- [x] Dialyzer runs without errors on Spot module - **PASS (0 errors)**
- [x] At least 80% of endpoints have working specs - **EXCEED (96.8%)**
- [x] Complex types (arrays, nested objects) work - **PASS**
- [x] Manual testing in IEx confirms types - **PASS**
- [x] No type-related compilation warnings - **PASS**

**Key Achievements**:
1. **Exceeded expectations**: 96.8% type coverage vs 80% target
2. **Zero new errors**: Type generation doesn't introduce any issues
3. **All complex types working**: Nested structures, enums, optional fields
4. **Ahead of schedule**: EndpointRegistry integration already complete

**Next**: Task 4 - Update Binance Futures Generator

---

_Last updated: 2025-10-27_
