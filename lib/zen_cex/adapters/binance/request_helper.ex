defmodule ZenCex.Adapters.Binance.RequestHelper do
  @moduledoc """
  Shared request execution logic for Binance adapter modules.

  This module extracts common request building and execution patterns
  to avoid code duplication across Common, Spot, and Futures modules.
  """

  alias ZenCex.Core.HTTP
  require Logger

  @doc """
  Executes a request with the given configuration.

  ## Parameters
  - `config` - Endpoint configuration map containing method, path, parsers, etc.
  - `params` - Request parameters (query params for GET, body for POST/PUT/DELETE)
  - `opts` - Additional options like custom timeout
  - `base_url` - The base URL for the API endpoint
  - `exchange` - The exchange atom (:binance)
  - `operation_type` - The operation type for Core.HTTP (:standard, :trading, :health, etc.)

  ## Returns
  - `{:ok, result}` - Parsed successful response
  - `{:error, reason}` - Error from parser or exception

  ## Error Scenarios

  The function handles several error cases:

  1. **HTTP Success (200-299)**: Response is parsed using `config.response_parser`
  2. **HTTP Error (non-2xx)**: Response is parsed using `config.error_mapping`
  3. **Network/Request Exception**: Logged and returned as `{:error, exception}`

  ### Common Error Responses

  - `{:error, {:invalid_symbol, "Invalid symbol."}}` - Invalid trading pair
  - `{:error, {:insufficient_balance, "Account has insufficient balance"}}` - Not enough funds
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  - `{:error, %Mint.TransportError{}}` - Network connectivity issues
  - `{:error, %Req.Response.AsyncError{}}` - Request timeout
  """
  @spec execute_request(map(), map(), keyword(), String.t(), atom(), atom()) ::
          {:ok, map()} | {:error, term()}
  def execute_request(config, params, opts, base_url, exchange, operation_type) do
    # Get API type from config if present (for rate limiter to use correct limits)
    api_type = Map.get(config, :api_type, :spot)

    # Build request params based on method
    # IMPORTANT: For Binance, auth params (timestamp, recvWindow, signature) 
    # MUST be in query string even for POST/PUT/DELETE methods
    request_params = build_request_params(config.method, params, config.requires_auth)

    # Build request using Core.HTTP patterns
    # Important: merge opts to pass through auth_credentials
    # Build base options - DON'T add empty params or json
    base_opts = %{
      method: config.method,
      url: base_url <> config.path,
      receive_timeout: Keyword.get(opts, :timeout, config.timeout),
      skip_auth: not config.requires_auth,
      retry: false
    }

    # Only add params if they exist and are not empty
    base_opts =
      if Map.has_key?(request_params, :params) and request_params.params != nil and
           request_params.params != %{} do
        Map.put(base_opts, :params, request_params.params)
      else
        base_opts
      end

    # Only add json if it exists and is not empty
    base_opts =
      if Map.has_key?(request_params, :json) and request_params.json != nil and
           request_params.json != %{} do
        Map.put(base_opts, :json, request_params.json)
      else
        base_opts
      end

    request =
      HTTP.base_request(exchange, operation_type)
      |> Req.merge(Map.to_list(base_opts))
      |> Req.merge(opts)
      |> Req.Request.put_private(:rate_limit_weight, config.weight)
      |> Req.Request.put_private(:endpoint_config, config)
      |> Req.Request.put_private(:endpoint_operation, config.operation)
      |> Req.Request.put_private(:api_type, api_type)

    # Execute request and handle response
    case Req.request(request) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        config.response_parser.(body)

      {:ok, %Req.Response{body: body}} ->
        config.error_mapping.(body)

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, exception}
    end
  end

  # Private helper to build request params based on HTTP method
  # For Binance, auth params MUST be in query string for ALL methods
  defp build_request_params(:get, params, _requires_auth) do
    # Don't set json for GET requests - causes issues with WAF
    %{params: params}
  end

  defp build_request_params(_method, params, requires_auth) do
    if requires_auth do
      # For authenticated requests, separate auth params from body params
      # Auth params (timestamp, recvWindow, signature) go in query string
      # Other params go in request body
      auth_params = Map.take(params, ["timestamp", "recvWindow", "signature"])
      body_params = Map.drop(params, ["timestamp", "recvWindow", "signature"])

      %{params: auth_params, json: body_params}
    else
      # For non-authenticated requests, all params go in body
      %{params: nil, json: params}
    end
  end
end
