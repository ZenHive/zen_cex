defmodule ZenCex.Adapters.Bybit.Common do
  @moduledoc """
  Common endpoints shared across all Bybit API types.

  Contains endpoints that are available on all API types like
  server time, announcements, etc.
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Bybit.Endpoints

  alias ZenCex.Adapters.Bybit.Parser
  alias ZenCex.Adapters.Bybit.RequestHelper

  @endpoints [
    %{
      operation: :get_server_time,
      method: :get,
      path: "/v5/market/time",
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
    },
    %{
      operation: :get_announcements,
      method: :get,
      path: "/v5/announcements/index",
      requires_auth: false,
      weight: 1,
      timeout: 5_000,
      retry_on: [:timeout],
      response_parser: &Parser.parse_announcements/1,
      error_mapping: &Parser.parse_error/1,
      doc: """
      Get latest announcements from the exchange.

      ## Parameters

      - `locale` (optional) - Language: "zh-CN", "en-US", "zh-TW", "ja", "es-AR", "tr-TR", etc.
      - `type` (optional) - Announcement type: "new_crypto", "latest_bybit_news", "defi", etc.
      - `tag` (optional) - Announcement tag: "spot", "linear", "inverse", "option"
      - `page` (optional) - Page number, default: 1
      - `limit` (optional) - Number per page, default: 20

      ## Error Scenarios

      - `{:error, {:invalid_parameter, _}}` - Invalid parameter value
      - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
      - `{:error, %Mint.TransportError{}}` - Network connectivity issues
      """
    }
  ]

  # The EndpointRegistry macro automatically generates:
  # - get_server_time/0 and get_server_time/1
  # - get_announcements/0 and get_announcements/1
  # - get_endpoint/1
  # - all_endpoints/0
  # - get_weight/1

  # Custom implementation for execute_endpoint_request to integrate with our infrastructure
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Use the unified API helper for common endpoints
    RequestHelper.execute_request_for_unified_api(config, params, opts)
  end
end
