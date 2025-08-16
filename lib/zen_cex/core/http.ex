defmodule ZenCex.Core.HTTP do
  @moduledoc """
  Core HTTP module that configures Req with Finch for connection pooling
  and integrates auth and rate limiting as composable request/response steps.

  This module provides:
  - Connection pooling via Finch
  - Exponential backoff with jitter
  - Operation-specific timeouts
  - Auth and rate limiting middleware
  - Telemetry event emission

  ## Operation Types

  - `:trading` - Order placement/cancellation (2s timeout)
  - `:market` - Current market data queries (5s timeout)
  - `:historical` - Historical data queries (30s timeout)
  - `:health` - Health check endpoints (5s timeout)
  - `:standard` - Default for unspecified operations (30s timeout)
  """

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
      2000

      iex> request = ZenCex.Core.HTTP.base_request(:kraken, :historical)
      iex> request.options[:receive_timeout]
      30000
  """
  def base_request(exchange, operation_type \\ :standard) do
    adapter = ZenCex.Core.Registry.get_adapter!(exchange)

    receive_timeout = get_timeout(operation_type)

    Req.new()
    |> Req.Request.register_options([:exchange, :operation_type, :skip_auth, :skip_rate_limit])
    |> Req.Request.prepend_request_steps(
      zen_cex_rate_limit: &rate_limit_step/1,
      zen_cex_auth: &auth_step/1
    )
    |> Req.Request.append_response_steps(zen_cex_update_rate_limit: &update_rate_limit_step/1)
    |> Req.Request.append_error_steps(zen_cex_telemetry: &telemetry_error_step/1)
    |> Req.merge(
      base_url: adapter.base_url(:prod),
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
  end

  @doc """
  Creates a request for health check endpoints with shorter timeout.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  A configured `Req.Request` struct optimized for health checks
  """
  def health_check_request(exchange) do
    base_request(exchange, :health)
    |> Req.merge(skip_auth: true, skip_rate_limit: true)
  end

  # Request Steps (run before the request is sent)

  defp rate_limit_step(request) do
    if request.options[:skip_rate_limit] do
      request
    else
      exchange = request.options[:exchange]
      adapter = ZenCex.Core.Registry.get_adapter!(exchange)

      # Get the rate limiter module
      rate_limiter = adapter.rate_limiter()

      # Extract endpoint from URL
      endpoint = get_endpoint(request)

      # Check rate limit
      case rate_limiter.check_and_increment(endpoint) do
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
             headers: [{"retry-after", Integer.to_string(div(retry_after_ms, 1000))}]
           }}
      end
    end
  end

  defp auth_step(request) do
    if request.options[:skip_auth] do
      request
    else
      exchange = request.options[:exchange]
      adapter = ZenCex.Core.Registry.get_adapter!(exchange)

      # Get the auth module
      auth = adapter.auth()

      # Sign the request
      auth.sign_request(request)
    end
  end

  # Response Steps (run after response is received)

  defp update_rate_limit_step({request, response}) do
    if request.options[:skip_rate_limit] do
      {request, response}
    else
      exchange = request.options[:exchange]
      adapter = ZenCex.Core.Registry.get_adapter!(exchange)

      # Get the rate limiter module
      rate_limiter = adapter.rate_limiter()

      # Update rate limit tracking from response headers
      if function_exported?(rate_limiter, :update_from_response, 1) do
        rate_limiter.update_from_response(response)
      end

      {request, response}
    end
  end

  # Error Steps (run when an error occurs)

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

    {request, exception}
  end

  # Telemetry attachment

  defp attach_telemetry(request) do
    # Attach to Req's built-in telemetry events
    request_ref = make_ref()

    request
    |> Req.Request.put_private(:zen_cex_request_ref, request_ref)
    |> Req.Request.put_private(:zen_cex_start_time, System.monotonic_time())
    |> Req.Request.append_response_steps(zen_cex_telemetry_response: &telemetry_response_step/1)
  end

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

  defp get_timeout(operation_type) do
    case operation_type do
      :trading -> 2_000
      :market -> 5_000
      :historical -> 30_000
      :health -> 5_000
      _ -> 30_000
    end
  end

  defp exponential_backoff_with_jitter(n) do
    base_ms = min(1000 * 2 ** min(n, 10), 60_000)
    jitter_ms = :rand.uniform(500)
    min(base_ms + jitter_ms, 60_000)
  end

  defp get_endpoint(%Req.Request{} = request) do
    uri =
      if request.url do
        request.url
      else
        # Build URI from parts if not yet resolved
        scheme = request.options[:scheme] || "https"
        host = request.options[:base_url] || ""
        path = request.options[:path] || "/"

        "#{scheme}://#{host}#{path}"
        |> URI.parse()
      end

    uri.path || "/"
  end

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
end
