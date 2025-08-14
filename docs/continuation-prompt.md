# AI Coder Implementation Guide for ZenCex

## CRITICAL: One Task Per Chat Session

### ⚠️ IMPORTANT: Task Scope Rules
1. **ONE TASK PER CHAT**: Only implement a single module or task per session
2. **NO FULL APP GENERATION**: Never try to create the entire application at once
3. **INCREMENTAL PROGRESS**: Each chat session should complete one specific task
4. **UPDATE DOCUMENTATION**: After completing a task, update this file's progress
5. **ASK FOR NEXT TASK**: After documenting progress, ask what to work on next

### Required Progress Documentation:
After completing each task, you MUST:
1. Edit this file (`continuation-prompt.md`) to mark the task complete
2. Update the progress percentage
3. Commit the documentation changes
4. THEN ask for the next task

### Example Correct Usage:
```
User: "Read docs/continuation-prompt.md and implement Core.Registry module"
AI: [Implements ONLY Core.Registry module]

User: "Read docs/continuation-prompt.md and implement Binance.Auth"
AI: [Implements ONLY Binance.Auth module]
```

### Example INCORRECT Usage:
```
User: "Read docs/continuation-prompt.md and implement everything"
AI: ❌ WRONG - This would try to create the entire app
```

## How to Use This Documentation as an AI Coder

### Document Hierarchy and Purpose
1. **START HERE**: Read this guide first
2. **ARCHITECTURE**: `cex-shared-modules-ai.md` - Complete technical specifications
3. **TASKS**: `cex-implementation-tasks-ai.md` - Step-by-step implementation
4. **REFERENCE**: Original docs (`cex-shared-modules-final.md`, `cex-implementation-tasks.md`) for context only

### Implementation Workflow

## Step 1: Understand the Architecture
Read `cex-shared-modules-ai.md` to understand:
- Plugin architecture structure
- Critical requirements (marked with CRITICAL)
- Exchange-specific quirks
- Code examples to copy

## Step 2: Follow Task Order
Use `cex-implementation-tasks-ai.md` for:
- Day-by-day implementation plan
- Exact file paths and directory structure
- Complete code blocks to implement
- Validation checklists

## Step 3: Implementation Rules for AI Coders

