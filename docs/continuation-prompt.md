# AI Coder Implementation Guide for ZenCex

## CRITICAL: One Task Per Chat Session

### ⚠️ IMPORTANT: Task Scope Rules
1. **ONE TASK PER CHAT**: Only implement a single module or task per session
2. **NO FULL APP GENERATION**: Never try to create the entire application at once
3. **INCREMENTAL PROGRESS**: Each chat session should complete one specific task
4. **ASK FOR NEXT TASK**: After completing a task, ask what to work on next

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

### Completed Modules (Reference Only - Being Rebuilt)
- ✅ Exchange.HTTP (4.5/5) - Reference implementation
- ✅ Exchange.Auth (4.5/5) - Reference implementation  
- ✅ Clock Sync (5/5) - Reference implementation
- ✅ Exchange.Cache (4.5/5) - Reference implementation
- ✅ Exchange.RateLimit (4.5/5) - Reference implementation

### New Plugin Architecture To Build (Days 1-5)
- [ ] Day 1: Core modules + Binance adapter
- [ ] Day 2: Kraken + Deribit adapters
- [ ] Day 3: WebSocket discovery + implementation
- [ ] Day 4: Integration layer + circuit breaker
- [ ] Day 5: Testing + documentation

## Suggested Task Order (One Per Chat Session)

### Day 1 Tasks (Do in Order):
1. "Implement Core.Registry module"
2. "Implement Core.HTTP module"
3. "Create all behavior definitions"
4. "Implement Binance.Adapter"
5. "Implement Binance.Auth"
6. "Implement Binance.RateLimiter"

### Day 2 Tasks (Do in Order):
7. "Implement Kraken.Auth with nonce"
8. "Implement Kraken.RateLimiter"
9. "Implement Deribit.OAuth"
10. "Implement Deribit.RateLimiter"

### Day 3 Tasks:
11. "Discover ZenWebsocket API"
12. "Implement Binance.MarketData"
13. "Implement Kraken.MarketData with binary frames"

### How to Request Each Task:
```
"Read docs/continuation-prompt.md and implement [SPECIFIC TASK]"
```

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
- [ ] Run integration tests against real API
- [ ] Verify no rate limit violations
- [ ] Check memory usage (no leaks)
- [ ] Confirm all CRITICAL features work

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
- Inform the user the specific task is complete
- Ask what task to work on next
- Do NOT automatically continue to the next task