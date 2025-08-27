defmodule ZenCex.Adapters.Binance.Endpoints do
  @moduledoc """
  Router module for Binance exchange endpoints.

  This module is registered with Core.Registry and delegates to sub-modules
  for different API types (Spot, Futures, Margin) to maintain clarity.

  ## Architecture

  This is a ROUTER ONLY - it contains no endpoint definitions.
  All endpoints are defined in nested modules:
  - `Binance.Spot` - Spot trading endpoints
  - `Binance.Margin` - Cross and Isolated margin trading endpoints
  - `Binance.UsdmFutures` - USD-M Futures (USDT-margined) trading endpoints
  - `Binance.CoinmFutures` - COIN-M Futures (coin-margined) trading endpoints
  - `Binance.PortfolioMargin` - Portfolio margin trading endpoints
  - `Binance.Common` - Shared endpoints (server_time, etc.)

  ## Usage

  The router automatically delegates based on function prefixes:
  - Functions starting with `spot_` → Binance.Spot
  - Functions starting with `margin_` → Binance.Margin
  - Functions starting with `usdm_` → Binance.UsdmFutures
  - Functions starting with `coinm_` → Binance.CoinmFutures
  - Functions starting with `portfolio_` → Binance.PortfolioMargin
  - Common functions (no prefix) → Binance.Common

  ## Examples

      # Prefixed functions for clarity
      Endpoints.spot_get_balances()
      Endpoints.spot_place_order(%{symbol: "BTCUSDT", side: "BUY", quantity: "0.01"})
      
      Endpoints.usdm_get_positions()
      Endpoints.usdm_place_order(%{symbol: "BTCUSDT", side: "LONG", quantity: "0.01"})
      
      Endpoints.portfolio_get_unified_account()
      Endpoints.portfolio_place_unified_order(%{symbol: "BTCUSDT", side: "BUY"})
      
      # Common endpoints without prefix
      Endpoints.get_server_time()
  """

  use ZenCex.Adapters.BaseEndpoints,
    exchange: :binance,
    prod_url: "https://api.binance.com",
    test_url: "https://testnet.binance.vision"

  alias ZenCex.Adapters.Binance.Auth
  alias ZenCex.Adapters.Binance.CoinmFutures
  alias ZenCex.Adapters.Binance.Common
  alias ZenCex.Adapters.Binance.Margin
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
  # Delegation to nested modules with prefixed names
  # ============================================================================

  # Common endpoints (shared across all API types - no prefix needed)
  defdelegate get_server_time(), to: Common
  defdelegate get_server_time(opts), to: Common

  # Spot trading endpoints with spot_ prefix
  defdelegate spot_get_balances(), to: Spot, as: :get_balances
  defdelegate spot_get_balances(opts), to: Spot, as: :get_balances
  defdelegate spot_get_balances(params, opts), to: Spot, as: :get_balances

  defdelegate spot_place_order(), to: Spot, as: :place_order
  defdelegate spot_place_order(params), to: Spot, as: :place_order
  defdelegate spot_place_order(params, opts), to: Spot, as: :place_order

  defdelegate spot_cancel_order(), to: Spot, as: :cancel_order
  defdelegate spot_cancel_order(params), to: Spot, as: :cancel_order
  defdelegate spot_cancel_order(params, opts), to: Spot, as: :cancel_order

  defdelegate spot_get_order(), to: Spot, as: :get_order
  defdelegate spot_get_order(params), to: Spot, as: :get_order
  defdelegate spot_get_order(params, opts), to: Spot, as: :get_order

  defdelegate spot_place_oco_order(params), to: Spot, as: :place_oco_order
  defdelegate spot_batch_cancel_orders(params), to: Spot, as: :batch_cancel_orders

  # USD-M Futures trading endpoints with usdm_ prefix
  defdelegate usdm_get_positions(), to: UsdmFutures, as: :get_positions
  defdelegate usdm_get_positions(opts), to: UsdmFutures, as: :get_positions
  defdelegate usdm_get_positions(params, opts), to: UsdmFutures, as: :get_positions

  # Portfolio Margin trading endpoints with portfolio_ prefix
  # Custom wrapper functions (not in endpoint registry)
  defdelegate portfolio_get_unified_account(), to: PortfolioMargin, as: :get_unified_account
  defdelegate portfolio_get_unified_account(params), to: PortfolioMargin, as: :get_unified_account
  defdelegate portfolio_get_unified_account(params, opts), to: PortfolioMargin, as: :get_unified_account

  defdelegate portfolio_place_unified_order(params), to: PortfolioMargin, as: :place_unified_order
  defdelegate portfolio_place_unified_order(params, opts), to: PortfolioMargin, as: :place_unified_order

  defdelegate portfolio_get_all_positions(), to: PortfolioMargin, as: :get_all_positions
  defdelegate portfolio_get_all_positions(params), to: PortfolioMargin, as: :get_all_positions
  defdelegate portfolio_get_all_positions(params, opts), to: PortfolioMargin, as: :get_all_positions

  # Endpoint registry functions from PortfolioMargin
  defdelegate portfolio_account_information(), to: PortfolioMargin, as: :account_information
  defdelegate portfolio_account_information(params), to: PortfolioMargin, as: :account_information
  defdelegate portfolio_account_information(params, opts), to: PortfolioMargin, as: :account_information

  defdelegate portfolio_account_balance(), to: PortfolioMargin, as: :account_balance
  defdelegate portfolio_account_balance(params), to: PortfolioMargin, as: :account_balance
  defdelegate portfolio_account_balance(params, opts), to: PortfolioMargin, as: :account_balance

  # ============================================================================
  # Registry compatibility functions
  # These are needed for tests and backward compatibility
  # ============================================================================

  @doc """
  Returns endpoint configuration for the given operation.
  Routes to the appropriate module based on the operation name prefix.
  """
  @spec get_endpoint(atom()) :: map() | nil
  def get_endpoint(operation) do
    # Extract prefix and operation name
    {prefix, base_op} = extract_prefix(operation)

    # Route based on prefix
    case prefix do
      :spot ->
        Spot.get_endpoint(base_op)

      :usdm ->
        UsdmFutures.get_endpoint(base_op)

      :coinm ->
        CoinmFutures.get_endpoint(base_op)

      :margin ->
        Margin.get_endpoint(base_op)

      :portfolio ->
        PortfolioMargin.get_endpoint(base_op)

      nil ->
        # No prefix - check if it's a common operation
        if operation in [:get_server_time] do
          Common.get_endpoint(operation)
        end
    end
  end

  # Extract prefix from operation name
  defp extract_prefix(operation) do
    # Pattern match on the string representation for better performance
    case Atom.to_string(operation) do
      "spot_" <> rest ->
        {:spot, String.to_atom(rest)}

      "usdm_" <> rest ->
        {:usdm, String.to_atom(rest)}

      "coinm_" <> rest ->
        {:coinm, String.to_atom(rest)}

      "margin_" <> rest ->
        {:margin, String.to_atom(rest)}

      "portfolio_" <> rest ->
        {:portfolio, String.to_atom(rest)}

      _ ->
        {nil, operation}
    end
  end

  @doc """
  Returns all endpoints from all modules.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints do
    Common.all_endpoints() ++
      Spot.all_endpoints() ++
      UsdmFutures.all_endpoints() ++
      CoinmFutures.all_endpoints() ++
      PortfolioMargin.all_endpoints()
  end

  @doc """
  Returns the weight for a given operation.
  """
  @spec get_weight(atom()) :: integer() | nil
  def get_weight(operation) do
    case get_endpoint(operation) do
      nil -> nil
      config -> config[:weight]
    end
  end

  # ============================================================================
  # Endpoint Discovery Functions
  # ============================================================================

  @doc """
  Lists all available endpoint operations across all API types.

  Returns a list of atoms representing all available operations,
  optionally filtered by API type.

  ## Examples

      # Get all endpoints
      iex> Endpoints.list_available_endpoints()
      [:spot_get_balances, :spot_place_order, :usdm_get_positions, ...]
      
      # Filter by API type
      iex> Endpoints.list_available_endpoints(:spot)
      [:spot_get_balances, :spot_place_order, :spot_cancel_order, ...]
      
      iex> Endpoints.list_available_endpoints(:usdm_futures)
      [:usdm_get_positions, :usdm_place_order, :usdm_cancel_order, ...]
  """
  @spec list_available_endpoints() :: [atom()]
  @spec list_available_endpoints(atom()) :: [atom()]
  def list_available_endpoints(api_type \\ :all) do
    case api_type do
      :all ->
        all_endpoints()
        |> Enum.map(& &1.operation)
        |> Enum.sort()
        |> Enum.uniq()

      :spot ->
        Spot.all_endpoints()
        |> Enum.map(fn ep -> :"spot_#{ep.operation}" end)
        |> Enum.sort()

      :usdm_futures ->
        UsdmFutures.all_endpoints()
        |> Enum.map(fn ep -> :"usdm_#{ep.operation}" end)
        |> Enum.sort()

      :coinm_futures ->
        CoinmFutures.all_endpoints()
        |> Enum.map(fn ep -> :"coinm_#{ep.operation}" end)
        |> Enum.sort()

      :margin ->
        Margin.all_endpoints()
        |> Enum.map(fn ep -> :"margin_#{ep.operation}" end)
        |> Enum.sort()

      :portfolio ->
        PortfolioMargin.all_endpoints()
        |> Enum.map(fn ep -> :"portfolio_#{ep.operation}" end)
        |> Enum.sort()

      :common ->
        Common.all_endpoints()
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

  ## Examples

      iex> Endpoints.get_endpoint_info(:spot_get_balances)
      %{
        operation: :get_balances,
        method: :get,
        path: "/api/v3/account",
        requires_auth: true,
        weight: 10,
        api_type: :spot,
        doc: "Get current account information",
        timeout: 5000,
        max_retries: 3
      }
      
      iex> Endpoints.get_endpoint_info(:nonexistent)
      nil
  """
  @spec get_endpoint_info(atom()) :: map() | nil
  def get_endpoint_info(operation) do
    case get_endpoint(operation) do
      nil ->
        nil

      endpoint ->
        # Add the full operation name with prefix
        {prefix, _base} = extract_prefix(operation)

        endpoint
        |> Map.put(:full_operation, operation)
        |> Map.put(:api_type_prefix, prefix)
        |> Map.put(:available_arities, get_available_arities(operation))
    end
  end

  # Helper to determine available function arities for an operation
  defp get_available_arities(operation) do
    # Check if the function exists with different arities (0, 1, or 2 params)
    0..2
    |> Enum.filter(&function_exported?(__MODULE__, operation, &1))
    |> Enum.reverse()
  end
end