### MUST FOLLOW Rules:
1. **Create directories first**: Follow exact structure in Task guide
2. **Copy code exactly**: Use provided code blocks without modification initially
3. **Test with real APIs**: Never use mocks for integration tests
4. **Handle all CRITICAL markers**: These are non-negotiable requirements
5. **Implement in order**: Day 1 → Day 2 → Day 3 (don't skip)

### MUST AVOID:
1. **NO WebSocket authentication** - Public streams only
2. **NO trading over WebSocket** - REST only for orders
3. **NO complex abstractions** - Keep it simple
4. **NO mocks before real tests** - Test real APIs first
5. **NO skipping CRITICAL sections** - All are required

## Current Implementation Status

### Completed Modules (Reference/Legacy Implementation)
- ✅ Exchange.HTTP (5/5) - Excellent REQ-based client with middleware
- ✅ Exchange.Auth (5/5) - Perfect implementation, all exchange quirks handled
- ✅ Exchange.RateLimit (5/5) - Outstanding atomic ETS implementation
- ✅ Exchange.Health (5/5) - Perfect clock sync and consensus monitoring  
- ✅ Exchange.Cache (4/5) - Solid TTL-based caching

### New Plugin Architecture Status
#### Completed (Day 1 - Tasks 1-3):
- ✅ Core.Registry (4/5) - Clean compile-time validation
- ✅ Core.HTTP (4/5) - Good foundation, missing rate limit integration
- ✅ All Behaviors (3/5) - Basic structure defined
- ✅ Adapter Placeholders (2/5) - Stubs only, need implementation

### New Plugin Architecture To Build (Days 1-5)
- [ ] Day 1: Core modules + Binance adapter
- [ ] Day 2: Kraken + Deribit adapters
- [ ] Day 3: WebSocket discovery + implementation
- [ ] Day 4: Integration layer + circuit breaker
- [ ] Day 5: Testing + documentation

## Task Progress Tracking

### IMPORTANT: Update This List After Each Task
Mark completed tasks with ✅ and add completion date/time.

### Day 1 Tasks (Do in Order):
- [x] 1. Implement Core.Registry module with tests ✅
- [x] 2. Implement Core.HTTP module with tests ✅
- [x] 3. Create all behavior definitions ✅
- [x] 4. Implement Binance.Adapter with tests ✅ (2024-11-14)
- [ ] 5. Implement Binance.Auth with tests
- [ ] 6. Implement Binance.RateLimiter with tests

### Day 2 Tasks (Do in Order):
- [ ] 7. Implement Kraken.Auth with nonce and tests
- [ ] 8. Implement Kraken.RateLimiter with tests
- [ ] 9. Implement Deribit.OAuth with tests
- [ ] 10. Implement Deribit.RateLimiter with tests

### Day 3 Tasks:
- [ ] 11. Discover ZenWebsocket API
- [ ] 12. Implement Binance.MarketData with tests
- [ ] 13. Implement Kraken.MarketData with binary frames and tests

### Day 4 Tasks:
- [ ] 14. Implement Core.Circuit breaker
- [ ] 15. Implement Core.Health monitoring
- [ ] 16. Create ZenCex.Client facade

### Day 5 Tasks:
- [ ] 17. Integration testing suite
- [ ] 18. Performance testing suite

### Progress Summary:
**Completed**: 4/18 tasks (22.2%)
**Current Day**: Day 1
**Next Task**: Task 5 - Implement Binance.Auth with tests
**Overall Code Quality**: 4.2/5 (Excellent legacy modules, plugin architecture in progress)

### Recent Achievements:
- ✅ Fixed 3 Dialyzer errors (2024-11-14)
- ✅ Implemented plugin architecture foundation
- ✅ Fixed Binance rate limit integration test (2024-11-14)
- ✅ All 86 tests passing with 0 failures
- ✅ Dialyzer clean (0 errors)

### How to Request Each Task:
```
"Read docs/continuation-prompt.md and implement [SPECIFIC TASK]"
```

### Task Prompt Templates:
Use these exact prompts for each task:

**Day 1:**
- Task 1: `"Read docs/continuation-prompt.md and implement Core.Registry module with tests"`
- Task 2: `"Read docs/continuation-prompt.md and implement Core.HTTP module with tests"`
- Task 3: `"Read docs/continuation-prompt.md and create all behavior definitions"`
- Task 4: `"Read docs/continuation-prompt.md and implement Binance.Adapter with tests"`
- Task 5: `"Read docs/continuation-prompt.md and implement Binance.Auth with tests"`
- Task 6: `"Read docs/continuation-prompt.md and implement Binance.RateLimiter with tests"`

**Day 2:**
- Task 7: `"Read docs/continuation-prompt.md and implement Kraken.Auth with nonce and tests"`
- Task 8: `"Read docs/continuation-prompt.md and implement Kraken.RateLimiter with tests"`
- Task 9: `"Read docs/continuation-prompt.md and implement Deribit.OAuth with tests"`
- Task 10: `"Read docs/continuation-prompt.md and implement Deribit.RateLimiter with tests"`

**Day 3:**
- Task 11: `"Read docs/continuation-prompt.md and discover ZenWebsocket API"`
- Task 12: `"Read docs/continuation-prompt.md and implement Binance.MarketData with tests"`
- Task 13: `"Read docs/continuation-prompt.md and implement Kraken.MarketData with binary frames and tests"`

## Quick Start Commands

```bash
# 1. Setup environment variables
export BINANCE_API_KEY="your_key"
export BINANCE_API_SECRET="your_secret"
export KRAKEN_API_KEY="your_key"
export KRAKEN_API_SECRET="your_secret"
export DERIBIT_CLIENT_ID="your_id"
export DERIBIT_CLIENT_SECRET="your_secret"

# 2. Install dependencies
mix deps.get

# 3. Create directory structure
mkdir -p lib/zen_cex/{core,behaviors,adapters}
mkdir -p lib/zen_cex/adapters/{binance,kraken,deribit}

# 4. Start implementing from Day 1 tasks
# ONE TASK AT A TIME - Follow cex-implementation-tasks-ai.md
```

## Implementation Checklist

### Before Starting Any Module:
- [ ] Read the CRITICAL requirements in `cex-shared-modules-ai.md`
- [ ] Check the exact file path in `cex-implementation-tasks-ai.md`
- [ ] Copy the provided code template exactly
- [ ] Set up environment variables for testing

### After Implementing Each Module:
- [ ] Create corresponding test file in test/ directory
- [ ] Write at least 3 unit tests for happy path
- [ ] Write at least 2 tests for error cases
- [ ] Run tests with `mix test path/to/test.exs`
- [ ] Run integration tests against real API
- [ ] Verify no rate limit violations
- [ ] Check memory usage (no leaks)
- [ ] Confirm all CRITICAL features work

### Test Coverage Requirements:
- **Minimum 80% coverage** for all modules
- **100% coverage** for critical paths (auth, rate limiting)
- **Integration tests** for each exchange
- **Performance tests** for rate limiting and WebSocket

### Exchange-Specific Critical Points:

#### Binance:
- MUST track separate limits for spot (1200/min) vs futures (2400/min)
- MUST include timestamp within 5000ms window
- MUST put signature as last parameter

#### Kraken:
- MUST use microsecond + counter nonce (not just microseconds!)
- MUST force HTTP/1.1 (HTTP/2 has issues)
- MUST handle binary WebSocket frames (zlib/gzip)

#### Deribit:
- MUST refresh OAuth token 120 seconds before expiry
- MUST use JSON-RPC format for all endpoints
- MUST implement single-flight protection for token refresh

## How to Read Error Messages

### Common Errors and What They Mean:
1. **"Timestamp for this request is outside of the recvWindow"** 
   - Your clock is off by >1000ms
   - Check clock sync implementation

2. **"EAPI:Invalid nonce"** (Kraken)
   - You're using just microseconds instead of microsecond + counter
   - Check Kraken.Nonce implementation

3. **"unauthorized"** (Deribit)
   - OAuth token expired
   - Check token refresh is happening 120s before expiry

4. **Rate limited immediately**
   - Wrong table for spot vs futures
   - Check you're using correct rate limit table

## Testing Strategy

### Order of Testing:
1. **Unit tests first**: Test pure functions
2. **Integration tests second**: Test against real APIs
3. **Performance tests last**: Test under load

### Integration Test Template:
```elixir
@tag :integration
test "real API call" do
  # ALWAYS test against real API
  # Use test credentials
  # Verify actual response format
end
```

## When You Get Stuck

### Debugging Checklist:
1. Check if it's marked as CRITICAL in the docs
2. Verify you're using exact code from examples
3. Confirm environment variables are set
4. Test with real API to see actual error
5. Check exchange-specific requirements section

### Where to Find Answers:
- **Architecture questions**: `cex-shared-modules-ai.md`
- **Implementation order**: `cex-implementation-tasks-ai.md`
- **Exchange quirks**: Search for exchange name in AI docs
- **Code examples**: Complete examples in both AI docs

## Progress Tracking

After completing each day's tasks, verify:
- [ ] All files created in correct locations
- [ ] All CRITICAL features implemented
- [ ] Integration tests pass
- [ ] No memory leaks after 1000 requests
- [ ] Rate limiting works correctly

## Remember

1. **ONE TASK PER CHAT SESSION** - Never try to implement the entire application
2. **INCREMENTAL PROGRESS** - Each module builds on the previous ones
3. **TEST AFTER EACH MODULE** - Verify each piece works before moving on
4. **PLUGIN ARCHITECTURE** - Each exchange is completely isolated
5. **CORE IS THIN** - Core modules are coordinators only (~300 lines total)

### After Completing a Task:
1. **Update the task list** - Mark the completed task with ✅
2. **Document what was created** - List files created/modified
3. **Report test results** - Show test output (`mix test` results)
4. **Update progress percentage** - Calculate completion (e.g., "6/18 modules = 33%")
5. **Provide next task prompt** - Give the exact command for the next task
6. **Do NOT automatically continue** to the next task

### Example Task Completion Report:
```
✅ Completed: Task 1 - Core.Registry module with tests

Files created:
- lib/zen_cex/core/registry.ex (32 lines)
- test/zen_cex/core/registry_test.exs (45 lines)

Test results:
4 tests, 0 failures
Coverage: 100%

Progress: 1/18 tasks complete (5.5%)
Next Task: Task 2 - Core.HTTP

To continue with the next task, use:
"Read docs/continuation-prompt.md and implement Core.HTTP module with tests"
```