defmodule ZenCex.Adapters.Binance.Endpoints do
  @moduledoc """
  Router module for Binance exchange endpoints.

  This module is registered with Core.Registry and delegates to sub-modules
  for different API types (Spot, Futures, Margin) to maintain clarity.

  ## Architecture

  This is a ROUTER ONLY - it contains no endpoint definitions.
  All endpoints are defined in nested modules:
  - `Binance.Spot` - Spot trading endpoints
  - `Binance.Futures` - Futures trading endpoints
  - `Binance.Margin` - Margin trading endpoints
  - `Binance.Common` - Shared endpoints (server_time, etc.)

  ## Usage

  The router automatically delegates based on function prefixes:
  - Functions starting with `spot_` → Binance.Spot
  - Functions starting with `futures_` → Binance.Futures
  - Functions starting with `margin_` → Binance.Margin
  - Common functions → Binance.Common
  """

  alias ZenCex.Adapters.Binance.Auth
  alias ZenCex.Adapters.Binance.Common
  alias ZenCex.Adapters.Binance.Futures
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RateLimiter

  # These will be created as separate modules
  # alias ZenCex.Adapters.Binance.Margin
  alias ZenCex.Adapters.Binance.Spot

  @doc """
  Returns the exchange name for this adapter.
  """
  @spec __exchange__() :: :binance
  def __exchange__, do: :binance

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
  Returns the current environment based on BINANCE_TESTNET env variable.

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
          case System.get_env("BINANCE_TESTNET") do
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

  # Futures (USD-M) Testnet
  def base_url(:test, :futures), do: "https://testnet.binancefuture.com"

  # COIN-M Futures (DAPI) Testnet
  def base_url(:test, :dapi), do: "https://testnet.binancefuture.com"

  # Portfolio Margin (PAPI) uses Futures Testnet
  def base_url(:test, :papi), do: "https://testnet.binancefuture.com"

  # SAPI endpoints are NOT supported on Testnet
  def base_url(:test, :sapi), do: {:error, :no_testnet_for_sapi}

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

  # Futures (USD-M)
  def base_url(:prod, :futures), do: "https://fapi.binance.com"

  # COIN-M Futures
  def base_url(:prod, :dapi), do: "https://dapi.binance.com"

  # Portfolio Margin
  def base_url(:prod, :papi), do: "https://papi.binance.com"

  # Default to Spot
  def base_url(:prod, _), do: "https://api.binance.com"

  # ============================================================================
  # Delegation to nested modules
  # ============================================================================

  # Common endpoints (shared across all API types)
  defdelegate get_server_time(), to: Common
  defdelegate get_server_time(opts), to: Common

  # Spot trading endpoints
  defdelegate get_balances(), to: Spot
  defdelegate get_balances(opts), to: Spot
  defdelegate get_balances(params, opts), to: Spot

  defdelegate place_order(), to: Spot
  defdelegate place_order(params), to: Spot
  defdelegate place_order(params, opts), to: Spot

  defdelegate cancel_order(), to: Spot
  defdelegate cancel_order(params), to: Spot
  defdelegate cancel_order(params, opts), to: Spot

  defdelegate get_order(), to: Spot
  defdelegate get_order(params), to: Spot
  defdelegate get_order(params, opts), to: Spot

  defdelegate place_oco_order(params), to: Spot
  defdelegate batch_cancel_orders(params), to: Spot

  # Futures trading endpoints
  defdelegate get_positions(), to: Futures
  defdelegate get_positions(opts), to: Futures
  defdelegate get_positions(params, opts), to: Futures

  # ============================================================================
  # Registry compatibility functions
  # These are needed for tests and backward compatibility
  # ============================================================================

  @doc """
  Returns endpoint configuration for the given operation.
  Routes to the appropriate module based on the operation name.
  """
  @spec get_endpoint(atom()) :: map() | nil
  def get_endpoint(operation) do
    cond do
      operation in [:get_server_time] ->
        Common.get_endpoint(operation)

      operation in [:get_balances, :place_order, :cancel_order, :get_order] ->
        Spot.get_endpoint(operation)

      operation in [:get_positions] ->
        Futures.get_endpoint(operation)

      true ->
        nil
    end
  end

  @doc """
  Returns all endpoints from all modules.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints do
    Common.all_endpoints() ++ Spot.all_endpoints() ++ Futures.all_endpoints()
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
end
