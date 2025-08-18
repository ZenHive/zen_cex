defmodule ZenCex.Adapters.Binance.Spot do
  @moduledoc """
  Spot trading endpoints for Binance.

  Contains all spot trading operations including:
  - Order management (place, cancel, query)
  - Account information (balances)
  - OCO orders
  - Batch operations
  """

  use ZenCex.EndpointRegistry

  alias ZenCex.Adapters.Binance.{Auth, Parser, RateLimiter}

  @endpoints [
    %{
      operation: :get_balances,
      method: :get,
      path: "/api/v3/account",
      requires_auth: true,
      weight: 10,
      # 5 second timeout for account query
      timeout: 5_000,
      max_retries: 2,
      retry_on: [:rate_limited, :timeout],
      response_parser: &Parser.parse_balances/1,
      error_mapping: &Parser.parse_error/1
    },
    %{
      operation: :place_order,
      method: :post,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      # 2 second timeout for trading
      timeout: 2_000,
      # CRITICAL: No retries for order placement
      max_retries: 0,
      # Never retry order placement
      retry_on: [],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    },
    %{
      operation: :cancel_order,
      method: :delete,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 1,
      # 2 second timeout for cancellation
      timeout: 2_000,
      # Limited retries for cancellation
      max_retries: 1,
      # Only retry on timeout, not rate limit
      retry_on: [:timeout],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    },
    %{
      operation: :get_order,
      method: :get,
      path: "/api/v3/order",
      requires_auth: true,
      weight: 2,
      # 5 second timeout for query
      timeout: 5_000,
      max_retries: 3,
      retry_on: [:rate_limited, :timeout, :server_error],
      response_parser: &Parser.parse_order/1,
      error_mapping: &Parser.parse_error/1
    }
  ]

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
  Returns the base URL for spot trading.
  """
  def base_url do
    env = ZenCex.Adapters.Binance.Endpoints.current_env()
    ZenCex.Adapters.Binance.Endpoints.base_url(env, :spot)
  end

  def base_url(env), do: ZenCex.Adapters.Binance.Endpoints.base_url(env, :spot)
  def base_url(env, _api_type), do: ZenCex.Adapters.Binance.Endpoints.base_url(env, :spot)

  @doc """
  Complex operation: Place One-Cancels-Other order.
  Hand-written because it requires special parameter handling.
  """
  def place_oco_order(_params) do
    # TODO: Implement OCO order placement
    # This is a complex operation that places two orders where one cancels the other
    {:error, :not_implemented}
  end

  @doc """
  Complex operation: Batch cancel multiple orders.
  Hand-written because it requires special batch handling.
  """
  def batch_cancel_orders(_params) do
    # TODO: Implement batch cancellation
    # This cancels multiple orders in a single API call
    {:error, :not_implemented}
  end
end
