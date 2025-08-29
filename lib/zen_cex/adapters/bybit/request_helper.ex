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

  use ZenCex.Adapters.BaseRequestHelper

  alias ZenCex.Adapters.Bybit.Endpoints

  require Logger

  # Retry configuration - milliseconds between retry attempts for linear backoff
  @backoff_multiplier_ms 1000

  # Delegate functions for backward compatibility
  defdelegate current_env(), to: Endpoints
  defdelegate base_url(), to: Endpoints
  defdelegate base_url(env), to: Endpoints

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
    # Get base URL for current environment from Endpoints module
    base_url = Endpoints.base_url()

    # Determine operation type from config
    operation_type = determine_operation_type(config)

    # Build request params based on method
    request_params = build_request_params(config, params)

    # Execute request
    execute_request(config, request_params, opts, base_url, :bybit, operation_type)
  end

  # NOTE: Bybit uses the default parameter handling from BaseRequestHelper
  # - GET requests: all params in query string
  # - POST/PUT/DELETE: all params in JSON body
  # No overrides needed as the defaults match Bybit's requirements

  # Override the base execute_request to add Bybit-specific retry logic
  @doc """
  Low-level request execution function with Bybit-specific retry configuration.

  This overrides the base implementation to add Bybit's retry configuration.
  """
  @spec execute_request(map(), map(), keyword(), String.t(), atom(), atom()) ::
          {:ok, any()} | {:error, term()}
  def execute_request(config, request_params, opts, base_url, exchange, operation_type) do
    # Build retry configuration from endpoint config
    retry_config = build_retry_config(config)

    # Normalize opts to keyword list (accept both maps and keyword lists)
    opts_list = if is_list(opts), do: opts, else: Map.to_list(opts)

    # Add Bybit-specific options
    bybit_opts =
      opts_list
      |> Keyword.put(:retry, retry_config)
      |> Keyword.put(:max_retries, Map.get(config, :max_retries, 0))
      |> Keyword.put(:retry_delay, fn attempt -> attempt * @backoff_multiplier_ms end)

    # Delegate to base implementation with Bybit-specific options
    super(config, request_params, bybit_opts, base_url, exchange, operation_type)
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
      :get when map_size(params) > 0 ->
        %{params: params}

      :get ->
        %{}

      _ when map_size(params) > 0 ->
        # For POST/PUT/DELETE, all params go in JSON body
        # Auth signature is handled via headers by Auth module
        %{json: params}

      _ ->
        %{}
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
  def build_url(path, env \\ nil) do
    # Use provided env or get current env
    actual_env = env || Endpoints.current_env()

    base_url =
      case actual_env do
        :test -> "https://api-testnet.bybit.com"
        _ -> "https://api.bybit.com"
      end

    base_url <> path
  end
end
