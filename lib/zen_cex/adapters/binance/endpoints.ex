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

  alias ZenCex.Adapters.Binance.{Auth, Parser, RateLimiter}

  # These will be created as separate modules
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Adapters.Binance.Futures
  # alias ZenCex.Adapters.Binance.Margin
  alias ZenCex.Adapters.Binance.Common

  @doc """
  Returns the exchange name for this adapter.
  """
  def __exchange__, do: :binance

  @doc """
  Returns the auth module for this adapter.
  """
  def auth, do: Auth

  @doc """
  Returns the rate limiter module for this adapter.
  """
  def rate_limiter, do: RateLimiter

  @doc """
  Returns the parser module for this adapter.
  """
  def parser, do: Parser

  @doc """
  Returns the current environment based on BINANCE_TESTNET env variable.
  """
  @spec current_env() :: :test | :prod
  def current_env do
    case System.get_env("BINANCE_TESTNET") do
      nil -> :prod
      "false" -> :prod
      "" -> :prod
      _ -> :test
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
  @spec base_url(:test | :prod, atom()) :: String.t()
  def base_url(env, api_type)

  # Test environment URLs
  def base_url(:test, :spot), do: "https://testnet.binance.vision"
  def base_url(:test, :futures), do: "https://testnet.binancefuture.com"
  def base_url(:test, :margin), do: "https://testnet.binance.vision"
  def base_url(:test, :sapi), do: "https://testnet.binance.vision"
  def base_url(:test, :dapi), do: "https://testnet.binancefuture.com"
  def base_url(:test, _), do: "https://testnet.binance.vision"

  # Production environment URLs
  def base_url(:prod, :spot), do: "https://api.binance.com"
  def base_url(:prod, :futures), do: "https://fapi.binance.com"
  def base_url(:prod, :margin), do: "https://api.binance.com"
  def base_url(:prod, :sapi), do: "https://api.binance.com"
  def base_url(:prod, :dapi), do: "https://dapi.binance.com"
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
  def all_endpoints do
    Common.all_endpoints() ++ Spot.all_endpoints() ++ Futures.all_endpoints()
  end

  @doc """
  Returns the weight for a given operation.
  """
  def get_weight(operation) do
    case get_endpoint(operation) do
      nil -> nil
      config -> config[:weight]
    end
  end
end
