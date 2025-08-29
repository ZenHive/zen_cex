defmodule ZenCex.Adapters.Bybit.Endpoints do
  @moduledoc """
  Registry and discovery module for Bybit exchange endpoints.

  This module provides registry functions for Core.Registry and endpoint discovery,
  but does NOT contain any actual endpoint implementations. Use the specific
  API modules directly for calling endpoints.

  ## Architecture

  This is a REGISTRY/DISCOVERY module only. All endpoints are implemented in:
  - `Bybit.Common` - Shared endpoints (server_time, announcements, etc.)
  - `Bybit.Unified` - Trading endpoints (orders, positions, account)
  - `Bybit.MarketData` - Public market data endpoints

  ## Unified API Categories

  Bybit v5 uses these category values:
  - `"spot"` - Spot trading
  - `"linear"` - USDT-margined perpetual futures
  - `"inverse"` - Coin-margined perpetual futures
  - `"option"` - Options trading

  ## Usage

  Use the specific modules directly:

      alias ZenCex.Adapters.Bybit.Common
      alias ZenCex.Adapters.Bybit.Unified
      alias ZenCex.Adapters.Bybit.MarketData

      # Direct module usage
      Common.get_server_time()
      Unified.place_order(%{category: "spot", symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      MarketData.get_tickers(%{category: "spot"})

  ## Discovery Functions

  This module provides discovery functions to explore available endpoints:

      # List all available endpoints
      Endpoints.list_available_endpoints()

      # List endpoints by category
      Endpoints.list_available_endpoints(:unified)

      # Get detailed endpoint information
      Endpoints.get_endpoint_info(:place_order, :unified)
  """

  use ZenCex.Adapters.BaseEndpoints,
    exchange: :bybit,
    prod_url: "https://api.bybit.com",
    test_url: "https://api-testnet.bybit.com"

  alias ZenCex.Adapters.Bybit.Auth
  alias ZenCex.Adapters.Bybit.Common
  alias ZenCex.Adapters.Bybit.MarketData
  alias ZenCex.Adapters.Bybit.Parser
  alias ZenCex.Adapters.Bybit.RateLimiter
  alias ZenCex.Adapters.Bybit.Unified

  @doc """
  Returns the auth module for this adapter.
  """
  @spec auth() :: module()
  def auth, do: Auth

  @doc """
  Returns the rate limiter module for this adapter.
  """
  @spec rate_limiter() :: module()
  def rate_limiter, do: RateLimiter

  @doc """
  Returns the parser module for this adapter.
  """
  @spec parser() :: module()
  def parser, do: Parser

  # Override base_url from BaseEndpoints to add support for explicit env parameter
  @doc """
  Returns the base URL for the current environment.
  """
  @spec base_url() :: String.t()
  def base_url do
    base_url(current_env())
  end

  @doc """
  Returns the base URL for the specified environment.

  Bybit uses a single unified API URL for all product types.
  """
  @spec base_url(:test | :prod) :: String.t()
  def base_url(:test), do: "https://api-testnet.bybit.com"
  def base_url(:prod), do: "https://api.bybit.com"

  # ============================================================================
  # Discovery Functions
  # ============================================================================

  @doc """
  Returns the API module for a given type.

  ## Examples

      iex> Endpoints.get_module(:unified)
      ZenCex.Adapters.Bybit.Unified

      iex> Endpoints.get_module(:common)
      ZenCex.Adapters.Bybit.Common
  """
  @spec get_module(atom()) :: module() | nil
  def get_module(api_type) do
    case api_type do
      :common -> Common
      :unified -> Unified
      :market_data -> MarketData
      _ -> nil
    end
  end

  @doc """
  Returns all available API types.

  ## Examples

      iex> Endpoints.list_api_types()
      [:common, :unified, :market_data]
  """
  @spec list_api_types() :: [atom()]
  def list_api_types do
    [:common, :unified, :market_data]
  end

  @doc """
  Lists all available endpoints for this exchange.

  Returns a list of endpoint operations that can be called.
  """
  @spec list_available_endpoints() :: [atom()]
  def list_available_endpoints do
    (Common.all_endpoints() ++ Unified.all_endpoints() ++ MarketData.all_endpoints())
    |> Enum.map(& &1.operation)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Lists available endpoints for a specific API category.

  ## Parameters
  - `category` - The API category (:common, :unified, :market_data, :spot, :linear, :inverse, :option)

  ## Examples

      iex> Endpoints.list_available_endpoints(:unified)
      [:place_order, :cancel_order, ...]

      iex> Endpoints.list_available_endpoints(:spot)
      [:place_order, :cancel_order, ...] # No position endpoints for spot
  """
  @spec list_available_endpoints(atom()) :: [atom()]
  def list_available_endpoints(category) when category in [:common] do
    Enum.map(Common.all_endpoints(), & &1.operation)
  end

  def list_available_endpoints(category) when category in [:unified] do
    # All unified endpoints without filtering
    Enum.map(Unified.all_endpoints(), & &1.operation)
  end

  def list_available_endpoints(category) when category in [:market_data] do
    # All market data endpoints
    Enum.map(MarketData.all_endpoints(), & &1.operation)
  end

  def list_available_endpoints(category) when category in [:spot, :linear, :inverse, :option] do
    # Filter endpoints that are available for the specific category
    # Spot doesn't have position-related endpoints
    base_endpoints = [
      :place_order,
      :cancel_order,
      :cancel_all_orders,
      :get_order,
      :get_order_history,
      :get_trades,
      :get_wallet_balance
    ]

    position_endpoints = [:get_positions, :set_leverage, :set_trading_stop]

    case category do
      :spot -> base_endpoints
      :linear -> base_endpoints ++ position_endpoints
      :inverse -> base_endpoints ++ position_endpoints
      # Options have positions but not leverage/stops
      :option -> base_endpoints ++ [:get_positions]
    end
  end

  def list_available_endpoints(_category) do
    []
  end

  @doc """
  Gets detailed information about an endpoint.

  Returns a map with endpoint configuration including method, path, auth requirements, etc.

  ## Parameters
  - `operation` - The operation name (e.g., :place_order, :get_server_time)
  - `api_type` - The API type (:common, :unified, :market_data)

  ## Examples

      iex> Endpoints.get_endpoint_info(:place_order, :unified)
      %{method: :post, path: "/v5/order/create", ...}
  """
  @spec get_endpoint_info(atom(), atom()) :: map() | nil
  def get_endpoint_info(operation, api_type) do
    with module when not is_nil(module) <- get_module(api_type),
         endpoint when not is_nil(endpoint) <- module.get_endpoint(operation) do
      endpoint
      |> Map.put(:api_type, api_type)
      |> Map.put(:module, module)
    else
      _ -> nil
    end
  end
end
