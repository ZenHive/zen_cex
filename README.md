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

### AI-Assisted Development Workflow

This project uses a two-document AI workflow:

1. **AI Coder**: Uses [docs/AI-IMPLEMENTATION.md](docs/AI-IMPLEMENTATION.md) (201 lines) to implement tasks
2. **AI Reviewer**: Uses [docs/AI-REVIEW.md](docs/AI-REVIEW.md) (700+ lines) to validate implementations

#### For AI Coders
```bash
# Start with the current task
"Read docs/AI-IMPLEMENTATION.md and implement the current task"
```

The implementation guide provides:
- ✅ One task per session rule (critical for quality)
- ✅ Current task assignment (Task #1: OrderSafety)
- ✅ Quick pattern references (5-10 lines each)
- ✅ Common mistakes to avoid
- ✅ Clear success criteria

#### For AI Reviewers
```bash
# Review completed implementations
"Read docs/AI-REVIEW.md and validate the implementation"
```

The review guide provides:
- ✅ Detailed checklists per task
- ✅ Full pattern implementations
- ✅ Performance targets
- ✅ Security requirements
- ✅ Pass/fail criteria

### For Human Developers

1. **Set up environment**:
   ```bash
   export BINANCE_API_KEY="your_key"
   export BINANCE_API_SECRET="your_secret"
   mix deps.get
   mix test
   ```
2. **Follow the workflow**: Implementation → Review → Deploy
3. **Monitor progress**: Check task completion in AI-IMPLEMENTATION.md

## Architecture Overview

**Adapter Pattern with Req-centric REST Design** - Each exchange adapter consists of multiple cooperating modules that collectively adapt external APIs to ZenCex's unified interface.

```
lib/zen_cex/
├── core/                    # Thin coordination layer
│   ├── registry.ex         # Maps exchanges to endpoint modules
│   ├── http.ex            # Req client with middleware pipeline
│   └── endpoint_registry.ex # Macro for declarative endpoints
├── behaviors/              # Contracts for adapter modules
└── adapters/               # Exchange adapters (collection of modules)
    ├── binance/            # Binance adapter modules
    │   ├── endpoints.ex    # Main entry point (uses EndpointRegistry)
    │   ├── auth.ex        # HMAC-SHA256 authentication
    │   ├── rate_limiter.ex # ETS-based rate limiting
    │   └── parser.ex      # Response normalization
    ├── kraken/            # (Future: Nonce-based, HTTP/1.1)
    └── deribit/           # (Future: OAuth2 with GenServer)
```

### Why "Adapters"?
The `Adapters` namespace accurately reflects that these modules work together to adapt external exchange APIs to ZenCex's interface. Each adapter is not just endpoints, but a complete integration package.

**Why minimal supervision**: Req provides connection pooling (Finch), retry with backoff, telemetry, and middleware pipeline
**Only GenServer needed**: Deribit OAuth token management (stateful)

### Key Technologies
- **HTTP Client**: Req with middleware pipeline (REST only)
- **Rate Limiting**: ETS atomic counters for REST endpoints
- **Testing**: Req.Test for unit tests, real APIs for integration
- **Auth**: Exchange-specific for REST APIs (HMAC, Nonce, OAuth2)
- **Scope**: REST APIs only - no WebSocket, no FIX, no binary protocols

## Current Status

- **Architecture**: Declarative Endpoint Registry with Req middleware pipeline
- **Binance**: Fully implemented with EndpointRegistry pattern
- **Kraken/Deribit**: Planned, following the same adapter structure
- **Focus**: REST APIs only - no WebSocket/streaming support

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

### Telemetry and Monitoring
**[docs/TELEMETRY.md](docs/TELEMETRY.md)** - Comprehensive telemetry guide
- Event architecture (Finch → Req → ZenCex events)
- All available telemetry events with measurements and metadata
- Production monitoring patterns and alert thresholds
- Phoenix LiveDashboard integration

**[examples/telemetry_handlers.ex](examples/telemetry_handlers.ex)** - Production-ready handlers
- Request logger with performance tracking
- Error tracker with full context
- Rate limit monitor with utilization warnings
- Performance reporter with in-memory statistics
- Circuit breaker alerts for critical failures

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

## Monitoring & Observability

ZenCex provides comprehensive telemetry for production monitoring:

### Quick Setup
```elixir
# In your application.ex
def start(_type, _args) do
  # Attach default telemetry handlers
  ZenCex.Core.Telemetry.attach_default_handlers()
  
  # Or use example handlers
  ZenCex.Examples.TelemetryHandlers.attach_all()
  
  # ... rest of supervision tree
end
```

### Available Events
- **Request metrics**: Duration, status, errors
- **Rate limiting**: Utilization, violations
- **Circuit breaker**: State changes, rejections
- **Order operations**: Placement, cancellation, idempotency
- **Connection pooling**: Reuse, timeouts (via Finch)

### Phoenix LiveDashboard Integration
```elixir
# In your telemetry.ex
def metrics do
  ZenCex.Examples.TelemetryDashboard.metrics()
end
```

See [docs/TELEMETRY.md](docs/TELEMETRY.md) for complete documentation.

## Debug Mode

ZenCex includes a powerful debug mode for development and troubleshooting:

### Features
- Export failed requests as curl commands for easy reproduction
- Capture and store recent failed requests for analysis
- Telemetry integration for debug events
- Automatic cleanup of old debug data

### Quick Setup
```elixir
# Enable debug mode in config/dev.exs
config :zen_cex, :debug,
  enabled: true,        # Enable debug mode
  export_curl: true,    # Export failed requests as curl
  log_level: :debug     # Log level for debug output

# Or enable at runtime
ZenCex.Core.Debug.enable()
```

### Usage Examples
```elixir
# When a request fails, the curl command is automatically logged
# [warning] [ZenCex.Debug] Request failed: {:error, :invalid_symbol}
# 
# Reproduce with curl:
# curl -X GET -H 'X-MBX-APIKEY: xxx' 'https://api.binance.com/api/v3/account'

# Get the last failed request as curl
{:ok, curl_command} = ZenCex.Core.Debug.get_last_curl()
IO.puts(curl_command)  # Copy and run in terminal

# Get recent failed requests
commands = ZenCex.Core.Debug.get_recent_curls(5)
Enum.each(commands, &IO.puts/1)

# Check debug statistics
stats = ZenCex.Core.Debug.stats()
# => %{
#   total_captured: 3,
#   debug_enabled: true,
#   curl_export_enabled: true,
#   recent_errors: [...]
# }
```

### Installation
Debug mode requires the optional `curl_req` dependency:
```elixir
# In mix.exs (already included as optional)
{:curl_req, "~> 0.98", only: [:dev, :test], optional: true}
```

**Note**: Debug mode is only available in `:dev` and `:test` environments.

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

