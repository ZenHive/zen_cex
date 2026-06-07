# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2026-06-07

### Fixed

#### Binance WebSocket — 2026 新架构适配（4 项 bug 修复）

Binance 于 2026 年 4 月 23 日对 Futures WebSocket 端点进行了重大架构调整，
将原来统一的 `/ws/<stream>` 拆分为三条独立通道（`/public`、`/market`、`/private`）。
本次修复解决了适配过程中发现的 4 个功能性 bug，均通过真实下单的集成测试验证。

- **`create_message_handler` 死分支清理**：移除永远不会触发的 `{:message, {:text, data}}`
  和 `{:message, {:binary, data}}` 分支。zen_websocket 实际分发的是已解码 map
  `{:message, %{}}` 而非原始 binary tuple，死分支造成代码误导。

- **`wrap_handler` 未解包 stream wrapper 传给 user handler**（功能 bug）：
  多事件私有流响应格式为 `{"stream": "lk@EVENT", "data": {...}}`，
  旧实现对内置缓存做了解包，但 `user_handler.(msg)` 传的仍是原始 wrapper（无 `"e"` key），
  导致 user handler 里所有基于 `"e"` 的事件匹配永远失败。
  修复：先 normalize（解包），再将 normalized_msg 传给 user handler 和内置缓存。

- **`markPriceUpdate` 事件类型错误**（功能 bug）：
  Binance futures markPrice stream 实际推送 `e: "markPriceUpdate"`，
  不是 `"markPrice"`。旧代码只有 `"markPrice"` 分支，导致 markPrice 数据
  全部进入 `Unhandled` 分支，ETS 永远没有 markPrice 缓存。
  修复：`t when t in ["markPrice", "markPriceUpdate"]`。

- **`process_user_data_event` symbol 提取错误**（功能 bug）：
  旧代码用 `get_in(data, ["o", "s"])` 提取 symbol，只对 `ORDER_TRADE_UPDATE` 有效。
  `ACCOUNT_UPDATE`、`ACCOUNT_CONFIG_UPDATE`、`MARGIN_CALL` 无此路径，
  全部以 `"unknown"` 为 ETS key 存储，导致无法按 symbol 查询。
  修复：fallback 到 `"_account"` key。

### Added

- **Binance 2026 WS 架构使用文档**：`docs/binance_ws_2026.md`
  - 三通道端点说明（`futures_public` / `futures_market` / `futures_private`）
  - 单事件 vs 多事件私有流连接示例
  - ETS 缓存键速查表
  - listenKey 管理说明
  - 常见问题排查

- **集成测试脚本**：`scripts/test_ws_full.exs`（10 项测试，全部真实断言）
  - T1–T4：ETS 缓存填充验证（kline、markPrice、orderbook、trade）
  - T5–T7：真实下单触发 ORDER_TRADE_UPDATE 私有流事件
  - T8：URL 构造验证（单事件 vs 多事件）
  - T9：动态 subscribe/unsubscribe
  - T10：`get_state/1` 连接状态验证

### Security

- 测试日志中 listenKey 截断为前 8 位 + `...`，避免完整 token 出现在日志或 CI 输出中

## [0.2.1] - 2025-01-19

### Added
- **Deribit Examples**: Complete trading workflow examples (`DeribitTrading` module)
  - Connection and authentication examples
  - Order placement (limit and market)
  - Order management (cancel, edit)
  - Order queries with filtering
  - Comprehensive integration tests with DeribitTestHelpers
- **Documentation**: Added Deribit section to README
  - Auto-generated examples from module documentation
  - Updated API Coverage section with Deribit features
  - Added Deribit testnet setup instructions

### Changed
- Updated README to reflect Deribit as implemented (not planned)
- Added DeribitTrading to README generator module list
- Enhanced IntegrationCase to support Deribit testnet credentials

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

[0.2.2]: https://github.com/superdecentman/zen_cex/tree/fix/binance-2026-ws-architecture
[0.2.1]: https://github.com/ZenHive/zen_cex/releases/tag/v0.2.1
[0.2.0]: https://github.com/ZenHive/zen_cex/releases/tag/v0.2.0
[0.1.0]: https://github.com/ZenHive/zen_cex/releases/tag/v0.1.0
