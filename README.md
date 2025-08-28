# ZenCex

A configurable Elixir library for cryptocurrency exchange REST APIs, featuring compile-time endpoint selection and focused on Binance and Bybit integrations.

**Key Features**:
- 🎯 **Configurable Compilation** - Ship all endpoints, compile only what you need
- 📊 **Market Data & Trading** - Prices, order books, positions, and order management  
- 🏦 **Two Major Exchanges** - Binance and Bybit (80%+ of global volume)
- ⚡ **REST-Only Design** - Perfect for position monitoring, hedging, and portfolio management
- 🔒 **Production Ready** - Rate limiting, clock sync, comprehensive error handling

**Perfect for**: Position monitoring (30s-5min intervals), portfolio hedging, subaccount management, and automated trading strategies. **NOT for HFT** or microsecond latency requirements.

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

### Configuration (Coming Soon)

Configure which endpoints to compile in your application:

```elixir
# config/config.exs
config :zen_cex, :endpoints, %{
  binance: %{
    market_data: [:get_ticker_price, :get_order_book],
    spot: [:get_balances, :place_order, :cancel_order],
    usdm_futures: :all  # Include all USDM futures endpoints
  },
  bybit: %{
    market_data: :all,
    unified: [:get_positions, :place_order]
  }
}
```

### Basic Usage

```elixir
# Market data (no auth required)
{:ok, price} = ZenCex.Binance.spot_get_ticker_price("BTCUSDT")
{:ok, orderbook} = ZenCex.Bybit.get_orderbook("BTCUSDT")

# Trading (requires API keys)
{:ok, balances} = ZenCex.Binance.spot_get_balances()
{:ok, positions} = ZenCex.Binance.usdm_get_position_risk()

# Place orders
{:ok, order} = ZenCex.Binance.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: "0.001",
  price: "40000"
})
```

### Development Workflow

See [docs/refactoring_sessions.md](docs/refactoring_sessions.md) for the current implementation plan and architecture details.

## Environment Setup

```bash
# Production credentials
export BINANCE_API_KEY="your_key"
export BINANCE_API_SECRET="your_secret"
export BYBIT_API_KEY="your_key"
export BYBIT_API_SECRET="your_secret"

# Testnet credentials (for testing)
export BINANCE_TESTNET_API_KEY="your_testnet_key"
export BINANCE_TESTNET_API_SECRET="your_testnet_secret"

mix deps.get
mix test
```

## Architecture Overview

**Adapter Pattern with Req-centric REST Design** - Each exchange adapter consists of multiple cooperating modules that collectively adapt external APIs to ZenCex's unified interface.

### Key Design Principles

- **Configurable Compilation**: Select endpoints at compile time for optimal performance
- **Req-Centric**: Leverages Req's connection pooling, retry, and middleware
- **ETS for State**: Rate limiting uses atomic counters, no GenServers needed
- **Testnet-First Testing**: All tests run against real testnet APIs
- **Declarative Endpoints**: Use `@endpoints` pattern for standard operations
- **Generated Code**: Macro-based function generation from endpoint specs

### Key Technologies
- **HTTP Client**: Req with middleware pipeline (REST only)
- **Rate Limiting**: ETS atomic counters for REST endpoints
- **Order Safety**: Pre-trade validation with balance checks, symbol validation, kill switches
- **Idempotency**: 30-minute sliding window duplicate protection

## Order Safety Features

```elixir
# Comprehensive pre-trade validation
order_params = %{
  symbol: "BTCUSDT",
  side: :buy,
  quantity: "0.001",
  price: "50000.00"
}

case ZenCex.Safety.OrderSafety.validate_order(:binance, order_params) do
  {:ok, validated_params} ->
    # Order is safe to place
    Binance.Endpoints.spot_place_order(validated_params)
  
  {:error, :kill_switch_active} ->
    # Trading disabled globally
    
  {:error, {:insufficient_balance, details}} ->
    # Not enough funds
    
  {:error, :duplicate} ->
    # Order already exists (idempotency check)
end

# Emergency kill switch
ZenCex.Safety.OrderSafety.set_kill_switch(:binance, false)  # Disable all trading
ZenCex.Safety.OrderSafety.set_kill_switch(:binance, true)   # Re-enable trading
```
- **Testing**: Req.Test for unit tests, real APIs for integration
- **Auth**: Exchange-specific for REST APIs (HMAC, Nonce, OAuth2)
- **Scope**: REST APIs only - no WebSocket, no FIX, no binary protocols

## Current Status

- ✅ **Binance**: Spot, margin, futures implemented (missing: market data endpoints)
- ✅ **Bybit**: Unified V5 trading implemented (missing: market data, options)
- 🚧 **Market Data**: To be added for both exchanges (prices, order books, klines)
- 🎯 **Configurable**: Compile-time endpoint selection (coming soon)

## Use Cases

This library is perfect for:
- **Position Monitoring**: Check balances and positions every 30s-5min
- **Portfolio Hedging**: Calculate exposure and place hedge orders
- **Automated Trading**: Execute trades based on signals or conditions
- **Risk Management**: Monitor PnL and adjust positions accordingly
- **Market Analysis**: Collect OHLCV data for technical indicators

Not suitable for:
- High-frequency trading (use WebSocket/FIX for that)
- Market making with microsecond requirements
- Real-time order book streaming
## Documentation

### Current Focus
**[docs/refactoring_sessions.md](docs/refactoring_sessions.md)** - Implementation roadmap
- Configurable endpoint architecture
- Session-based development plan
- Market data and trading endpoints
- Binance and Bybit focus

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

## Emergency Bypass (Safety Feature)

ZenCex implements an emergency bypass system to ensure critical safety operations can always execute, even during rate limit pressure:

### How It Works
- **10% Capacity Reserved**: Regular operations can use up to 90% of rate limit capacity
- **Emergency Operations Always Execute**: Cancel orders and close positions bypass limits
- **Automatic Detection**: Operations identified by function name or endpoint pattern

### Protected Operations
- Order cancellation (single, batch, all)
- Position closing
- Risk management operations
- Any operation matching: `:cancel_*`, `:close_*` patterns

### Example
```elixir
# Regular operations respect 90% capacity limit
{:error, {:rate_limited, retry_after}} = Binance.Endpoints.get_ticker(symbol: "BTCUSDT")

# Emergency operations always execute
{:ok, _} = Binance.Endpoints.cancel_order(symbol: "BTCUSDT", order_id: "12345")
{:ok, _} = Binance.Endpoints.cancel_all_orders(symbol: "BTCUSDT")
```

This ensures traders can always exit positions and manage risk, even under extreme load.

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

| Exchange | Auth | Rate Limit | Testnet | Status |
|----------|------|------------|---------|---------|
| Binance | HMAC-SHA256 | 1200/min | testnet.binance.vision | ✅ Trading Complete, 🚧 Market Data |
| Bybit | HMAC-SHA256 | Variable | api-testnet.bybit.com | ✅ Trading Complete, 🚧 Market Data & Options |

## Contributing

1. Read `docs/refactoring_sessions.md` for the development plan
2. Follow the session-based approach
3. Test against real testnet APIs
4. Ensure all tests pass
5. Update task status in the roadmap

