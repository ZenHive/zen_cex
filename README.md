# ZenCex

A comprehensive Elixir library for centralized cryptocurrency exchange (CEX) integrations, providing unified REST and WebSocket access with built-in safety features and optimized performance.

## Features

- **Multi-Exchange Support**: Binance (fully implemented), Bybit (trading complete)
- **REST + WebSocket**: Full support for both HTTP APIs and real-time WebSocket streams
- **Unified API Interface**: Consistent function naming across exchanges
- **Built-in Safety Features**: Rate limiting, clock synchronization, order safety checks
- **Req-Centric Architecture**: Leverages Req's powerful HTTP client capabilities
- **zen_websocket Integration**: Battle-tested WebSocket client with automatic reconnection
- **Comprehensive Market Coverage**: Spot, margin, futures (USD-M & COIN-M), portfolio margin
- **Real Testnet Testing**: All integration tests run against real exchange testnets
- **High-Level Strategies**: Pre-built trading strategies for hedging and rebalancing
- **Debug Mode**: Export failed requests as curl commands for troubleshooting

## Installation

Add `zen_cex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:zen_cex, "~> 0.1.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Configuration

### Authentication

**IMPORTANT**: ZenCex is a **library**, not an application. The library **NEVER** reads environment variables directly. You must always pass credentials explicitly via the `auth_credentials` option.

#### Explicit Credentials (Recommended Pattern)

```elixir
alias ZenCex.Adapters.Binance.Spot

# Pass credentials directly to each API call
{:ok, balances} = Spot.get_balances(%{}, [
  auth_credentials: %{
    api_key: "your_api_key",
    api_secret: "your_api_secret",
    testnet: true  # Optional: use testnet (default: false)
  }
])

# Works with any authenticated endpoint
{:ok, order} = Spot.place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "MARKET",
  quantity: "0.001"
}, [
  auth_credentials: %{
    api_key: "your_api_key",
    api_secret: "your_api_secret"
  }
])
```

#### Optional: Calling Code Reads Environment Variables

**Your application code** (not the library) can read environment variables and pass them to the library:

```elixir
# In your application code (NOT in the library)
defmodule MyApp.Binance do
  alias ZenCex.Adapters.Binance.Spot

  def get_balances do
    # Your code reads ENV
    api_key = System.get_env("BINANCE_API_KEY")
    api_secret = System.get_env("BINANCE_API_SECRET")

    # Your code passes to library
    Spot.get_balances(%{}, [
      auth_credentials: %{
        api_key: api_key,
        api_secret: api_secret
      }
    ])
  end
end
```

**Environment variables for testing:**
```bash
# These are read by test code and IEx helpers, NOT by the library
export BINANCE_TESTNET_API_KEY="your_testnet_key"
export BINANCE_TESTNET_API_SECRET="your_testnet_secret"
export BYBIT_TESTNET_API_KEY="your_testnet_key"
export BYBIT_TESTNET_API_SECRET="your_testnet_secret"
```

**Why this design?**
- Multi-account support: Different credentials per request
- No namespace collisions: Multiple apps can use zen_cex
- Testnet + production: Can connect to both simultaneously
- Flexible credential storage: ENV, vault, database, or dynamic generation

### Application Configuration

The library starts automatically with your application. Key components include:
- **Finch**: HTTP connection pooling (via Req)
- **OrderSafety**: Idempotency checks for safe order placement
- **ClockSync**: Synchronizes time with exchange servers
- **WebSocket Supervisor**: Manages WebSocket connections with automatic restart
- **ConnectionRegistry**: Tracks active WebSocket connections

Optional features can be configured in your `config.exs`:

```elixir
# Enable debug mode (dev/test only)
config :zen_cex, :debug,
  enabled: true,
  export_curl: true,
  log_level: :debug

# Enable circuit breaker (optional)
config :zen_cex, :circuit_breaker,
  enabled: true,
  binance: [
    failure_threshold: 5,
    failure_window: 60_000,
    reset_timeout: 30_000
  ]
