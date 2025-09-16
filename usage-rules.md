# ZenCex Usage Rules - How to Use This Library

## Quick Start

```elixir
# 1. Set credentials (in shell)
export BINANCE_API_KEY="your_key"
export BINANCE_API_SECRET="your_secret"

# 2. Use the library
alias ZenCex.Adapters.Binance.Endpoints, as: Binance

# Get current BTC price
{:ok, price} = Binance.get_ticker_price(%{symbol: "BTCUSDT"})

# Get your balances
{:ok, balances} = Binance.spot_get_balances()

# Place a market buy order
{:ok, order} = Binance.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "MARKET",
  quantity: "0.001"
})
```

## Essential Entry Points

### Primary Modules to Use
```elixir
# Binance - Full trading support
alias ZenCex.Adapters.Binance.Endpoints, as: Binance

# Bybit - Trading operations
alias ZenCex.Adapters.Bybit.Endpoints, as: Bybit
```

### Function Naming Convention
```elixir
# Binance functions are prefixed by product type
Binance.spot_*         # Spot trading
Binance.usdm_*         # USD-M futures
Binance.coinm_*        # COIN-M futures  
Binance.margin_*       # Margin trading
Binance.portfolio_*    # Portfolio margin

# Bybit uses category prefixes
Bybit.spot_*           # Spot trading
Bybit.linear_*         # Linear futures
Bybit.inverse_*        # Inverse futures
```

## Common Operations

### 1. Check Connection
```elixir
# Always verify connection first
{:ok, server_time} = Binance.get_server_time()
```

### 2. Get Market Prices (No Auth Required)
```elixir
# Current price
{:ok, ticker} = Binance.get_ticker_price(%{symbol: "BTCUSDT"})
price = ticker["price"]

# 24hr stats
{:ok, stats} = Binance.get_ticker_24hr(%{symbol: "BTCUSDT"})
volume = stats["volume"]

# Order book
{:ok, book} = Binance.get_order_book(%{symbol: "BTCUSDT", limit: 10})
best_bid = hd(book["bids"])
best_ask = hd(book["asks"])
```

### 3. Account Operations (Auth Required)
```elixir
# Get balances
{:ok, balances} = Binance.spot_get_balances()
btc_balance = Enum.find(balances, &(&1["asset"] == "BTC"))

# Get open orders
{:ok, orders} = Binance.spot_get_open_orders()

# Get positions (futures)
{:ok, positions} = Binance.usdm_get_positions()
```

### 4. Trading
```elixir
# Market order
{:ok, order} = Binance.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",    # or "SELL"
  type: "MARKET",
  quantity: "0.001"
})

# Limit order
{:ok, order} = Binance.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "SELL",
  type: "LIMIT",
  price: "70000",
  quantity: "0.001",
  timeInForce: "GTC"  # Good-Till-Canceled
})

# Cancel order
{:ok, _} = Binance.spot_cancel_order(%{
  symbol: "BTCUSDT",
  orderId: order["orderId"]
})
```

## Authentication Setup

### Method 1: Direct Credentials (Multi-Account/Dynamic)
```elixir
# Pass credentials directly in options
{:ok, balances} = Binance.spot_get_balances(%{}, [
  auth_credentials: %{
    api_key: "your_api_key",
    api_secret: "your_api_secret"
  }
])

# Works with any authenticated endpoint
{:ok, order} = Binance.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "MARKET",
  quantity: "0.001"
}, [
  auth_credentials: %{
    api_key: "account2_key",
    api_secret: "account2_secret"
  }
])

# Useful for multi-account management
accounts = [
  %{api_key: "account1_key", api_secret: "account1_secret"},
  %{api_key: "account2_key", api_secret: "account2_secret"}
]

Enum.each(accounts, fn creds ->
  {:ok, balances} = Binance.spot_get_balances(%{}, [auth_credentials: creds])
  IO.inspect(balances)
end)
```

