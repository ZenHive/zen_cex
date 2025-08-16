# Expert Review Request: ZenCex Plugin Architecture & Implementation

## Your Role
You are a senior Elixir developer with:
- 10+ years of Elixir/Erlang experience, deep OTP expertise
- Extensive experience integrating with cryptocurrency exchange APIs (Binance, Kraken, Deribit, FTX, etc.)
- Expert-level knowledge of the Req HTTP client library and its advanced features
- Production experience with high-throughput, fault-tolerant financial systems
- Deep understanding of rate limiting, authentication patterns, and WebSocket protocols

## Review Scope
Please review the ZenCex library documentation and provide expert feedback on our plugin architecture for CEX integrations.

## Document to Review

**docs/AI-IMPLEMENTATION.md** - Our streamlined implementation guide (242 lines)
- This single document combines all architecture, implementation, progress, and review criteria
- Previously 2,346 lines across 4 files, now optimized for clarity
- Contains essential patterns, current status, and validation criteria

Please analyze this document for:
- **Architecture Assessment**: Is the plugin architecture with Req middleware sound?
- **Implementation Patterns**: Are the 5 essential patterns correct and complete?
- **Progress Evaluation**: At 21.2% complete, are we on the right track?
- **Review Criteria**: Do our validation checklists cover critical aspects?

## Specific Areas for Expert Input

### 1. Req Library Usage
Review our essential patterns in the document:
- **Pattern 1**: Auth as Req request step - Is returning `{request, options}` tuple correct?
- **Pattern 2**: Rate limiter as middleware - Should we halt the pipeline this way?
- **Pattern 3**: ETS atomic operations - Is this better than GenServer state?
- **Pattern 5**: Req.Test for unit testing - Should we use this for deterministic tests?

Are we missing critical Req features like:
- Request/response steps for telemetry?
- Custom retry strategies per exchange?
- Connection pooling optimization?
- Circuit breaker as middleware?

### 2. CEX API Patterns
Review the Exchange Requirements Table:
| Exchange | Auth Method | Critical Requirement | Common Error |
|----------|------------|---------------------|-------------|
| Binance | HMAC-SHA256 | Signature LAST in params | Wrong param order |
| Kraken | Nonce | Microsecond + counter | Using only microseconds |
| Deribit | OAuth2 | Refresh 120s before expiry | Token expiration |

Questions:
- Are these the most critical requirements for each exchange?
- What other exchange-specific gotchas should we document?
- Is our approach to handle these requirements optimal?

### 3. Plugin Architecture
Based on the task sequence (Day 1-5):
- Is our Core modules approach (thin coordination layer) correct?
- Should behaviors be more or less prescriptive?
- Are we missing critical production features?
- How would you structure the 33 tasks differently?

### 4. Common AI Coder Mistakes Section
We document 4 common mistakes:
1. Using Req for WebSocket (wrong - use zen_websocket)
2. Manual request manipulation instead of Req functions
3. GenServer state for counters instead of ETS atomic
4. Implementing everything at once

Are these the right mistakes to highlight? What others should we add?

### 5. Performance & Scalability
Our targets:
- Rate limiter: <1ms per check
- 10,000 concurrent requests: <100ms
- Memory growth: <1MB under load
- ETS cleanup: Every 60 seconds

Are these realistic? What benchmarks would you recommend?

## Specific Questions

1. **One-Task-Per-Session Rule**: We enforce completing one task at a time for AI coders. Is this too restrictive or beneficial for quality?

2. **Documentation Approach**: We reduced 2,346 lines to 242. Did we cut too much essential information?

3. **Essential Patterns**: Are our 4 HTTP/testing patterns the right ones to highlight, or should we include others?

4. **Req.Test**: Should we prioritize Req.Test stubs over real API testing for unit tests?

5. **Task Prioritization**: Current task is #2 (Core.HTTP refactoring). Should we prioritize differently?

6. **Missing Components**: What critical components are we not considering?

## Expected Output

Please provide:

### 1. Architecture Assessment (1-10 rating)
- Strengths of the streamlined approach
- Critical gaps in the essential patterns
- Missing architectural components

### 2. Req Usage Improvements
- Specific Req features we're underutilizing
- Better patterns for our 5 essential examples
- Advanced Req techniques for production

### 3. CEX Integration Insights
- Exchange-specific issues not covered
- Better auth/rate limiting strategies
- Production gotchas from your experience

### 4. Priority Fixes
- Top 5 issues in our current approach
- Which of the 33 tasks to prioritize
- What tasks to add or remove

### 5. Code Improvements
- Better versions of our essential patterns
- Missing patterns we should add
- Production-ready enhancements

## Context
This library is being built for:
- Production cryptocurrency trading systems
- High-frequency operations (10,000+ req/s)
- Multi-exchange arbitrage and market making
- Easy extension with new exchanges

The documentation is optimized for AI-assisted development, hence the directive style and minimal examples.

## Review Focus
Please focus on:
1. **Production readiness** - Will this architecture handle real trading volumes?
2. **Req optimization** - Are we using Req's full potential?
3. **Exchange quirks** - What CEX-specific issues will bite us?
4. **Documentation completeness** - Is 242 lines enough for AI coders?

## Start Your Review
Begin by reading the entire AI-IMPLEMENTATION.md document and provide your initial assessment of our approach, especially:
- The essential HTTP and testing patterns
- The one-task-per-session rule
- The current architecture at 21.2% complete
- Whether our streamlined approach loses critical information

Please be direct and critical. We want honest expert feedback to build a world-class CEX integration library that can be efficiently implemented by AI coders.