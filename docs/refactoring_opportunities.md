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

*To be completed - analyzing all `**/rate_limiter.ex` files and `base_rate_limiter.ex`*

---

### Task 3: Authentication and Signing Patterns

*To be completed - analyzing all `**/auth.ex`, `**/signer.ex`, `common_signer.ex`, `base_auth.ex`*

---

### Task 4: Parser Implementations

*To be completed - analyzing all `**/parser.ex` files, `base_parser.ex`, `parser_macros.ex`, `response_parser.ex`*

---

### Task 5: Parameter Builders

*To be completed - analyzing all `**/parameter_builder.ex` files, `base_parameter_builder.ex`*

---

### Task 6: Request Helpers

*To be completed - analyzing all `**/request_helper.ex` files, `base_request_helper.ex`*

---

### Task 7: Binance Adapter Structure

*To be completed - analyzing `lib/zen_cex/adapters/binance/` (excluding generated files)*

---

### Task 8: Bybit Adapter Structure

*To be completed - analyzing `lib/zen_cex/adapters/bybit/` (excluding generated files)*

---

### Task 9: Generated vs Handwritten Code

*To be completed - analyzing all `generated_*.ex` files vs non-generated counterparts*

---

### Task 10: WebSocket Adapters

*To be completed - analyzing WebSocket adapter implementations and connection management*

---

### Task 11: Market Data and Caching

*To be completed - analyzing cache usage patterns and ETS table management*

---

### Task 12: Order Safety Components

*To be completed - analyzing all files in `lib/zen_cex/safety/order_safety/`*

---

### Task 13: Clock Sync and Circuit Breaker

*To be completed - analyzing `safety/clock_sync.ex`, `core/circuit_breaker.ex`*

---

### Task 14: Configuration Management

*To be completed - analyzing `config.ex`, `config/time_constants.ex`, `application.ex`*

---

### Task 15: Telemetry and Debug Systems

*To be completed - analyzing telemetry and debug infrastructure*

---

### Task 16: Test Utilities and Helpers

*To be completed - analyzing test helper duplication and fixture patterns*

---

### Task 17: Integration Test Patterns

*To be completed - analyzing integration test structure across adapters*

---

### Task 18: Behavior Definitions

*To be completed - analyzing all files in `lib/zen_cex/behaviors/`*

---

### Task 19: Endpoint Registry Pattern

*To be completed - analyzing endpoint definition and discovery mechanisms*

---

### Task 20: Analysis Modules

*To be completed - analyzing business logic organization and calculation patterns*

---

### Task 21: Cross-Module Dependency Analysis

*To be completed - analyzing module dependencies using `mix xref`*

---

### Task 22: Performance and Complexity Metrics

*To be completed - analyzing complex modules and performance bottlenecks*

---

### Task 23: Create Refactoring Priority Matrix

*To be completed - final synthesis and prioritization*

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