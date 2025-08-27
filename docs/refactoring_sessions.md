# Refactoring Sessions - Configurable Endpoint Architecture

## New Architecture: Compile-Time Endpoint Selection

### Core Principle: Ship All Trading Products & Market Data, Compile What You Need

**Focus on core features ONLY:**
- **Market Data** - Prices, order books, klines (OHLCV), tickers
- **Spot** - Regular spot trading & positions (balances)
- **Futures/Perps** - USDT-margined (USDM) and Coin-margined (COINM)
- **Margin** - Cross and isolated margin trading
- **Options** - Options trading (Bybit only)

**Skip non-trading features:** No staking, earn, NFTs, mining, pay, gift cards, fiat, etc.

**Exchange Focus:** Binance and Bybit only (covering 80%+ of volume)

```elixir
# In Phoenix app's config/config.exs
config :zen_cex, :endpoints, %{
  binance: [:spot_get_ticker_price, :spot_get_balances, :spot_place_order],
  bybit: [:get_ticker, :get_wallet_balance, :place_order]
}

# Or by feature category
config :zen_cex, :endpoints, %{
  binance: %{
    market_data: [:get_ticker_price, :get_order_book, :get_klines],
    spot: [:get_balances, :place_order, :cancel_order],
    margin: false,  # Exclude entirely
    usdm_futures: :all,  # Include all USDT-margined futures
    coinm_futures: :all  # Include all coin-margined futures
  },
  bybit: %{
    market_data: :all,  # All market data endpoints
    unified: [:get_positions, :place_order, :get_wallet_balance]
  }
}
```

### Benefits for Users:
- **Smaller compiled size** - Only includes code for endpoints you use
- **Faster compilation** - Less code to generate
- **Cleaner API** - Autocomplete only shows what's available
- **Security** - Can't accidentally call endpoints you didn't intend to use
- **Memory efficient** - Smaller BEAM file size

### Perfect for REST-based Use Cases:
- **Position Monitoring** - Check balances/positions every 30s-5min
- **Portfolio Hedging** - Calculate exposure and hedge when needed
- **Subaccount Management** - Transfer funds between accounts for risk management
- **Trade Execution** - Place/cancel orders based on market conditions
- **Risk Management** - Monitor PnL and adjust positions
- **Market Analysis** - Fetch OHLCV data for technical indicators

**NOT for**: HFT, market making, arbitrage, or anything requiring <100ms latency

## Current State

### What We Have:
- **EndpointRegistry macro** - Generates functions from specs (needs config support)
- **Mix tasks** - Generate endpoints from OpenAPI (used successfully)
- **Base modules** - Common patterns extracted (BaseEndpoints, BaseAuth, etc.)
- **Binance**: Trading endpoints complete for spot, margin, futures ✅
- **Bybit**: Trading endpoints complete for unified V5 API ✅

### Actual Coverage:
- Binance Spot: ~30 trading endpoints ✅ (market data pending)
- Binance Margin: ~30 trading endpoints ✅
- Binance USDM/COINM: ~40 trading endpoints each ✅
- Binance Portfolio: ~10 endpoints ✅
- Bybit Unified V5: ~50 trading endpoints ✅ (market data & options pending)

## Goal: Complete ALL Endpoints as Configurable Modules

Generate ALL endpoints but let users choose what to compile.

---

## Session 0: Add Configurability to EndpointRegistry

**Size**: ~10K tokens
**Focus**: Make endpoint compilation configurable

### Tasks:
1. **Update EndpointRegistry macro** to read config:
   ```elixir
   defmacro __using__(opts) do
     adapter = Keyword.fetch!(opts, :adapter)
     module_type = detect_module_type(__CALLER__.module)
     
     # Read config at compile time
     included_endpoints = read_endpoint_config(adapter, module_type)
     
     # Filter endpoints based on config
     filtered_endpoints = filter_by_config(@endpoints, included_endpoints)
   end
   ```

2. **Add configuration helpers**:
   ```elixir
   # Default: include all
   # User can specify: list of operations, :all, or false
   defp read_endpoint_config(exchange, api_type) do
     config = Application.get_env(:zen_cex, :endpoints, :all)
     # Navigate config structure to find this module's config
   end
   ```

