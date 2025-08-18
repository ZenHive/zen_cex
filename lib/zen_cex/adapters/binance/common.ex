defmodule ZenCex.Adapters.Binance.Common do
  @moduledoc """
  Common endpoints shared across all Binance API types.

  Contains endpoints that are available on all API types like
  server time, exchange info, etc.
  """

  use ZenCex.EndpointRegistry

  alias ZenCex.Adapters.Binance.{Auth, Parser, RateLimiter}

  @endpoints [
    %{
      operation: :get_server_time,
      method: :get,
      path: "/api/v3/time",
      requires_auth: false,
      weight: 1,
      # 2 second timeout
      timeout: 2_000,
      # Public endpoint, only retry on timeout
      retry_on: [:timeout],
      response_parser: &Parser.parse_server_time/1,
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
  Returns the base URL for this adapter.
  Delegates to main Endpoints module.
  """
  def base_url, do: ZenCex.Adapters.Binance.Endpoints.base_url()
  def base_url(env), do: ZenCex.Adapters.Binance.Endpoints.base_url(env)
  def base_url(env, api_type), do: ZenCex.Adapters.Binance.Endpoints.base_url(env, api_type)
end
