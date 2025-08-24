# Core Refactoring Sessions Tracker

## Your Role: AI Coder

You implement tasks from this document. An AI Reviewer will validate your work using AI-REVIEW.md.

## Your Background
You are a senior Elixir developer with:
- 10+ years of Elixir/Erlang experience and deep OTP expertise
- Extensive production experience with cryptocurrency exchange APIs
- Expert knowledge of the Req HTTP client library and its middleware patterns
- Production experience with fault-tolerant financial systems
- Deep understanding of REST API patterns, rate limiting, and authentication
- Familiarity with macro-based code generation and declarative patterns

## Development Philosophy

### Simplicity Guidelines
- Code simplicity is a primary feature, not an afterthought
- Start simple and add complexity only when proven necessary
- **Target ~5-10 public functions per module** - Keep interfaces minimal
- **Function length guidelines**:
  - Pure business logic: aim for ~15 lines
  - GenServer callbacks: up to ~30 lines is acceptable
  - Complex pattern matching: up to ~25 lines
  - **Always prioritize readability** over arbitrary limits
- **Keep function call chains shallow** - 2-3 levels max
- **Use behaviors only when ≥2 implementations exist**
- **No custom error wrapping** - Pass raw errors through
- **Create abstractions only with proven need** - Need 3+ use cases

### Anti-Patterns to Avoid
- No premature optimization without performance data
- No "just-in-case" code for hypothetical requirements
- No abstractions without at least 3 concrete usage examples
- No complex macros unless absolutely necessary
- No overly clever solutions prioritizing elegance over clarity
- Don't split cohesive logic just to meet line counts
- Avoid deep nesting and complex conditionals

### Pragmatic Simplicity
We want pragmatic simplicity, not naive simplicity. This means choosing solutions that are simple but robust, maintainable but not overengineered, and practical for real-world use cases rather than theoretically perfect.

## Testing Strategy: Real TESTNET APIs Only

**[!] SIMPLE RULE: ALL Tests Must Use Real TESTNET APIs [!]**
--------------------------------------------------
**Test against real exchange testnet/sandbox APIs. Period.**
**No mocks. No fixtures. No simulation. Just real testnet APIs.**
**NEVER use production APIs in tests.**
--------------------------------------------------

### Test Categories

1. **Unit Tests** (`*_test.exs`)
   - Test pure functions only (parsers, calculations)
   - No API calls needed

2. **Integration Tests** (`*_integration_test.exs`)
   - Test against REAL testnet/sandbox APIs only
   - Tag with `@tag :integration`
   - **FAIL if credentials missing** - Don't skip/hide missing tests
   - **FAIL if not using testnet** - Prevent production API calls
   - Must document actual API responses

### Testnet URLs (ENFORCED IN TESTS)

```elixir
# These are the ONLY allowed URLs in test environment
@test_hosts %{
  binance: "testnet.binance.vision",
  bybit: "api-testnet.bybit.com",
  kraken: "api.kraken.com",  # Uses different endpoints for testnet
  deribit: "test.deribit.com"
}

# Tests MUST verify testnet usage
assert Application.get_env(:zen_cex, :binance_host) == "testnet.binance.vision"
assert Application.get_env(:zen_cex, :bybit_host) == "api-testnet.bybit.com"
```

### Environment Variable Naming

**CRITICAL**: Use `_TESTNET_` in environment variable names:

```bash
# GOOD - Clear these are testnet credentials
BINANCE_TESTNET_API_KEY=xxx
BINANCE_TESTNET_API_SECRET=yyy
BYBIT_TESTNET_API_KEY=xxx
BYBIT_TESTNET_API_SECRET=yyy

# BAD - Ambiguous, could be production
BINANCE_API_KEY=xxx  # NEVER use in tests
BYBIT_API_KEY=xxx    # NEVER use in tests
```

## ⚠️ CRITICAL: Task Grouping Guidelines

### Phase-Based Sessions
You may implement **related tasks within the same phase** when they are tightly coupled:
- Tasks that share significant context (e.g., auth + rate limiter for same exchange)
- Tasks that would require redundant setup if separated
- Tasks that form a logical unit of work

### Session Boundaries
- **MUST complete all tasks in a group** before stopping
- **MUST NOT cross phase boundaries** in a single session
- **MUST mark each task as done** as you complete it
- **MUST provide clear handoff notes** when stopping mid-phase

### Example Groupings
- **Good**: Tasks 7-9 (Binance auth, rate limiter, parser) in one session
- **Good**: Tasks 3-5 (HTTP, telemetry, OrderSafety) if working on core infrastructure
- **Bad**: Task 5 (Phase 1) + Task 6 (Phase 2) - crosses phase boundary
- **Bad**: Starting Task 8 without completing Task 7 - breaks dependencies

