# ZenCex Agent Guide

Quick reference for AI agents using the ZenCex library for cryptocurrency exchange REST APIs.

## Quick Start (30 seconds)

```elixir
# Add to mix.exs
{:zen_cex, "~> 0.1.0"}

# Set environment variables
export BINANCE_TESTNET=true
export BINANCE_TESTNET_API_KEY=your_key
export BINANCE_TESTNET_API_SECRET=your_secret

# Use the library
alias ZenCex.Adapters.Binance.Endpoints

# Get account balances
{:ok, balances} = Endpoints.spot_get_balances()

# Place an order
{:ok, order} = Endpoints.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: "0.001",
  price: "40000"
})
```

## Endpoint Discovery

```elixir
alias ZenCex.Adapters.Binance.Endpoints

# List all available operations
Endpoints.list_available_endpoints()
# => [:spot_get_balances, :spot_place_order, :usdm_get_positions, ...]

# Filter by API type
Endpoints.list_available_endpoints(:spot)     # Spot trading
Endpoints.list_available_endpoints(:margin)   # Margin trading
Endpoints.list_available_endpoints(:usdm_futures)  # USD-M futures
Endpoints.list_available_endpoints(:coinm_futures) # COIN-M futures

# Get endpoint details
Endpoints.get_endpoint_info(:spot_place_order)
# => %{
#   method: :post,
#   path: "/api/v3/order",
#   requires_auth: true,
#   weight: 1,
#   params: [:symbol, :side, :type, :quantity, :price]
# }
```

## Common Operations

### Account Management

```elixir
# Get spot balances
{:ok, balances} = Endpoints.spot_get_balances()
# => [%{asset: "BTC", free: #Decimal<0.5>, locked: #Decimal<0.1>}, ...]

# Get margin account info
{:ok, account} = Endpoints.margin_get_account()

# Get futures positions
{:ok, positions} = Endpoints.usdm_get_positions()

# Get unified portfolio margin account
{:ok, unified} = Endpoints.portfolio_get_unified_account()
```

### Order Management

```elixir
# Place spot limit order
{:ok, order} = Endpoints.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "BUY",
  type: "LIMIT",
  quantity: "0.001",
  price: "40000",
  timeInForce: "GTC"
})

# Place market order
{:ok, order} = Endpoints.spot_place_order(%{
  symbol: "BTCUSDT",
  side: "SELL",
  type: "MARKET",
  quantity: "0.001"
})

# Cancel order
{:ok, result} = Endpoints.spot_cancel_order(%{
  symbol: "BTCUSDT",
  orderId: 123456
})

# Get order status
{:ok, order} = Endpoints.spot_get_order(%{
  symbol: "BTCUSDT",
  orderId: 123456
})

# Get open orders
{:ok, orders} = Endpoints.spot_get_open_orders()
# Or for specific symbol
{:ok, orders} = Endpoints.spot_get_open_orders(%{symbol: "BTCUSDT"})
```

### Market Data

```elixir
# Get server time (no auth required)
{:ok, %{server_time: timestamp}} = Endpoints.get_server_time()

# Get exchange info
{:ok, info} = Endpoints.get_exchangeInfo()

# Get ticker price
{:ok, ticker} = Endpoints.get_ticker_price(%{symbol: "BTCUSDT"})

# Get order book
{:ok, depth} = Endpoints.get_depth(%{symbol: "BTCUSDT", limit: 10})
```

## Multi-API Usage

ZenCex supports multiple API types for Binance. Use the appropriate prefix:

```elixir
# Spot trading (prefix: spot_)
{:ok, spot_balance} = Endpoints.spot_get_balances()
{:ok, spot_order} = Endpoints.spot_place_order(params)

# Margin trading (prefix: margin_)
{:ok, margin_account} = Endpoints.margin_get_account()
{:ok, margin_order} = Endpoints.margin_place_order(params)

# USD-M Futures (prefix: usdm_)
{:ok, positions} = Endpoints.usdm_get_positions()
{:ok, futures_order} = Endpoints.usdm_place_order(params)

# COIN-M Futures (prefix: coinm_)
{:ok, coin_positions} = Endpoints.coinm_get_positions()

# Portfolio Margin (prefix: portfolio_)
{:ok, unified} = Endpoints.portfolio_get_unified_account()
```

## Error Handling

```elixir
case Endpoints.spot_place_order(params) do
  {:ok, order} ->
    # Order placed successfully
    IO.inspect(order.order_id)
  
  {:error, :insufficient_balance} ->
    # Not enough funds
    
  {:error, :invalid_symbol} ->
    # Symbol doesn't exist
    
  {:error, :rate_limited} ->
    # Too many requests
    Process.sleep(1000)
    # Retry...
    
  {:error, {:exchange_error, msg}} ->
    # Custom exchange error
    Logger.error("Exchange error: #{msg}")
    
  {:error, reason} ->
    # Other errors
    Logger.error("Unexpected error: #{inspect(reason)}")
end
```

