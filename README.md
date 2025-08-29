# ZenCex

A comprehensive Elixir library for centralized cryptocurrency exchange (CEX) REST API integrations, providing unified access to multiple exchanges with built-in safety features and optimized performance.

## Features

- **Multi-Exchange Support**: Binance (fully implemented), Bybit (trading complete)
- **Unified API Interface**: Consistent function naming across exchanges
- **Built-in Safety Features**: Rate limiting, clock synchronization, order safety checks
- **Req-Centric Architecture**: Leverages Req's powerful HTTP client capabilities
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

### Environment Variables

Set your API credentials as environment variables:

```bash
# Production credentials
export BINANCE_API_KEY="your_binance_api_key"
export BINANCE_API_SECRET="your_binance_api_secret"
export BYBIT_API_KEY="your_bybit_api_key"
export BYBIT_API_SECRET="your_bybit_api_secret"

# Testnet credentials (required for running tests)
export BINANCE_TESTNET_API_KEY="your_testnet_key"
export BINANCE_TESTNET_API_SECRET="your_testnet_secret"
export BYBIT_TESTNET_API_KEY="your_testnet_key"
export BYBIT_TESTNET_API_SECRET="your_testnet_secret"
```

### Application Configuration

The library starts automatically with your application. Key components include:
- **Finch**: HTTP connection pooling (via Req)
- **OrderSafety**: Idempotency checks for safe order placement
- **ClockSync**: Synchronizes time with exchange servers

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

## Quick Start

### Basic Usage

```elixir
# Import the API modules directly
alias ZenCex.Adapters.Binance.Spot
alias ZenCex.Adapters.Binance.Common

# Check server connectivity
{:ok, _} = Common.get_server_time()

# Get account balances (requires API credentials)
{:ok, balances} = Spot.get_balances()
```

### Custom Authentication Credentials

You can pass custom API credentials directly to any endpoint instead of using environment variables:

```elixir
# Pass credentials as keyword list options (second argument)
opts = [
  auth_credentials: %{
    api_key: "your_api_key",
    api_secret: "your_api_secret"
  }
]

{:ok, balances} = Spot.get_balances(%{}, opts)

# Or pass as a map
opts = %{
  auth_credentials: %{
    api_key: "your_api_key",
    api_secret: "your_api_secret"
  }
}

{:ok, order} = Spot.place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "MARKET",
  quantity: "0.001"
}, opts)
```

This is useful for:
- Managing multiple accounts or subaccounts
- Using different credentials per request
- Testing with different API keys
- Implementing credential rotation

#### Security Warnings

⚠️ **NEVER commit API keys to version control!** Always use environment variables or secure credential management systems.

**Security Best Practices:**
- Store API keys in environment variables or a secure vault (e.g., HashiCorp Vault, AWS Secrets Manager)
- Use read-only API keys when write access is not needed
- Restrict API key permissions to only required operations
- Enable IP whitelisting on exchange APIs when possible
- Rotate credentials regularly (see example below)
- Monitor API key usage for suspicious activity
- Use testnet credentials for development and testing

#### Credential Rotation Pattern

```elixir
defmodule MyApp.CredentialManager do
  @rotation_interval_ms 24 * 60 * 60 * 1000  # 24 hours
  
  def get_current_credentials do
    # Fetch from secure storage (vault, encrypted DB, etc.)
    %{
      api_key: fetch_from_vault("binance_api_key"),
      api_secret: fetch_from_vault("binance_api_secret")
    }
  end
  
  def execute_with_rotation(params) do
    creds = get_current_credentials()
    opts = [auth_credentials: creds]
    
    case ZenCex.Adapters.Binance.Spot.place_order(params, opts) do
      {:error, :unauthorized} ->
        # Trigger credential rotation
        rotate_credentials()
        # Retry with new credentials
        new_creds = get_current_credentials()
        ZenCex.Adapters.Binance.Spot.place_order(params, [auth_credentials: new_creds])
      
      result -> result
    end
  end
  
  defp rotate_credentials do
    # Implementation depends on your credential management system
    :ok
  end
end
```

#### Performance Considerations

When using per-request authentication:
- Credentials are validated on each request (minimal overhead: ~0.1ms)
- No credential caching between requests (stateless design)
- Consider connection pooling for high-frequency operations
- Rate limits apply per API key, not per request

### Spot Trading

```elixir
alias ZenCex.Adapters.Binance.Spot

# Get current balances
{:ok, balances} = Spot.get_balances()

# Place a market order
{:ok, order} = Spot.place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "MARKET",
  quantity: "0.001"
})

# Place a limit order
{:ok, order} = Spot.place_order(%{
  symbol: "BTCUSDT",
  side: "SELL",
  type: "LIMIT",
  price: "70000",
  quantity: "0.001",
  timeInForce: "GTC"
})

# Check order status
{:ok, status} = Spot.get_order(%{
  symbol: "BTCUSDT",
  orderId: order["orderId"]
})

# Cancel an order
{:ok, _} = Spot.cancel_order(%{
  symbol: "BTCUSDT",
  orderId: order["orderId"]
})
```

### Futures Trading

