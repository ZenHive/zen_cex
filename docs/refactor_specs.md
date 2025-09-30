# Refactoring Analysis Task Specification

## Overview

This document breaks down the comprehensive refactoring analysis of the zen_cex codebase into manageable tasks. Each numbered task is designed to be completed in a single Claude Code session and will produce a specific section of the final refactoring opportunities document.

The final output will be `docs/refactoring_opportunities.md`, built incrementally through these tasks.

## Session Continuation Prompt

Use this prompt to continue the refactoring analysis in the next session:

```
I'm working through the refactoring analysis tasks defined in docs/refactor_specs.md.

Please execute Task 2: Analyze Rate Limiting Implementations

The task scope includes analyzing these modules:
- All **/rate_limiter.ex files
- lib/zen_cex/behaviors/base_rate_limiter.ex

Please:
1. Read and analyze the specified files
2. Identify refactoring opportunities following the guidelines in the spec
3. Append to docs/refactoring_opportunities.md with the findings
4. Update the checkbox in docs/refactor_specs.md to mark this task complete

Focus on finding: duplication, inconsistent patterns, missing abstractions, performance issues, and maintainability improvements.
```

### Generic Template for Subsequent Tasks

```
I'm working through the refactoring analysis tasks defined in docs/refactor_specs.md.

Please execute Task [NUMBER]: [TASK TITLE]

The task scope includes analyzing these modules:
[LIST MODULES FROM TASK]

Please:
1. Read and analyze the specified files
2. Identify refactoring opportunities following the guidelines in the spec
3. Create or append to docs/refactoring_opportunities.md with the findings
4. Update the checkbox in docs/refactor_specs.md to mark this task complete

Focus on finding: duplication, inconsistent patterns, missing abstractions, performance issues, and maintainability improvements.
```

## Task Prioritization Framework

### Scoring System
- **Difficulty**: 1-10 (1=trivial, 10=very complex)
- **Benefit**: 1-10 (1=minimal impact, 10=transformative)
- **Priority Score**: Benefit/Difficulty ratio (higher = better ROI)

### Priority Quadrants
```
High Benefit │ Plan Carefully     │ Do First!
      8-10   │ (High Diff,        │ (Low Diff,
             │  High Benefit)     │  High Benefit)
             │                    │
      5-7    │ Consider Context   │ Do Soon
             │                    │
      1-4    │ Avoid!            │ Do When Free
Low Benefit  │ (High Diff,        │ (Low Diff,
             │  Low Benefit)      │  Low Benefit)
             └────────────────────┴────────────────
                High Difficulty     Low Difficulty
                    8-10               1-4
```

### Benefit Criteria
- **Code Maintainability**: Reduces complexity, improves readability
- **Performance**: Reduces latency, memory usage, or CPU cycles
- **Developer Velocity**: Speeds up feature development or debugging
- **Bug Reduction**: Prevents common errors or edge cases
- **Reusability**: Enables code sharing across modules

## Progress Tracking

Mark tasks as complete by checking the boxes below:

## Task List

### Phase 1: Core Infrastructure Analysis

- [x] **Task 1: Analyze Core HTTP and Request Pipeline** [D:4/B:7 → Priority:1.75] ✅
  - **Scope**: `lib/zen_cex/core/http.ex`, `lib/zen_cex/core/auth.ex`, `lib/zen_cex/core/registry.ex`
  - **Output**: Document request pipeline duplication, middleware patterns, and consolidation opportunities
  - **Deliverable**: Create/append to `docs/refactoring_opportunities.md` section "Request Pipeline Refactoring"

- [ ] **Task 2: Analyze Rate Limiting Implementations** [D:6/B:8 → Priority:1.33]
  - **Scope**: All `**/rate_limiter.ex` files, `base_rate_limiter.ex`
  - **Output**: Document rate limiter pattern variations, ETS usage, and unification potential
  - **Deliverable**: Append section "Rate Limiting Consolidation"

- [ ] **Task 3: Analyze Authentication and Signing Patterns** [D:5/B:6 → Priority:1.20]
  - **Scope**: All `**/auth.ex`, `**/signer.ex`, `common_signer.ex`, `base_auth.ex`
  - **Output**: Document HMAC implementations, auth step patterns, and consolidation paths
  - **Deliverable**: Append section "Authentication Module Refactoring"

### Phase 2: Adapter Pattern Analysis

- [ ] **Task 4: Analyze Parser Implementations** [D:7/B:7 → Priority:1.00]
  - **Scope**: All `**/parser.ex` files, `base_parser.ex`, `parser_macros.ex`, `response_parser.ex`
  - **Output**: Document response parsing patterns, macro usage, and standardization opportunities
  - **Deliverable**: Append section "Parser Consolidation Strategy"

- [ ] **Task 5: Analyze Parameter Builders** [D:5/B:5 → Priority:1.00]
  - **Scope**: All `**/parameter_builder.ex` files, `base_parameter_builder.ex`
  - **Output**: Document parameter building patterns, validation logic duplication
  - **Deliverable**: Append section "Parameter Builder Unification"

