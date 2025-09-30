# Refactoring Opportunities

This document contains analysis findings from the systematic refactoring analysis defined in `docs/refactor_specs.md`. Each task section documents specific code issues discovered, with locations, impact assessment, and suggested fixes.

Issues may appear in multiple task sections - this duplication is intentional and reveals cross-cutting patterns. After 5-7 tasks are complete, the "Cross-Cutting Patterns" section will consolidate issues that span multiple modules.

---

## Task Findings

### Task 1: Core HTTP and Request Pipeline ✅

**Scope**: `lib/zen_cex/core/http.ex`, `lib/zen_cex/core/auth.ex`, `lib/zen_cex/core/registry.ex`

#### 1. Duplicated Error Handling Logic

**Issue**: Error handling logic is scattered across multiple layers with similar patterns

**Location**:
- `lib/zen_cex/core/http.ex:266-334` (handle_response_step, handle_client_error, handle_server_error)
- Parser modules in each adapter (parse_error functions)
- Individual endpoint implementations

**Impact**: Maintenance burden when error handling needs updates, inconsistent error responses across exchanges

**Current Philosophy**: Pass through raw exchange errors to preserve context

**Suggested Fix**:
- Remove unnecessary error wrapping/transformation layers
- Keep parser error functions for recognizing error types but return raw exchange response
- Simplify error handling to just categorization (for retry logic) without transformation
- Let users handle exchange-specific error details directly

**Effort**: Medium

#### 2. Magic Numbers in Timeout and Retry Configuration

**Issue**: Hardcoded timeout values and retry parameters scattered throughout

**Location**:
- `lib/zen_cex/core/http.ex:65-90` (multiple timeout constants)
- `lib/zen_cex/core/http.ex:462-464` (exponential backoff calculation)

**Impact**: Difficult to tune performance characteristics, no runtime configuration

**Suggested Fix**:
- Extract all timing constants to a configuration module
- Support runtime configuration through Application.get_env
- Create timeout profiles that can be selected per operation type

**Effort**: Low

#### 3. Registry Module Loading Pattern

**Issue**: Runtime module validation repeated in multiple places

**Location**:
- `lib/zen_cex/core/registry.ex:42-47` (ensure_module_loaded!)
- Similar patterns in endpoint registry and other dynamic module loading

**Impact**: Performance overhead on every request, duplicate validation logic

**Suggested Fix**:
- Cache validated modules in ETS after first load
- Create a module loader behavior that standardizes validation
- Move validation to application startup for known modules

**Effort**: Medium

#### 4. Telemetry Event Emission Duplication

**Issue**: Similar telemetry event patterns repeated across multiple steps

**Location**:
- `lib/zen_cex/core/http.ex:387-397` (telemetry_error_step)
- `lib/zen_cex/core/http.ex:422-445` (telemetry_response_step)
- `lib/zen_cex/core/http.ex:485-503` (emit_rate_limit_telemetry)

**Impact**: Inconsistent telemetry metadata, maintenance burden for telemetry changes

**Suggested Fix**:
- Create a telemetry helper module with standardized event builders
- Define telemetry event schemas for consistency
- Use macros to reduce boilerplate in telemetry emission

**Effort**: Low

#### 5. Request Step Composition Complexity

**Issue**: Complex step registration and ordering logic mixed with business logic

**Location**:
- `lib/zen_cex/core/http.ex:129-159` (step registration in base_request)

**Impact**: Difficult to understand request flow, hard to test individual steps

**Suggested Fix**:
- Create a RequestPipeline module that encapsulates step composition
- Define step interfaces more clearly with behaviors
- Allow declarative pipeline configuration

**Effort**: High

#### 6. Credential Resolution Logic Duplication

**Issue**: Similar credential lookup patterns across Core.Auth and adapter auth modules

**Location**:
- `lib/zen_cex/core/auth.ex:101-116` (get_api_key)
- `lib/zen_cex/core/auth.ex:150-164` (get_api_secret)
- `lib/zen_cex/core/auth.ex:382-404` (get_api_key_from_env, get_api_secret_from_env)

**Impact**: Duplicate logic for testnet/production credential resolution

**Suggested Fix**:
- Consolidate credential resolution into a single function with options
- Create a CredentialStore abstraction that can be swapped (env, file, vault)
- Reduce the number of helper functions for environment variable names

**Effort**: Medium

#### 7. Parser Module Discovery Pattern

**Issue**: Dynamic module construction and validation repeated

**Location**:
- `lib/zen_cex/core/http.ex:336-345` (get_parser_module)
- Similar patterns in registry for other module types

**Impact**: Runtime overhead, potential for module name mismatches

**Suggested Fix**:
- Pre-compute module mappings at compile time
- Use a protocol or behavior for parser discovery
- Cache discovered modules in persistent_term or ETS

**Effort**: Medium

#### 8. Rate Limit State Management

**Issue**: Rate limit state extraction and URL handling is convoluted

**Location**:
- `lib/zen_cex/core/http.ex:361-377` (update_rate_limit_step URL handling)
- `lib/zen_cex/core/http.ex:194-199` (weight and operation extraction)

**Impact**: Difficult to track rate limit state flow, potential for state inconsistencies

**Suggested Fix**:
- Create a RateLimitContext struct to encapsulate all rate limit data
- Standardize how request metadata is attached and retrieved
- Move URL resolution logic to a dedicated helper

**Effort**: Medium

#### 9. Circuit Breaker Integration

**Issue**: Optional circuit breaker attachment with runtime checks

**Location**:
- `lib/zen_cex/core/http.ex:505-512` (maybe_attach_circuit_breaker)

**Impact**: Runtime overhead for feature detection, unclear when circuit breaker is active

**Suggested Fix**:
- Make circuit breaker a compile-time configuration
- Use a null object pattern for disabled circuit breaker
- Move to a middleware pattern consistent with other steps

**Effort**: Low

#### 10. Debug Capture Integration

**Issue**: Debug capture checks scattered throughout error handling