## Rate Limiting

Rate limiting is handled transparently by the library:

```elixir
# Rate limits are enforced automatically
{:ok, _} = Endpoints.spot_get_balances()  # Uses weight: 20
{:ok, _} = Endpoints.spot_place_order(params)  # Uses weight: 1

# If rate limited, you'll get:
{:error, :rate_limited}

# Rate limits are tracked per API type
# Spot, Margin, Futures have separate limits

# Override rate limiting (use carefully!)
{:ok, _} = Endpoints.spot_get_balances(%{}, skip_rate_limit: true)
```

## Request Options

```elixir
# All endpoints accept options as second parameter
params = %{symbol: "BTCUSDT"}
opts = %{
  skip_auth: false,          # Skip authentication
  skip_rate_limit: false,    # Skip rate limiting
  receive_timeout: 30_000,   # Custom timeout (ms)
  auth_credentials: %{       # Override credentials
    api_key: "different_key",
    api_secret: "different_secret"
  }
}

{:ok, ticker} = Endpoints.get_ticker_price(params, opts)
```

## Testing Against Testnet

```elixir
# Set environment to use testnet
System.put_env("BINANCE_TESTNET", "true")
System.put_env("BINANCE_TESTNET_API_KEY", "your_testnet_key")
System.put_env("BINANCE_TESTNET_API_SECRET", "your_testnet_secret")

# Verify using testnet
alias ZenCex.Adapters.Binance.Endpoints
Endpoints.current_env()
# => :test

Endpoints.base_url()
# => "https://testnet.binance.vision"

# Now all operations hit testnet
{:ok, testnet_balance} = Endpoints.spot_get_balances()
```

## Advanced: Trading Strategies

```elixir
alias ZenCex.Adapters.Binance.Strategies

# Auto-hedge spot positions
{:ok, result} = Strategies.auto_hedge_spot_positions(
  0.5,  # Hedge 50% of spot
  %{hedge_asset: "USDT"}
)

# Hedge with PAXG (gold-backed token)
{:ok, result} = Strategies.hedge_with_paxg_long(%{
  target_percentage: 0.3
})

# Rebalance portfolio
{:ok, result} = Strategies.rebalance_portfolio(
  %{"BTC" => 0.5, "ETH" => 0.3, "USDT" => 0.2},
  %{threshold: 0.05}
)
```

## Response Formats

```elixir
# Successful responses return {:ok, data}
{:ok, balances} = Endpoints.spot_get_balances()
# balances = [
#   %{asset: "BTC", free: #Decimal<0.5>, locked: #Decimal<0.1>, total: #Decimal<0.6>},
#   %{asset: "ETH", free: #Decimal<10>, locked: #Decimal<0>, total: #Decimal<10>}
# ]

# Order responses
{:ok, order} = Endpoints.spot_place_order(params)
# order = %{
#   order_id: "123456",
#   symbol: "BTCUSDT",
#   side: :buy,
#   type: :limit,
#   price: #Decimal<40000>,
#   quantity: #Decimal<0.001>,
#   status: :new
# }

# Error responses return {:error, reason}
{:error, :insufficient_balance}
{:error, :invalid_symbol}
{:error, {:exchange_error, "Order would immediately match"}}
```

## Tips for AI Agents

1. **Always handle errors** - Exchange APIs fail frequently
2. **Use testnet first** - Test your logic with fake money
3. **Respect rate limits** - The library handles this, but design accordingly
4. **Check server time** - Some operations require synchronized clocks
5. **Use decimals** - All numeric values are `Decimal` structs for precision
6. **Endpoint discovery** - Use `list_available_endpoints()` to explore capabilities
7. **Read endpoint info** - Use `get_endpoint_info/1` to understand requirements

## Common Patterns

```elixir
# Pattern 1: Retry on rate limit
def place_order_with_retry(params, retries \\ 3) do
  case Endpoints.spot_place_order(params) do
    {:ok, order} -> {:ok, order}
    {:error, :rate_limited} when retries > 0 ->
      Process.sleep(1000)
      place_order_with_retry(params, retries - 1)
    error -> error
  end
end

# Pattern 2: Get balance for specific asset
def get_asset_balance(asset) do
  with {:ok, balances} <- Endpoints.spot_get_balances() do
    balance = Enum.find(balances, &(&1.asset == asset))
    {:ok, balance || %{asset: asset, free: Decimal.new(0), locked: Decimal.new(0)}}
  end
end

# Pattern 3: Place order with validation
def safe_place_order(params) do
  with {:ok, _info} <- Endpoints.get_exchangeInfo(),
       {:ok, balances} <- Endpoints.spot_get_balances(),
       :ok <- validate_balance(params, balances),
       {:ok, order} <- Endpoints.spot_place_order(params) do
    {:ok, order}
  end
end
```