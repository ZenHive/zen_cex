defmodule ZenCex.Adapters.Binance.Endpoints do
  @moduledoc """
  Registry and discovery module for Binance exchange endpoints.

  This module provides registry functions for Core.Registry and endpoint discovery,
  but does NOT contain any actual endpoint implementations. Use the specific
  API modules directly for calling endpoints.

  ## Architecture

  This is a REGISTRY/DISCOVERY module only. All endpoints are implemented in:
  - `Binance.Spot` - Spot trading endpoints
  - `Binance.Margin` - Cross and Isolated margin trading endpoints
  - `Binance.UsdmFutures` - USD-M Futures (USDT-margined) trading endpoints
  - `Binance.CoinmFutures` - COIN-M Futures (coin-margined) trading endpoints
  - `Binance.PortfolioMargin` - Portfolio margin trading endpoints
  - `Binance.Common` - Shared endpoints (server_time, etc.)
  - `Binance.MarketData` - Public market data endpoints

  ## Usage

  Use the specific modules directly:

      alias ZenCex.Adapters.Binance.Spot
      alias ZenCex.Adapters.Binance.UsdmFutures
      alias ZenCex.Adapters.Binance.Common
      
      # Direct module usage
      Spot.get_balances()
      Spot.place_order(%{symbol: "BTCUSDT", side: "BUY", quantity: "0.01"})
      
      UsdmFutures.get_positions()
      Common.get_server_time()

  ## Discovery Functions

  This module provides discovery functions to explore available endpoints:

      # List all available endpoints
      Endpoints.list_available_endpoints()
      
      # List endpoints by API type
      Endpoints.list_available_endpoints(:spot)
      
      # Get detailed endpoint information
      Endpoints.get_endpoint_info(:get_balances, :spot)
  """

  use ZenCex.Adapters.BaseEndpoints,
    exchange: :binance,
    prod_url: "https://api.binance.com",
    test_url: "https://testnet.binance.vision"

  alias ZenCex.Adapters.Binance.Auth
  alias ZenCex.Adapters.Binance.CoinmFutures
  alias ZenCex.Adapters.Binance.Common
  alias ZenCex.Adapters.Binance.Margin
  alias ZenCex.Adapters.Binance.MarketData
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.PortfolioMargin
  alias ZenCex.Adapters.Binance.RateLimiter
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Adapters.Binance.UsdmFutures

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

  # Override base_url to support API type-specific URLs
  @doc """
  Returns the base URL for the current environment.
  """
  @spec base_url() :: String.t()
  def base_url do
    base_url(current_env())
  end

  @doc """
  Returns the base URL for the specified environment.
  """
  @spec base_url(:test | :prod) :: String.t()
  def base_url(:test), do: "https://testnet.binance.vision"
  def base_url(:prod), do: "https://api.binance.com"

  @doc """
  Returns the base URL for the specified environment and API type.
  """
  @spec base_url(:test | :prod, atom()) :: String.t() | {:error, atom()}
  def base_url(env, api_type)

  # ============================
  # Testnet Environment
  # ============================

  # Spot (and Margin) — only /api/* endpoints (NOT /sapi/*)
  def base_url(:test, :spot), do: "https://testnet.binance.vision"
  def base_url(:test, :margin), do: "https://testnet.binance.vision"

  # USD-M Futures Testnet
  def base_url(:test, :usdm_futures), do: "https://testnet.binancefuture.com"

  # COIN-M Futures Testnet
  def base_url(:test, :coinm_futures), do: "https://testnet.binancefuture.com"

  # SAPI endpoints are NOT supported on Testnet
  def base_url(:test, :sapi), do: {:error, :no_testnet_for_sapi}

  # Portfolio Margin endpoints are NOT supported on Testnet
  def base_url(:test, :portfolio), do: {:error, :no_testnet_for_portfolio_margin}

  # Default to Spot Testnet
  def base_url(:test, _), do: "https://testnet.binance.vision"

  # ============================
  # Production Environment
  # ============================

  # Spot + Margin
  def base_url(:prod, :spot), do: "https://api.binance.com"
  def base_url(:prod, :margin), do: "https://api.binance.com"

  # SAPI (sub-account, fiat, etc.)
  def base_url(:prod, :sapi), do: "https://api.binance.com"

  # USD-M Futures
  def base_url(:prod, :usdm_futures), do: "https://fapi.binance.com"

  # COIN-M Futures
  def base_url(:prod, :coinm_futures), do: "https://dapi.binance.com"

  # Portfolio Margin
  def base_url(:prod, :portfolio), do: "https://papi.binance.com"

  # Default to Spot
  def base_url(:prod, _), do: "https://api.binance.com"

  # ============================================================================
  # Discovery Functions
  # ============================================================================

  @doc """
  Returns the API module for a given type.

  ## Examples

      iex> Endpoints.get_module(:spot)
      ZenCex.Adapters.Binance.Spot
      
      iex> Endpoints.get_module(:usdm_futures)
      ZenCex.Adapters.Binance.UsdmFutures
  """
  @spec get_module(atom()) :: module() | nil
  def get_module(api_type) do
    case api_type do
      :spot -> Spot
      :margin -> Margin
      :usdm_futures -> UsdmFutures
      :coinm_futures -> CoinmFutures
      :portfolio -> PortfolioMargin
      :common -> Common
      :market_data -> MarketData
      _ -> nil
    end
  end

  @doc """
  Returns all available API types.

  ## Examples

      iex> Endpoints.list_api_types()
      [:spot, :margin, :usdm_futures, :coinm_futures, :portfolio, :common, :market_data]
  """
  @spec list_api_types() :: [atom()]
  def list_api_types do
    [:spot, :margin, :usdm_futures, :coinm_futures, :portfolio, :common, :market_data]
  end

  @doc """
  Lists all available endpoint operations across all API types.

  Returns a list of atoms representing all available operations,
  optionally filtered by API type.

  ## Examples

      # Get all endpoints
      iex> Endpoints.list_available_endpoints()
      [:get_balances, :place_order, :get_positions, ...]
      
      # Filter by API type
      iex> Endpoints.list_available_endpoints(:spot)
      [:get_balances, :place_order, :cancel_order, ...]
      
      iex> Endpoints.list_available_endpoints(:usdm_futures)
      [:get_positions, :place_order, :cancel_order, ...]
  """
  @spec list_available_endpoints() :: [atom()]
  @spec list_available_endpoints(atom()) :: [atom()]
  def list_available_endpoints(api_type \\ :all) do
    case api_type do
      :all ->
        # Collect all endpoints from all modules
        all =
          Common.all_endpoints() ++
            MarketData.all_endpoints() ++
            Spot.all_endpoints() ++
            Margin.all_endpoints() ++
            UsdmFutures.all_endpoints() ++
            CoinmFutures.all_endpoints() ++
            PortfolioMargin.all_endpoints()

        all
        |> Enum.map(& &1.operation)
        |> Enum.sort()
        |> Enum.uniq()

      :spot ->
        Spot.all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      :usdm_futures ->
        UsdmFutures.all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      :coinm_futures ->
        CoinmFutures.all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      :margin ->
        Margin.all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      :portfolio ->
        PortfolioMargin.all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      :common ->
        Common.all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      :market_data ->
        MarketData.all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()

      _ ->
        []
    end
  end

  @doc """
  Returns detailed information about a specific endpoint operation.

  Returns a map with endpoint configuration including method, path,
  authentication requirements, rate limits, and documentation.

  ## Parameters
  - `operation` - The operation name (e.g., :get_balances, :place_order)
  - `api_type` - The API type (:spot, :margin, :usdm_futures, etc.)

  ## Examples

      iex> Endpoints.get_endpoint_info(:get_balances, :spot)
      %{
        operation: :get_balances,
        method: :get,
        path: "/api/v3/account",
        requires_auth: true,
        weight: 10,
        doc: "Get current account information",
        timeout: 5000,
        max_retries: 3
      }
      
      iex> Endpoints.get_endpoint_info(:nonexistent, :spot)
      nil
  """
  @spec get_endpoint_info(atom(), atom()) :: map() | nil
  def get_endpoint_info(operation, api_type) do
    with module when not is_nil(module) <- get_module(api_type),
         endpoint when not is_nil(endpoint) <- module.get_endpoint(operation) do
      endpoint
      |> Map.put(:api_type, api_type)
      |> Map.put(:module, module)
      |> Map.put(:available_arities, get_available_arities(module, operation))
    else
      _ -> nil
    end
  end

  # Helper to determine available function arities for an operation in a module
  defp get_available_arities(module, operation) do
    0..2
    |> Enum.filter(&function_exported?(module, operation, &1))
    |> Enum.reverse()
  end
end