- [x] **Task 6: Analyze Request Helpers** [D:4/B:6 → Priority:1.50] ✅
  - **Scope**: All `**/request_helper.ex` files, `base_request_helper.ex`
  - **Output**: Document request helper patterns, common functionality extraction
  - **Deliverable**: Append section "Request Helper Consolidation"

### Phase 3: Exchange-Specific Analysis

- [ ] **Task 7: Analyze Binance Adapter Structure** [D:7/B:8 → Priority:1.14]
  - **Scope**: `lib/zen_cex/adapters/binance/` (excluding generated files)
  - **Output**: Document Binance-specific duplications across Spot, Margin, Futures modules
  - **Deliverable**: Append section "Binance Adapter Refactoring"

- [ ] **Task 8: Analyze Bybit Adapter Structure** [D:6/B:7 → Priority:1.17]
  - **Scope**: `lib/zen_cex/adapters/bybit/` (excluding generated files)
  - **Output**: Document Bybit module organization and internal duplication
  - **Deliverable**: Append section "Bybit Adapter Refactoring"

- [ ] **Task 9: Analyze Generated vs Handwritten Code** [D:8/B:9 → Priority:1.13]
  - **Scope**: All `generated_*.ex` files vs their non-generated counterparts
  - **Output**: Document overlap between generated and manual code, generation strategy improvements
  - **Deliverable**: Append section "Code Generation Strategy"

### Phase 4: WebSocket and Real-time Systems

- [ ] **Task 10: Analyze WebSocket Adapters** [D:8/B:8 → Priority:1.00]
  - **Scope**: `adapters/binance/websocket.ex`, `adapters/bybit/websocket.ex`, `websocket/connection_registry.ex`
  - **Output**: Document WebSocket adapter duplication, connection management patterns
  - **Deliverable**: Append section "WebSocket Architecture Refactoring"

- [ ] **Task 11: Analyze Market Data and Caching** [D:7/B:7 → Priority:1.00]
  - **Scope**: `cache/market.ex`, `core/cache.ex`, `safety/order_safety/cache.ex`, `safety/order_safety/market_data.ex`
  - **Output**: Document cache usage patterns, ETS table management, data flow
  - **Deliverable**: Append section "Cache and Market Data Consolidation"

### Phase 5: Safety and Validation Systems

- [ ] **Task 12: Analyze Order Safety Components** [D:6/B:9 → Priority:1.50]
  - **Scope**: All files in `lib/zen_cex/safety/order_safety/`
  - **Output**: Document safety validation patterns, decimal handling, configuration
  - **Deliverable**: Append section "Order Safety Module Refactoring"

- [ ] **Task 13: Analyze Clock Sync and Circuit Breaker** [D:5/B:6 → Priority:1.20]
  - **Scope**: `safety/clock_sync.ex`, `core/circuit_breaker.ex`
  - **Output**: Document reliability patterns, error handling, recovery mechanisms
  - **Deliverable**: Append section "Reliability Module Consolidation"

### Phase 6: Configuration and Application Structure

- [ ] **Task 14: Analyze Configuration Management** [D:4/B:8 → Priority:2.00]
  - **Scope**: `config.ex`, `config/time_constants.ex`, `application.ex`
  - **Output**: Document configuration patterns, environment handling, initialization
  - **Deliverable**: Append section "Configuration Management Refactoring"

- [ ] **Task 15: Analyze Telemetry and Debug Systems** [D:5/B:7 → Priority:1.40]
  - **Scope**: `core/telemetry.ex`, `core/debug.ex`, `core/debug_table.ex`, `examples/telemetry_handlers.ex`
  - **Output**: Document observability patterns, debug tooling, telemetry events
  - **Deliverable**: Append section "Observability Infrastructure"

### Phase 7: Testing Infrastructure

- [ ] **Task 16: Analyze Test Utilities and Helpers** [D:6/B:7 → Priority:1.17]
  - **Scope**: All files in `lib/zen_cex/test_utilities/`, `test/support/`
  - **Output**: Document test helper duplication, fixture patterns, integration test structure
  - **Deliverable**: Append section "Test Infrastructure Refactoring"

- [ ] **Task 17: Analyze Integration Test Patterns** [D:7/B:8 → Priority:1.14]
  - **Scope**: Sample of integration tests across adapters (5-10 test files)
  - **Output**: Document test patterns, mock vs real API usage, test data management
  - **Deliverable**: Append section "Integration Test Strategy"

### Phase 8: Behavior and Interface Analysis

- [ ] **Task 18: Analyze Behavior Definitions** [D:5/B:6 → Priority:1.20]
  - **Scope**: All files in `lib/zen_cex/behaviors/`
  - **Output**: Document behavior usage, callback implementations, interface consistency
  - **Deliverable**: Append section "Behavior and Interface Refinement"

- [ ] **Task 19: Analyze Endpoint Registry Pattern** [D:8/B:7 → Priority:0.88]
  - **Scope**: `core/endpoint_registry.ex`, all `endpoints.ex` files, endpoint loader modules
  - **Output**: Document endpoint definition patterns, registry usage, discovery mechanisms
  - **Deliverable**: Append section "Endpoint Management Refactoring"

