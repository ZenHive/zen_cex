defmodule ZenCex.Adapters.Binance.Common do
  @moduledoc """
  Common endpoints shared across all Binance API types.

  Contains endpoints that are available on all API types like
  server time, exchange info, etc.
  """

  alias ZenCex.Adapters.Binance.{Parser, RequestHelper}
  require Logger

  @endpoint_config %{
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

  @doc """
  Get server time from the exchange.
  
  ## Error Scenarios
  
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  - `{:error, %Mint.TransportError{}}` - Network connectivity issues
  """
  @spec get_server_time() :: {:ok, map()} | {:error, term()}
  def get_server_time(opts \\ []) do
    config = @endpoint_config
    base_url = ZenCex.Adapters.Binance.Endpoints.base_url()
    
    # Server time is a health check endpoint
    RequestHelper.execute_request(config, %{}, opts, base_url, :binance, :health)
  end

  @doc """
  Returns the endpoint configuration for the given operation.
  """
  @spec get_endpoint(atom()) :: map() | nil
  def get_endpoint(:get_server_time), do: @endpoint_config
  def get_endpoint(_), do: nil

  @doc """
  Returns all endpoints defined in this module.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints, do: [@endpoint_config]
end