**Location**:
- `lib/zen_cex/core/http.ex:302-304` (client error capture)
- `lib/zen_cex/core/http.ex:400-402` (exception capture)

**Impact**: Performance overhead when disabled, inconsistent capture points

**Suggested Fix**:
- Create a debug middleware step that can be conditionally added
- Centralize all debug capture logic in one place
- Use compile-time flags to completely remove debug code in production

**Effort**: Low

---

### Task 2: Rate Limiting Implementations

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 3: Authentication and Signing Patterns

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 4: Parser Implementations

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 5: Parameter Builders

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 6: Request Helpers ✅

**Scope**: `lib/zen_cex/adapters/binance/request_helper.ex`, `lib/zen_cex/adapters/bybit/request_helper.ex`, `lib/zen_cex/adapters/base_request_helper.ex`

#### 1. Inconsistent Base Module Usage Pattern

**Issue**: Bybit uses `use ZenCex.Adapters.BaseRequestHelper` while Binance does not, leading to inconsistent inheritance patterns

**Location**:
- `lib/zen_cex/adapters/bybit/request_helper.ex:39` (uses BaseRequestHelper)
- `lib/zen_cex/adapters/binance/request_helper.ex` (no inheritance, standalone implementation)
- `lib/zen_cex/adapters/base_request_helper.ex:1-180` (shared base implementation)

**Impact**: Code duplication between Binance and BaseRequestHelper, inconsistent maintenance burden, unclear which pattern to follow for new exchanges

**Suggested Fix**:
- Migrate Binance.RequestHelper to use BaseRequestHelper inheritance
- Override only exchange-specific logic (e.g., Spot API parameter handling)
- Document when to use inheritance vs standalone implementation

**Effort**: Medium

#### 2. Duplicate Request Execution Logic

**Issue**: Core request execution pattern duplicated between BaseRequestHelper and Binance.RequestHelper

**Location**:
- `lib/zen_cex/adapters/base_request_helper.ex:56-105` (execute_request implementation)
- `lib/zen_cex/adapters/binance/request_helper.ex:128-173` (nearly identical execute_request)
- Both handle: success status range checking, error logging, response mapping

**Impact**: Changes to request execution must be applied in multiple places, risk of divergence

**Suggested Fix**:
- Binance should inherit from BaseRequestHelper and only override if truly necessary
- Extract common patterns (status range checking, error handling) into shared helpers
- Use overridable callbacks for exchange-specific behavior

**Effort**: Low

#### 3. Duplicated Helper Functions Across Modules

**Issue**: Multiple helper functions repeated across both implementations

**Location**:
- `lib/zen_cex/adapters/binance/request_helper.ex:224-231` (normalize_to_keyword_list, maybe_add_option)
- `lib/zen_cex/adapters/base_request_helper.ex:155-169` (maybe_add_option, extract params functions)
- `lib/zen_cex/adapters/bybit/request_helper.ex` (implicit use via BaseRequestHelper)

**Impact**: Duplicate maintenance, potential for inconsistent behavior

**Suggested Fix**:
- Keep helper functions ONLY in BaseRequestHelper
- Remove duplicates from Binance.RequestHelper once it uses inheritance
- Consider moving to a shared Utils module if used beyond request helpers

**Effort**: Low

#### 4. Inconsistent Parameter Building Approaches

**Issue**: Three different approaches to parameter building across the codebase

**Location**:
- `lib/zen_cex/adapters/binance/request_helper.ex:82-88` (API-type-specific with case statement)
- `lib/zen_cex/adapters/binance/request_helper.ex:184-209` (Spot and Margin-specific functions)
- `lib/zen_cex/adapters/bybit/request_helper.ex:186-202` (method-based with simple logic)
- `lib/zen_cex/adapters/base_request_helper.ex:133-169` (method-based default implementation)

**Impact**: Difficult to understand which pattern applies when, maintenance complexity for parameter logic changes

**Suggested Fix**:
- Standardize on method-based approach as the default (GET → params, POST → json)
- Override with exchange-specific logic ONLY when necessary (e.g., Binance Spot all-in-query-string)
- Document the parameter building decision tree clearly
- Consider a ParameterRouter abstraction if complexity grows

**Effort**: Medium

#### 5. Magic Numbers in Retry Configuration

**Issue**: Hardcoded retry constants scattered in Bybit implementation

**Location**:
- `lib/zen_cex/adapters/bybit/request_helper.ex:46` (@backoff_multiplier_ms 1000)
- `lib/zen_cex/adapters/bybit/request_helper.ex:118` (max_retries: 3)
- `lib/zen_cex/adapters/bybit/request_helper.ex:119` (retry_delay calculation with 1000)
- `lib/zen_cex/adapters/base_request_helper.ex:36` (@default_timeout 30_000)

**Impact**: Cannot tune retry behavior without code changes, magic numbers reduce readability

**Suggested Fix**:
- Extract retry constants to module attributes with descriptive names
- Move to configuration module for runtime tuning
- Create retry profiles (aggressive, standard, conservative) that can be selected

**Effort**: Low

#### 6. Complex Retry Configuration Builder

**Issue**: Retry configuration logic in Bybit is complex with multiple nested conditions

**Location**:
- `lib/zen_cex/adapters/bybit/request_helper.ex:128-176` (build_retry_config and helper functions)

**Impact**: Difficult to test all retry scenarios, hard to understand retry behavior at a glance

**Suggested Fix**:
- Extract retry strategies to separate modules/functions with clear names
- Use pattern matching on structured retry policies instead of nested conds
- Consider a RetryPolicy behavior that exchanges can implement
- Document retry behavior clearly in module docs

**Effort**: Medium

#### 7. Inconsistent Error Response Handling

**Issue**: Different error response patterns between implementations

**Location**:
- `lib/zen_cex/adapters/binance/request_helper.ex:165-172` (returns {:error, %Req.Response{}} or {:error, exception})
- `lib/zen_cex/adapters/base_request_helper.ex:96-104` (returns {:error, {:http_error, status, body}} or {:error, exception})
- Different tuple structures for HTTP errors

