# WebSocket Migration Refactor Tasks

This document tracks the remaining tasks to complete the WebSocket migration to zen_websocket.
Each task is designed to be completed in a single Claude Code session.

## Status: 🚧 IN PROGRESS

Successfully refactored to use zen_websocket's ClientSupervisor for production-ready WebSocket connections.
All tests pass (86 tests, 0 failures). Currently implementing connection health monitoring.

## zen_websocket Design Philosophy

zen_websocket uses a "thin adapter" architecture with these principles:
- **5 Functions Max**: Each adapter should have maximum 5 public functions
- **GenServer-based Client**: Connection ownership stays with the Client GenServer
- **Automatic Reconnection**: Built-in exponential backoff with state preservation
- **Gun Transport**: Production-ready HTTP/2 & WebSocket client
- **Message Handlers**: Function-based handlers for platform-specific processing
- **Optional Supervision**: ClientSupervisor for production crash recovery

ZenCex now fully leverages zen_websocket's ClientSupervisor for robust supervision.

---

## ✅ COMPLETED TASKS

### Task 1: Fix Broken Supervisor Reference ✅ COMPLETE
**File**: `lib/zen_cex/safety/order_safety/market_data.ex:333`
**Status**: COMPLETE - Removed old WebSocket.Supervisor reference

### Task 2: Align Binance Adapter with zen_websocket 5-Function Rule ✅ COMPLETE
**File**: `lib/zen_cex/adapters/binance/websocket.ex`
**Status**: COMPLETE - Simplified to 5 functions, removed GenServer wrapper

**Final implementation**:
- `connect/2` - Connect with optional supervision
- `subscribe/2` - Subscribe to streams
- `unsubscribe/2` - Unsubscribe from streams  
- `close/1` - Close connection
- `get_state/1` - Get connection state

### Task 3: Simplify Bybit Adapter to Match zen_websocket Pattern ✅ COMPLETE
**File**: `lib/zen_cex/adapters/bybit/websocket.ex`
**Status**: COMPLETE - Simplified to 5 functions, removed GenServer wrapper

**Final implementation**:
- Same 5 functions as Binance adapter
- Properly handles Bybit-specific ping/pong
- Uses `:topics` parameter (not `:streams`)

### Task 4: Improve Error Handling Following zen_websocket Patterns ✅ COMPLETE
**Status**: COMPLETE - All functions return proper `{:ok, result} | {:error, reason}` tuples

### Task 5: Add WebSocket Integration Tests ✅ COMPLETE
**Files**: 
- `test/zen_cex/adapters/websocket_supervision_test.exs` (NEW)
- `test/zen_cex/adapters/websocket_reconnection_test.exs` (NEW)
**Status**: COMPLETE - Comprehensive tests for supervision and reconnection

**Test coverage**:
- Supervised connections via ClientSupervisor
- Automatic reconnection scenarios
- Message handler error recovery
- ETS cache continuity during failures
- Multiple concurrent connections
- **Result: 86 tests, 0 failures**

### Task 6: Use zen_websocket's ClientSupervisor ✅ COMPLETE
**File**: `lib/zen_cex/application.ex`
**Status**: COMPLETE - Added `ZenWebsocket.ClientSupervisor` to application supervisor

**Key changes**:
- ClientSupervisor now starts with application
- Adapters use `supervised: true` for production
- Direct connections available for development with `supervised: false`

### Task 6.1: Add @spec Annotations ✅ COMPLETE
**Files**: `lib/zen_cex/adapters/binance/websocket.ex`, `lib/zen_cex/adapters/bybit/websocket.ex`
**Status**: COMPLETE - All functions have proper @spec annotations

**Verification results**:
- Both adapters show 100% spec coverage in `mix doctor`
- All public functions (5 each) have @spec annotations
- All private helper functions have @spec annotations
- Compilation successful with no warnings
- Dialyzer passes for WebSocket modules

---

## Architecture After Refactor

### Simplified Adapter Pattern
Both Binance and Bybit adapters now:
1. Are thin wrappers over zen_websocket (no GenServer)
2. Have exactly 5 public functions
3. Use zen_websocket's ClientSupervisor for supervision
4. Handle message parsing via function handlers
5. Store data directly in ETS cache

### Connection Modes
```elixir
# Development - Direct connection
{:ok, ws} = Binance.WebSocket.connect(streams, testnet: true)

# Production - Supervised by ClientSupervisor
{:ok, ws} = Binance.WebSocket.connect(streams, testnet: true, supervised: true)
```

### Supervision Architecture
```
ZenCex.Application
├── ZenWebsocket.ClientSupervisor  # Manages all WebSocket connections
│   ├── Binance WebSocket Client(s)
│   └── Bybit WebSocket Client(s)
├── ZenCex.Core.Cache              # ETS cache for market data
├── ZenCex.Safety.OrderSafety      # Order idempotency
└── ZenCex.Safety.ClockSync        # Time synchronization
```

---

## 🔧 CURRENT TASK

### Task 7: Add Connection Health Monitoring
**Status**: IN PROGRESS
**Files to modify**:
- `lib/zen_cex/safety/order_safety/market_data.ex` - Fix TODO at line 333
- `lib/zen_cex/adapters/binance/websocket.ex` - Add health check support
- `lib/zen_cex/adapters/bybit/websocket.ex` - Add health check support

**Implementation plan**:
1. Implement `ensure_websocket_connection/2` in `market_data.ex`
2. Add connection registry to track active connections
3. Use zen_websocket's `get_heartbeat_health/1` for health checks
4. Add telemetry events for monitoring
5. Create test coverage for health monitoring

**zen_websocket provides**:
- `Client.get_heartbeat_health/1` - Returns heartbeat health status
- `Client.get_state/1` - Returns connection state (:connected, :connecting, :disconnected)
- `Client.get_state_metrics/1` - Returns detailed connection metrics

## Remaining Tasks (Optional Enhancements)

### Task 8: Document zen_websocket Integration Patterns
**Status**: PARTIALLY COMPLETE
- Usage documented in adapter @moduledoc
- Could add dedicated WebSocket usage guide if needed

### Task 9: Performance Optimization
**Status**: NOT NEEDED
- Current implementation handles high throughput well
- ETS cache provides sub-millisecond access
- zen_websocket handles backpressure

---

## Key Achievements

1. **Simplified Architecture** - Removed unnecessary GenServer wrappers
2. **Production-Ready Supervision** - Leveraging zen_websocket's ClientSupervisor
3. **Comprehensive Testing** - 86 tests covering all scenarios
4. **Clean Separation** - zen_websocket handles connection, adapters handle data
5. **5-Function Rule** - Both adapters follow zen_websocket's design philosophy
6. **Zero Test Failures** - All integration and unit tests pass

---

## Next Steps

The WebSocket refactor core functionality is complete. Task 7 (Connection Health Monitoring) is ready for implementation to add observability features.

### Continuation Prompt for Next Session

> Continue implementing Task 7: Add Connection Health Monitoring as specified in docs/ws_refactor.md. The task involves:
> 1. Implementing the `ensure_websocket_connection/2` function in `market_data.ex` (currently has a TODO)
> 2. Adding connection registry to track active WebSocket connections
> 3. Using zen_websocket's health check functions (`get_heartbeat_health/1`, `get_state/1`)
> 4. Adding telemetry events for monitoring
> 5. Creating tests for the health monitoring functionality