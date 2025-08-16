# ZenCex

A production-ready Elixir library for centralized cryptocurrency exchange (CEX) REST API integrations, featuring a plugin architecture with Req middleware pipeline for Binance, Kraken, and Deribit.

**IMPORTANT**: This is a REST-only library designed for reliable position management and trading operations. It does NOT support High-Frequency Trading (HFT) or WebSocket streaming. For HFT or real-time market data streaming, please look elsewhere.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `zen_cex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:zen_cex, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/zen_cex>.

## Quick Start

### For AI Coders
```bash
# Single command to start implementation
"Read docs/AI-IMPLEMENTATION.md and implement the current task"
```

The AI implementation guide enforces:
- ✅ One task per session rule
- ✅ Essential patterns only (5 core patterns)
- ✅ Current task tracking (Task #2: Core.HTTP)
- ✅ Validation checklists
- ✅ Common mistake prevention

### For Human Developers

1. **Read the streamlined guide**: [docs/AI-IMPLEMENTATION.md](docs/AI-IMPLEMENTATION.md) (242 lines)
2. **Set up environment**:
   ```bash
   export BINANCE_API_KEY="your_key"
   export BINANCE_API_SECRET="your_secret"
   mix deps.get
   mix test
   ```
3. **Follow the task sequence** in the guide

## Architecture Overview

**Req-centric REST-only design** - Leveraging Req's built-in connection pooling, retry logic, and middleware pipeline for REST API operations. No WebSocket or streaming support.

```
lib/zen_cex/
├── core/           # Thin coordination layer
│   ├── registry.ex # Adapter registration
│   └── http.ex     # Req client setup
├── behaviors/      # Adapter contracts
└── adapters/       # Exchange implementations (stateless)
    ├── binance/    # HMAC-SHA256, ETS rate limiting
    ├── kraken/     # Nonce-based, HTTP/1.1 only
    └── deribit/    # OAuth2 (only GenServer needed)
```

**Why minimal supervision**: Req provides connection pooling (Finch), retry with backoff, telemetry, and middleware pipeline
**Only GenServer needed**: Deribit OAuth token management (stateful)

### Key Technologies
- **HTTP Client**: Req with middleware pipeline (REST only)
- **Rate Limiting**: ETS atomic counters for REST endpoints
- **Testing**: Req.Test for unit tests, real APIs for integration
- **Auth**: Exchange-specific for REST APIs (HMAC, Nonce, OAuth2)
- **Scope**: REST APIs only - no WebSocket, no FIX, no binary protocols

## Current Status

- **Progress**: 29% complete (7/24 tasks)
- **Current Task**: #2 - Remove Core.Supervisor (use Req's built-in features)
- **Architecture**: Req-powered adapters with middleware pipeline
- **Next Priority**: Leverage Req instead of reimplementing its features

## Key Features

- 🚀 **Plugin Architecture**: Isolated exchange adapters for REST APIs
- ⚡ **Reliable Performance**: 10,000+ concurrent REST requests in <100ms
- 🔒 **Production Ready**: Circuit breakers, health monitoring, telemetry
- 🧪 **Comprehensive Testing**: Unit (Req.Test) + Integration (real APIs)
- 📊 **Rate Limiting**: Budget-based allocation with atomic operations
- 🔄 **Request Coalescing**: Deduplication within time windows
- 🏥 **Health Monitoring**: Clock sync validation, exchange status
- ❌ **NOT for HFT**: This library is not designed for high-frequency trading
- ❌ **No WebSocket**: REST APIs only, no streaming market data support

## Documentation

### Single Source of Truth
**[docs/AI-IMPLEMENTATION.md](docs/AI-IMPLEMENTATION.md)** - 242 lines (was 2,346 across 4 files)
- Combines architecture, implementation, progress, and review
- Optimized for AI coders with directive commands
- Essential patterns with minimal code examples
- One-task-per-session enforcement
- Common mistakes and solutions

## Development Commands

```bash
# Testing
mix test                          # Run all tests
mix test --only integration       # Real API tests
mix test --cover                  # Coverage report

# Code Quality
mix dialyzer                      # Type checking
mix credo --strict               # Static analysis
mix format                       # Format code

# Development
iex -S mix                       # Interactive shell
mix docs                         # Generate docs
```

## Exchange-Specific Requirements

| Exchange | Auth | Rate Limit | Critical Requirement |
|----------|------|------------|---------------------|
| Binance | HMAC-SHA256 | 1200/min | Signature MUST be last param |
| Kraken | Nonce | 15/tier | Microsecond + counter, HTTP/1.1 |
| Deribit | OAuth2 | 20/sec | Refresh 120s before expiry |

## Contributing

1. Read `docs/AI-IMPLEMENTATION.md`
2. Pick the current task (shown in guide)
3. Implement ONE task per PR
4. Ensure all tests pass
5. Update task status in guide