**Impact**: Calling code must handle different error formats depending on which helper is used

**Suggested Fix**:
- Standardize on ONE error response format across all request helpers
- Document the canonical error format in BaseRequestHelper
- Ensure Binance conforms to the same pattern
- Consider creating an ErrorResponse struct for consistency

**Effort**: Low

#### 8. Operation Type Determination Duplication

**Issue**: Operation type logic repeated with similar patterns

**Location**:
- `lib/zen_cex/adapters/binance/request_helper.ex:214-221` (determine_spot_operation_type)
- `lib/zen_cex/adapters/bybit/request_helper.ex:213-232` (determine_operation_type)
- Both map operations to :trading, :standard, :market, :health categories

**Impact**: Changes to operation categorization require updates in multiple places

**Suggested Fix**:
- Define operation type mapping in BaseRequestHelper with sensible defaults
- Allow exchanges to override with custom mappings via callbacks
- Use a consistent set of operation type atoms across all exchanges
- Consider creating an OperationTypeResolver behavior

**Effort**: Medium

#### 9. Inconsistent Function Visibility and Documentation

**Issue**: Some helpers are public when they should be private, inconsistent @doc coverage

**Location**:
- `lib/zen_cex/adapters/binance/request_helper.ex:214-221` (determine_spot_operation_type is public but internal)
- `lib/zen_cex/adapters/binance/request_helper.ex:184-209` (build_*_request_params public but internal)
- `lib/zen_cex/adapters/bybit/request_helper.ex:245-258` (build_url public but seems internal)

**Impact**: Exposes internal implementation details, increases API surface area, harder to refactor

**Suggested Fix**:
- Make helper functions private unless they're genuinely part of the public API
- Add @doc false to functions that must be public but are internal
- Complete @doc coverage for all truly public functions
- Define clear boundaries between public API and internal helpers

**Effort**: Low

#### 10. Backward Compatibility Delegates in Bybit

**Issue**: Delegation functions for backward compatibility clutter the API

**Location**:
- `lib/zen_cex/adapters/bybit/request_helper.ex:48-51` (defdelegate current_env, base_url)

**Impact**: Unclear where functionality lives, potential for circular dependencies, API bloat

**Suggested Fix**:
- Remove delegates if they're not actually used externally
- If needed, document why they exist with TODO comments for removal
- Consider deprecating and removing in next major version
- Direct callers to use Endpoints module instead

**Effort**: Low

#### 11. URL Building Logic Should Be Centralized

**Issue**: URL construction scattered across multiple functions

**Location**:
- `lib/zen_cex/adapters/bybit/request_helper.ex:245-258` (build_url function)
- `lib/zen_cex/adapters/binance/request_helper.ex:70-75` (inline base_url construction)
- Both duplicate environment detection and URL assembly logic

**Impact**: Changes to URL structure require updates in multiple places

**Suggested Fix**:
- URL construction should live ONLY in Endpoints modules
- Request helpers should call Endpoints.base_url() without reimplementing logic
- Remove build_url from Bybit.RequestHelper (use Endpoints directly)
- BaseRequestHelper should expect base_url as a parameter, not construct it

**Effort**: Low

#### 12. Auth Parameter Extraction Logic

**Issue**: Hardcoded auth parameter list used for splitting params vs body

**Location**:
- `lib/zen_cex/adapters/binance/request_helper.ex:176` (@auth_params ["timestamp", "recvWindow", "signature"])
- `lib/zen_cex/adapters/binance/request_helper.ex:205-207` (splitting logic in build_margin_request_params)

**Impact**: Fragile if auth parameters change, knowledge duplication with Auth module

**Suggested Fix**:
- Define auth parameter list in Auth module (single source of truth)
- Request helper should query Auth module for parameter names
- Consider whether this splitting logic belongs in RequestHelper at all
- Document why Margin API requires this split (preserve knowledge)

**Effort**: Low

---

### Task 7: Binance Adapter Structure

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 8: Bybit Adapter Structure

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 9: Generated vs Handwritten Code

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 10: WebSocket Adapters

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 11: Market Data and Caching

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 12: Order Safety Components ✅

**Scope**: `lib/zen_cex/safety/order_safety/cache.ex`, `lib/zen_cex/safety/order_safety/decimal_utils.ex`, `lib/zen_cex/safety/order_safety/market_data.ex`, `lib/zen_cex/safety/order_safety/validation.ex`, `lib/zen_cex/safety/order_safety/config.ex`

#### 1. Duplicated Asset Extraction Heuristics

**Issue**: Asset extraction logic repeated with inconsistent approaches across modules

**Location**:
- `lib/zen_cex/safety/order_safety/validation.ex:398-406` (extract_quote_asset_heuristic)
- `lib/zen_cex/safety/order_safety/validation.ex:408-411` (extract_base_asset - uses heuristic)
- `lib/zen_cex/safety/order_safety/validation.ex:414-447` (extract_assets_from_symbol_info - exchange-specific)
- Similar logic likely exists in other modules for parsing symbol pairs

**Impact**: Changes to asset extraction require updates in multiple places, inconsistent behavior across symbol parsing

**Suggested Fix**:
- Create a dedicated SymbolParser module with canonical implementations
- Support both heuristic (fallback) and API-based (authoritative) extraction
- Cache symbol → {base, quote} mappings to avoid repeated parsing
- Use symbol info from exchange when available, heuristic only as fallback
- Single source of truth for common quote assets list

**Effort**: Medium

#### 2. Safe ETS Operations Pattern Duplication

**Issue**: Identical safe ETS wrapper pattern repeated across multiple functions

**Location**:
- `lib/zen_cex/safety/order_safety/cache.ex:272-303` (safe_ets_lookup, safe_ets_insert, safe_ets_delete, safe_ets_select_delete)
- Each function has same rescue ArgumentError pattern
- All return safe defaults ([], false, 0) when table doesn't exist

**Impact**: Maintenance burden if error handling changes, code duplication

