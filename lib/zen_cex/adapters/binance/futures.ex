defmodule ZenCex.Adapters.Binance.Futures do
  @moduledoc """
  Futures trading endpoints for Binance.

  Contains all futures trading operations including:
  - Position management
  - Futures order operations
  - Margin and leverage controls
  """

  alias ZenCex.Adapters.Binance.{Parser, RequestHelper}
  require Logger

  @endpoint_config %{
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

  @doc """
  Get futures positions.

  ## Error Scenarios

  - `{:error, {:insufficient_margin, "Insufficient margin"}}` - Not enough margin for position
  - `{:error, {:position_not_found, "Position does not exist"}}` - No position for symbol
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  """
  @spec get_positions(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_positions(params \\ %{}, opts \\ []) do
    config = @endpoint_config

    base_url =
      ZenCex.Adapters.Binance.Endpoints.base_url(
        ZenCex.Adapters.Binance.Endpoints.current_env(),
        :futures
      )

    RequestHelper.execute_request(config, params, opts, base_url, :binance, :standard)
  end

  @doc """
  Returns the endpoint configuration for the given operation.
  """
  @spec get_endpoint(atom()) :: map() | nil
  def get_endpoint(:get_positions), do: @endpoint_config
  def get_endpoint(_), do: nil

  @doc """
  Returns all endpoints defined in this module.
  """
  @spec all_endpoints() :: [map()]
  def all_endpoints, do: [@endpoint_config]
end
