defmodule ZenCex.Adapters.Binance.Futures do
  @moduledoc """
  Futures trading endpoints for Binance.

  Contains all futures trading operations including:
  - Position management
  - Futures order operations
  - Margin and leverage controls
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints

  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RequestHelper

  require Logger

  @endpoints [
    %{
      operation: :get_positions,
      method: :get,
      path: "/fapi/v2/positionRisk",
      api_type: :usdm_futures,
      requires_auth: true,
      weight: 5,
      timeout: 5_000,
      max_retries: 2,
      retry_on: [:rate_limited, :timeout],
      response_parser: &Parser.parse_positions/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get futures positions.

      ## Error Scenarios

      - `{:error, {:insufficient_margin, "Insufficient margin"}}` - Not enough margin for position
      - `{:error, {:position_not_found, "Position does not exist"}}` - No position for symbol
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      """
    }
  ]

  # The EndpointRegistry macro automatically generates:
  # - get_positions/1 and get_positions/2
  # - get_endpoint/1 
  # - all_endpoints/0
  # - get_weight/1

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Use the new high-level helper with simple operation type logic
    RequestHelper.execute_request_for_api_type(
      config,
      params,
      opts,
      :usdm_futures,
      fn _ -> :standard end
    )
  end
end