**Suggested Fix**:
- Create a SafeETS utility module with generic wrappers
- Use macros to define safe wrappers with consistent behavior
- Consider moving to shared ZenCex.Core.ETS module since pattern appears elsewhere
- Document when to use safe vs unsafe ETS operations

**Effort**: Low

#### 3. Inconsistent Balance Field Access Patterns

**Issue**: Multiple exchange formats handled with cascading pattern matches

**Location**:
- `lib/zen_cex/safety/order_safety/decimal_utils.ex:89-106` (extract_available_balance with 4 different field names)
- `lib/zen_cex/safety/order_safety/market_data.ex:646-655` (normalize_spot_balances)
- `lib/zen_cex/safety/order_safety/market_data.ex:674-684` (normalize_margin_balances)
- `lib/zen_cex/safety/order_safety/market_data.ex:704-713` (normalize_futures_balances)
- `lib/zen_cex/safety/order_safety/market_data.ex:783-793` (normalize_bybit_balances)

**Impact**: Adding new exchanges requires updates in multiple places, fragile to API changes

**Suggested Fix**:
- Create exchange-specific balance normalizer behaviors/protocols
- Each exchange adapter provides its own balance normalizer implementation
- DecimalUtils should accept pre-normalized balance format
- Consolidate normalization logic in adapter modules, not in OrderSafety
- Define canonical internal balance structure as a struct

**Effort**: Medium

#### 4. Redundant Decimal Parsing Functions

**Issue**: Two nearly identical decimal parsing functions with overlapping responsibility

**Location**:
- `lib/zen_cex/safety/order_safety/decimal_utils.ex:10-45` (parse_decimal - returns Decimal, falls back to zero)
- `lib/zen_cex/safety/order_safety/decimal_utils.ex:51-83` (safe_parse_decimal - returns {:ok, Decimal} | {:error, reason})
- Similar special value handling in both (Infinity, NaN, empty string)
- Duplicate validation logic for partial parse detection

**Impact**: Duplicate maintenance, confusion about which function to use when

**Suggested Fix**:
- Keep only safe_parse_decimal/1 as the authoritative implementation
- Implement parse_decimal/1 as a wrapper: `safe_parse_decimal(val) |> Result.unwrap_or(Decimal.new("0"))`
- Document clearly: safe_parse for validation, parse for permissive contexts
- Consider renaming: parse_decimal! (raises) and parse_decimal (returns Decimal)

**Effort**: Low

#### 5. Duplicate Price Fetching Logic

**Issue**: Price fetching with WebSocket fallback pattern duplicated

**Location**:
- `lib/zen_cex/safety/order_safety/market_data.ex:83-114` (fetch_current_price)
- `lib/zen_cex/safety/order_safety/market_data.ex:117-145` (fetch_price_from_websocket helper)
- `lib/zen_cex/safety/order_safety/market_data.ex:148-161` (fetch_and_cache_rest_price helper)
- Similar pattern for orderbook: lines 220-306

**Impact**: Changes to fallback strategy require updates in multiple places

**Suggested Fix**:
- Extract fallback pattern to generic function: `with_websocket_fallback(fetch_ws_fn, fetch_rest_fn, cache_key)`
- Parameterize freshness threshold and cache TTL
- Reuse pattern for both price and orderbook fetching
- Consider making this a general DataSource behavior

**Effort**: Medium

#### 6. Exchange-Specific Module Coupling

**Issue**: MarketData module directly depends on all exchange adapter modules

**Location**:
- `lib/zen_cex/safety/order_safety/market_data.ex:9-16` (imports for Binance adapters)
- `lib/zen_cex/safety/order_safety/market_data.ex:500-602` (fetch_symbol_info_from_exchange with hardcoded module calls)
- `lib/zen_cex/safety/order_safety/market_data.ex:554-598` (fetch_price_from_exchange with exchange-specific logic)
- `lib/zen_cex/safety/order_safety/market_data.ex:604-794` (fetch_balances with account-type switching)

**Impact**: Adding new exchanges requires modifying MarketData module, tight coupling, difficult to test

**Suggested Fix**:
- Use Core.Registry to look up exchange adapters dynamically
- Define MarketDataProvider behavior that exchanges implement
- Remove direct module references, use dynamic module resolution
- MarketData becomes a coordinator, not implementation
- Each exchange adapter provides its own MarketDataProvider implementation

**Effort**: High

#### 7. Hardcoded Account Type → API Module Mapping

**Issue**: Binance account type routing uses explicit case statements

**Location**:
- `lib/zen_cex/safety/order_safety/market_data.ex:604-627` (fetch_binance_balances case statement)
- Maps :spot → Spot, :margin → Margin, :usdm_futures → UsdmFutures, etc.
- Similar pattern for determining WebSocket connection type at lines 357-406

**Impact**: Adding new account types requires code changes, not data-driven

**Suggested Fix**:
- Define account_type → module mapping in Binance adapter configuration
- Use dynamic module lookup: `account_module = get_account_module(:binance, account_type)`
- Move account type knowledge to exchange adapter where it belongs
- MarketData shouldn't need to know Binance's internal account structure

**Effort**: Medium

#### 8. Credential Validation Complexity

**Issue**: Complex credential validation with suspicious pattern detection

**Location**:
- `lib/zen_cex/safety/order_safety/market_data.ex:447-498` (validate_auth_credentials and helpers)
- Whitelist approach with allowed_keys check
- Regex pattern matching for "suspicious" content (password, token, bearer, oauth)
- Validation duplicated before every balance fetch

**Impact**: Overly defensive validation adds complexity, unclear security benefit, performance overhead

**Suggested Fix**:
- Move credential validation to Core.Auth module (single responsibility)
- Validation should happen at credential configuration time, not per-request
- Question whether suspicious pattern check provides real security value
- If keeping validation, make it a compile-time check or startup validation
- Consider removing entirely if Core.Auth already validates credentials

**Effort**: Low

#### 9. Duplicate WebSocket Connection Management

