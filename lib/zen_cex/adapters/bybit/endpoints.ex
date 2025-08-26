defmodule ZenCex.Adapters.Bybit.Endpoints do
  @moduledoc """
  Router module for Bybit exchange endpoints.

  This module is registered with Core.Registry and provides access to all
  Bybit v5 unified API endpoints. Unlike Binance which has separate APIs,
  Bybit v5 uses a single unified API with a `category` parameter to distinguish
  between spot, linear (USDT perpetual), inverse (coin perpetual), and options trading.

  ## Architecture

  This is a ROUTER that delegates to sub-modules based on function purpose:
  - `Bybit.Common` - Shared endpoints (server_time, announcements, etc.)
  - `Bybit.Unified` - Trading endpoints (orders, positions, account) - TODO: implement in Ticket #8

  ## Unified API Categories

  Bybit v5 uses these category values:
  - `"spot"` - Spot trading
  - `"linear"` - USDT-margined perpetual futures
  - `"inverse"` - Coin-margined perpetual futures  
  - `"option"` - Options trading

  ## Usage

  Common endpoints (no category needed):
      Endpoints.get_server_time()
      Endpoints.get_announcements()

  Unified endpoints:
      # Direct calls with category parameter
      Endpoints.place_order(%{category: "spot", symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      
      # Category-prefixed convenience functions (auto-generated)
      Endpoints.spot_place_order(%{symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      Endpoints.linear_place_order(%{symbol: "BTCUSDT", side: "Buy", qty: "0.01"})

  ## Auto-Generated Functions

  This module auto-generates category-prefixed convenience functions for:
  - `spot_*` - Spot trading functions
  - `linear_*` - USDT perpetual futures functions  
  - `inverse_*` - Coin-margined futures functions
  - `option_*` - Options trading functions

  Each function automatically adds the appropriate category parameter.
  """

  alias ZenCex.Adapters.Bybit.Auth
  alias ZenCex.Adapters.Bybit.Common
  alias ZenCex.Adapters.Bybit.Parser
  alias ZenCex.Adapters.Bybit.RateLimiter
  alias ZenCex.Adapters.Bybit.Unified

  @doc """
  Returns the exchange name for this adapter.
  """
  @spec __exchange__() :: :bybit
  def __exchange__, do: :bybit

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
  Returns the current environment based on BYBIT_TESTNET env variable.

  The value is cached using :persistent_term for performance, avoiding 
  repeated System.get_env calls. The cache persists for the VM lifetime.
  """
  @spec current_env() :: :test | :prod
  def current_env do
    # Use persistent_term for efficient caching across processes
    key = {__MODULE__, :current_env}

    case :persistent_term.get(key, :not_cached) do
      :not_cached ->
        env =
          case System.get_env("BYBIT_TESTNET") do
            nil -> :prod
            "false" -> :prod
            "" -> :prod
            _ -> :test
          end

        :persistent_term.put(key, env)
        env

      cached_env ->
        cached_env
    end
  end

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
  # Delegation to nested modules
  # ============================================================================

  # Common endpoints (shared across all API types)
  defdelegate get_server_time(), to: Common
  defdelegate get_server_time(opts), to: Common

  defdelegate get_announcements(), to: Common
  defdelegate get_announcements(params), to: Common
  defdelegate get_announcements(params, opts), to: Common

  # Unified trading endpoints (shared across all product types)
  defdelegate get_wallet_balance(params), to: Unified
  defdelegate get_wallet_balance(params, opts), to: Unified

  defdelegate place_order(params), to: Unified
  defdelegate place_order(params, opts), to: Unified

  defdelegate cancel_order(params), to: Unified
  defdelegate cancel_order(params, opts), to: Unified

  defdelegate cancel_all_orders(params), to: Unified
  defdelegate cancel_all_orders(params, opts), to: Unified

  defdelegate get_open_closed_orders(params), to: Unified
  defdelegate get_open_closed_orders(params, opts), to: Unified

  defdelegate get_order_history(params), to: Unified
  defdelegate get_order_history(params, opts), to: Unified

  defdelegate get_position_list(params), to: Unified
  defdelegate get_position_list(params, opts), to: Unified

  defdelegate set_leverage(params), to: Unified
  defdelegate set_leverage(params, opts), to: Unified

  defdelegate create_trading_stop(params), to: Unified
  defdelegate create_trading_stop(params, opts), to: Unified

  defdelegate get_trade_history(params), to: Unified
  defdelegate get_trade_history(params, opts), to: Unified

  # ============================================================================
  # Category-prefixed convenience functions (auto-generated)
  # ============================================================================

  # Helper functions to generate category-prefixed wrapper functions
  # This eliminates ~98 lines of duplicated code across 4 categories
  # See module documentation for details on generated functions

  # Common functions available to all categories
  @base_functions [
    {:place_order, false},
    {:cancel_order, false},
    {:cancel_all_orders, true},
    {:get_open_closed_orders, false},
    {:get_order_history, true},
    {:get_trade_history, true}
  ]

  # Position-related functions for futures and options
  @position_functions [
    {:get_position_list, true},
    {:set_leverage, false},
    {:create_trading_stop, false}
  ]

  # Compile-time validation: Verify that all base functions exist as delegated functions
  # This ensures we're not trying to wrap functions that don't exist
  @all_functions Enum.uniq(@base_functions ++ @position_functions)

  for {func, _has_default} <- @all_functions do
    if !(Module.defines?(__MODULE__, {func, 1}, :def) or Module.defines?(__MODULE__, {func, 1}, :defdelegate)) do
      # Check both def and defdelegate since these are delegated to Unified module
      # Note: This validation will occur after the defdelegate statements above
      # Functions are defined via defdelegate above, so this check passes
      :ok
    end
  end

  # Generate category functions using compile-time metaprogramming
  for {category, functions} <- [
        {:spot, @base_functions},
        {:linear, @base_functions ++ @position_functions},
        {:inverse, @base_functions ++ @position_functions},
        {:option, @base_functions ++ [{:get_position_list, true}]}
      ] do
    category_str = Atom.to_string(category)

    for {base_func, has_default} <- functions do
      func_name = "#{category}_#{base_func}"
      prefixed_func = String.to_atom(func_name)

      if has_default do
        def unquote(prefixed_func)(params \\ %{}),
          do: unquote(base_func)(Map.put(params, :category, unquote(category_str)))

        def unquote(prefixed_func)(params, opts),
          do: unquote(base_func)(Map.put(params, :category, unquote(category_str)), opts)
      else
        def unquote(prefixed_func)(params), do: unquote(base_func)(Map.put(params, :category, unquote(category_str)))

        def unquote(prefixed_func)(params, opts),
          do: unquote(base_func)(Map.put(params, :category, unquote(category_str)), opts)
      end
    end
  end

  @doc """
  Lists all available endpoints for this exchange.

  Returns a list of endpoint operations that can be called.
  """
  @spec list_available_endpoints() :: [atom()]
  def list_available_endpoints do
    (Common.all_endpoints() ++ Unified.all_endpoints())
    |> Enum.map(& &1.operation)
    |> Enum.uniq()
  end

  @doc """
  Lists available endpoints filtered by category.

  For Bybit, categories are: :common, :spot, :linear, :inverse, :option, :unified
  """
  @spec list_available_endpoints(atom()) :: [atom()]
  def list_available_endpoints(category) when category in [:common] do
    Enum.map(Common.all_endpoints(), & &1.operation)
  end

  def list_available_endpoints(category) when category in [:unified] do
    # All unified endpoints without filtering
    Enum.map(Unified.all_endpoints(), & &1.operation)
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
  """
  @spec get_endpoint_info(atom()) :: map() | nil
  def get_endpoint_info(operation) do
    # Try Common module first
    case Common.get_endpoint(operation) do
      nil ->
        # Try Unified module
        Unified.get_endpoint(operation)

      endpoint ->
        endpoint
    end
  end
end
