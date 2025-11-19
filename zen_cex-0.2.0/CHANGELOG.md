# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-01-13

### Added

#### Deribit Support (WebSocket-Only)
- **WebSocket-First Architecture**: JSON-RPC 2.0 protocol for all operations
- **Trading Operations**: Place, cancel, and edit orders via WebSocket
  - Order types: limit, market, stop-limit, stop-market
  - Time-in-force options: GTC, FOK, IOC
  - Advanced options: post-only, reduce-only, trigger orders
- **Market Data**: Subscription-based real-time data with ETS caching
  - Order books with configurable depth
  - Ticker data (mark price, funding rate, open interest)
  - Instruments metadata (contracts, expirations, specs)
- **Authentication**: OAuth 2.0 client credentials flow
- **Rate Limiter**: Built-in rate limiting for API compliance
- **Parser**: JSON-RPC 2.0 response normalization
- **RPC Module**: Centralized JSON-RPC method definitions
- **Comprehensive Tests**: Integration tests with shared WebSocket connections

#### Product Support
- **Spot Trading**: Zero-fee spot markets
- **Perpetuals**: BTC-PERPETUAL, ETH-PERPETUAL, SOL-PERPETUAL
- **Futures**: Dated contracts (e.g., BTC-29MAR24)
- **Options**: BTC/ETH/SOL options with full Greeks support

### Changed
- Updated zen_websocket to 0.1.4 for improved stability
- Optimized test suite with shared WebSocket connections

## [0.1.0] - 2025-01-XX

### Added

#### Core Infrastructure
- Req-centric HTTP client architecture with Finch connection pooling
- Built-in rate limiting with exchange-specific limits
- Clock synchronization with exchange servers for accurate timestamps
- Order safety system with idempotency checks
- Debug mode with curl export for troubleshooting
- Comprehensive telemetry integration
- ETS-based caching for market data

#### Binance Support (Complete)
- **Spot Trading**: Full order management (market, limit, stop-loss, OCO)
- **Margin Trading**: Cross and isolated margin support
- **USD-M Futures**: USDT-margined perpetual and delivery contracts
- **COIN-M Futures**: Coin-margined perpetual and delivery contracts
- **Portfolio Margin**: Unified account management
- **Market Data**: Tickers, order books, klines, trades, funding rates
- **WebSocket Streams**: Real-time market data with automatic caching
- **High-Level Strategies**: Auto-hedging, portfolio rebalancing, PAXG hedging

#### Bybit Support (Trading Complete)
- **Unified Trading API**: Spot, linear, and inverse products via category parameter
- **Spot Trading**: Complete order management
- **Linear Futures**: USDT perpetual contracts
- **Inverse Futures**: Coin-margined contracts
- **Market Data**: Basic ticker and order book support
- **WebSocket Streams**: Real-time data feeds

#### WebSocket Integration
- zen_websocket integration for production-grade WebSocket connections
- Automatic reconnection with exponential backoff
- Connection registry for tracking active streams
- Supervised WebSocket connections with automatic restart
- Message caching in ETS for fast access
- Health monitoring and heartbeat support

#### Developer Experience
- Real testnet integration tests (no mocks)
- Tidewave MCP server integration for development
- Comprehensive test utilities for external applications
- Environment variable-based configuration
- Per-request credential override support
- Endpoint discovery and introspection
- ExDoc documentation with examples

### Architecture Decisions
- Library-first design: no global configuration, explicit credentials
- Stateless operations with ETS for performance-critical state
- Compile-time endpoint registry with runtime validation
- Minimal supervision tree (only for critical components)
- Direct module usage (no delegation layers)

### Dependencies
- `req ~> 0.5.0` - HTTP client
- `finch ~> 0.20.0` - Connection pooling
- `zen_websocket 0.1.4` - WebSocket client
- `jason ~> 1.4` - JSON encoding/decoding
- `telemetry ~> 1.0` - Observability

[0.2.0]: https://github.com/ZenHive/zen_cex/releases/tag/v0.2.0
[0.1.0]: https://github.com/ZenHive/zen_cex/releases/tag/v0.1.0