**Issue**: WebSocket connection logic repeated for each exchange

**Location**:
- `lib/zen_cex/safety/order_safety/market_data.ex:322-352` (ensure_websocket_connection with registry lookup)
- `lib/zen_cex/safety/order_safety/market_data.ex:356-407` (reconnect helpers per exchange)
- `lib/zen_cex/safety/order_safety/market_data.ex:369-406` (ensure_binance_connection, ensure_bybit_connection)
- Nearly identical pattern with different stream format and topics

**Impact**: Adding exchanges requires duplicating connection logic, inconsistent error handling

**Suggested Fix**:
- Create WebSocketConnectionManager behavior that exchanges implement
- Move exchange-specific stream formatting to adapter modules
- MarketData.ensure_websocket_connection/2 should delegate to adapter
- Consolidate connection registry interaction in one place
- Define standard connection interface: `Adapter.WebSocket.ensure_connection(symbol)`

**Effort**: Medium

#### 10. Configuration Value Extraction Pattern Duplication

**Issue**: Similar environment variable + application config pattern repeated

**Location**:
- `lib/zen_cex/safety/order_safety/config.ex:67-79` (max_price_deviation_percent)
- `lib/zen_cex/safety/order_safety/config.ex:101-120` (max_price_deviation_percent/1)
- `lib/zen_cex/safety/order_safety/config.ex:133-146` (idempotency_window_ms)
- `lib/zen_cex/safety/order_safety/config.ex:159-172` (cleanup_interval_ms)
- `lib/zen_cex/safety/order_safety/config.ex:198-211` (websocket_data_max_age_ms)
- `lib/zen_cex/safety/order_safety/config.ex:227-245` (default_min_notional)

**Impact**: Every config value requires 10-15 lines of boilerplate, difficult to add new config

**Suggested Fix**:
- Create a generic get_config/3 helper: `get_config(key, default, opts)`
- Support both global and exchange-specific lookups in one function
- Use NimbleOptions or similar for schema-based configuration
- Example: `get_config(:max_price_deviation, 20, exchange: :binance)`
- Reduces each config function to 1-2 lines

**Effort**: Low

#### 11. Cache Key Pattern Duplication

**Issue**: Cache key construction `{cache_type, {exchange, symbol}}` repeated

**Location**:
- `lib/zen_cex/safety/order_safety/cache.ex:30-35` (lookup with cache key construction)
- `lib/zen_cex/safety/order_safety/cache.ex:73-76` (put with cache key construction)
- `lib/zen_cex/safety/order_safety/cache.ex:131-155` (invalidate functions with key construction)
- Pattern repeated 8+ times across the module

**Impact**: Changes to key structure require updates in multiple places

**Suggested Fix**:
- Create private cache_key/2 and cache_key/3 helper functions
- All cache operations use helper: `cache_key(:price, exchange, symbol)`
- Encapsulates key format in one place
- Makes future key structure changes easier (e.g., adding version)

**Effort**: Low

#### 12. Telemetry Event Emission Pattern Duplication

**Issue**: Similar telemetry emission pattern repeated for cache events

**Location**:
- `lib/zen_cex/safety/order_safety/cache.ex:39-43` (cache hit event)
- `lib/zen_cex/safety/order_safety/cache.ex:48-52` (cache expired event)
- `lib/zen_cex/safety/order_safety/cache.ex:59-63` (cache miss event)
- `lib/zen_cex/safety/order_safety/validation.ex:151-155` (notional calc failed event)
- Each has same structure: [:zen_cex, :order_safety, ...], %{count: 1}, metadata

**Impact**: Inconsistent metadata, difficult to update telemetry structure

**Suggested Fix**:
- Create emit_cache_event/3 helper: `emit_cache_event(event_type, cache_type, key)`
- Standardize metadata structure in one place
- Consider using macros for telemetry emission consistency
- Extract to shared Telemetry.OrderSafety module if pattern grows

**Effort**: Low

#### 13. Inconsistent Error Return Formats

**Issue**: Mix of :ok, {:error, atom}, and {:error, {atom, details}} across validation

**Location**:
- `lib/zen_cex/safety/order_safety/validation.ex:32-38` (validate_order returns :ok | {:error, term})
- `lib/zen_cex/safety/order_safety/validation.ex:84-120` (calculate_required_quote_amount returns {:ok, Decimal} | {:error, {:price_required_for_market_order, details}})
- `lib/zen_cex/safety/order_safety/validation.ex:132-171` (calculate_order_notional returns {:ok, Decimal} | {:error, {:price_unavailable, details}})
- `lib/zen_cex/safety/order_safety/validation.ex:185` ({:error, {:missing_required_fields, fields}})
- Some errors are just atoms, others are tuples with maps

**Impact**: Callers must handle multiple error formats, inconsistent error handling patterns

**Suggested Fix**:
- Standardize on {:error, {error_type, details_map}} for all validation errors
- Define error types as module constants or a dedicated ErrorTypes module
- Provide error_message/1 helper to extract human-readable messages
- Document canonical error format in module docs
- Consider using error structs for richer error information

**Effort**: Medium

#### 14. Notional Calculation Duplication

**Issue**: Similar notional calculation logic in two places

**Location**:
- `lib/zen_cex/safety/order_safety/validation.ex:84-120` (calculate_required_quote_amount)
- `lib/zen_cex/safety/order_safety/validation.ex:132-171` (calculate_order_notional)
- Both handle market orders by fetching current price
- Both multiply price * quantity
- Different error messages but same logic

**Impact**: Changes to calculation logic require dual updates

**Suggested Fix**:
- Implement calculate_required_quote_amount/1 in terms of calculate_order_notional/1
- Single implementation of price * quantity logic
- calculate_required_quote_amount becomes a semantic wrapper
- Reduces duplication while keeping intent clear

**Effort**: Low

#### 15. Validation Step Composition Pattern

**Issue**: Multiple validation steps chained with `with` could be more declarative

