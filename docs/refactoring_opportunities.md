# Refactoring Opportunities Document

This document identifies and prioritizes refactoring opportunities discovered through systematic analysis of the zen_cex codebase. Each section corresponds to a specific analysis task from docs/refactor_specs.md.

## Request Pipeline Refactoring

### 1. Duplicated Error Handling Logic

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

### 2. Magic Numbers in Timeout and Retry Configuration

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

### 3. Registry Module Loading Pattern

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

### 4. Telemetry Event Emission Duplication

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

### 5. Request Step Composition Complexity

**Issue**: Complex step registration and ordering logic mixed with business logic
**Location**:
- `lib/zen_cex/core/http.ex:129-159` (step registration in base_request)

**Impact**: Difficult to understand request flow, hard to test individual steps
**Suggested Fix**:
- Create a RequestPipeline module that encapsulates step composition
- Define step interfaces more clearly with behaviors
- Allow declarative pipeline configuration

**Effort**: High

### 6. Credential Resolution Logic Duplication

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

### 7. Parser Module Discovery Pattern

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

### 8. Rate Limit State Management

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

### 9. Circuit Breaker Integration

**Issue**: Optional circuit breaker attachment with runtime checks
**Location**:
- `lib/zen_cex/core/http.ex:505-512` (maybe_attach_circuit_breaker)

**Impact**: Runtime overhead for feature detection, unclear when circuit breaker is active
**Suggested Fix**:
- Make circuit breaker a compile-time configuration
- Use a null object pattern for disabled circuit breaker
- Move to a middleware pattern consistent with other steps

**Effort**: Low

### 10. Debug Capture Integration

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

## Cross-Cutting Concerns

### Missing Abstractions

1. **Request Context**: No unified structure for carrying request metadata through the pipeline
2. **Response Envelope**: No standard response format across exchanges
3. **Error Hierarchy**: No structured error types with proper categorization

### Performance Optimizations

1. **Module Loading**: Convert runtime module discovery to compile-time where possible
2. **ETS Key Generation**: Standardize and optimize ETS key generation patterns
3. **String Operations**: Replace string concatenation with iolist where applicable

### Testing Improvements

1. **Step Testing**: Individual request/response steps are hard to test in isolation
2. **Mock Support**: No clean abstraction for mocking exchange responses
3. **Integration Test Helpers**: Duplicate test setup across adapter tests

## Priority Recommendations

### High Priority (Immediate Impact)
1. Extract magic numbers to configuration (Low effort, high impact)
2. Consolidate telemetry helpers (Low effort, improves consistency)
3. Standardize error handling (Medium effort, high value)

### Medium Priority (Foundation Work)
1. Create request context abstraction (Medium effort, enables future work)
2. Optimize module loading patterns (Medium effort, performance gain)
3. Consolidate credential resolution (Medium effort, reduces duplication)

### Low Priority (Nice to Have)
1. Request pipeline refactoring (High effort, architectural improvement)
2. Circuit breaker improvements (Low effort, minor impact)
3. Debug capture refactoring (Low effort, developer experience)

## Next Steps

Continue with Task 2: Analyze Rate Limiting Implementations to identify patterns across rate limiter modules.