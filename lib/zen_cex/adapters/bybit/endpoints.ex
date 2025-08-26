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

  Future unified endpoints (will be implemented in Ticket #8):
      # Direct calls with category parameter
      Endpoints.place_order(%{category: "spot", symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      
      # Category-prefixed convenience functions
      Endpoints.spot_place_order(%{symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
      Endpoints.linear_place_order(%{symbol: "BTCUSDT", side: "Buy", qty: "0.01"})
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

  # Category-prefixed convenience functions for spot trading
  def spot_place_order(params), do: place_order(Map.put(params, :category, "spot"))
  def spot_place_order(params, opts), do: place_order(Map.put(params, :category, "spot"), opts)

  def spot_cancel_order(params), do: cancel_order(Map.put(params, :category, "spot"))
  def spot_cancel_order(params, opts), do: cancel_order(Map.put(params, :category, "spot"), opts)

  def spot_cancel_all_orders(params \\ %{}), do: cancel_all_orders(Map.put(params, :category, "spot"))
  def spot_cancel_all_orders(params, opts), do: cancel_all_orders(Map.put(params, :category, "spot"), opts)

  def spot_get_open_closed_orders(params), do: get_open_closed_orders(Map.put(params, :category, "spot"))
  def spot_get_open_closed_orders(params, opts), do: get_open_closed_orders(Map.put(params, :category, "spot"), opts)

  def spot_get_order_history(params \\ %{}), do: get_order_history(Map.put(params, :category, "spot"))
  def spot_get_order_history(params, opts), do: get_order_history(Map.put(params, :category, "spot"), opts)

  def spot_get_trade_history(params \\ %{}), do: get_trade_history(Map.put(params, :category, "spot"))
  def spot_get_trade_history(params, opts), do: get_trade_history(Map.put(params, :category, "spot"), opts)

  # Category-prefixed convenience functions for linear futures (USDT perpetual)
  def linear_place_order(params), do: place_order(Map.put(params, :category, "linear"))
  def linear_place_order(params, opts), do: place_order(Map.put(params, :category, "linear"), opts)

  def linear_cancel_order(params), do: cancel_order(Map.put(params, :category, "linear"))
  def linear_cancel_order(params, opts), do: cancel_order(Map.put(params, :category, "linear"), opts)

  def linear_cancel_all_orders(params \\ %{}), do: cancel_all_orders(Map.put(params, :category, "linear"))
  def linear_cancel_all_orders(params, opts), do: cancel_all_orders(Map.put(params, :category, "linear"), opts)

  def linear_get_open_closed_orders(params), do: get_open_closed_orders(Map.put(params, :category, "linear"))
  def linear_get_open_closed_orders(params, opts), do: get_open_closed_orders(Map.put(params, :category, "linear"), opts)

  def linear_get_order_history(params \\ %{}), do: get_order_history(Map.put(params, :category, "linear"))
  def linear_get_order_history(params, opts), do: get_order_history(Map.put(params, :category, "linear"), opts)

  def linear_get_position_list(params \\ %{}), do: get_position_list(Map.put(params, :category, "linear"))
  def linear_get_position_list(params, opts), do: get_position_list(Map.put(params, :category, "linear"), opts)

  def linear_set_leverage(params), do: set_leverage(Map.put(params, :category, "linear"))
  def linear_set_leverage(params, opts), do: set_leverage(Map.put(params, :category, "linear"), opts)

  def linear_create_trading_stop(params), do: create_trading_stop(Map.put(params, :category, "linear"))
  def linear_create_trading_stop(params, opts), do: create_trading_stop(Map.put(params, :category, "linear"), opts)

  def linear_get_trade_history(params \\ %{}), do: get_trade_history(Map.put(params, :category, "linear"))
  def linear_get_trade_history(params, opts), do: get_trade_history(Map.put(params, :category, "linear"), opts)

  # Category-prefixed convenience functions for inverse futures (coin-margined)
  def inverse_place_order(params), do: place_order(Map.put(params, :category, "inverse"))
  def inverse_place_order(params, opts), do: place_order(Map.put(params, :category, "inverse"), opts)

  def inverse_cancel_order(params), do: cancel_order(Map.put(params, :category, "inverse"))
  def inverse_cancel_order(params, opts), do: cancel_order(Map.put(params, :category, "inverse"), opts)

  def inverse_cancel_all_orders(params \\ %{}), do: cancel_all_orders(Map.put(params, :category, "inverse"))
  def inverse_cancel_all_orders(params, opts), do: cancel_all_orders(Map.put(params, :category, "inverse"), opts)

  def inverse_get_open_closed_orders(params), do: get_open_closed_orders(Map.put(params, :category, "inverse"))

  def inverse_get_open_closed_orders(params, opts),
    do: get_open_closed_orders(Map.put(params, :category, "inverse"), opts)

  def inverse_get_order_history(params \\ %{}), do: get_order_history(Map.put(params, :category, "inverse"))
  def inverse_get_order_history(params, opts), do: get_order_history(Map.put(params, :category, "inverse"), opts)

  def inverse_get_position_list(params \\ %{}), do: get_position_list(Map.put(params, :category, "inverse"))
  def inverse_get_position_list(params, opts), do: get_position_list(Map.put(params, :category, "inverse"), opts)

  def inverse_set_leverage(params), do: set_leverage(Map.put(params, :category, "inverse"))
  def inverse_set_leverage(params, opts), do: set_leverage(Map.put(params, :category, "inverse"), opts)

  def inverse_create_trading_stop(params), do: create_trading_stop(Map.put(params, :category, "inverse"))
  def inverse_create_trading_stop(params, opts), do: create_trading_stop(Map.put(params, :category, "inverse"), opts)

  def inverse_get_trade_history(params \\ %{}), do: get_trade_history(Map.put(params, :category, "inverse"))
  def inverse_get_trade_history(params, opts), do: get_trade_history(Map.put(params, :category, "inverse"), opts)

  # Category-prefixed convenience functions for options trading
  def option_place_order(params), do: place_order(Map.put(params, :category, "option"))
  def option_place_order(params, opts), do: place_order(Map.put(params, :category, "option"), opts)

  def option_cancel_order(params), do: cancel_order(Map.put(params, :category, "option"))
  def option_cancel_order(params, opts), do: cancel_order(Map.put(params, :category, "option"), opts)

  def option_cancel_all_orders(params \\ %{}), do: cancel_all_orders(Map.put(params, :category, "option"))
  def option_cancel_all_orders(params, opts), do: cancel_all_orders(Map.put(params, :category, "option"), opts)

  def option_get_open_closed_orders(params), do: get_open_closed_orders(Map.put(params, :category, "option"))
  def option_get_open_closed_orders(params, opts), do: get_open_closed_orders(Map.put(params, :category, "option"), opts)

  def option_get_order_history(params \\ %{}), do: get_order_history(Map.put(params, :category, "option"))
  def option_get_order_history(params, opts), do: get_order_history(Map.put(params, :category, "option"), opts)

  def option_get_position_list(params \\ %{}), do: get_position_list(Map.put(params, :category, "option"))
  def option_get_position_list(params, opts), do: get_position_list(Map.put(params, :category, "option"), opts)

  def option_get_trade_history(params \\ %{}), do: get_trade_history(Map.put(params, :category, "option"))
  def option_get_trade_history(params, opts), do: get_trade_history(Map.put(params, :category, "option"), opts)

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