**Location**:
- `lib/zen_cex/safety/order_safety/validation.ex:32-38` (validate_order with clause)
- `lib/zen_cex/safety/order_safety/validation.ex:347-364` (validate_buy_balance with clause)
- Each validation function called explicitly in order
- Implicit ordering dependency

**Impact**: Difficult to reorder validations, hard to make validation pipeline configurable

**Suggested Fix**:
- Create a ValidationPipeline abstraction
- Define validations as a list of {validator_fn, opts} tuples
- Allow runtime composition of validation steps
- Make validation ordering explicit and configurable
- Example: `run_validations(order, [required_fields, symbol_exists, order_size, price_levels])`

**Effort**: Medium

#### 16. Magic Numbers for Cache Statistics

**Issue**: Hardcoded statistical calculations with assumptions

**Location**:
- `lib/zen_cex/safety/order_safety/cache.ex:256-257` (avg_age calculation assumes length > 0)
- `lib/zen_cex/safety/order_safety/cache.ex:263` (similar check for oldest_ms)
- Inline mathematical operations without explanation

**Impact**: Unclear intent, potential for division by zero (prevented by check)

**Suggested Fix**:
- Extract statistical calculations to helper functions: `calculate_avg_age/1`, `find_oldest/1`
- Use Enum functions more idiomatically (Enum.sum/1, Enum.max/1 with defaults)
- Add @doc explaining what statistics are calculated
- Consider returning nil instead of 0 for empty collections

**Effort**: Low

#### 17. Multiple Responsibilities in MarketData Module

**Issue**: MarketData module handles too many concerns: caching, fetching, WebSocket management, balance normalization

**Location**:
- Lines 1-830 span symbol info, prices, balances, orderbook, WebSocket connections, credential validation
- Each concern has 50-200 lines of code
- Module is 830 lines (exceeds recommended max ~400)

**Impact**: Difficult to understand, test, and maintain. Changes cascade across unrelated functionality

**Suggested Fix**:
- Split into focused modules:
  - MarketData.SymbolInfo (symbol info fetching + caching)
  - MarketData.Pricing (price + orderbook data)
  - MarketData.Balances (balance fetching + normalization)
  - MarketData.WebSocket (connection management)
- Main MarketData module becomes facade/coordinator
- Each submodule has clear, single responsibility
- Easier to test and modify in isolation

**Effort**: High

#### 18. Missing Minimum Notional Validation Configuration

**Issue**: Hardcoded minimum notional defaults without clear rationale

**Location**:
- `lib/zen_cex/safety/order_safety/market_data.ex:28` (@binance_default_min_notional from Config)
- `lib/zen_cex/safety/order_safety/config.ex:248-252` (fallback values: Binance $10, Bybit $1, Kraken $10)
- `lib/zen_cex/safety/order_safety/market_data.ex:796-825` (extract_min_notional with hardcoded Bybit value of $1)

**Impact**: Arbitrary defaults may not match current exchange minimums, could cause order rejections

**Suggested Fix**:
- Document the source of default values (exchange docs as of date)
- Add TODO comments to check defaults periodically
- Consider fetching actual minimums from exchange APIs at startup
- Make defaults configurable per symbol category (spot vs futures)
- Log warnings when using fallback defaults instead of API values

**Effort**: Low

---

### Task 13: Clock Sync and Circuit Breaker

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 14: Configuration Management ✅

**Scope**: `lib/zen_cex/config.ex`, `lib/zen_cex/config/time_constants.ex`, `lib/zen_cex/application.ex`

#### 1. Repeated Testnet Detection Pattern

**Issue**: Duplicate testnet detection logic across exchange functions

**Location**:
- `lib/zen_cex/config.ex:46-56` (testnet?/1 - three nearly identical functions)
- `lib/zen_cex/config.ex:90-109` (base_url/1 - repeated testnet checks)
- `lib/zen_cex/config.ex:127-167` (credentials/1 - repeated testnet checks)

**Impact**: Changes to testnet detection logic require updates in multiple places, violates DRY

**Suggested Fix**:
- Create a generic `get_env_var/2` helper that constructs exchange-specific env var names
- Single testnet detection pattern: `System.get_env("#{String.upcase(exchange)}_TESTNET") == "true"`
- Reduce three separate functions to one with pattern matching or use a macro
- Example: `def testnet?(exchange), do: System.get_env(env_var_name(exchange, "TESTNET")) == "true"`

**Effort**: Low

#### 2. Hardcoded Exchange-Specific Environment Variable Names

**Issue**: Environment variable naming patterns scattered and duplicated

**Location**:
- `lib/zen_cex/config.ex:130-131` (BINANCE_TESTNET_API_KEY, BINANCE_TESTNET_API_SECRET)
- `lib/zen_cex/config.ex:135-136` (BINANCE_API_KEY, BINANCE_API_SECRET)
- `lib/zen_cex/config.ex:143-151` (KRAKEN patterns)
- `lib/zen_cex/config.ex:158-165` (DERIBIT patterns - different naming: CLIENT_ID/CLIENT_SECRET)

**Impact**: Inconsistent credential naming across exchanges (api_key vs client_id), difficult to add new exchanges

**Suggested Fix**:
- Create a credential configuration map at module level that defines naming patterns per exchange
- Example: `@credential_patterns %{binance: {"API_KEY", "API_SECRET"}, deribit: {"CLIENT_ID", "CLIENT_SECRET"}}`
- Single function to build env var names: `build_env_var_name(exchange, credential_type, testnet?)`
- Makes adding new exchanges just a matter of adding to the configuration map

**Effort**: Low

#### 3. Duplicated Testnet/Production Branching Logic

**Issue**: Repeated if/else pattern for testnet vs production in every function

**Location**:
- `lib/zen_cex/config.ex:90-96` (base_url - testnet branch)
- `lib/zen_cex/config.ex:103-109` (base_url - testnet branch)
- `lib/zen_cex/config.ex:128-138` (credentials - testnet branch)
- `lib/zen_cex/config.ex:141-152` (credentials - testnet branch)
- `lib/zen_cex/config.ex:155-166` (credentials - testnet branch)

