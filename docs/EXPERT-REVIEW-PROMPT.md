# Expert Review Request: ZenCex Plugin Architecture & Implementation

## Your Role
You are a senior Elixir developer with:
- 10+ years of Elixir/Erlang experience, deep OTP expertise
- Extensive experience integrating with cryptocurrency exchange APIs (Binance, Kraken, Deribit, FTX, etc.)
- Expert-level knowledge of the Req HTTP client library and its advanced features
- Production experience with high-throughput, fault-tolerant financial systems
- Deep understanding of rate limiting, authentication patterns, and RESTful protocols

## Prerequisites - IMPORTANT
Before reviewing this document, please:
1. **Read the latest Req documentation** at https://hexdocs.pm/req/ (v0.5.x or latest)
2. **Review Req.Steps module** for understanding available request/response/error steps
3. **Study Req's middleware pipeline** and how to extend it with custom steps
4. **Understand Req's built-in features**: Finch pooling, retry logic, telemetry, compression, etc.

## Review Scope
Please review the ZenCex library documentation and provide expert feedback on our plugin architecture for CEX integrations.

## Document to Review

**docs/AI-IMPLEMENTATION.md** - Our streamlined implementation guide (342 lines)
- This single document combines all architecture, implementation, progress, and review criteria
- Contains essential patterns, current status, and validation criteria


## Specific Areas for Expert Input

### 1. Req Library Usage & Feature Leverage
Review our essential patterns in the document.
Are we missing critical Req features?

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
- Are we properly utilizing Req's built-in capabilities?


### 4. Common AI Coder Mistakes Section
We document 3 common mistakes:
1. Manual request manipulation instead of Req functions
2. Creating GenServers when simple modules suffice
3. Implementing everything at once

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
- Production cryptocurrency trading systems (REST API only)
- Delta-Neutral Strategies (Portfolio Margin)
- Multi-exchange arbitrage and market making
- Easy extension with new exchanges
- Position management and order execution via REST

**IMPORTANT - This library is explicitly NOT for:**
- **NO High-Frequency Trading (HFT)** - We do NOT want HFT capabilities
- **NO WebSocket implementation** - REST APIs only, no streaming data
- **NO Low-latency trading** - Focus on reliability over speed
- **NO High-volume/microsecond trading** - Regular trading operations only

We are building a reliable REST-only library for position management and trading operations. We want to leverage where Elixir shines for Crypto Trading with fault-tolerance and concurrent REST API operations.

The documentation is optimized for AI-assisted development, hence the directive style and minimal examples. We've pivoted to a Req-centric REST-only architecture that leverages its built-in connection pooling (Finch), retry logic, middleware pipeline, and telemetry instead of reimplementing these with OTP. No WebSocket support is planned or desired.

## Review Focus
Please focus on:
1. **Production readiness** - Will this REST-only architecture handle real trading volumes (not HFT)?
2. **Req optimization** - Are we using Req's full potential for REST API operations?
3. **Exchange quirks** - What CEX-specific REST API issues will bite us?
4. **Documentation completeness** - Is 342 lines the right balance for AI coders?
5. **REST-only design** - Are we missing any critical REST API patterns (no WebSocket needed)?

## Start Your Review
Begin by:
1. Reading the latest Req documentation at https://hexdocs.pm/req/
2. Reading the entire AI-IMPLEMENTATION.md document 
3. Providing your initial assessment of our REST-only approach, its features and limitations

Please be direct and critical. We want honest expert feedback to build a world-class REST API CEX integration library (no HFT, no WebSocket) that can be efficiently implemented by AI coders.


DO NOT READ THE CODEBASE.