### Phase 9: Analysis and Business Logic

- [ ] **Task 20: Analyze Analysis Modules** [D:6/B:5 → Priority:0.83]
  - **Scope**: `analysis/basis.ex`, `analysis/market.ex`, `adapters/binance/strategies.ex`
  - **Output**: Document business logic organization, calculation patterns, strategy implementation
  - **Deliverable**: Append section "Business Logic Organization"

### Phase 10: Final Review and Prioritization

- [ ] **Task 21: Cross-Module Dependency Analysis** [D:7/B:9 → Priority:1.29]
  - **Scope**: Review module dependencies using `mix xref`
  - **Output**: Document circular dependencies, coupling issues, module boundaries
  - **Deliverable**: Append section "Module Dependency Refactoring"

- [ ] **Task 22: Performance and Complexity Metrics** [D:8/B:8 → Priority:1.00]
  - **Scope**: Run complexity analysis tools, identify hotspots
  - **Output**: Document complex modules, performance bottlenecks, optimization targets
  - **Deliverable**: Append section "Performance and Complexity Improvements"

- [ ] **Task 23: Create Refactoring Priority Matrix** [D:9/B:10 → Priority:1.11]
  - **Scope**: Review all previous sections
  - **Output**: Create prioritized list of refactoring opportunities with effort/impact analysis
  - **Deliverable**: Append section "Refactoring Roadmap and Priorities"

## Task Execution Guidelines

For each task:
1. Start by reading the specified files completely
2. Look for these refactoring patterns:
   - Code duplication (exact or similar logic)
   - Violation of DRY principle
   - Inconsistent error handling
   - Missing or inconsistent type specs
   - Complex functions that could be simplified
   - Unused or dead code
   - Inconsistent naming conventions
   - Missing abstractions or over-abstraction
   - Performance issues (N+1 queries, unnecessary iterations)
   - Test coverage gaps

3. Document findings in structured format:
   - **Issue**: Description of the problem
   - **Location**: Specific files and line numbers
   - **Impact**: How this affects maintainability/performance
   - **Suggested Fix**: Concrete refactoring approach
   - **Effort**: Estimated complexity (Low/Medium/High)

4. Each session should produce ~200-500 lines of documentation

## Task Priority Rankings (by ROI)

### 🎯 Do First! (High Benefit, Low Difficulty)
1. **Task 14**: Configuration Management [Priority: 2.00] - Quick win for runtime configuration
2. **Task 1**: Core HTTP Pipeline [Priority: 1.75] ✅ - Already completed
3. **Task 6**: Request Helpers [Priority: 1.50] - Easy consolidation opportunity
4. **Task 12**: Order Safety [Priority: 1.50] - Critical for trading safety

### 🚀 Do Soon (Good ROI)
5. **Task 15**: Telemetry/Debug [Priority: 1.40] - Improves observability
6. **Task 2**: Rate Limiting [Priority: 1.33] - Important for API stability
7. **Task 21**: Dependency Analysis [Priority: 1.29] - Reveals architectural issues

### 📋 Plan Carefully (High Impact but Complex)
8. **Task 3**: Authentication [Priority: 1.20] - Security critical
9. **Task 13**: Clock Sync [Priority: 1.20] - Reliability improvement
10. **Task 18**: Behaviors [Priority: 1.20] - Interface consistency
11. **Task 8**: Bybit Adapter [Priority: 1.17] - Exchange-specific improvements
12. **Task 16**: Test Utilities [Priority: 1.17] - Testing infrastructure
13. **Task 7**: Binance Adapter [Priority: 1.14] - Largest exchange adapter
14. **Task 17**: Integration Tests [Priority: 1.14] - Test reliability
15. **Task 9**: Generated Code [Priority: 1.13] - Code generation strategy
16. **Task 23**: Priority Matrix [Priority: 1.11] - Final synthesis

### 🤔 Consider Context (Neutral ROI)
17. **Task 4**: Parsers [Priority: 1.00] - Complex but valuable
18. **Task 5**: Parameter Builders [Priority: 1.00] - Moderate impact
19. **Task 10**: WebSocket [Priority: 1.00] - Real-time system improvements
20. **Task 11**: Market Data [Priority: 1.00] - Cache optimization
21. **Task 22**: Performance Metrics [Priority: 1.00] - Measurement infrastructure

### ⚠️ Low Priority (Poor ROI)
22. **Task 19**: Endpoint Registry [Priority: 0.88] - Complex macro work
23. **Task 20**: Analysis Modules [Priority: 0.83] - Limited scope

## Success Criteria

The refactoring analysis is complete when:
- All 23 tasks have been executed
- Each major module has been analyzed
- Common patterns across modules have been identified
- A prioritized refactoring roadmap exists
- Each refactoring opportunity has clear rationale and approach

## Notes

- Tasks can be executed in any order within their phase
- Later tasks may reference findings from earlier tasks
- If a task reveals issues requiring immediate attention, note them specially
- Keep focus on pragmatic refactoring that improves maintainability without over-engineering