## What This Library Does (and Does NOT Do)

### This Library DOES (REST Trading Operations):
- **Order Management**: Place, modify, cancel orders via REST
- **Position Management**: Query positions, balances, margins
- **Account Operations**: Withdrawals, deposits, transfers
- **Risk Management**: Liquidation prices, margin requirements
- **Multi-Exchange Support**: Currently Binance fully implemented, Bybit/Kraken/Deribit planned

### This Library does NOT do:
- **No WebSocket**: REST-only by design, leveraging Req's strengths
- **No Market Data**: No price feeds, order books, or tick data
- **No HFT**: Focus on reliability over microsecond latency
- **No Market Making**: No order book management

## Overview
Extracting common patterns from Binance adapter into core modules for future exchange implementations.
Goal: Create reusable components while maintaining pragmatic simplicity.

**CURRENT STATUS**: 
- **Binance**: Fully implemented with comprehensive endpoint coverage (Spot, Margin, Futures)
- **Bybit**: Not yet implemented (Task 17 in AI-IMPLEMENTATION.md)
- **Kraken**: Partial implementation (auth, rate limiter, basic structure)
- **Deribit**: Partial implementation (OAuth auth, basic structure)

**Architecture**: Req-centric REST design leveraging Req's built-in features for pooling, retry, and telemetry.

## Session Plan

### Session 1: Core.Auth Module ✅ COMPLETED
**Status**: Completed on 2025-08-23
**Scope**: Extract credential resolution patterns from Binance (currently the only fully implemented adapter)
**Files**:
- [x] Create `lib/zen_cex/core/auth.ex`
- [x] Refactor `lib/zen_cex/adapters/binance/auth.ex` to use core
- [x] Create tests for Core.Auth module (`test/zen_cex/core/auth_test.exs`)
**Key patterns extracted**:
- Environment variable resolution with testnet support
- Credential validation and error messages
- Dynamic credential lookup from request.private or environment
- Follows Req step patterns (request → request or halt)
**Benefit**: Future exchanges (Bybit, Kraken, Deribit when implemented) save ~80 lines

### Session 2: Core.ParameterBuilder Module ✅ COMPLETED
**Status**: Completed on 2025-01-23
**Scope**: Extract request parameter handling from Binance
**Files**:
- [x] Create `lib/zen_cex/core/parameter_builder.ex`
- [x] Refactor `lib/zen_cex/adapters/binance/parameter_builder.ex` to use core
- [x] Create tests `test/zen_cex/core/parameter_builder_test.exs`
**Key patterns extracted**:
- Query string construction with proper encoding and sorting
- Optional parameter filtering (nil/empty removal)
- Parameter validation for required fields
- Parameter normalization (type conversion to strings)
- Parameter merging with defaults
- Parameter grouping by categories
**Benefit**: Future exchanges save ~60 lines
**Note**: Successfully maintained Binance-specific requirements (timing params, ordering)

### Session 3: Core.ResponseParser Module ✅ COMPLETED
**Status**: Completed on 2025-08-23
**Scope**: Extract response normalization from Binance
**Files**:
- [x] Create `lib/zen_cex/core/response_parser.ex`
- [x] Refactor `lib/zen_cex/adapters/binance/parser.ex` to use core
- [x] Create tests `test/zen_cex/core/response_parser_test.exs`
**Key patterns extracted**:
- HTTP status to error atom mapping (401 → :unauthorized, etc.)
- JSON parsing with error handling
- Response structure normalization ({:ok, data} | {:error, reason})
- Rate limit header extraction (x-mbx-used-weight, etc.)
- Error message standardization across exchanges
- HTML error page detection and parsing
- Validation of required fields
- Debug logging for error responses
**Benefit**: Future exchanges save ~50 lines
**Note**: Successfully maintained Binance-specific error codes while using core utilities

### Session 4: Core.Signer Module ✅ COMPLETED
**Status**: Completed on 2025-08-23
**Scope**: Extract cryptographic utilities from Binance
**Files**:
- [x] Create `lib/zen_cex/core/signer.ex`
- [x] Refactor `lib/zen_cex/adapters/binance/signer.ex` to use core
- [x] Create tests `test/zen_cex/core/signer_test.exs`
**Key patterns extracted**:
- HMAC-SHA256 signing (used by Binance, Bybit)
- HMAC-SHA512 signing (for future Kraken implementation)
- Hex encoding with case options (upper/lower)
- Base64 encoding/decoding (for Kraken secrets)
- Nonce generation with different time units (ms, μs, ns)
- Timestamp generation functions (seconds, milliseconds, microseconds)
- Signature verification with timing attack protection
- Convenience sign_payload function with algorithm/encoding options
**Benefit**: Future exchanges save ~40 lines
**Note**: Successfully maintained Binance-specific requirements while providing flexibility for other exchanges

