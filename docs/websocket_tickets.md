# WebSocket Implementation Tickets

## Phase 1: Foundation (COMPLETED ✅)
- [x] Add zen_websocket dependency to mix.exs
- [x] Create WebSocket base behavior module
- [x] Implement Binance WebSocket adapter with order book support
- [x] Implement Bybit WebSocket adapter with order book support
- [x] Extend Cache.Market module for WebSocket data storage

## Phase 2: Core.Cache Enhancement ✅
### Ticket: Update Core.Cache for Infinity TTL
**Priority**: High
**Status**: COMPLETED
**Description**: Core.Cache now supports :infinity TTL for WebSocket data that doesn't expire
```elixir
# Implemented in Core.Cache:
@spec put(binary(), term(), pos_integer() | :infinity) :: :ok
def put(key, value, :infinity) # Store without expiry
```

## Phase 3: WebSocket Supervision Tree 📋
### Ticket: Create WebSocket Supervisor
**Priority**: High
**Status**: TODO
**Description**: Implement supervision tree for production WebSocket connections
```elixir
# lib/zen_cex/websocket/supervisor.ex
defmodule ZenCex.WebSocket.Supervisor do
  use Supervisor

  # Dynamic supervisor for multiple connections
  # Restart strategy for failed connections
  # Connection pooling per exchange
end
```

### Ticket: Add WebSocket to Application Tree
**Priority**: High
**Status**: TODO
**Description**: Integrate WebSocket supervisor into main application
```elixir
# lib/zen_cex/application.ex
children = [
  # ... existing children
  {ZenCex.WebSocket.Supervisor, []},
  # Start key WebSocket connections on boot
]
```

## Phase 4: OrderSafety Integration 🔄
### Ticket: Update OrderSafety.MarketData
**Priority**: Medium
**Status**: TODO
**Description**: Modify OrderSafety to prefer WebSocket data over REST
```elixir
# lib/zen_cex/safety/order_safety/market_data.ex
def fetch_current_price(exchange, symbol) do
  # 1. Check WebSocket cache first (get_book_ticker)
  # 2. Fall back to REST if no WebSocket data
  # 3. Use appropriate TTL based on data source
end
```

## Phase 5: WebSocket Manager 🎮
### Ticket: Create Connection Manager
**Priority**: Medium
**Status**: TODO
**Description**: Centralized WebSocket connection management
```elixir
defmodule ZenCex.WebSocket.Manager do
  # Track active connections
  # Handle subscription management
  # Implement connection pooling
  # Monitor connection health
end
```

## Phase 6: Testing Infrastructure 🧪
### Ticket: WebSocket Integration Tests
**Priority**: High
**Status**: TODO
**Files to create**:
- `test/zen_cex/adapters/binance/websocket_test.exs`
- `test/zen_cex/adapters/bybit/websocket_test.exs`
- `test/zen_cex/websocket/manager_test.exs`

**Test Coverage**:
- Connection establishment
- Subscription handling
- Message parsing
- Reconnection logic
- Cache integration
- Error scenarios

## Phase 7: Advanced Features 🚀
### Ticket: Aggregated Order Books
**Priority**: Low
**Status**: TODO
**Description**: Combine multiple depth levels for complete order book view
- Maintain full order book state
- Handle incremental updates
- Implement snapshot + diff pattern

### Ticket: Trade Aggregation
**Priority**: Low
**Status**: TODO
**Description**: Aggregate trades into volume-weighted candles
- Store trade history in circular buffer
- Calculate VWAP in real-time
- Emit custom telemetry events

### Ticket: WebSocket Metrics Dashboard
**Priority**: Low
**Status**: TODO
**Description**: Real-time monitoring of WebSocket connections
- Connection status per exchange
- Message rate monitoring
- Latency tracking
- Error rate tracking

## Phase 8: Production Hardening 💪
### Ticket: Circuit Breaker for WebSocket
**Priority**: Medium
**Status**: TODO
**Description**: Implement circuit breaker pattern for WebSocket connections
- Detect repeated failures
- Implement backoff strategy
- Auto-recovery logic
- Telemetry integration

### Ticket: WebSocket Rate Limiting
**Priority**: Medium
**Status**: TODO
**Description**: Respect exchange WebSocket limits
- Track subscription count
- Implement subscription batching
- Handle rate limit errors

## Phase 9: Documentation 📚
### Ticket: WebSocket Usage Guide
**Priority**: Medium
**Status**: TODO
**Description**: Create comprehensive WebSocket documentation
- Usage examples
- Configuration guide
- Best practices
- Troubleshooting guide

