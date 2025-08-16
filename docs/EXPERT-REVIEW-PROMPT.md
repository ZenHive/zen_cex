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

**docs/AI-IMPLEMENTATION.md** - Our streamlined implementation guide (342 lines)
- This single document combines all architecture, implementation, progress, and review criteria
- Previously 2,346 lines across 4 files, now optimized for clarity
- Contains essential patterns, current status, and validation criteria

Please analyze this document for:
- **Architecture Assessment**: Is leveraging Req's built-in features instead of OTP supervision correct?
- **Implementation Patterns**: Are the 4 essential patterns utilizing Req properly?
- **Progress Evaluation**: At 29% complete (7/24 tasks), are we on the right track?
- **Review Criteria**: Is removing Core.Supervisor justified given Req's capabilities?

## Specific Areas for Expert Input

### 1. Req Library Usage & Feature Leverage
Review our essential patterns in the document:
- **Pattern 1**: Auth as Req request step - Is returning `{request, options}` tuple correct?
- **Pattern 2**: Rate limiter as middleware - Should we halt the pipeline this way?
- **Pattern 3**: ETS tables without GenServer - Does Req's pipeline make this viable?
- **Pattern 4**: Req.Test for unit testing - Should we use this for deterministic tests?

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

### 3. Req-Centric Architecture
Based on leveraging Req's features:
- Is removing Core.Supervisor justified since Req provides pooling, retry, telemetry?
- Do rate limiters work better as Req middleware with ETS than as GenServers?
- Is having only Deribit.Auth as a GenServer correct (stateful OAuth)?
- Are we properly utilizing Req's built-in capabilities?

### 4. Leveraging Req's Built-in Capabilities
We're removing OTP supervision because Req provides:
- **Connection pooling** via Finch integration
- **Retry logic** with exponential backoff
- **Middleware pipeline** for auth, rate limiting, telemetry
- **Built-in observability** through telemetry events

Only Deribit.Auth needs GenServer (OAuth state). Is this the right approach?

### 5. Common AI Coder Mistakes Section
We document 4 common mistakes:
1. Using Req for WebSocket (wrong - use zen_websocket)
2. Manual request manipulation instead of Req functions
3. Creating GenServers when simple modules suffice
4. Implementing everything at once

Are these the right mistakes to highlight? What others should we add?

### 6. Performance & Scalability
Our targets:
- Rate limiter: <1ms per check
- 10,000 concurrent requests: <100ms
- Memory growth: <1MB under load
- ETS cleanup: Every 60 seconds

Are these realistic? What benchmarks would you recommend?

## Specific Questions

1. **One-Task-Per-Session Rule**: We enforce completing one task at a time for AI coders. Is this too restrictive or beneficial for quality?

2. **Documentation Approach**: We reduced 2,346 lines to 342. Did we cut too much essential information?

3. **Essential Patterns**: Are our 4 HTTP/testing patterns the right ones to highlight, or should we include others?

4. **Req.Test**: Should we prioritize Req.Test stubs over real API testing for unit tests?

5. **Task Prioritization**: Current task is #2 (Remove Core.Supervisor to use Req features). Is leveraging Req's capabilities the right priority?

6. **Missing Components**: What critical components are we not considering?

7. **Req vs OTP Trade-offs**: By relying on Req's features instead of OTP supervision, what failure modes might we miss? Does Req's retry and pooling sufficiently replace supervision trees for HTTP operations?

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
- **NEW**: Maximum simplicity - modules over processes

The documentation is optimized for AI-assisted development, hence the directive style and minimal examples. We've pivoted to a Req-centric architecture that leverages its built-in connection pooling (Finch), retry logic, middleware pipeline, and telemetry instead of reimplementing these with OTP.

## Review Focus
Please focus on:
1. **Production readiness** - Will this architecture handle real trading volumes?
2. **Req optimization** - Are we using Req's full potential?
3. **Exchange quirks** - What CEX-specific issues will bite us?
4. **Documentation completeness** - Is 342 lines the right balance for AI coders?

## Start Your Review
Begin by reading the entire AI-IMPLEMENTATION.md document and provide your initial assessment of our approach, especially:
- The Req-centric architecture (leveraging built-in pooling, retry, telemetry)
- Whether removing OTP supervision makes sense given Req's capabilities
- The essential HTTP and testing patterns using Req features
- The one-task-per-session rule for AI development
- Whether we're properly utilizing Req instead of reimplementing its features

Please be direct and critical. We want honest expert feedback to build a world-class CEX integration library that can be efficiently implemented by AI coders.