**Impact**: Same branching logic repeated 8+ times, makes code verbose and hard to maintain

**Suggested Fix**:
- Create a higher-order function: `select_by_env(exchange, testnet_value, prod_value)`
- Or use a generic config lookup: `get_config(exchange, config_type, testnet?)`
- Centralize the testnet/production selection logic in one place
- Example: `def credentials(exchange), do: get_config(exchange, :credentials, testnet?(exchange))`

**Effort**: Low

#### 4. Missing Exchange Configuration (Bybit)

**Issue**: Bybit is not included in the configuration module despite being implemented in the codebase

**Location**:
- `lib/zen_cex/config.ex:28` (type spec only lists :binance, :kraken, :deribit)
- No base_url/1 clause for :bybit
- No credentials/1 clause for :bybit
- Bybit adapter exists at `lib/zen_cex/adapters/bybit/`

**Impact**: Inconsistent configuration coverage, Bybit must handle its own config elsewhere (duplication)

**Suggested Fix**:
- Add :bybit to @type exchange
- Implement testnet?(:bybit), base_url(:bybit), credentials(:bybit)
- Verify Bybit testnet environment variables are documented
- Check if Bybit currently has duplicate config logic in its adapter

**Effort**: Low

#### 5. Hardcoded URL Strings Without Constants

**Issue**: Base URLs hardcoded as string literals throughout the module

**Location**:
- `lib/zen_cex/config.ex:92-95` ("https://testnet.binance.vision", "https://api.binance.com")
- `lib/zen_cex/config.ex:100` ("https://api.kraken.com")
- `lib/zen_cex/config.ex:105-108` ("https://test.deribit.com", "https://www.deribit.com")

**Impact**: Magic strings reduce readability, no single source of truth for endpoints

**Suggested Fix**:
- Extract URLs to module attributes at the top of the file
- Example: `@binance_testnet_url "https://testnet.binance.vision"`
- Group by exchange for clarity: `@binance_urls %{test: "...", prod: "..."}`
- Or move to a dedicated ExchangeUrls configuration module if list grows

**Effort**: Low

#### 6. Inconsistent Cache Clearing Implementation

**Issue**: Cache clearing only targets Binance-specific cache, incomplete implementation

**Location**:
- `lib/zen_cex/config.ex:202-210` (clear_cache/0)
- Only clears `{ZenCex.Adapters.Binance.Endpoints, :current_env}`
- No clearing for other exchanges (Kraken, Deribit, Bybit)
- Comment says "Clear Binance cached environment" but function name suggests global clearing

**Impact**: Misleading function name, incomplete cache management, testing gaps

**Suggested Fix**:
- Either rename to `clear_binance_cache/0` to match behavior
- Or implement proper multi-exchange cache clearing: iterate over all known exchanges
- Document what caches exist and why they need clearing
- Consider creating a CacheRegistry to track all caches that need clearing

**Effort**: Low

#### 7. Missing Configuration for Application-Level Settings

**Issue**: TimeConstants and Application modules contain config that should be unified

**Location**:
- `lib/zen_cex/config/time_constants.ex:80-111` (cache TTLs by environment)
- `lib/zen_cex/config/time_constants.ex:138-149` (rate limit windows)
- `lib/zen_cex/application.ex:43-46` (enable_debug_table configuration)
- No centralized place for all application configuration

**Impact**: Configuration scattered across multiple modules, hard to discover all settings

**Suggested Fix**:
- Create a unified Config.Application module or expand Config module
- Centralize: cache TTLs, timeouts, rate limit windows, feature flags
- Support runtime configuration via Application.get_env
- Document all configuration options in one place (or generate docs from config schema)

**Effort**: Medium

#### 8. Compile-Time Environment Detection in TimeConstants

**Issue**: Cache TTLs locked at compile time based on Mix.env()

**Location**:
- `lib/zen_cex/config/time_constants.ex:114` (@current_env Mix.env())
- `lib/zen_cex/config/time_constants.ex:115-120` (@cache_ttls set at compile time)

**Impact**: Cannot change cache TTLs without recompilation, limits runtime flexibility

**Suggested Fix**:
- Change cache_ttls/0 to runtime lookup: `cache_ttls_by_env()[Mix.env()]`
- Remove @current_env and @cache_ttls module attributes
- Make all timeout/TTL configurations runtime-configurable via Application env
- Provide sensible defaults but allow overrides

**Effort**: Low

#### 9. Magic Numbers Throughout TimeConstants

**Issue**: While TimeConstants addresses some magic numbers, many remain throughout the codebase

**Location**:
- `lib/zen_cex/config/time_constants.ex:87` (5 seconds for prices - hardcoded)
- `lib/zen_cex/config/time_constants.ex:89` (10 seconds for balances - hardcoded)
- `lib/zen_cex/config/time_constants.ex:143` (seconds(5) - duplicates 5 seconds value)
- Values defined but not consistently used across the codebase

**Impact**: TimeConstants module exists but isn't universally adopted, residual magic numbers remain

**Suggested Fix**:
- Audit entire codebase for timeout/delay literals
- Ensure ALL timeout values use TimeConstants functions
- Add missing constants to TimeConstants for values not yet defined
- Create a mix task or credo check to catch new magic number introductions

**Effort**: Medium

#### 10. Inconsistent Timeout Groupings

**Issue**: Timeout configurations spread across multiple functions with overlapping purposes

**Location**:
- `lib/zen_cex/config/time_constants.ex:156-170` (websocket_timeouts)
- `lib/zen_cex/config/time_constants.ex:196-210` (operation_timeouts)
- `lib/zen_cex/config/time_constants.ex:217-231` (retry_delays)
- Some timeouts could belong in multiple categories

**Impact**: Unclear where to find specific timeout values, potential for duplication

**Suggested Fix**:
- Reorganize timeouts by domain: network, trading, cache, websocket
- Create a single unified timeout map with nested structure
- Document the timeout taxonomy clearly
- Consider returning a single `all_timeouts/0` function with categorized map