```elixir
alias ZenCex.Adapters.Binance.UsdmFutures
alias ZenCex.Adapters.Binance.CoinmFutures

# USD-M Futures (USDT-margined)
{:ok, positions} = UsdmFutures.get_positions()

{:ok, order} = UsdmFutures.place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "MARKET",
  quantity: "0.001"
})

# COIN-M Futures (coin-margined)
{:ok, positions} = CoinmFutures.get_positions()

{:ok, order} = CoinmFutures.place_order(%{
  symbol: "BTCUSD_PERP",
  side: "BUY",
  type: "LIMIT",
  price: "70000",
  quantity: "1"  # Contracts
})
```

### Market Data

```elixir
alias ZenCex.Adapters.Binance.Spot
alias ZenCex.Adapters.Binance.UsdmFutures

# Get ticker information
{:ok, ticker} = Spot.get_ticker_24hr(%{symbol: "BTCUSDT"})

# Get order book
{:ok, book} = Spot.get_order_book(%{symbol: "BTCUSDT", limit: 20})

# Get recent trades
{:ok, trades} = Spot.get_recent_trades(%{symbol: "BTCUSDT"})

# Get klines/candlestick data
{:ok, klines} = Spot.get_klines(%{
  symbol: "BTCUSDT",
  interval: "1h",
  limit: 100
})

# Futures-specific market data
{:ok, funding} = UsdmFutures.get_funding_rate(%{symbol: "BTCUSDT"})
{:ok, oi} = UsdmFutures.get_open_interest(%{symbol: "BTCUSDT"})
```

### Bybit Exchange

```elixir
alias ZenCex.Adapters.Bybit.Unified
alias ZenCex.Adapters.Bybit.Common

# Check server connectivity
{:ok, time} = Common.get_server_time()

# Spot trading
{:ok, order} = Unified.place_order(%{
  category: "spot",
  symbol: "BTCUSDT",
  side: "Buy",
  orderType: "Market",
  qty: "0.001"
})

# Linear futures (USDT perpetual)
{:ok, positions} = Unified.get_positions(%{category: "linear"})

{:ok, order} = Unified.place_order(%{
  category: "linear",
  symbol: "BTCUSDT",
  side: "Buy",
  orderType: "Market",
  qty: "0.001"
})

# Inverse futures (coin-margined)
{:ok, order} = Unified.place_order(%{
  category: "inverse",
  symbol: "BTCUSD",
  side: "Buy",
  orderType: "Limit",
  price: "70000",
  qty: "100"  # USD value
})
```

## Advanced Features

### High-Level Trading Strategies

```elixir
alias ZenCex.Adapters.Binance.Strategies

# Automatically hedge 50% of spot positions with futures
{:ok, result} = Strategies.auto_hedge_spot_positions(0.5,
  hedge_type: :usdt_m,
  dry_run: false
)

# Hedge using PAXG (gold-backed token) long positions
{:ok, result} = Strategies.hedge_with_paxg_long(%{
  target_hedge_value: Decimal.new("10000"),
  leverage: Decimal.new("2.0")
})

# Rebalance portfolio to target allocations
{:ok, result} = Strategies.rebalance_portfolio(
  %{"BTC" => 0.5, "ETH" => 0.3, "BNB" => 0.2},
  tolerance: 0.05
)
```

### Debug Mode

Enable debug mode to troubleshoot API issues:

```elixir
# Enable debug mode
ZenCex.Core.Debug.enable()

# Make a request that fails
{:error, reason} = Spot.place_order(%{invalid: "params"})

# Get the curl command to reproduce
{:ok, curl_command} = ZenCex.Core.Debug.get_last_curl()
IO.puts(curl_command)
# Copy and run in terminal to see exact API response

# Get debug statistics
ZenCex.Core.Debug.stats()

# Disable when done
ZenCex.Core.Debug.disable()
```

### Endpoint Discovery

Explore available endpoints dynamically:

```elixir
alias ZenCex.Adapters.Binance.Endpoints

# List all available endpoints
Endpoints.list_available_endpoints()

# List endpoints by API type
Endpoints.list_available_endpoints(:spot)
Endpoints.list_available_endpoints(:usdm_futures)

# Get detailed endpoint information
Endpoints.get_endpoint_info(:place_order, :spot)
# Returns method, path, auth requirements, rate limits, etc.
```

### Custom Request Options

Pass additional options to any endpoint:

```elixir
# Custom timeout for large data requests
{:ok, data} = Spot.get_klines(
  %{symbol: "BTCUSDT", interval: "1m", limit: 1000},
  [timeout: 30_000]
)

# Skip rate limiting for critical operations
{:ok, order} = Spot.cancel_order(
  %{symbol: "BTCUSDT", orderId: "12345"},
  [skip_rate_limit: true]
)

# Use specific credentials (bypassing environment variables)
{:ok, balances} = Spot.get_balances(
  [],
  [auth_credentials: %{api_key: "key", api_secret: "secret"}]
)
```

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
- **API Modules**: Spot, Margin, Futures, etc.
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
- 🚧 **Market Data**: Tickers, order books, klines (partial)

### Bybit
- ✅ **Unified Trading**: All product types via category parameter
- ✅ **Spot Trading**: Complete order management
- ✅ **Linear Futures**: USDT perpetuals
- ✅ **Inverse Futures**: Coin-margined contracts
- 🚧 **Options**: To be implemented
- 🚧 **Market Data**: To be implemented

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
https://github.com/yourusername/zen_cex