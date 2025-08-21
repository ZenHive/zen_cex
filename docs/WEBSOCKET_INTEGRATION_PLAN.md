# WebSocket Integration Plan for ZenCex

## Overview
This document outlines the integration of WebSocket functionality into ZenCex using ZenWebsocket as the underlying transport layer, with a macro-based code generation approach for exchange-specific implementations.

## Context
- **Current State**: ZenCex has REST API support for Binance, Kraken, and Deribit
- **Goal**: Add WebSocket support using similar declarative patterns as REST endpoints
- **Foundation**: ZenWebsocket library (linked in `external/zen_websocket`)
- **Approach**: Macro-generated WebSocket clients similar to `EndpointRegistry`

## Integration Prompt

### Task: Implement WebSocket Support for ZenCex

**Objective**: Create a WebSocket integration layer that mirrors the simplicity and declarative nature of the existing REST endpoint system.

**Key Requirements**:

1. **Create WebSocket Registry Macro** (`lib/zen_cex/websocket_registry.ex`)
   - Similar pattern to `EndpointRegistry` but for WebSocket streams
   - Generate subscription/unsubscription functions from declarative definitions
   - Auto-generate message routing and parsing dispatch
   - Support both public and authenticated streams

2. **Implement Binance WebSocket Adapter** (`lib/zen_cex/adapters/binance/websocket.ex`)
   - Use the WebSocket Registry macro
   - Define common streams: trade, kline, depth, bookTicker, user data
   - Implement parsers that normalize to ZenCex common format
   - Share parser utilities with REST where applicable (e.g., Decimal conversion)

3. **Create Mix Task for Generation** (`lib/mix/tasks/zen_cex.generate_websocket.ex`)
   - Fetch and parse exchange WebSocket documentation
   - Generate stream definitions from API specs
   - Create parser templates based on message structures
   - Similar to existing `generate_futures_endpoints.ex` task

4. **Integration Points with Existing Architecture**:
   - Reuse `Behaviors.Parser` patterns for message normalization
   - Share auth modules for signed WebSocket connections (user data streams)
   - Emit telemetry events consistent with REST operations
   - Use same error handling patterns (`{:ok, _}` / `{:error, _}`)

## Technical Design

### Stream Definition Structure
```elixir
@streams [
  %{
    name: :trade,                                    # Atom identifier
    params: [:symbol],                               # Required parameters
    subscribe_msg: fn symbol -> %{...} end,         # Subscription message builder
    unsubscribe_msg: fn symbol -> %{...} end,       # Unsubscription message builder
    parser: :parse_trade,                           # Parser function name
    matcher: fn msg -> msg["e"] == "trade" end,     # Message type matcher
    auth: false                                     # Authentication requirement
  }
]
```

### Generated API Example
```elixir
# Generated subscription functions
Binance.WebSocket.subscribe_trade("BTCUSDT")
Binance.WebSocket.subscribe_kline("BTCUSDT", "1m")
Binance.WebSocket.subscribe_user_data(listen_key)

# Generated callbacks for PubSub or handler registration
Binance.WebSocket.on_trade("BTCUSDT", &handle_trade/1)
```

### Parser Normalization
- Convert exchange-specific formats to common ZenCex types
- Use Decimal for all numeric values
- Consistent timestamp handling (Unix ms)
- Map exchange status codes to common enums

## Implementation Steps

### Phase 1: Foundation (2-3 hours)
1. Study ZenWebsocket client patterns in `external/zen_websocket`
2. Create `WebSocketRegistry` macro with basic function generation
3. Set up GenServer wrapper around ZenWebsocket.Client
4. Implement subscription tracking and message routing

### Phase 2: Binance Prototype (2-3 hours)
1. Create Binance WebSocket module using the macro
2. Define 3-4 core stream types (trade, kline, depth)
3. Implement and test parsers with real Binance testnet
4. Verify reconnection and error handling

### Phase 3: Generation Tooling (2-3 hours)
1. Create mix task for WebSocket generation
2. Parse Binance WebSocket docs (JSON format available)
3. Generate stream definitions and basic parsers
4. Create templates for common patterns

### Phase 4: Full Integration (2-3 hours)
1. Add remaining Binance streams
2. Implement Kraken WebSocket (different format)
3. Implement Deribit WebSocket (JSON-RPC style)
4. Add comprehensive tests with real testnet APIs

## Testing Strategy

### Unit Tests
- Parser functions (pure, no I/O)
- Message routing logic
- Subscription state management

### Integration Tests
```elixir
@tag :integration
test "subscribes to real Binance testnet trade stream" do
  {:ok, _} = Binance.WebSocket.start_link()
  :ok = Binance.WebSocket.subscribe_trade("BTCUSDT")
  
  assert_receive {:trade, %{symbol: "BTCUSDT", price: _}}, 5_000
end
```

### Performance Tests
- Handle 1000+ concurrent subscriptions
- Process 10,000+ messages/second
- Measure memory growth under load
- Verify cleanup on unsubscribe

## Success Criteria

1. **API Simplicity**: Single function call to subscribe/unsubscribe
2. **Reliability**: Automatic reconnection with resubscription
3. **Performance**: Handle high message rates without blocking
4. **Maintainability**: Adding new streams requires minimal code
5. **Consistency**: Similar patterns to REST implementation
6. **Testability**: Easy to test with real and simulated streams

## Files to Reference

### Existing Patterns to Follow
- `lib/zen_cex/core/endpoint_registry.ex` - Macro pattern for code generation
- `lib/zen_cex/adapters/binance/endpoints.ex` - Declarative endpoint definitions
- `lib/mix/tasks/zen_cex.generate_futures_endpoints.ex` - API doc parsing
- `lib/zen_cex/behaviors/parser.ex` - Parser behavior to implement

### ZenWebsocket Files to Study
- `external/zen_websocket/lib/zen_websocket/client.ex` - Client API
- `external/zen_websocket/lib/zen_websocket/examples/` - Platform adapters
- `external/zen_websocket/lib/zen_websocket/message_handler.ex` - Message routing

## Notes

- WebSocket is supplementary to REST, not a replacement
- Focus on market data and user data streams (not order placement)
- Maintain REST-first philosophy per CLAUDE.md guidelines
- Consider rate limits for WebSocket connections (different from REST)
- Some exchanges limit concurrent WebSocket connections

## Command to Start Implementation

```bash
# When ready to implement, use this prompt:
"Implement WebSocket support for ZenCex following the plan in docs/WEBSOCKET_INTEGRATION_PLAN.md. 
Start with Phase 1: Create the WebSocketRegistry macro that generates subscription functions and 
message routing from declarative stream definitions. Reference the existing EndpointRegistry pattern 
and use ZenWebsocket from external/zen_websocket as the transport layer."
```