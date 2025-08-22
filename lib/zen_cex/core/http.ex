defmodule ZenCex.Core.HTTP do
  @moduledoc """
  Core HTTP module that configures Req with Finch for connection pooling
  and integrates auth and rate limiting as composable request/response steps.

  This module provides a Req-centric architecture for HTTP operations with:
  - Connection pooling via Finch (named: ZenCex.Finch)
  - Exponential backoff with jitter for retries
  - Operation-specific timeouts based on use case
  - Auth and rate limiting as composable Req middleware steps
  - Comprehensive telemetry event emission for monitoring
  - Error handling with proper Req step patterns

  ## Architecture

  The module follows Req's step-based middleware pattern:
  1. **Request Steps**: Rate limiting and authentication (run before request)
  2. **Response Steps**: Rate limit updates and telemetry (run after response)
  3. **Error Steps**: Error telemetry and handling (run on exceptions)

  ## Operation Types and Timeouts

  Different operation types have optimized timeout configurations:
  - `:trading` - Order placement/cancellation (2s timeout) - Critical path
  - `:market` - Current market data queries (5s timeout) - Real-time data
  - `:historical` - Historical data queries (30s timeout) - Large datasets
  - `:health` - Health check endpoints (5s timeout) - Status monitoring
  - `:standard` - Default for unspecified operations (30s timeout) - General use

  ## Req Step Integration

  The module integrates with exchange modules through the Registry:
  - Rate limiting: Calls exchange's `rate_limiter().check_and_increment/1`
  - Authentication: Calls exchange's `auth().sign_request/1` 
  - Updates: Calls exchange's `rate_limiter().update_from_response/1`

  ## Telemetry Events

  Emits telemetry events for monitoring:
  - `[:zen_cex, :request, :complete]` - Successful requests with duration
  - `[:zen_cex, :request, :error]` - Failed requests with error details
  - `[:zen_cex, :rate_limit, :exceeded]` - Rate limit violations

  ## Examples

      # Basic trading request (uses environment variables for auth)
      request = ZenCex.Core.HTTP.base_request(:binance, :trading)
      
      # Health check (no auth/rate limiting)
      health_request = ZenCex.Core.HTTP.health_check_request(:kraken)
      
      # Testing with manual credentials (no environment setup needed)
      request = ZenCex.Core.HTTP.base_request(:binance, :trading)
      |> Req.merge(auth_credentials: %{api_key: "test_key", api_secret: "test_secret"})
      
      # Custom configuration
      request = ZenCex.Core.HTTP.base_request(:deribit, :market)
      |> Req.merge(skip_rate_limit: true)
  """
  alias ZenCex.Core.CircuitBreaker
  alias ZenCex.Core.Debug

  # Timing constants in milliseconds
  # Random jitter added to exponential backoff
  @jitter_range_ms 500
  # Default request timeout (15 seconds)
  @default_timeout_ms 15_000
  # Base delay for exponential backoff (1 second)
  @base_backoff_ms 1_000

  # Operation timeout values in milliseconds
  # Critical path operations (order placement/cancellation)
  @trading_timeout_ms 2_000
  # Real-time market data queries
  @market_timeout_ms 5_000
  # Large dataset queries (historical data)
  @historical_timeout_ms 30_000
  # Health check endpoints
  @health_timeout_ms 5_000
  # Default for unspecified operations
  @default_timeout_ms 30_000

  # Exponential backoff parameters
  # Initial backoff delay in milliseconds
  @base_backoff_ms 1_000
  # Maximum exponent for exponential backoff (2^10 = 1024)
  @max_backoff_exponent 10
  # Maximum backoff delay cap in milliseconds
  @max_backoff_ms 60_000

  # Rate limit response parameters
  # Convert milliseconds to seconds
  @seconds_per_millisecond_divisor 1_000

  @doc """
  Creates a base Req request configured for the specified exchange and operation type.

  ## Parameters
  - `exchange` - The exchange atom (e.g., `:binance`, `:kraken`, `:deribit`)
  - `operation_type` - The type of operation (affects timeout configuration)

  ## Returns
  A configured `Req.Request` struct with:
  - Finch connection pooling
  - Exponential backoff retry logic
  - Operation-specific timeouts
  - Auth and rate limiting steps
  - Telemetry hooks

  ## Examples

      iex> request = ZenCex.Core.HTTP.base_request(:binance, :trading)
      iex> request.options[:receive_timeout]
      2000  # 2 seconds for trading operations

      iex> request = ZenCex.Core.HTTP.base_request(:kraken, :historical)
      iex> request.options[:receive_timeout]
      30000  # 30 seconds for historical data
  """
  @spec base_request(atom(), atom()) :: Req.Request.t()
  def base_request(exchange, operation_type \\ :standard) do
    endpoints = ZenCex.Core.Registry.get_endpoints!(exchange)

    receive_timeout = get_timeout(operation_type)

    # First create Req with user_agent option, this ensures put_user_agent step is included
    [user_agent: "curl/7.68.0"]
    |> Req.new()
    |> Req.Request.register_options([
      :exchange,
      :operation_type,
      :skip_auth,
      :skip_rate_limit,
      :skip_response_handling,
      :auth_credentials
    ])
    |> Req.Request.prepend_request_steps(
      zen_cex_rate_limit: &rate_limit_step/1,
      zen_cex_auth: &auth_step/1
    )
    |> Req.Request.append_response_steps(
      zen_cex_handle_response: &handle_response_step/1,
      zen_cex_update_rate_limit: &update_rate_limit_step/1
    )
    |> Req.Request.append_error_steps(zen_cex_telemetry: &telemetry_error_step/1)
    |> Req.merge(
      base_url: endpoints.base_url(),
      finch: ZenCex.Finch,
      retry: :safe_transient,
      retry_delay: &exponential_backoff_with_jitter/1,
      max_retries: 3,
      receive_timeout: receive_timeout,
      exchange: exchange,
      operation_type: operation_type,
      skip_auth: false,
      skip_rate_limit: false
    )
    |> attach_telemetry()
    |> maybe_attach_circuit_breaker(exchange)
  end

  @doc """
  Creates a request for health check endpoints with shorter timeout.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  A configured `Req.Request` struct optimized for health checks
  """
  @spec health_check_request(atom()) :: Req.Request.t()
  def health_check_request(exchange) do
    exchange
    |> base_request(:health)
    |> Req.merge(skip_auth: true, skip_rate_limit: true)
  end

  # Request Steps (run before the request is sent)

  @spec rate_limit_step(Req.Request.t()) :: Req.Request.t() | {Req.Request.t(), Req.Response.t()}
  defp rate_limit_step(request) do
    if request.options[:skip_rate_limit] do
      request
    else
      exchange = request.options[:exchange]
      endpoints = ZenCex.Core.Registry.get_endpoints!(exchange)

      # Get the rate limiter module
      rate_limiter = endpoints.rate_limiter()

      # Extract endpoint from URL
      endpoint = get_endpoint(request)

      # Get weight from request.private if set by endpoint registry, otherwise default to 1
      weight = get_in(request.private, [:rate_limit_weight]) || 1

      # Check rate limit with weight
      case rate_limiter.check_and_increment(endpoint, weight) do
        :ok ->
          request

        {:error, :rate_limited} ->
          emit_rate_limit_telemetry(exchange, endpoint)
          # Return a response to halt the pipeline
          {request, %Req.Response{status: 429, body: "Rate limited"}}

        {:error, {:rate_limited, retry_after_ms}} ->
          emit_rate_limit_telemetry(exchange, endpoint, retry_after_ms)
          # Return a response with retry-after header
          {request,
           %Req.Response{
             status: 429,
             body: "Rate limited",
             headers: [{"retry-after", Integer.to_string(div(retry_after_ms, @seconds_per_millisecond_divisor))}]
           }}
      end
    end
  end

  @spec auth_step(Req.Request.t()) :: Req.Request.t()
  defp auth_step(request) do
    # TODO: Remove debug logging
    require Logger

    Logger.debug("Core.HTTP auth_step called, skip_auth: #{request.options[:skip_auth]}")

    if request.options[:skip_auth] do
      request
    else
      exchange = request.options[:exchange]
      endpoints = ZenCex.Core.Registry.get_endpoints!(exchange)

      # Get the auth module
      auth = endpoints.auth()

      # Call the unified apply_auth function
      # The auth module will handle getting credentials from options or environment
      auth.apply_auth(request)
    end
  end

  # Response Steps (run after response is received)

  @spec handle_response_step({Req.Request.t(), Req.Response.t()}) ::
          {Req.Request.t(), Req.Response.t() | Exception.t()}
  defp handle_response_step({request, response}) do
    # Check if response handling is disabled (e.g., for raw responses)
    if request.options[:skip_response_handling] do
      {request, response}
    else
      case response.status do
        status when status in 200..299 ->
          # Success - pass through for parser handling
          {request, response}

        429 ->
          # Rate limit error - already handled by rate_limit_step
          {request, response}

        status when status in 400..499 ->
          # Client error - parse and potentially convert to error
          handle_client_error(request, response)

        status when status in 500..599 ->
          # Server error - these should typically be retried
          handle_server_error(request, response)

        _ ->
          # Unexpected status - use the Mint-style error format
          {request,
           %Req.TransportError{
             reason: {:unexpected_status, response.status}
           }}
      end
    end
  end

  defp handle_client_error(request, response) do
    exchange = request.options[:exchange]

    # Capture client errors for debug if enabled
    if Mix.env() in [:dev, :test] && response.status >= 400 do
      Debug.capture_request(request, {:http_error, response.status, response.body})
    end

    # Try to parse the error using the exchange's parser if available
    if exchange do
      parser_module = get_parser_module(exchange)

      if parser_module && function_exported?(parser_module, :parse_error, 1) do
        case parser_module.parse_error(response.body) do
          {:error, _error_atom} ->
            # Parser recognized the error - keep response for downstream handling
            # The endpoint registry or caller will handle the parsed error
            {request, response}

          _ ->
            # Parser couldn't handle it, return as-is
            {request, response}
        end
      else
        # No parser available, return response as-is
        {request, response}
      end
    else
      {request, response}
    end
  end

  defp handle_server_error(request, response) do
    # Server errors should typically trigger retries
    # Return response as-is, let retry logic handle it
    {request, response}
  end

  defp get_parser_module(exchange) do
    # Build the parser module name
    exchange_string = exchange |> Atom.to_string() |> Macro.camelize()
    module = Module.concat([ZenCex, Adapters, exchange_string, Parser])

    # Check if the module is loaded
    if Code.ensure_loaded?(module) do
      module
    end
  end

  @spec update_rate_limit_step({Req.Request.t(), Req.Response.t()}) ::
          {Req.Request.t(), Req.Response.t()}
  defp update_rate_limit_step({request, response}) do
    if request.options[:skip_rate_limit] do
      {request, response}
    else
      exchange = request.options[:exchange]
      endpoints = ZenCex.Core.Registry.get_endpoints!(exchange)

      # Get the rate limiter module
      rate_limiter = endpoints.rate_limiter()

      # Store full request URL in response private for rate limiter to detect API type
      # We need the full URL (including host) to properly detect API type (spot vs futures vs sapi)
      full_url =
        if request.url do
          URI.to_string(request.url)
        else
          get_endpoint(request)
        end

      response_with_url =
        put_in(response.private[:req_url], full_url)

      # Update rate limit tracking from response headers
      if function_exported?(rate_limiter, :update_from_response, 1) do
        rate_limiter.update_from_response(response_with_url)
      end

      {request, response_with_url}
    end
  end

  # Error Steps (run when an error occurs)

  @spec telemetry_error_step({Req.Request.t(), Exception.t()}) :: {Req.Request.t(), Exception.t()}
  defp telemetry_error_step({request, exception}) do
    exchange = request.options[:exchange]
    operation_type = request.options[:operation_type]
    endpoint = get_endpoint(request)

    :telemetry.execute(
      [:zen_cex, :request, :error],
      %{count: 1},
      %{
        exchange: exchange,
        operation_type: operation_type,
        endpoint: endpoint,
        error: exception
      }
    )

    # Capture request for debug if enabled
    if Mix.env() in [:dev, :test] do
      Debug.capture_request(request, exception)
    end

    {request, exception}
  end

  # Telemetry attachment

  @spec attach_telemetry(Req.Request.t()) :: Req.Request.t()
  defp attach_telemetry(request) do
    # Attach to Req's built-in telemetry events
    request_ref = make_ref()

    request
    |> Req.Request.put_private(:zen_cex_request_ref, request_ref)
    |> Req.Request.put_private(:zen_cex_start_time, System.monotonic_time())
    |> Req.Request.append_response_steps(zen_cex_telemetry_response: &telemetry_response_step/1)
  end

  @spec telemetry_response_step({Req.Request.t(), Req.Response.t()}) ::
          {Req.Request.t(), Req.Response.t()}
  defp telemetry_response_step({request, response}) do
    start_time = Req.Request.get_private(request, :zen_cex_start_time)
    duration = System.monotonic_time() - start_time

    exchange = request.options[:exchange]
    operation_type = request.options[:operation_type]
    endpoint = get_endpoint(request)

    :telemetry.execute(
      [:zen_cex, :request, :complete],
      %{
        duration: System.convert_time_unit(duration, :native, :microsecond),
        count: 1
      },
      %{
        exchange: exchange,
        operation_type: operation_type,
        endpoint: endpoint,
        status: response.status
      }
    )

    {request, response}
  end

  # Helper functions

  @spec get_timeout(atom()) :: non_neg_integer()
  defp get_timeout(operation_type) do
    case operation_type do
      :trading -> @trading_timeout_ms
      :market -> @market_timeout_ms
      :historical -> @historical_timeout_ms
      :health -> @health_timeout_ms
      _ -> @default_timeout_ms
    end
  end

  @spec exponential_backoff_with_jitter(non_neg_integer()) :: non_neg_integer()
  defp exponential_backoff_with_jitter(n) do
    base_ms = min(@base_backoff_ms * 2 ** min(n, @max_backoff_exponent), @max_backoff_ms)
    jitter_ms = :rand.uniform(@jitter_range_ms)
    min(base_ms + jitter_ms, @max_backoff_ms)
  end

  @spec get_endpoint(Req.Request.t()) :: String.t()
  defp get_endpoint(%Req.Request{} = request) do
    uri =
      if request.url do
        request.url
      else
        # Build URI from parts if not yet resolved
        scheme = request.options[:scheme] || "https"
        host = request.options[:base_url] || ""
        path = request.options[:path] || "/"

        URI.parse("#{scheme}://#{host}#{path}")
      end

    uri.path || "/"
  end

  @spec emit_rate_limit_telemetry(atom(), String.t(), non_neg_integer() | nil) :: :ok
  defp emit_rate_limit_telemetry(exchange, endpoint, retry_after_ms \\ nil) do
    metadata = %{
      exchange: exchange,
      endpoint: endpoint
    }

    metadata =
      if retry_after_ms do
        Map.put(metadata, :retry_after_ms, retry_after_ms)
      else
        metadata
      end

    :telemetry.execute(
      [:zen_cex, :rate_limit, :exceeded],
      %{count: 1},
      metadata
    )
  end

  @spec maybe_attach_circuit_breaker(Req.Request.t(), atom()) :: Req.Request.t()
  defp maybe_attach_circuit_breaker(request, exchange) do
    if Code.ensure_loaded?(CircuitBreaker) do
      CircuitBreaker.maybe_attach(request, exchange)
    else
      request
    end
  end
end
