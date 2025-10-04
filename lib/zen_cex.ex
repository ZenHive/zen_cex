defmodule ZenCex do
  @moduledoc """
  ZenCex - A comprehensive Elixir library for centralized cryptocurrency exchange integrations.

  Provides unified REST and WebSocket access to major cryptocurrency exchanges with built-in
  safety features, rate limiting, and real-time data streaming.

  ## Features

  - **Multi-Exchange Support**: Binance (complete), Bybit (trading complete)
  - **REST + WebSocket**: Full HTTP API and real-time streaming support
  - **Built-in Safety**: Rate limiting, clock sync, order idempotency checks
  - **Production Ready**: Battle-tested WebSocket client with automatic reconnection
  - **High-Level Strategies**: Pre-built trading strategies for hedging and rebalancing
  - **Developer Friendly**: Comprehensive testing utilities and debug mode

  ## Quick Start

      # Import exchange modules directly
      alias ZenCex.Adapters.Binance.Spot
      alias ZenCex.Adapters.Binance.UsdmFutures

      # Check connectivity
      {:ok, _time} = Spot.get_server_time()

      # Get account balances
      {:ok, balances} = Spot.get_balances()

      # Place a market order
      {:ok, order} = Spot.place_order(%{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "MARKET",
        quantity: "0.001"
      })

      # WebSocket real-time data
      alias ZenCex.Adapters.Binance.WebSocket
      {:ok, client} = WebSocket.connect(["btcusdt@depth20", "ethusdt@ticker"])

  ## Architecture

  ZenCex uses a modular adapter-based architecture:

  - `ZenCex.Adapters.Binance.*` - Binance exchange integration
  - `ZenCex.Adapters.Bybit.*` - Bybit exchange integration
  - `ZenCex.Core.*` - Shared infrastructure (HTTP, caching, rate limiting)
  - `ZenCex.Safety.*` - Safety features (clock sync, order safety)
  - `ZenCex.Websocket.*` - WebSocket connection management

  ## Configuration

  No global configuration required. Pass credentials explicitly or via environment variables:

      # Via environment (recommended)
      export BINANCE_API_KEY="your_key"
      export BINANCE_API_SECRET="your_secret"

      # Or per-request
      Spot.get_balances(%{}, auth_credentials: %{
        api_key: "your_key",
        api_secret: "your_secret"
      })

  See the README for complete documentation and examples.
  """
end
