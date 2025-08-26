defmodule ZenCex.Adapters.Bybit.Unified do
  @moduledoc """
  Unified trading endpoints for Bybit v5 API.

  This module provides access to all Bybit v5 unified trading endpoints which
  serve spot, linear (USDT perpetual), inverse (coin perpetual), and options
  trading through a single API distinguished by the `category` parameter.

  ## Category Values

  - `"spot"` - Spot trading
  - `"linear"` - USDT-margined perpetual futures
  - `"inverse"` - Coin-margined perpetual futures
  - `"option"` - Options trading

  ## Usage

  Direct calls with category parameter:
      Unified.place_order(%{category: "spot", symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      Unified.cancel_order(%{category: "linear", symbol: "BTCUSDT", orderId: "abc123"})

  Or use the category-prefixed convenience functions defined in the main Endpoints module:
      Endpoints.spot_place_order(%{symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      Endpoints.linear_cancel_order(%{symbol: "BTCUSDT", orderId: "abc123"})
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Bybit.Endpoints

  alias ZenCex.Adapters.Bybit.EndpointLoader
  alias ZenCex.Adapters.Bybit.Parser
  alias ZenCex.Adapters.Bybit.RequestHelper

  require EndpointLoader

  # Load endpoints from generated file instead of inline definitions
  EndpointLoader.load_endpoints("generated_endpoints.ex")

  # The EndpointRegistry macro automatically generates functions for all operations

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Use the unified API helper
    RequestHelper.execute_request_for_unified_api(config, params, opts)
  end
end