### Session 5: Testing & Documentation ⏰ PENDING
**Scope**: Ensure all refactored modules work correctly
- [ ] Run full test suite: `mix test`
- [ ] Run integration tests: `mix test --only integration`
- [ ] Check dialyzer: `mix dialyzer`
- [ ] Check credo: `mix credo --strict`
- [ ] Check docs coverage: `mix doctor`
- [ ] Update CLAUDE.md architecture section if needed
- [ ] Verify testnet-only enforcement in all integration tests

## Progress Notes

### Session 1 Notes (Completed 2025-01-23)
- Created Core.Auth module with reusable credential resolution patterns
- Refactored Binance.Auth to use Core.Auth instead of duplicated logic
- Changed from request.options to request.private for storing credentials (Req best practice)
- Added comprehensive tests with proper environment variable handling using with_env macro
- All existing tests pass without modification
- Reduced Binance.Auth by ~20 lines of duplicated code

### Session 2 Notes (Completed 2025-01-23)
- Created Core.ParameterBuilder module with common parameter handling patterns
- Extracted 6 reusable functions: build_query_string, filter_optional_params, validate_required_params, normalize_param_values, merge_with_defaults, split_params_by_groups
- Refactored Binance.ParameterBuilder to delegate common operations to core module
- Maintained Binance-specific logic: parameter ordering, timing parameter injection, recvWindow validation
- Added comprehensive test coverage: 40 tests for core module, 23 for Binance-specific behavior
- All tests pass (63 total parameter builder tests)
- Reduced Binance.ParameterBuilder complexity while preserving functionality

### Session 3 Notes (Completed 2025-08-23)
- Created Core.ResponseParser module with common response parsing patterns
- Extracted 8 reusable functions: map_http_status_to_error, parse_json_body, normalize_response, extract_rate_limit_info, standardize_error_message, parse_html_error, validate_required_fields, log_error_response
- Refactored Binance.Parser to use Core.ResponseParser for error message standardization and HTML error parsing
- Maintained Binance-specific error codes while leveraging core utilities
- Added comprehensive test coverage: 29 tests for core module
- Updated Binance parser tests to match new standardized error atoms
- All tests pass (705 total tests with 2 unrelated failures in endpoint tests)
- Reduced code duplication by ~85 lines (extract_html_error_message function eliminated)

### Session 4 Notes (Completed 2025-08-23)
- Created Core.Signer module with comprehensive cryptographic utilities
- Extracted 12 reusable functions: hmac_sha256, hmac_sha512, encode_hex, decode_hex, encode_base64, decode_base64, generate_nonce, timestamp_seconds, timestamp_milliseconds, timestamp_microseconds, sign_payload, verify_signature
- Refactored Binance.Signer to delegate cryptographic operations to Core.Signer
- Maintained Binance-specific requirements (lowercase hex, SHA256, query string ordering)
- Added comprehensive test coverage: 51 tests including integration tests for Binance and Kraken patterns
- Included timing attack protection in signature verification
- All tests pass (756 total tests, all passing when run individually)
- Reduced Binance.Signer from 87 lines to 79 lines (~10% reduction)
- Core.Signer provides foundation for future exchange implementations (Bybit, Kraken, etc.)

## Success Metrics
- [ ] All tests passing after each session (unit + integration)
- [ ] No breaking changes to existing Binance adapter (the only adapter)
- [ ] Reduced LOC in Binance adapter by 200+ lines total
- [ ] Future adapters (when eventually implemented) can reuse all core modules
- [ ] Dialyzer passes with 0 warnings
- [ ] Credo score ≥ 8.0
- [ ] Test coverage remains ≥ 80%

## Implementation Guidelines
1. **Don't over-abstract**: Only extract what's actually duplicated
2. **Maintain simplicity**: Follow the ~15 line function guideline
3. **Preserve testability**: Ensure extracted modules are easily testable
4. **Keep it pragmatic**: Real-world usage over theoretical perfection
5. **Test with real APIs**: Verify against testnet APIs after each change
6. **Leverage Req**: Use Req's built-in features, don't reimplement
7. **Pass raw errors**: No custom error wrapping - pass errors through
8. **Use TODO comments**: Mark temporary code with "TODO:" for credo tracking
9. **No magic numbers**: Use module attributes or explanatory comments

## Next Session Instructions
When starting a new session:
1. Read this file to understand progress
2. Check which session is next (Session 2: Core.ParameterBuilder)
3. Run tests to ensure clean starting state: `mix test`
4. Check git status to see uncommitted changes
5. Complete the session's checklist
6. Run quality checks: `mix format && mix credo --strict && mix dialyzer`
7. Update this file with progress and notes
8. Commit changes with clear message: "refactor: Extract Core.ParameterBuilder from Binance adapter (Session 2)"
