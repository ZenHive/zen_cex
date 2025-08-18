defmodule ZenCex.Adapters.Binance.Futures do
  @moduledoc """
  Futures trading endpoints for Binance.

  Contains all futures trading operations including:
  - Position management
  - Futures order operations
  - Margin and leverage controls
  """

  use ZenCex.EndpointRegistry

  alias ZenCex.Adapters.Binance.{Auth, Parser, RateLimiter}

  @endpoints [
    %{
      operation: :get_positions,
      method: :get,
      path: "/fapi/v2/positionRisk",
      # Uses futures API
      api_type: :futures,
      requires_auth: true,
      weight: 5,
      # 5 second timeout for position query
      timeout: 5_000,
      max_retries: 2,
      retry_on: [:rate_limited, :timeout],
      response_parser: &Parser.parse_positions/1,
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
  Returns the base URL for futures trading.
  Always uses futures-specific URLs.
  """
  def base_url do
    env = ZenCex.Adapters.Binance.Endpoints.current_env()
    ZenCex.Adapters.Binance.Endpoints.base_url(env, :futures)
  end

  def base_url(env), do: ZenCex.Adapters.Binance.Endpoints.base_url(env, :futures)
  def base_url(env, _api_type), do: ZenCex.Adapters.Binance.Endpoints.base_url(env, :futures)
end
