# Expert Review Request: ZenCex Library

## Your Background
You are a senior Elixir developer with:
- 10+ years of Elixir/Erlang experience and deep OTP expertise
- Extensive production experience with cryptocurrency exchange APIs
- Expert knowledge of the Req HTTP client library
- Production experience with fault-tolerant financial systems
- Deep understanding of REST API patterns, rate limiting, and authentication

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

## Review Request

We're building ZenCex, a REST-only library for cryptocurrency exchange trading operations. We'd appreciate your expert review of our architecture and implementation approach.

## Documentation to Review

Please review the following two documents that work together:

1. **docs/AI-IMPLEMENTATION.md** - Task guide for AI Coders (201 lines)
2. **docs/AI-REVIEW.md** - Review checklist for AI Reviewers (700+ lines)

These documents implement an AI-to-AI workflow where:
- AI Coders implement tasks using the streamlined AI-IMPLEMENTATION.md
- AI Reviewers validate implementations using the comprehensive AI-REVIEW.md
- Humans supervise the overall process

To see the recent restructuring, you can run:
```bash
git diff docs/AI-IMPLEMENTATION.md
git diff docs/AI-REVIEW.md  # (new file)
```

## Context

### What ZenCex Is
- A REST-only trading operations library for cryptocurrency exchanges
- Focused on order management, position tracking, and account operations
- Built for reliability over speed (not HFT)
- Market Making where elixir is used to implement strategies
- Leverages Req's built-in capabilities instead of custom OTP supervision
- Uses a **Declarative Endpoint Registry** pattern instead of traditional adapters

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

### Recent Architectural Change
We've moved from traditional `adapter.ex` files to a **Declarative Endpoint Registry** pattern:
- Old: `lib/zen_cex/adapters/{exchange}/adapter.ex` with behavior implementations
- New: `lib/zen_cex/adapters/{exchange}/endpoints.ex` using `ZenCex.EndpointRegistry` macro
- This provides compile-time safety, automatic function generation, and better maintainability

## Review Guidelines

Please provide an unbiased, comprehensive review of both documents covering:

1. **Documentation Structure**
   - Is the split between implementation and review effective?
   - Are the documents appropriately sized for their purposes?
   - Is the AI-to-AI workflow clear and practical?

2. **Technical Content**
   - Are the safety patterns comprehensive?
   - Are the requirements clear and testable?
   - Are there any critical gaps?
   - **Does the new Endpoint Registry pattern properly documented?**
   - **Should references to "adapter.ex" be updated to "endpoints.ex"?**

3. **Usability**
   - Can an AI Coder effectively implement tasks with AI-IMPLEMENTATION.md?
   - Can an AI Reviewer effectively validate with AI-REVIEW.md?
   - Is the workflow sustainable?

4. **Production Readiness**
   - Do the patterns address real-world trading issues?
   - Are the safety mechanisms sufficient?
   - What could go wrong?

5. **Architectural Consistency**
   - Review AI-IMPLEMENTATION.md and AI-REVIEW.md for outdated adapter references
   - Ensure the Declarative Endpoint Registry pattern is properly explained
   - Check if examples need updating to reflect the new architecture

## Specific Considerations

While we want your independent assessment, please also consider:

- The documents are designed for AI agents, not human developers
- The one-task-per-session rule is intentional for quality control
- The REST-only scope is a deliberate architectural decision
- We're using Req instead of building OTP supervision trees

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
- Assessment of whether this approach will work in practice

## Important Note

These documents are designed specifically for AI-assisted development. The workflow assumes AI agents will be doing the implementation and review, with human oversight. Please evaluate them in this context.

---

We're looking for critical, unfiltered feedback. Don't hold back - we need to know if this approach will work before deploying it.


REMEMBER WE ARE STILL PLANNING, WE CAN NOT PLAN EVERYTHING to 100%. We need a place to start, and we need to be able to code and iterate quickly.