3. **Create introspection module**:
   ```elixir
   defmodule ZenCex.EndpointCatalog do
     # Returns all available endpoints (even if not compiled)
     def list_all_available_endpoints(exchange)
     
     # Returns only compiled endpoints
     def list_compiled_endpoints(exchange)
     
     # Search endpoints by name/path
     def search_endpoints(pattern)
   end
   ```

4. **Add compile-time warnings**:
   ```elixir
   # Warn when trying to call unconfigured endpoint
   # Show helpful message about adding it to config
   ```

### Deliverables:
- [ ] Configurable EndpointRegistry
- [ ] EndpointCatalog for discovery
- [ ] Documentation for configuration
- [ ] Example configs for common use cases

---

## Session 1: Add Binance & Bybit Market Data

**Size**: ~10K tokens  
**Focus**: Add market data endpoints for both exchanges

### Tasks:
1. **Add Binance market data endpoints** (no auth required):
   ```elixir
   @market_data_endpoints %{
     spot: [
       :get_ticker_price,      # Current price
       :get_ticker_24hr,       # 24hr stats
       :get_order_book,        # Order book depth
       :get_recent_trades,     # Recent trades
       :get_klines,           # OHLCV/candlesticks
       :get_avg_price,        # Average price
       :get_exchange_info     # Trading rules
     ],
     usdm_futures: [
       :get_ticker_price,
       :get_ticker_24hr,
       :get_order_book,
       :get_mark_price,       # Mark price for futures
       :get_funding_rate,     # Funding rate
       :get_open_interest,    # Open interest
       :get_klines
     ]
   }
   ```

2. **Add Bybit market data endpoints**:
   ```elixir
   @market_data_endpoints [
     :get_tickers,          # Price tickers
     :get_orderbook,        # Order book
     :get_kline,           # OHLCV data
     :get_recent_trades,    # Recent trades
     :get_open_interest,    # Open interest
     :get_funding_rate,     # Funding history
     :get_instruments_info, # Trading rules
     :get_mark_price_kline  # Mark price klines
   ]
   ```

3. **Ensure category prefixes work**:
   ```elixir
   # Each category gets market data
   spot_get_ticker("BTCUSDT")
   linear_get_ticker("BTCUSDT")
   inverse_get_ticker("BTCUSD")
   option_get_ticker("BTC-29DEC23-40000-C")
   ```

### Deliverables:
- [ ] ~15 Binance market data endpoints (spot, futures)
- [ ] ~12 Bybit market data endpoints
- [ ] Category-prefixed functions for Bybit
- [ ] Integration tests for market data

---

## Session 2: Add Bybit Options Support

**Size**: ~8K tokens
**Focus**: Complete Bybit options trading endpoints

### Tasks:
1. **Add options-specific endpoints**:
   ```elixir
   @options_endpoints [
     :option_get_delivery_price,    # Delivery prices
     :option_get_greeks,            # Option greeks (IV, delta, gamma)
     :option_place_order,           # Options order placement
     :option_get_positions,         # Options positions
     :option_get_settlement_history # Settlement records
   ]
   ```

2. **Options-specific parameters**:
   ```elixir
   # Handle option symbols
   option_place_order(%{
     symbol: "BTC-29DEC23-40000-C",  # Call option
     side: "Buy",
     orderType: "Limit",
     qty: "0.1",
     price: "1000"
   })
   ```

3. **Greeks and volatility data**:
   - Implied volatility
   - Delta, gamma, theta, vega
   - Historical volatility

### Deliverables:
- [ ] ~15 options endpoints
- [ ] Greeks data parsing
- [ ] Options position management
- [ ] Integration tests for options

---

## Session 3: Testing & Documentation

**Size**: ~10K tokens
**Focus**: Quality assurance for market data and trading