### Method 2: Environment Variables (Default)
```bash
# Production
export BINANCE_API_KEY="your_key"
export BINANCE_API_SECRET="your_secret"

# Testnet (for development)
export BINANCE_TESTNET=true
export BINANCE_TESTNET_API_KEY="testnet_key"
export BINANCE_TESTNET_API_SECRET="testnet_secret"
```

When no credentials are passed, the library automatically uses environment variables.

## Parameter Patterns

### Standard Function Signatures
```elixir
# No parameters (uses defaults)
{:ok, result} = Binance.spot_get_balances()

# With parameters
{:ok, result} = Binance.spot_place_order(%{symbol: "BTCUSDT", ...})

# With options
{:ok, result} = Binance.spot_get_balances(%{}, [timeout: 10_000])
```

### Common Options
```elixir
[
  timeout: 10_000,           # Custom timeout in ms
  skip_rate_limit: true,     # Bypass rate limiting
  auth_credentials: %{...}   # Manual auth
]
```

## Error Handling

```elixir
case Binance.spot_place_order(params) do
  {:ok, order} ->
    IO.puts("Order ID: #{order["orderId"]}")
    
  {:error, %{"code" => -2010}} ->
    IO.puts("Insufficient balance")
    
  {:error, %{"code" => -1121}} ->
    IO.puts("Invalid symbol")
    
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Discovering Available Functions

```elixir
# List all endpoints
Binance.list_available_endpoints()

# List by type
Binance.list_available_endpoints(:spot)
Binance.list_available_endpoints(:usdm_futures)

# Get function details
Binance.get_endpoint_info(:spot_place_order)
# => %{
#   method: :post,
#   path: "/api/v3/order",
#   requires_auth: true,
#   rate_limit_weight: 1
# }
```

## Advanced: Trading Strategies (Binance Only)

```elixir
alias ZenCex.Adapters.Binance.Strategies

# Auto-hedge spot with futures
Strategies.auto_hedge_spot_positions(0.5,
  hedge_type: :usdt_m,
  dry_run: true  # Test first!
)

# Portfolio rebalancing
Strategies.rebalance_portfolio(
  %{"BTC" => 0.5, "ETH" => 0.3, "BNB" => 0.2},
  tolerance: 0.05
)
```

## Debugging Failed Requests

```elixir
# Enable debug mode
ZenCex.Core.Debug.enable()

# Make request
{:error, reason} = Binance.spot_get_balances()

# Get curl command to reproduce
{:ok, curl} = ZenCex.Core.Debug.get_last_curl()
IO.puts(curl)  # Run in terminal to debug
```

## Test Utilities for External Applications

ZenCex provides comprehensive test utilities that external applications can use for integration testing.

### Setup

Add ZenCex to your test dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:zen_cex, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

### Using the Integration Test Case

The `IntegrationCase` ensures you're using testnet and validates credentials:

```elixir
defmodule MyApp.BinanceIntegrationTest do
  use ZenCex.TestUtilities.IntegrationCase, exchange: :binance, api_type: :spot

  test "fetch balances from Binance testnet" do
    {:ok, balances} = ZenCex.Adapters.Binance.Spot.get_balances()

    assert is_list(balances)
    ZenCex.TestUtilities.assert_valid_balance_structure(balances, :binance)
  end
end
```

### Environment Variable Manipulation

Use the `with_env` macro to safely test different credential scenarios:

```elixir
defmodule MyApp.AuthTest do
  use ExUnit.Case
  import ZenCex.TestUtilities.EnvHelpers

  test "handles missing API key" do
    with_env [{"BINANCE_TESTNET_API_KEY", nil}] do
      assert {:error, :missing_credentials} = MyModule.authenticate()
    end
    # Environment automatically restored after the block
  end

  test "handles invalid credentials" do
    with_env [{"BINANCE_TESTNET_API_KEY", "invalid"}] do
      result = MyModule.call_exchange()
      assert {:error, _} = result
    end
  end
end
```

### Test Configuration Helpers

```elixir
# Get valid test configuration (fails if credentials missing)
config = ZenCex.TestUtilities.get_test_config!(:binance)

