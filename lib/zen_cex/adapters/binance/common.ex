defmodule ZenCex.Adapters.Binance.Common do
  @moduledoc """
  Common endpoints shared across all Binance API types.

  Contains endpoints that are available on all API types like
  server time, exchange info, etc.
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints

  alias ZenCex.Adapters.Binance.{Parser, RequestHelper}
  require Logger

  @endpoints [
    %{
      operation: :get_server_time,
      method: :get,
      path: "/api/v3/time",
      requires_auth: false,
      weight: 1,
      timeout: 2_000,
      retry_on: [:timeout],
      response_parser: &Parser.parse_server_time/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get server time from the exchange.

      ## Error Scenarios

      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      - `{:error, %Mint.TransportError{}}` - Network connectivity issues
      """
    }
  ]

  # The EndpointRegistry macro automatically generates:
  # - get_server_time/0 and get_server_time/1
  # - get_endpoint/1 
  # - all_endpoints/0
  # - get_weight/1

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  defp execute_endpoint_request(config, params, opts, _adapter) do
    base_url = ZenCex.Adapters.Binance.Endpoints.base_url()
    request_params = %{params: params}

    # Use shared RequestHelper for consistency
    RequestHelper.execute_request(config, request_params, opts, base_url, :binance, :health)
  end
end
