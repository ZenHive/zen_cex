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

  # TODO: Unified trading endpoints will be added in Ticket #8
  # These will include:
  # - place_order/1,2,3 (with category parameter)
  # - cancel_order/1,2,3
  # - get_order/1,2,3
  # - get_positions/1,2,3
  # - get_wallet_balance/1,2,3
  # Plus category-prefixed helpers:
  # - spot_place_order/1,2
  # - linear_place_order/1,2
  # - inverse_place_order/1,2
  # - option_place_order/1,2

  @doc """
  Lists all available endpoints for this exchange.

  Returns a list of endpoint operations that can be called.
  """
  @spec list_available_endpoints() :: [atom()]
  def list_available_endpoints do
    # Currently only Common endpoints are implemented
    Enum.map(Common.all_endpoints(), & &1.operation)
    # TODO: When Unified module is added in Ticket #8:
    # (Common.all_endpoints() ++ Unified.all_endpoints())
    # |> Enum.map(& &1.operation)
    # |> Enum.uniq()
  end

  @doc """
  Lists available endpoints filtered by category.

  For Bybit, categories are: :common, :spot, :linear, :inverse, :option
  """
  @spec list_available_endpoints(atom()) :: [atom()]
  def list_available_endpoints(category) when category in [:common] do
    # Currently only common endpoints
    Enum.map(Common.all_endpoints(), & &1.operation)
  end

  def list_available_endpoints(category) when category in [:spot, :linear, :inverse, :option] do
    # TODO: Filter unified endpoints by category when implemented in Ticket #8
    []
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
        # TODO: Try Unified module when implemented in Ticket #8
        nil

      endpoint ->
        endpoint
    end
  end
end