**Effort**: Low

#### 11. No Validation of Configuration Values

**Issue**: Configuration values are returned as-is without validation

**Location**:
- `lib/zen_cex/config.ex:185-194` (validate_credentials only checks presence, not format)
- `lib/zen_cex/config/time_constants.ex` (no validation that values are positive integers)
- No validation that URLs are well-formed
- No validation that exchange atom is supported

**Impact**: Invalid configuration silently accepted, errors surface later during runtime

**Suggested Fix**:
- Add validate_base_url/1 to check URL format
- Add validate_exchange/1 to check supported exchanges
- Add validate_timeout/1 to ensure positive integers
- Create a Config.Validator module for comprehensive validation
- Validate configuration at application startup

**Effort**: Medium

#### 12. Application Supervision Strategy Could Be Clearer

**Issue**: Children list construction is imperative with conditional logic

**Location**:
- `lib/zen_cex/application.ex:13-47` (children list with conditional append)
- Comment about "Req-centric architecture" mixed with child list definition

**Impact**: Supervision tree structure not immediately obvious, architectural notes buried in code

**Suggested Fix**:
- Extract child spec building to separate functions: `base_children/0`, `optional_children/0`
- Create `build_supervision_tree/1` that composes children based on config
- Move architectural notes to module @moduledoc
- Consider using a more declarative supervision spec format

**Effort**: Low

#### 13. No Configuration Schema or Type Specs for Config Values

**Issue**: Configuration structure is implicit, no schema defines valid configurations

**Location**:
- All configuration modules lack formal schema definitions
- Return types are basic (String.t(), pos_integer()) without semantic meaning
- No way to validate entire configuration structure

**Impact**: Difficult to validate configuration is complete and correct, no auto-generated docs

**Suggested Fix**:
- Define configuration schema using typed structs or NimbleOptions
- Create Config.Schema module with all configuration definitions
- Add validate_config!/0 function that checks entire configuration
- Generate configuration documentation from schema
- Support config file loading (e.g., config.exs, runtime.exs integration)

**Effort**: High

#### 14. Missing Environment Variable Documentation

**Issue**: No centralized list of all required/optional environment variables

**Location**:
- Environment variables mentioned in @moduledoc but scattered
- `lib/zen_cex/config.ex:8-13` (only lists testnet flags)
- Credential variables not documented in Config module
- No documentation of BYBIT environment variables

**Impact**: Developers must read code to discover required configuration, poor DX

**Suggested Fix**:
- Create comprehensive environment variable documentation in Config @moduledoc
- List all variables with: name, purpose, required/optional, example value
- Generate this documentation from code if possible
- Add a `list_required_env_vars/1` function for runtime checking
- Consider creating a .env.example file for the project

**Effort**: Low

---

### Task 15: Telemetry and Debug Systems

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 16: Test Utilities and Helpers

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 17: Integration Test Patterns

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 18: Behavior Definitions

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 19: Endpoint Registry Pattern

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 20: Analysis Modules

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 21: Cross-Module Dependency Analysis

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 22: Performance and Complexity Metrics

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

### Task 23: Create Refactoring Priority Matrix

**Status**: Not yet analyzed. See `docs/refactor_specs.md` for task details and priority ranking.

---

## Cross-Cutting Patterns

*This section will be populated after Tasks 5-7 are complete to identify patterns that appear across multiple analysis areas.*

**Guidelines for consolidation**:
- Issues appearing in 3+ tasks should be documented here
- Include references back to specific task findings
- Provide unified fix strategy that addresses all instances
- Calculate total impact across all affected modules

**Expected patterns to track**:
- Magic numbers and configuration
- Error handling approaches
- ETS usage patterns
- Telemetry emission patterns
- Module discovery/loading patterns
- Test setup duplication
- Parameter validation logic

---

## Prioritized Recommendations

*This section will be populated incrementally as task findings accumulate, with final prioritization completed in Task 23.*

### Current High-Priority Items (from Task 1)

#### 🎯 Exceptional ROI (Priority > 2.0) - Do Immediately

1. **Magic Numbers to Configuration** [D:2/B:8 → Priority:4.00]
   - Extract timeout/retry constants to configuration module
   - Support runtime configuration
   - **Impact**: Low effort, high impact on maintainability

2. **Debug Capture Consolidation** [D:2/B:5 → Priority:2.50]
   - Centralize debug capture in middleware step
   - Use compile-time flags for production builds
   - **Impact**: Quick win for performance

3. **Telemetry Helper Module** [D:3/B:7 → Priority:2.33]
   - Create standardized event builders
   - Define consistent telemetry schemas
   - **Impact**: Improves observability consistency

#### 🚀 High ROI (Priority 1.5-2.0) - Do Soon

4. **Credential Resolution Consolidation** [D:4/B:6 → Priority:1.50]
   - Single function for all credential lookup
   - Create swappable CredentialStore abstraction
   - **Impact**: Reduces duplication, improves flexibility

5. **Error Handling Simplification** [D:5/B:7 → Priority:1.40]
   - Remove unnecessary error transformation layers
   - Pass through raw exchange errors
   - **Impact**: Better context preservation, less complexity

#### 📋 Good ROI (Priority 1.0-1.5) - Plan Carefully

6. **Registry Module Caching** [D:5/B:6 → Priority:1.20]
   - Cache validated modules in ETS
   - Move validation to startup for known modules
   - **Impact**: Performance improvement with moderate effort

7. **Parser Module Discovery Optimization** [D:5/B:6 → Priority:1.20]
   - Pre-compute module mappings at compile time
   - Cache in persistent_term
   - **Impact**: Reduces per-request overhead

8. **Rate Limit Context Struct** [D:5/B:6 → Priority:1.20]
   - Encapsulate rate limit data in struct
   - Standardize metadata attachment
   - **Impact**: Improves state flow clarity

---

## Implementation Roadmap

*This section will be populated in Task 23 to provide sequencing guidance and identify dependencies between refactoring opportunities.*