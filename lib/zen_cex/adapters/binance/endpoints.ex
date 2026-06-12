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
    test_url: "https://demo-api.binance.com"

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

  @doc """
  Returns the base URL for spot API (production).

  This 0-arity version defaults to spot API in production.
  """
  @spec base_url() :: String.t()
  def base_url do
    base_url(:spot, [])
  end

  @doc """
  Returns the base URL based on API type and options.

  ## Parameters
  - `api_type` - The API type (e.g., :spot, :usdm_futures, :portfolio)
  - `opts` - Keyword list of options:
    - `:testnet` - Boolean flag indicating testnet (true) or production (false).
      Default: false (production)

  ## Examples
      base_url(:spot, testnet: true)  # => "https://demo-api.binance.com"
      base_url(:spot, testnet: false) # => "https://api.binance.com"
      base_url(:spot)                 # => "https://api.binance.com" (production)
  """
  @spec base_url(atom(), keyword()) :: String.t() | {:error, atom()}
  def base_url(api_type, opts \\ [])

  def base_url(api_type, opts) do
    env = Keyword.get(opts, :testnet, :live)
    base_url_impl(env, api_type)
  end

  @spec base_url_impl(:demo | :testnet | :live, atom()) :: String.t() | {:error, atom()}
  defp base_url_impl(env, api_type)

  # ============================
  # Demo Trading (demo-fapi.binance.com / demo-api.binance.com)
  # ============================
  defp base_url_impl(:demo, :usdm_futures), do: "https://demo-fapi.binance.com"
  defp base_url_impl(:demo, :coinm_futures), do: "https://demo-fapi.binance.com"
  defp base_url_impl(:demo, :spot),          do: "https://demo-api.binance.com"
  defp base_url_impl(:demo, :margin),        do: "https://demo-api.binance.com"
  defp base_url_impl(:demo, :sapi),          do: {:error, :no_demo_for_sapi}
  defp base_url_impl(:demo, :portfolio),     do: {:error, :no_demo_for_portfolio}
  defp base_url_impl(:demo, _),              do: "https://demo-api.binance.com"

  # ============================
  # Futures Testnet (testnet.binancefuture.com / demo-api.binance.com for spot)
  # ============================
  defp base_url_impl(:testnet, :usdm_futures), do: "https://testnet.binancefuture.com"
  defp base_url_impl(:testnet, :coinm_futures), do: "https://testnet.binancefuture.com"
  defp base_url_impl(:testnet, :spot),          do: "https://testnet.binance.vision"
  defp base_url_impl(:testnet, :margin),        do: "https://testnet.binance.vision"
  defp base_url_impl(:testnet, :sapi),          do: {:error, :no_testnet_for_sapi}
  defp base_url_impl(:testnet, :portfolio),     do: {:error, :no_testnet_for_portfolio_margin}
  defp base_url_impl(:testnet, _),              do: "https://testnet.binance.vision"

  # ============================
  # Live / Production
  # ============================
  defp base_url_impl(:live, :spot),          do: "https://api.binance.com"
  defp base_url_impl(:live, :margin),        do: "https://api.binance.com"
  defp base_url_impl(:live, :sapi),          do: "https://api.binance.com"
  defp base_url_impl(:live, :usdm_futures),  do: "https://fapi.binance.com"
  defp base_url_impl(:live, :coinm_futures), do: "https://dapi.binance.com"
  defp base_url_impl(:live, :portfolio),     do: "https://papi.binance.com"
  defp base_url_impl(:live, _),              do: "https://api.binance.com"

  # Fallback for legacy boolean callers (should not happen in new code)
  defp base_url_impl(true, api_type),  do: base_url_impl(:testnet, api_type)
  defp base_url_impl(false, api_type), do: base_url_impl(:live, api_type)

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