## Phase 10: Code Quality & Refactoring 🔨
### Ticket: Integrate zen_websocket Telemetry
**Priority**: Medium
**Status**: TODO
**Description**: Replace Logger calls with telemetry event handlers
```elixir
# zen_websocket emits these events:
[:zen_websocket, :client, :message_received]
[:zen_websocket, :client, :message_sent]
[:zen_websocket, :connection, :connected]
[:zen_websocket, :connection, :disconnected]

# Attach handlers in Application.start/2:
:telemetry.attach_many(
  "zen-cex-websocket",
  [
    [:zen_websocket, :client, :message_received],
    [:zen_websocket, :connection, :connected],
    [:zen_websocket, :connection, :disconnected]
  ],
  &ZenCex.WebSocket.TelemetryHandler.handle_event/4,
  nil
)
```

## Phase 11: Module Refactoring 🔨
### Ticket: OrderSafety Module Refactoring
**Priority**: High
**Status**: TODO
**Description**: Split large OrderSafety modules to meet complexity guidelines
```elixir
# Current: 42 functions in OrderSafety -> Target: 6 max per module
# Extract into separate modules:
- ZenCex.Safety.KillSwitch (global trading kill switch)
- ZenCex.Safety.OrderSafety (core validation only)

# Current: 32 functions in MarketData -> Target: 6 max per module
# Split by exchange:
- ZenCex.Safety.OrderSafety.MarketData.Binance
- ZenCex.Safety.OrderSafety.MarketData.Bybit
- ZenCex.Safety.OrderSafety.MarketData.Common

# Current: 28 functions in Validation -> Target: 6 max per module
# Split by validation type:
- ZenCex.Safety.OrderSafety.Validation.Price
- ZenCex.Safety.OrderSafety.Validation.Size
- ZenCex.Safety.OrderSafety.Validation.Balance
- ZenCex.Safety.OrderSafety.Validation.Symbol
```

### Ticket: Test Coverage Improvements
**Priority**: Medium
**Status**: TODO
**Description**: Improve test coverage to meet standards
- MarketData: 53.1% → 80% minimum (critical business logic)
- OrderSafety: 85.6% → Maintain above 80%
- Cache: 86.7% → Maintain above 80%
Note: 80% is the new standard per CLAUDE.md update

### Ticket: Configuration Management System
**Priority**: Medium
**Status**: TODO
**Description**: Create central configuration management
```elixir
defmodule ZenCex.Config.Manager do
  # Central config GenServer
  # Exchange-specific settings
  # Runtime configuration updates
  # No backward compatibility needed
end
```

### Ticket: WebSocket Market Data Parser
**Priority**: High
**Status**: TODO
**Description**: Complete WebSocket parsing implementation
```elixir
# lib/zen_cex/adapters/binance/parser.ex
# Add WebSocket-specific parsing functions:
- parse_trade_data/1
- parse_kline_data/1
- parse_depth_update/1
- parse_ticker_data/1
```

## Implementation Notes

### Current State
- Basic WebSocket adapters implemented for Binance and Bybit
- Cache.Market extended with WebSocket-specific functions
- WebSocket data flows into ETS cache automatically
- No supervision tree yet (development mode only)

### Next Steps (Priority Order)
1. Fix Core.Cache to support :infinity TTL
2. Create WebSocket supervisor for production
3. Update OrderSafety to use WebSocket data
4. Write integration tests
5. Implement connection manager

### Technical Debt
- DONE: Core.Cache now supports :infinity TTL for non-expiring WebSocket data
- DONE: zen_websocket has built-in telemetry events ([:zen_websocket, :client, :message_received] etc.)
- TODO: Replace Logger calls with telemetry event handlers in our adapters
- TODO: No additional reconnection logic needed (zen_websocket handles reconnect)
- TODO: No subscription management - currently fire-and-forget

### Configuration Required
```elixir
# config/config.exs or runtime.exs
config :zen_cex, :websocket,
  enabled: true,
  exchanges: [
    binance: [
      symbols: ["BTCUSDT", "ETHUSDT"],
      streams: [:orderbook, :trades, :ticker]
    ],
    bybit: [
      symbols: ["BTCUSDT", "ETHUSDT"],
      streams: [:orderbook, :trades]
    ]
  ]
```

### Performance Considerations
- Each WebSocket connection uses ~50KB memory (zen_websocket)
- Order book updates can be 100+ messages/second during volatility
- ETS cache can handle millions of reads/writes per second
- Consider connection pooling for many symbols

### Security Notes
- WebSocket connections are read-only (no trading)
- No authentication required for public market data
- Use WSS (encrypted) endpoints only
- Monitor for malformed messages (possible attacks)

## Success Metrics
- [ ] Order book latency < 10ms (WebSocket vs REST: 200ms+)
- [ ] Zero REST calls for actively traded symbols
- [ ] 99.9% WebSocket uptime in production
- [ ] Automatic recovery from all failure scenarios
- [ ] Complete test coverage for WebSocket code