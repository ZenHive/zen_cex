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

  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Core.HTTP

  require Logger

  # HTTP status code ranges
  @success_status_range 200..299

  @doc """
  Executes a request with standard preprocessing for Binance API modules.

  This is the high-level function that coordinates preprocessing and execution.
  It handles base URL resolution, operation type determination, and parameter
  preparation before delegating to the lower-level execute_request/6 function.

  ## Parameters
  - `config` - Endpoint configuration map containing method, path, parsers, etc.
  - `params` - Raw parameter map from the calling function
  - `opts` - Additional options like custom timeout or auth credentials
  - `api_type` - The API type (:spot, :usdm_futures, :common) for URL resolution
  - `operation_type_resolver` - Function to determine operation type from config

  ## Returns
  - `{:ok, body}` - Raw response body for successful requests (parser called by macro)
  - `{:error, response_or_exception}` - Error response or exception

  ## Examples

      # Simple case (Futures, Common)
      execute_request_for_api_type(config, params, opts, :usdm_futures, fn _ -> :standard end)

      # Complex case (Spot with operation type logic)
      execute_request_for_api_type(config, params, opts, :spot, &determine_spot_operation_type/1)
  """
  @spec execute_request_for_api_type(map(), map(), keyword() | map(), atom(), (map() -> atom())) ::
          {:ok, any()} | {:error, term()}
  def execute_request_for_api_type(config, params, opts, api_type, operation_type_resolver) do
    # Get base URL for the API type
    base_url =
      Endpoints.base_url(
        Endpoints.current_env(),
        api_type
      )

    # Determine operation type using provided resolver
    operation_type = operation_type_resolver.(config)

    # Build request params - delegate to specialized function based on API type
    request_params =
      case api_type do
        :spot -> build_spot_request_params(config, params)
        :margin -> build_margin_request_params(config, params)
        # Simple case for futures and common
        _ -> %{params: params}
      end

    # Execute request using existing function
    execute_request(config, request_params, opts, base_url, :binance, operation_type)
  end

  @doc """
  Low-level request execution function.

  This function handles the actual HTTP request execution and should not
  be called directly by endpoint modules. Use execute_request_for_api_type/5 instead.

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
  @spec execute_request(map(), map(), keyword() | map(), String.t(), atom(), atom()) ::
          {:ok, any()} | {:error, term()}
  def execute_request(config, request_params, opts, base_url, exchange, operation_type) do
    # Get API type from config if present (for rate limiter)
    api_type = Map.get(config, :api_type, :spot)

    # Normalize opts to keyword list (accept both maps and keyword lists)
    opts_list = normalize_to_keyword_list(opts)

    # Build base options
    base_opts = %{
      method: config.method,
      url: base_url <> config.path,
      receive_timeout: Keyword.get(opts_list, :timeout, config.timeout),
      skip_auth: not config.requires_auth,
      retry: false
    }

    # Only add params if they exist and are not empty
    base_opts = maybe_add_option(base_opts, :params, request_params[:params])
    base_opts = maybe_add_option(base_opts, :json, request_params[:json])

    # Build and execute request
    request =
      exchange
      |> HTTP.base_request(operation_type)
      |> Req.merge(Map.to_list(base_opts))
      |> Req.merge(opts_list)
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

  # Auth parameters that must be in query string for Spot API
  @auth_params ["timestamp", "recvWindow", "signature"]

  @doc """
  Builds request parameters for Spot API endpoints.

  For Binance Spot, auth parameters (timestamp, recvWindow, signature) MUST be in query string,
  while body parameters go in JSON for POST/PUT/DELETE requests.
  """
  @spec build_spot_request_params(map(), map()) :: map()
  def build_spot_request_params(config, params) do
    case config.method do
      :get ->
        %{params: params}

      _ ->
        # For POST/PUT/DELETE, auth params go in query, body params in json
        auth_params = Map.take(params, @auth_params)
        body_params = Map.drop(params, @auth_params)
        %{params: auth_params, json: body_params}
    end
  end

  @doc """
  Builds request parameters for Margin API endpoints.

  Margin API uses /sapi/ endpoints which handle parameters differently than spot:
  - All parameters go in query string for GET requests
  - For POST/PUT/DELETE, auth params go in query, body params in JSON
  """
  @spec build_margin_request_params(map(), map()) :: map()
  def build_margin_request_params(config, params) do
    case config.method do
      :get ->
        %{params: params}

      _ ->
        # For POST/PUT/DELETE, auth params go in query, body params in json
        auth_params = Map.take(params, @auth_params)
        body_params = Map.drop(params, @auth_params)
        %{params: auth_params, json: body_params}
    end
  end

  @doc """
  Determines operation type for Spot API endpoints based on the operation.
  """
  @spec determine_spot_operation_type(map()) :: atom()
  def determine_spot_operation_type(config) do
    cond do
      config.operation in [:place_order, :cancel_order] -> :trading
      config.operation == :get_order -> :standard
      true -> :standard
    end
  end

  # Helper to normalize options to keyword list (accepts both maps and keyword lists)
  defp normalize_to_keyword_list(opts) when is_list(opts), do: opts
  defp normalize_to_keyword_list(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_to_keyword_list(_), do: []

  # Helper to conditionally add non-empty options
  defp maybe_add_option(opts, _key, nil), do: opts
  defp maybe_add_option(opts, _key, %{} = value) when map_size(value) == 0, do: opts
  defp maybe_add_option(opts, key, value), do: Map.put(opts, key, value)
end