```

<!-- AUTO-GENERATED SECTIONS START -->


## Binance Quick Start

Quick start examples for Binance API integration.


### Check Connectivity/0

Check server connectivity by getting server time.


```elixir
{:ok, time_data} = ZenCex.Examples.BinanceQuickStart.check_connectivity()
is_map(time_data)
```


### Get Account Balances/1

Get account balances using environment variable credentials.



### Get Balances With Credentials/1

Get balances using custom authentication credentials.



### Place Market Order/2

Place a simple market buy order with custom credentials.





## Credential Management

Authentication and credential management patterns for ZenCex.


### Manage Multiple Accounts/1

Manage multiple accounts by passing different credentials to each request.



### Rotate Credentials On Error/2

Implement credential rotation with automatic retry on authorization errors.



### Use Credentials From Env/0

Calling code reads environment variables, then passes to library.



### Use Explicit Credentials/3

Pass credentials explicitly to API calls (PRIMARY PATTERN).





## Binance Spot Trading

Complete spot trading workflow examples for Binance.


### Cancel All Orders/2

Cancel all open orders for a symbol.



### Cancel Order/3

Cancel an open order.



### Check Order Status/3

Check the status of an order.



### Get Current Balances/1

Get current account balances.



### Get Open Orders/2

Get all open orders for a symbol.



### Place Limit Buy/4

Place a limit buy order.



### Place Limit Sell/4

Place a limit sell order.



### Place Market Buy/3

Place a market buy order.





## Binance Futures Trading

Futures trading examples for Binance (USD-M and COIN-M).


### Get Coinm Positions/1

Get all COIN-M futures positions.



### Get Usdm Positions/1

Get all USD-M futures positions.



### Place Coinm Limit Order/5

Place a COIN-M futures limit order.



### Place Usdm Market Order/4

Place a USD-M futures market order.





## Binance Market Data

Market data fetching examples for Binance.


### Get 24hr Stats/1

Get 24-hour ticker statistics.



### Get Current Price/1

Get current ticker price for a symbol.



### Get Funding Rate/1

Get funding rate history for USD-M futures.



### Get Klines/3

Get candlestick/klines data.



### Get Open Interest/1

Get open interest for USD-M futures.



### Get Order Book/2

Get order book depth.



### Get Recent Trades/2

Get recent trades.





## Binance Websocket Streams

Example module demonstrating WebSocket streaming functionality with Binance.


### Check Connection Health/1

Gets comprehensive health information for a WebSocket connection.



### Close Connection/1

Closes a WebSocket connection.



### Connect Multiple Streams/2

Connects to multiple Binance WebSocket streams at once.



### Connect Single Stream/2

Connects to a single Binance WebSocket stream.



### Connect Supervised/2

Connects with supervision for production deployments.



### Connect With Retry/2

Connects with production-ready configuration including automatic reconnection.



### Get Cached Book Ticker Data/1

Gets cached book ticker data (best bid/ask) for a symbol.



### Get Cached Orderbook Data/1

Gets cached orderbook data for a symbol.



### Get Cached Ticker Data/1

Gets cached ticker data for a symbol.



### Get Cached Trade Data/1

Gets cached trade data for a symbol.



### Get Connection State/1

Gets the current state of a WebSocket connection.



### Reconnect Connection/1

Manually triggers a reconnection for the WebSocket client.



### Run Complete Example/0

Complete example showing the full WebSocket workflow.



### Run Monitoring Example/0

Example showing connection monitoring and health checks.



### Run Production Example/0

Production example demonstrating resilient WebSocket connections.



### Subscribe Additional/2

Subscribes to additional streams on an existing connection.





## Bybit Trading

Complete trading workflow examples for Bybit Unified API.


### Check Server Connectivity/0

Check server connectivity.



### Get Positions/2

Get positions for a specific category.



### Place Inverse Futures Order/6

Place an inverse futures limit order.



### Place Linear Futures Order/5

Place a linear futures market order.



### Place Spot Order/5

Place a spot market order.





## Binance Strategies

Example module demonstrating high-level trading strategies with Binance.


### Auto Hedge Spot Positions/2

Automatically hedge spot positions with futures contracts.



### Hedge With Paxg Long/1

Opens a PAXGUSDT perpetual long position equal to the total hedged portfolio value.



### Rebalance Portfolio/2

Rebalance portfolio to target allocation percentages.



### Run Complete Example/0

Complete example demonstrating the full hedging workflow.





## Production Rest Features

Demonstrates zen_cex's production-ready REST features for building resilient trading systems.


### Demonstrate Circuit Breaker/0

Demonstrates circuit breaker protection against cascading failures.


```elixir
ProductionRestFeatures.demonstrate_circuit_breaker()
```


### Demonstrate Clock Sync/0

Demonstrates clock synchronization for accurate authentication timestamps.


```elixir
ProductionRestFeatures.demonstrate_clock_sync()
```


### Demonstrate Debug Mode/0

Demonstrates debug mode for troubleshooting failed requests.


```elixir
ProductionRestFeatures.demonstrate_debug_mode()
```


### Demonstrate Operation Timeouts/0

Demonstrates operation-specific timeout optimization.


```elixir
ProductionRestFeatures.demonstrate_operation_timeouts()
```


### Demonstrate Rate Limiting/0

Demonstrates automatic rate limit tracking and enforcement.


```elixir
ProductionRestFeatures.demonstrate_rate_limiting()
```


### Demonstrate Telemetry/0

Demonstrates telemetry integration for monitoring.


```elixir
ProductionRestFeatures.demonstrate_telemetry()
```


### Run Production Workflow/0

Runs a complete production workflow demonstrating all resilience features.


```elixir
ProductionRestFeatures.run_production_workflow()
```




## Debug Troubleshooting

Debug mode and troubleshooting utilities for ZenCex API issues.


### Debug Failed Request/1

Make a failing API request to demonstrate debug capture.


```elixir
ZenCex.Examples.DebugTroubleshooting.enable_debug_mode()