### Tasks:
1. **Integration tests for key use cases**:
   ```elixir
   # Position monitoring & hedging
   test "monitor positions and hedge when needed" do
     {:ok, spot} = Binance.spot_get_account()
     {:ok, futures} = Binance.usdm_get_position_risk()
     {:ok, price} = Binance.spot_get_ticker_price("BTCUSDT")
     
     exposure = calculate_exposure(spot, futures, price)
     assert exposure < hedge_threshold
   end
   
   # Market data for decision making
   test "fetch market data for trading decision" do
     {:ok, orderbook} = Bybit.get_orderbook("BTCUSDT")
     {:ok, klines} = Bybit.get_kline("BTCUSDT", "1h")
     
     signal = analyze_market(orderbook, klines)
     assert signal in [:buy, :sell, :hold]
   end
   ```

2. **Endpoint discovery & catalog**:
   ```elixir
   ZenCex.EndpointCatalog.list(:binance, :market_data)
   ZenCex.EndpointCatalog.list(:binance, :spot)
   ZenCex.EndpointCatalog.search("ticker")
   ```

3. **Configuration examples**:
   ```elixir
   # Position monitor config (REST only)
   config :zen_cex, :endpoints, %{
     binance: %{
       market_data: [:get_ticker_price],
       spot: [:get_account],
       usdm_futures: [:get_position_risk, :get_account]
     }
   }
   
   # Hedge bot config
   config :zen_cex, :endpoints, %{
     binance: %{
       market_data: [:get_ticker_price, :get_ticker_24hr],
       spot: [:get_account, :place_order],
       usdm_futures: [:get_position_risk, :place_order]
     }
   }
   ```

4. **Performance for REST operations**:
   - Market data polling intervals
   - Position check frequency
   - Rate limit compliance

### Deliverables:
- [ ] Use case tests (hedging, monitoring)
- [ ] Config templates for common scenarios
- [ ] REST polling best practices doc
- [ ] Market data caching patterns

---

## Technical Implementation Notes

### Configuration Architecture:

```elixir
# 1. Library ships with trading endpoint definitions as data
defmodule ZenCex.Adapters.Binance.EndpointData do
  def all_endpoints do
    %{
      spot: [...],         # ~50 spot trading endpoints
      margin: [...],       # ~40 margin trading endpoints
      usdm_futures: [...], # ~60 USDT-margined futures
      coinm_futures: [...] # ~60 coin-margined futures
    }
  end
end

# 2. EndpointRegistry reads config and generates only selected
defmacro __using__(opts) do
  all_endpoints = EndpointData.all_endpoints()
  configured = read_user_config()
  selected = filter_endpoints(all_endpoints, configured)
  
  # Only generate functions for selected endpoints
  generate_functions(selected)
end

# 3. Users configure in their app
config :zen_cex, :endpoints, %{
  binance: %{
    spot: [:get_balances, :place_order],
    margin: false,  # Don't compile any margin endpoints
    futures: :all   # Compile all futures endpoints
  }
}
```

### Endpoint Catalog (Runtime Discovery):

```elixir
# Users can discover available endpoints even if not compiled
ZenCex.EndpointCatalog.available(:binance, :spot)
# => Lists all 200+ spot endpoints

ZenCex.EndpointCatalog.compiled(:binance, :spot)  
# => Only shows [:get_balances, :place_order]

ZenCex.EndpointCatalog.suggest(:binance, "withdraw")
# => "To use wallet_withdraw, add to config: binance.wallet: [:withdraw]"
```

### Zero Runtime Overhead:

- All filtering happens at compile time
- No runtime checks or conditions
- Unconfigured endpoints simply don't exist
- Full tree-shaking of unused code

---

## Success Metrics

- [ ] Complete coverage for Binance & Bybit:
  - Market Data: ~15 endpoints per exchange
  - Spot: ~30-50 endpoints
  - Margin: ~25-40 endpoints (Binance)
  - Futures/Perps: ~40-60 endpoints
  - Options: ~30 endpoints (Bybit)
- [ ] Configurable compilation for all endpoints
- [ ] Integration tests for position monitoring & hedging flows
- [ ] REST-only implementation perfect for portfolio management
- [ ] <100ms endpoint discovery
- [ ] Example configs for common use cases (hedging, monitoring, trading)

---

## Remember

- Use the generators - they work!
- Test against real testnets
- Keep patterns consistent
- Document as you go
- Each session completable in one context