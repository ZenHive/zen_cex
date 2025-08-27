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
- **Mix tasks** - Generate endpoints from OpenAPI (Binance, Bybit partially done)
- **Base modules** - Common patterns extracted (BaseEndpoints, BaseAuth, etc.)
- **Binance**: Partially implemented (spot, margin, futures modules exist but limited endpoints)
- **Bybit**: Structure ready, minimal endpoints implemented

### Actual Coverage:
- Binance Spot: ~12 endpoints (only basic trading)
- Binance Margin: ~30 endpoints defined
- Binance USDM/COINM: Structure exists, endpoints defined
- Binance Portfolio: ~5 endpoints
- Bybit: ~10 basic endpoints

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

## Session 1: Complete Binance Market Data & Trading

**Size**: ~15K tokens  
**Focus**: Complete ALL market data and trading endpoints

### Tasks:
1. **Add market data endpoints** (no auth required):
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

2. **Complete position/account endpoints**:
   ```elixir
   # Spot positions (balances)
   :spot_get_account,           # Full account with balances
   :spot_get_balances,          # Just balances
   
   # Futures positions
   :usdm_get_position_risk,    # Current positions with PnL
   :usdm_get_account,          # Account with margin info
   :usdm_get_balance,          # Wallet balance
   
   # Margin positions
   :margin_get_account,         # Cross margin account
   :margin_get_isolated_account # Isolated positions
   ```

3. **Complete trading endpoints**:
   - All order types (market, limit, stop, OCO, OTO)
   - Order management (place, cancel, cancel all, query)
   - Trade history & order history
   - Subaccount operations for hedging

4. **Complete futures-specific**:
   - Leverage adjustment
   - Margin type switching
   - Position mode (hedge/one-way)
   - Income history

### Deliverables:
- [ ] ~15 market data endpoints per product
- [ ] ~30 spot trading endpoints
- [ ] ~25 margin endpoints
- [ ] ~40 futures endpoints per type (USDM/COINM)
- [ ] Subaccount management endpoints

---

## Session 2: Complete Bybit Market Data & Trading  

**Size**: ~15K tokens
**Focus**: Full Bybit V5 unified API with market data

### Tasks:
1. **Add market data endpoints** (public, no auth):
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

2. **Complete position endpoints**:
   ```elixir
   # Unified position API
   :get_positions,        # All positions with PnL
   :get_wallet_balance,   # Account balances
   :get_account_info,     # Account details
   :get_closed_pnl,       # Realized PnL history
   ```

3. **Category-specific functions**:
   ```elixir
   # Auto-generate prefixed functions
   spot_place_order()      # adds category: "spot"
   spot_get_positions()    # spot balances
   linear_place_order()    # USDT perpetuals
   linear_get_positions()  # linear positions
   inverse_place_order()   # coin-margined
   option_place_order()    # options
   ```

4. **Trading & risk management**:
   - Order management (place, amend, cancel)
   - Leverage adjustment
   - Position TP/SL
   - Risk limits
   - Subaccount transfers

### Deliverables:
- [ ] ~12 market data endpoints
- [ ] ~60 unified trading endpoints
- [ ] Category prefixed functions for all products
- [ ] Subaccount management

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