# Create invalid config for error testing
invalid_config = ZenCex.TestUtilities.get_invalid_config(:binance, :spot)

# Add account type to configuration
config = ZenCex.TestUtilities.with_account_type(config, :futures_usdm)

# Check if API tests should run
if ZenCex.TestUtilities.should_run_api_tests?(:binance) do
  # Run tests that require real API access
end
```

### Response Validators

Validate that API responses match expected structure:

```elixir
# Validate balance structure
balances = get_balances_somehow()
ZenCex.TestUtilities.assert_valid_balance_structure(balances, :binance)

# Validate order structure
order = place_order_somehow()
ZenCex.TestUtilities.assert_valid_order_structure(order, :binance)

# Other validators
assert_valid_position_structure(data, exchange)
assert_valid_ticker_structure(data, exchange)
assert_valid_kline_structure(data, exchange)
```

### Test Data Generators

Generate test data matching exchange formats:

```elixir
# Generate test balance
balance = ZenCex.TestUtilities.generate_test_balance(:binance, "BTC", "10.5", "0.5")

# Generate test order
order = ZenCex.TestUtilities.generate_test_order(
  :binance,
  "BTCUSDT",
  :buy,
  :limit,
  "0.001",
  "50000"
)

# Generate test position
position = ZenCex.TestUtilities.generate_test_position(
  :binance,
  "BTCUSDT",
  :long,
  "0.1",
  "45000",
  "46000"
)
```

### Available Modules

- `ZenCex.TestUtilities` - Main module with configuration helpers
- `ZenCex.TestUtilities.IntegrationCase` - Test case template for integration tests
- `ZenCex.TestUtilities.EnvHelpers` - Environment variable manipulation macros
- `ZenCex.TestUtilities.Generators` - Test data generators
- `ZenCex.TestUtilities.Validators` - Response structure validators

### Required Environment Variables

For integration tests to work, you need testnet credentials:

```bash
# Binance Spot/Margin testnet
export BINANCE_TESTNET_API_KEY=your_key
export BINANCE_TESTNET_API_SECRET=your_secret
export BINANCE_TESTNET=true

# Binance Futures testnet (separate credentials)
export BINANCE_FUTURES_TEST_API_KEY=your_futures_key
export BINANCE_FUTURES_TEST_API_SECRET=your_futures_secret

# Bybit testnet
export BYBIT_TESTNET_API_KEY=your_key
export BYBIT_TESTNET_API_SECRET=your_secret
export BYBIT_TESTNET=true
```

## Testing with Tidewave

When Tidewave is running (`mix tidewave`):
```elixir
# Test code directly
mcp__tidewave__project_eval(code: """
  alias ZenCex.Adapters.Binance.Endpoints
  Endpoints.spot_get_balances()
""")

# Check available functions
mcp__tidewave__project_eval(code: """
  exports(ZenCex.Adapters.Binance.Endpoints)
""")
```

## Key Rules for AI Agents

1. **Always use the Endpoints module** - Don't try to call internal modules directly
2. **Check server time first** - Ensures connection and time sync
3. **Use testnet for testing** - Set BINANCE_TESTNET=true
4. **Handle errors properly** - All functions return {:ok, result} or {:error, reason}
5. **Respect rate limits** - Library handles this automatically
6. **Use prefixed functions** - spot_*, usdm_*, etc. for clarity
7. **Never mock APIs** - Test against real testnets only

## Quick Reference

| Task | Function | Parameters |
|------|----------|------------|
| Get price | `get_ticker_price/1` | `%{symbol: "BTCUSDT"}` |
| Get balances | `spot_get_balances/0` | None |
| Place order | `spot_place_order/1` | `%{symbol, side, type, quantity}` |
| Cancel order | `spot_cancel_order/1` | `%{symbol, orderId}` |
| Get positions | `usdm_get_positions/0` | None |
| Server time | `get_server_time/0` | None |