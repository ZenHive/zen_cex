defmodule ZenCex do
  @moduledoc """
  ZenCex - A comprehensive Elixir library for centralized cryptocurrency exchange integrations.

  Features:
  - Multi-exchange support (Binance, Kraken, Deribit, etc.)
  - Atomic rate limiting with sliding windows
  - OAuth token management with caching
  - Health monitoring and time synchronization
  - Comprehensive telemetry integration
  - REQ-based HTTP client with exchange optimizations

  ## Usage

      # Make authenticated requests
      ZenCex.HTTP.request(:binance, :get, "/api/v3/account", 
        auth: true,
        api_key: "your_key",
        api_secret: "your_secret"
      )

      # Check rate limits
      ZenCex.RateLimit.check_rate(:binance, "/api/v3/order", 1)

      # Monitor exchange health
      ZenCex.Health.check_exchange_sync(:binance)
  """

  # Main entry points - actual implementations are in submodules
  # Use ZenCex.HTTP.base_request/2 for HTTP requests
  # Use ZenCex.RateLimit.check_and_update/3 for rate limiting  
  # Use ZenCex.Health.check_exchange_sync/2 for health checks
end