ZenCex.Examples.DebugTroubleshooting.debug_failed_request(%{

{:ok, curl} = ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()
```


### Disable Debug Mode/0

Disable debug mode to stop capturing failed requests.


```elixir
ZenCex.Examples.DebugTroubleshooting.disable_debug_mode()
```


### Enable Debug Mode/0

Enable debug mode to capture failed requests.


```elixir
ZenCex.Examples.DebugTroubleshooting.enable_debug_mode()
```


### Get Debug Stats/0

Get debug statistics and captured request information.


```elixir
stats = ZenCex.Examples.DebugTroubleshooting.get_debug_stats()
IO.inspect(stats)
```


### Get Last Curl Command/0

Get the last failed request as a curl command.


```elixir
ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()

ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()
```




## Endpoint Discovery

Demonstrates endpoint introspection and discovery capabilities.


### Get Endpoint Details/2

Returns detailed information about a specific endpoint operation.


```elixir
{:ok, info} = ZenCex.Examples.EndpointDiscovery.get_endpoint_details(:get_balances, :spot)
info[:operation]

info[:requires_auth]

info[:api_type]

{:ok, info} = ZenCex.Examples.EndpointDiscovery.get_endpoint_details(:place_order, :spot)
info[:method]

info[:requires_auth]

ZenCex.Examples.EndpointDiscovery.get_endpoint_details(:nonexistent, :spot)
```


### List All Endpoints/0

Lists all available endpoint operations across all Binance API types.


```elixir
{:ok, endpoints} = ZenCex.Examples.EndpointDiscovery.list_all_endpoints()
:get_balances in endpoints

:place_order in endpoints

is_list(endpoints)
```


### List Futures Endpoints/0

Lists all available endpoint operations for USD-M Futures trading API.


```elixir
{:ok, endpoints} = ZenCex.Examples.EndpointDiscovery.list_futures_endpoints()
:get_positions in endpoints

:place_order in endpoints
```


### List Spot Endpoints/0

Lists all available endpoint operations for Spot trading API.


```elixir
{:ok, endpoints} = ZenCex.Examples.EndpointDiscovery.list_spot_endpoints()
:get_balances in endpoints

:place_order in endpoints
```



<!-- AUTO-GENERATED SECTIONS END -->

## Architecture

### Core Components

- **`Core.HTTP`**: Req-based HTTP client with middleware pipeline
- **`Core.Registry`**: Exchange registration and routing
- **`Core.RateLimiter`**: Base rate limiting implementation
- **`Safety.ClockSync`**: Time synchronization with exchanges
- **`Safety.OrderSafety`**: Idempotency and order validation

### Exchange Adapters

Each exchange adapter consists of:
- **API Modules**: Spot, Margin, Futures, etc. (use these directly)
- **Endpoints**: Registry module (for discovery only)
- **Auth**: Authentication and request signing
- **RateLimiter**: Exchange-specific rate limiting
- **Parser**: Response normalization

### Design Principles

1. **Req-Centric**: Leverages Req for HTTP, no custom client logic
2. **Stateless Operations**: ETS for rate limiting, no GenServers (except OAuth)
3. **Compile-Time Configuration**: Endpoint registry with runtime validation
4. **Real API Testing**: No mocks, only real testnet APIs
5. **Safety First**: Built-in rate limiting, clock sync, order validation

## API Coverage

### Binance
- ✅ **Spot Trading**: Complete (orders, balances, OCO)
- ✅ **Margin Trading**: Cross and isolated margin
- ✅ **USD-M Futures**: USDT-margined perpetuals
- ✅ **COIN-M Futures**: Coin-margined contracts
- ✅ **Portfolio Margin**: Unified account management
- ✅ **Market Data**: Tickers, order books, klines

### Bybit
- ✅ **Unified Trading**: All product types via category parameter
- ✅ **Spot Trading**: Complete order management
- ✅ **Linear Futures**: USDT perpetuals
- ✅ **Inverse Futures**: Coin-margined contracts
- 🚧 **Options**: To be implemented
- 🚧 **Market Data**: To be implemented

## Testing

The library uses real exchange testnet APIs for all integration tests:

```bash
# Run unit tests only (no API calls)
mix test --exclude integration

# Run all tests including integration (requires testnet credentials)
mix test

# Run specific exchange tests
mix test --only integration:binance
mix test --only integration:bybit

# Run with coverage
mix test --cover
mix coveralls.html
```

**Important**: Integration tests require testnet API credentials. Tests will fail (not skip) if credentials are missing, ensuring visibility of test coverage.

### Setting Up Testnet Accounts

1. **Binance Testnet**: https://testnet.binance.vision/
2. **Bybit Testnet**: https://testnet.bybit.com/

Generate API keys and set them as environment variables with `_TESTNET_` in the name.

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Format code
mix format

# Run static analysis
mix credo --strict

# Type checking
mix dialyzer

# Documentation coverage
mix doctor

# Generate docs
mix docs

# Pre-commit checks
mix precommit

# Generate README from examples
mix zen_cex.generate_readme
```

### Using Tidewave (Development Tool)

Tidewave provides an MCP server for enhanced development:

```bash
# Start Tidewave server
mix tidewave

# Now you can use MCP tools in your editor for:
# - Direct code evaluation in project context
# - Documentation lookup
# - Source navigation
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes (using real testnet APIs)
4. Ensure all tests pass (`mix test`)
5. Run pre-commit checks (`mix precommit`)
6. Commit your changes
7. Push to the branch
8. Create a Pull Request

## License

Copyright (c) 2024 ZenCex

Licensed under the MIT License. See LICENSE file for details.

## Support

For issues, questions, or contributions, please visit:
https://github.com/ZenHive/zen_cex
