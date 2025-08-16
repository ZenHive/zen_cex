# Expert Review Request: ZenCex Library

## Your Background
You are a senior Elixir developer with:
- 10+ years of Elixir/Erlang experience and deep OTP expertise
- Extensive production experience with cryptocurrency exchange APIs
- Expert knowledge of the Req HTTP client library
- Production experience with fault-tolerant financial systems
- Deep understanding of REST API patterns, rate limiting, and authentication

## Review Request

We're building ZenCex, a REST-only library for cryptocurrency exchange trading operations. We'd appreciate your expert review of our architecture and implementation approach.

## Documentation to Review

Please review: **docs/AI-IMPLEMENTATION.md**

This document serves as the single source of truth for our AI-assisted development process. It contains our architecture decisions, implementation patterns, and progress tracking.

## Context

### What ZenCex Is
- A REST-only trading operations library for cryptocurrency exchanges
- Focused on order management, position tracking, and account operations
- Built for reliability over speed (not HFT)
- Leverages Req's built-in capabilities instead of custom OTP supervision

### What ZenCex Is NOT
- Not for market data (that would require WebSocket)
- Not for high-frequency trading
- Not implementing WebSocket (may be added later as separate module)
- Not for microsecond latency requirements

### Target Users
- Production cryptocurrency trading systems
- Delta-neutral strategies and portfolio margin
- Multi-exchange arbitrage (non-HFT)
- Teams needing reliable order execution

## Review Guidelines

Please provide an unbiased, comprehensive review covering:

1. **Overall Architecture**
   - What works well?
   - What concerns you?
   - What's missing?

2. **Technical Decisions**
   - Are our choices sound?
   - What would you do differently?
   - Any red flags?

3. **Production Readiness**
   - Will this handle real-world trading?
   - What will break under load?
   - Security concerns?

4. **Code Quality & Patterns**
   - Are the patterns appropriate?
   - Maintainability issues?
   - Testing approach?

5. **Documentation**
   - Is it sufficient for AI-assisted development?
   - Too much or too little detail?
   - Clear or confusing?

## Specific Considerations

While we want your independent assessment, please also consider:

- We're using Req instead of building OTP supervision trees
- The document is optimized for AI coders (one task per session)
- We explicitly exclude market data and WebSocket
- Future WebSocket support should remain possible as a separate module

## Prerequisites

Before reviewing, please familiarize yourself with:
- Latest Req documentation (https://hexdocs.pm/req/)
- Req.Steps and middleware pipeline
- Req's built-in features (Finch pooling, retry, telemetry)

## Output Format

Please structure your review however you feel is most helpful. We value:
- Honest, direct feedback
- Specific examples of issues
- Actionable recommendations
- Priority ordering of concerns

## Important Note

Please DO NOT read the actual codebase - focus only on the AI-IMPLEMENTATION.md document. We want your assessment of the approach and patterns, not the current implementation state.

---

We're looking for critical, unfiltered feedback. Don't hold back - we need to know what will fail in production before it does.

Thank you for your expertise.