defmodule ZenCex.Adapters.Bybit.RequestHelper do
  @moduledoc """
  Minimal shared request execution logic for Bybit adapter modules.

  This module provides a single, focused helper for common request execution
  patterns to avoid code duplication across Bybit endpoint modules.

  ## Scope and Purpose

  This helper ONLY handles:
  - Building Req request with proper options
  - Executing the request
  - Mapping responses to success/error tuples

  It does NOT handle:
  - Authentication (handled by Auth module via Req steps)
  - Rate limiting (handled by RateLimiter via Req steps)
  - Parameter building (handled by calling modules)

  ## Bybit v5 API Structure

  Bybit v5 uses a unified API where the same endpoints serve different product types:
  - Category parameter: "spot", "linear", "inverse", "option"
  - Base URL: api.bybit.com (prod), api-testnet.bybit.com (test)
  - All endpoints under /v5/ path prefix

  ## Error Responses

  Common error responses from Bybit:
  - `{:error, {:invalid_symbol, "Symbol not found"}}` - Invalid trading pair
  - `{:error, {:insufficient_balance, "Insufficient balance"}}` - Not enough funds
  - `{:error, {:rate_limited, "Too many requests"}}` - Rate limit exceeded
  - `{:error, {:invalid_order, "Order does not exist"}}` - Order not found
  - `{:error, {:network_error, message}}` - Connectivity issues
  - `{:error, %Mint.TransportError{}}` - Network connectivity issues
  - `{:error, %Req.Response.AsyncError{}}` - Request timeout
  """

  alias ZenCex.Core.HTTP

  require Logger

  # HTTP status code ranges
  @success_status_range 200..299

  # Retry configuration - milliseconds per retry attempt for linear backoff
  @backoff_multiplier_ms 1000

  # Bybit production and testnet base URLs
  @production_base_url "https://api.bybit.com"
  @testnet_base_url "https://api-testnet.bybit.com"

  @doc """
  Gets the base URL for the current environment.

  ## Examples

      iex> base_url()
      "https://api.bybit.com"

      iex> base_url(:test)
      "https://api-testnet.bybit.com"
  """
  @spec base_url() :: String.t()
  @spec base_url(atom()) :: String.t()
  def base_url(env \\ current_env()) do
    case env do
      :test -> @testnet_base_url
      _ -> @production_base_url
    end
  end

  @doc """
  Gets the current environment based on BYBIT_TESTNET environment variable.

  ## Examples

      iex> System.put_env("BYBIT_TESTNET", "true")
      iex> current_env()
      :test

      iex> System.delete_env("BYBIT_TESTNET")
      iex> current_env()
      :prod
  """
  @spec current_env() :: atom()
  def current_env do
    if System.get_env("BYBIT_TESTNET") == "true" do
      :test
    else
      :prod
    end
  end

  @doc """
  Executes a request with standard preprocessing for Bybit API modules.

  This is the high-level function that coordinates preprocessing and execution.
  It handles base URL resolution, operation type determination, and parameter
  preparation before delegating to the lower-level execute_request/5 function.

  ## Parameters
  - `config` - Endpoint configuration map containing method, path, parsers, etc.
  - `params` - Raw parameter map from the calling function
  - `opts` - Additional options like custom timeout or auth credentials

  ## Returns
  - `{:ok, body}` - Raw response body for successful requests (parser called by macro)
  - `{:error, response_or_exception}` - Error response or exception

  ## Examples

      # Simple GET request
      execute_request_for_unified_api(config, params, opts)

      # POST request with category
      params = %{category: "spot", symbol: "BTCUSDT", side: "Buy", qty: "0.1"}
      execute_request_for_unified_api(config, params, opts)
  """
  @spec execute_request_for_unified_api(map(), map(), keyword()) ::
          {:ok, any()} | {:error, term()}
  def execute_request_for_unified_api(config, params, opts) do
    # Get base URL for current environment
    base_url = base_url()

    # Determine operation type from config
    operation_type = determine_operation_type(config)

    # Build request params based on method
    request_params = build_request_params(config, params)

    # Execute request
    execute_request(config, request_params, opts, base_url, :bybit, operation_type)
  end

  @doc """
  Low-level request execution function.

  This function handles the actual HTTP request execution and should not
  be called directly by endpoint modules. Use execute_request_for_unified_api/3 instead.

  ## Parameters
  - `config` - Endpoint configuration map containing method, path, parsers, etc.
  - `request_params` - Map with `:params` and/or `:json` keys for request data
  - `opts` - Additional options like custom timeout or auth credentials
  - `base_url` - The base URL for the API endpoint
  - `exchange` - The exchange atom (:bybit)
  - `operation_type` - The operation type for Core.HTTP (:standard, :trading, :market, :health)

  ## Returns
  - `{:ok, body}` - Raw response body for successful requests (parser called by macro)
  - `{:error, response_or_exception}` - Error response or exception
  """
  @spec execute_request(map(), map(), keyword(), String.t(), atom(), atom()) ::
          {:ok, any()} | {:error, term()}
  def execute_request(config, request_params, opts, base_url, exchange, operation_type) do
    # Build retry configuration from endpoint config
    retry_config = build_retry_config(config)

    # Build base options with proper Req retry configuration
    base_opts = %{
      method: config.method,
      url: base_url <> config.path,
      receive_timeout: Keyword.get(opts, :timeout, config.timeout),
      skip_auth: not config.requires_auth,
      retry: retry_config,
      max_retries: config.max_retries,
      # Linear backoff: 1s, 2s, 3s, 4s...
      # TODO: Consider exponential backoff for production: 1s, 2s, 4s, 8s...
      retry_delay: fn attempt -> attempt * @backoff_multiplier_ms end
    }

    # Only add params if they exist and are not empty
    base_opts = maybe_add_option(base_opts, :params, request_params[:params])
    base_opts = maybe_add_option(base_opts, :json, request_params[:json])

    # Build and execute request
    request =
      exchange
      |> HTTP.base_request(operation_type)
      |> Req.merge(Map.to_list(base_opts))
      |> Req.merge(opts)
      |> Req.Request.put_private(:rate_limit_weight, config.weight)
      |> Req.Request.put_private(:endpoint_config, config)
      |> Req.Request.put_private(:endpoint_operation, config.operation)
      |> Req.Request.put_private(:zen_cex_operation, config.operation)

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

  # Builds retry configuration from endpoint config.
  # Returns :safe_transient, :transient, false, or a custom function based on config.
  # Critical operations like order placement should have max_retries: 0.
  @spec build_retry_config(map()) :: atom() | false | fun()
  defp build_retry_config(config) do
    max_retries = Map.get(config, :max_retries, 0)
    retry_on = Map.get(config, :retry_on, [])

    cond do
      max_retries == 0 or retry_on == [] ->
        # No retry for critical operations
        false

      # For GET requests with standard retry conditions, use Req's built-in :safe_transient
      config.method == :get and retry_on == [:timeout, :server_error] ->
        :safe_transient

      # For other safe operations with retries, use :transient
      retry_on == [:timeout, :server_error] ->
        :transient

      # For timeout-only retries, use custom function
      retry_on == [:timeout] ->
        fn _request, error ->
          case error do
            %Mint.TransportError{reason: :timeout} -> true
            %Req.TransportError{reason: :timeout} -> true
            _ -> false
          end
        end

      # Default to :safe_transient for other GET requests
      config.method == :get ->
        :safe_transient

      # Default to no retry for other methods
      true ->
        false
    end
  end

  @doc """
  Builds request parameters for Bybit v5 unified API endpoints.

  For Bybit:
  - GET requests: All parameters in query string
  - POST/PUT/DELETE: All parameters in JSON body (auth headers handle signature)
  """
  @spec build_request_params(map(), map()) :: map()
  def build_request_params(config, params) do
    case config.method do
      :get ->
        %{params: params}

      _ ->
        # For POST/PUT/DELETE, all params go in JSON body
        # Auth signature is handled via headers by Auth module
        %{json: params}
    end
  end

  @doc """
  Determines operation type for Bybit API endpoints based on the operation.

  Returns appropriate operation type for timeout configuration:
  - :trading - Critical order operations (2s timeout)
  - :market - Market data queries (5s timeout)
  - :standard - Default operations (30s timeout)
  - :health - Health checks (5s timeout)
  """
  @spec determine_operation_type(map()) :: atom()
  def determine_operation_type(config) do
    cond do
      # Trading operations - critical path
      config.operation in [:place_order, :cancel_order, :cancel_all_orders] ->
        :trading

      # Market data operations - real-time data
      config.operation in [:get_tickers, :get_orderbook, :get_trades] ->
        :market

      # Health check operations
      config.operation == :server_time ->
        :health

      # Everything else is standard
      true ->
        :standard
    end
  end

  @doc """
  Constructs a full URL for a given endpoint path.

  ## Examples

      iex> build_url("/v5/market/time")
      "https://api.bybit.com/v5/market/time"

      iex> build_url("/v5/account/wallet-balance", :test)
      "https://api-testnet.bybit.com/v5/account/wallet-balance"
  """
  @spec build_url(String.t()) :: String.t()
  @spec build_url(String.t(), atom()) :: String.t()
  def build_url(path, env \\ current_env()) do
    base_url(env) <> path
  end

  # Helper to conditionally add non-empty options
  defp maybe_add_option(opts, _key, nil), do: opts
  defp maybe_add_option(opts, _key, %{} = value) when map_size(value) == 0, do: opts
  defp maybe_add_option(opts, key, value), do: Map.put(opts, key, value)
end
