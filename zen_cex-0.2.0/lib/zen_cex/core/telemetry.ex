defmodule ZenCex.Core.Telemetry do
  @moduledoc """
  Telemetry event definitions and helpers for ZenCex.

  This module provides telemetry events for monitoring exchange operations,
  request performance, and error tracking.

  ## Events

  ### Request Events

  - `[:zen_cex, :request, :start]` - Emitted when a request starts
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{exchange: atom(), operation_type: atom(), endpoint: String.t()}`

  - `[:zen_cex, :request, :complete]` - Emitted when a request completes successfully
    - Measurements: `%{duration: integer(), count: 1}`
    - Metadata: `%{exchange: atom(), operation_type: atom(), endpoint: String.t(), status: integer()}`

  - `[:zen_cex, :request, :error]` - Emitted when a request fails
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), operation_type: atom(), endpoint: String.t(), error: term()}`

  ### Rate Limit Events

  - `[:zen_cex, :rate_limit, :exceeded]` - Emitted when rate limit is exceeded
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), endpoint: String.t(), retry_after_ms: integer() | nil}`

  - `[:zen_cex, :rate_limit, :updated]` - Emitted when rate limit is updated from headers
    - Measurements: `%{used: integer(), limit: integer()}`
    - Metadata: `%{exchange: atom()}`

  ### Auth Events

  - `[:zen_cex, :auth, :success]` - Emitted when authentication succeeds
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), auth_method: atom()}`

  - `[:zen_cex, :auth, :failure]` - Emitted when authentication fails
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), auth_method: atom(), reason: term()}`

  ### Order Events

  - `[:zen_cex, :order, :placed]` - Emitted when an order is placed
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), order_id: String.t(), side: atom(), amount: Decimal.t()}`

  - `[:zen_cex, :order, :cancelled]` - Emitted when an order is cancelled
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), order_id: String.t()}`

  - `[:zen_cex, :order, :idempotency_detected]` - Emitted when duplicate order is detected
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), client_order_id: String.t()}`

  ### Circuit Breaker Events

  - `[:zen_cex, :circuit_breaker, :blown]` - Emitted when circuit opens due to failures
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom()}`

  - `[:zen_cex, :circuit_breaker, :reset]` - Emitted when circuit closes/resets
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom(), manual: boolean()}`

  - `[:zen_cex, :circuit_breaker, :rejected]` - Emitted when request is rejected due to open circuit
    - Measurements: `%{count: 1}`
    - Metadata: `%{exchange: atom()}`

  ## Usage

  To attach handlers to these events, use `:telemetry.attach/4`:

      :telemetry.attach(
        "log-request-duration",
        [:zen_cex, :request, :complete],
        &log_handler/4,
        nil
      )

      def log_handler(_event, measurements, metadata, _config) do
        Logger.info("Request to \#{metadata.exchange} took \#{measurements.duration}μs")
      end

  ## Req Integration

  This module also hooks into Req's built-in telemetry events:
  - `[:req, :request, :start]`
  - `[:req, :request, :stop]`
  - `[:req, :request, :exception]`
  """

  alias ZenCex.Core.Telemetry

  require Logger

  @doc """
  Attaches default telemetry handlers for logging and metrics.

  This function attaches handlers that:
  - Log slow requests (>1000ms)
  - Log all errors
  - Track rate limit violations
  - Monitor auth failures

  ## Examples

      iex> ZenCex.Core.Telemetry.attach_default_handlers()
      :ok
  """
  @spec attach_default_handlers() :: :ok
  def attach_default_handlers do
    handlers = [
      {
        "zen-cex-log-slow-requests",
        [:zen_cex, :request, :complete],
        &Telemetry.log_slow_request/4
      },
      {
        "zen-cex-log-errors",
        [:zen_cex, :request, :error],
        &Telemetry.log_error/4
      },
      {
        "zen-cex-log-rate-limits",
        [:zen_cex, :rate_limit, :exceeded],
        &Telemetry.log_rate_limit/4
      },
      {
        "zen-cex-log-auth-failures",
        [:zen_cex, :auth, :failure],
        &Telemetry.log_auth_failure/4
      },
      {
        "zen-cex-log-circuit-breaker-blown",
        [:zen_cex, :circuit_breaker, :blown],
        &Telemetry.log_circuit_breaker_blown/4
      },
      {
        "zen-cex-log-circuit-breaker-reset",
        [:zen_cex, :circuit_breaker, :reset],
        &Telemetry.log_circuit_breaker_reset/4
      },
      {
        "zen-cex-log-circuit-breaker-rejected",
        [:zen_cex, :circuit_breaker, :rejected],
        &Telemetry.log_circuit_breaker_rejected/4
      },
      {
        "zen-cex-req-integration",
        [:req, :request, :stop],
        &Telemetry.handle_req_stop/4
      }
    ]

    Enum.each(handlers, fn {name, event, handler} ->
      :telemetry.attach(name, event, handler, nil)
    end)

    :ok
  end

  @doc """
  Detaches all default handlers attached by `attach_default_handlers/0`.

  ## Examples

      iex> ZenCex.Core.Telemetry.detach_default_handlers()
      :ok
  """
  @spec detach_default_handlers() :: :ok
  def detach_default_handlers do
    handler_names = [
      "zen-cex-log-slow-requests",
      "zen-cex-log-errors",
      "zen-cex-log-rate-limits",
      "zen-cex-log-auth-failures",
      "zen-cex-log-circuit-breaker-blown",
      "zen-cex-log-circuit-breaker-reset",
      "zen-cex-log-circuit-breaker-rejected",
      "zen-cex-req-integration"
    ]

    Enum.each(handler_names, &:telemetry.detach/1)
    :ok
  end

  @doc """
  Executes a telemetry event.

  This is a convenience wrapper around `:telemetry.execute/3`.

  ## Parameters
  - `event` - Event name segments (e.g., `[:request, :complete]`)
  - `measurements` - Map of measurements
  - `metadata` - Map of metadata

  ## Examples

      iex> ZenCex.Core.Telemetry.execute([:request, :start], %{count: 1}, %{exchange: :binance})
      :ok
  """
  @spec execute(list(atom()), map(), map()) :: :ok
  def execute(event, measurements, metadata) do
    :telemetry.execute([:zen_cex | event], measurements, metadata)
  end

  # Handler functions (public for telemetry MFA references)

  @doc false
  @spec log_slow_request(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def log_slow_request(_event, %{duration: duration}, metadata, _config) do
    # > 1 second in microseconds
    if duration > 1_000_000 do
      Logger.warning("Slow request to #{metadata.exchange} #{metadata.endpoint}: #{div(duration, 1000)}ms")
    end

    :ok
  end

  @doc false
  @spec log_error(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def log_error(_event, _measurements, metadata, _config) do
    Logger.error("Request error for #{metadata.exchange} #{metadata.endpoint}: #{inspect(metadata.error)}")

    :ok
  end

  @doc false
  @spec log_rate_limit(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def log_rate_limit(_event, _measurements, metadata, _config) do
    retry_msg =
      if metadata[:retry_after_ms] do
        " (retry after #{metadata.retry_after_ms}ms)"
      else
        ""
      end

    Logger.warning("Rate limit exceeded for #{metadata.exchange} #{metadata.endpoint}#{retry_msg}")

    :ok
  end

  @doc false
  @spec log_auth_failure(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def log_auth_failure(_event, _measurements, metadata, _config) do
    Logger.error("Auth failure for #{metadata.exchange} using #{metadata.auth_method}: #{inspect(metadata.reason)}")

    :ok
  end

  @doc false
  @spec log_circuit_breaker_blown(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def log_circuit_breaker_blown(_event, _measurements, metadata, _config) do
    Logger.error("Circuit breaker BLOWN for #{metadata.exchange} - rejecting all requests")
    :ok
  end

  @doc false
  @spec log_circuit_breaker_reset(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def log_circuit_breaker_reset(_event, _measurements, metadata, _config) do
    reset_type = if metadata[:manual], do: "manually", else: "automatically"
    Logger.info("Circuit breaker RESET #{reset_type} for #{metadata.exchange} - accepting requests")
    :ok
  end

  @doc false
  @spec log_circuit_breaker_rejected(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok
  def log_circuit_breaker_rejected(_event, _measurements, metadata, _config) do
    Logger.warning("Request rejected by circuit breaker for #{metadata.exchange}")
    :ok
  end

  @doc false
  @spec handle_req_stop(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          :telemetry.handler_config()
        ) :: :ok | nil
  def handle_req_stop(_event, measurements, metadata, _config) do
    # Bridge Req telemetry to our own events for unified monitoring
    if metadata[:options][:exchange] do
      execute(
        [:req, :bridged],
        %{duration: measurements.duration},
        %{
          exchange: metadata.options.exchange,
          status: metadata.response && metadata.response.status,
          method: metadata.request.method,
          url: to_string(metadata.request.url)
        }
      )
    end
  end
end
