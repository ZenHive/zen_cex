defmodule ZenCex.Adapters.Binance.RequestHelper do
  @moduledoc """
  Minimal shared request execution logic for Binance adapter modules.

  This module provides a single, focused helper for common request execution
  patterns to avoid code duplication across Common, Spot, and Futures modules.

  ## Scope and Purpose

  This helper ONLY handles:
  - Building Req request with proper options
  - Executing the request
  - Mapping responses to success/error tuples

  It does NOT handle:
  - Authentication (handled by Auth module via Req steps)
  - Rate limiting (handled by RateLimiter via Req steps)
  - Parameter building (handled by calling modules)

  ## Error Responses

  Common error responses from Binance:
  - `{:error, {:invalid_symbol, "Invalid symbol."}}` - Invalid trading pair
  - `{:error, {:insufficient_balance, "Account has insufficient balance"}}` - Not enough funds
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  - `{:error, {:html_error, message}}` - CDN/WAF HTML error page
  - `{:error, {:waf_blocked, message}}` - Request blocked by WAF
  - `{:error, {:cdn_error, message}}` - CloudFlare protection triggered
  - `{:error, %Mint.TransportError{}}` - Network connectivity issues
  - `{:error, %Req.Response.AsyncError{}}` - Request timeout
  """

  alias ZenCex.Core.HTTP
  require Logger

  # HTTP status code ranges
  @success_status_range 200..299

  @doc """
  Executes a request with the given configuration.

  ## Parameters
  - `config` - Endpoint configuration map containing method, path, parsers, etc.
  - `request_params` - Map with `:params` and/or `:json` keys for request data
  - `opts` - Additional options like custom timeout or auth credentials
  - `base_url` - The base URL for the API endpoint
  - `exchange` - The exchange atom (:binance)
  - `operation_type` - The operation type for Core.HTTP (:standard, :trading, :health)

  ## Returns
  - `{:ok, body}` - Raw response body for successful requests (parser called by macro)
  - `{:error, response_or_exception}` - Error response or exception

  ## Examples

      # GET request with query params
      execute_request(config, %{params: %{"symbol" => "BTCUSDT"}}, [], base_url, :binance, :standard)

      # POST request with JSON body and auth params in query
      execute_request(
        config, 
        %{params: auth_params, json: body_params}, 
        [auth_credentials: creds],
        base_url,
        :binance,
        :trading
      )
  """
  @spec execute_request(map(), map(), keyword(), String.t(), atom(), atom()) ::
          {:ok, any()} | {:error, term()}
  def execute_request(config, request_params, opts, base_url, exchange, operation_type) do
    # Get API type from config if present (for rate limiter)
    api_type = Map.get(config, :api_type, :spot)

    # Build base options
    base_opts = %{
      method: config.method,
      url: base_url <> config.path,
      receive_timeout: Keyword.get(opts, :timeout, config.timeout),
      skip_auth: not config.requires_auth,
      retry: false
    }

    # Only add params if they exist and are not empty
    base_opts = maybe_add_option(base_opts, :params, request_params[:params])
    base_opts = maybe_add_option(base_opts, :json, request_params[:json])

    # Build and execute request
    request =
      HTTP.base_request(exchange, operation_type)
      |> Req.merge(Map.to_list(base_opts))
      |> Req.merge(opts)
      |> Req.Request.put_private(:rate_limit_weight, config.weight)
      |> Req.Request.put_private(:endpoint_config, config)
      |> Req.Request.put_private(:endpoint_operation, config.operation)
      |> Req.Request.put_private(:api_type, api_type)

    # Execute request and return response for parsing
    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in @success_status_range ->
        # Return raw body - calling module will apply parser
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        # Return error response - calling module will apply error mapping
        {:error, %Req.Response{status: status, body: body}}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, exception}
    end
  end

  # Helper to conditionally add non-empty options
  defp maybe_add_option(opts, _key, nil), do: opts
  defp maybe_add_option(opts, _key, %{} = value) when map_size(value) == 0, do: opts
  defp maybe_add_option(opts, key, value), do: Map.put(opts, key, value)
end
