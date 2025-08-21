defmodule ZenCex.Examples.TelemetryHandlers do
  @moduledoc """
  Example telemetry handlers for ZenCex.

  This module provides production-ready telemetry handlers that you can use
  as-is or customize for your application's needs.

  ## Usage

      # In your application.ex
      def start(_type, _args) do
        # Attach handlers
        ZenCex.Examples.TelemetryHandlers.attach_all()
        
        # ... rest of your supervision tree
      end

  ## Available Handlers

  - `RequestLogger` - Logs all requests with timing information
  - `ErrorTracker` - Tracks and logs errors with context
  - `RateLimitMonitor` - Monitors rate limit usage
  - `PerformanceReporter` - Tracks performance metrics
  - `CircuitBreakerAlerts` - Alerts on circuit breaker state changes
  """

  require Logger

  @doc """
  Attaches all example handlers.
  """
  def attach_all do
    __MODULE__.RequestLogger.attach()
    __MODULE__.ErrorTracker.attach()
    __MODULE__.RateLimitMonitor.attach()
    __MODULE__.PerformanceReporter.attach()
    __MODULE__.CircuitBreakerAlerts.attach()
    :ok
  end

  @doc """
  Detaches all example handlers.
  """
  def detach_all do
    __MODULE__.RequestLogger.detach()
    __MODULE__.ErrorTracker.detach()
    __MODULE__.RateLimitMonitor.detach()
    __MODULE__.PerformanceReporter.detach()
    __MODULE__.CircuitBreakerAlerts.detach()
    :ok
  end

  defmodule RequestLogger do
    @moduledoc """
    Logs all requests with timing and status information.

    Logs at INFO level for successful requests, WARN for slow requests (>1s).
    """

    require Logger

    def attach do
      :telemetry.attach(
        "zen-cex-request-logger",
        [:zen_cex, :request, :complete],
        &handle_request/4,
        nil
      )
    end

    def detach do
      :telemetry.detach("zen-cex-request-logger")
    end

    def handle_request(_event, measurements, metadata, _config) do
      duration_ms = div(measurements.duration, 1_000)

      log_level =
        cond do
          duration_ms > 1_000 -> :warning
          metadata.status >= 400 -> :warning
          true -> :info
        end

      Logger.log(log_level, fn ->
        "[#{metadata.exchange}] #{metadata.endpoint} - #{metadata.status} in #{duration_ms}ms"
      end)
    end
  end

  defmodule ErrorTracker do
    @moduledoc """
    Tracks and logs errors with full context.

    Useful for debugging and error monitoring services.
    """

    require Logger

    def attach do
      events = [
        [:zen_cex, :request, :error],
        [:zen_cex, :auth, :failure]
      ]

      :telemetry.attach_many(
        "zen-cex-error-tracker",
        events,
        &handle_error/4,
        nil
      )
    end

    def detach do
      :telemetry.detach("zen-cex-error-tracker")
    end

    def handle_error([:zen_cex, :request, :error], _measurements, metadata, _config) do
      Logger.error("""
      Request failed for #{metadata.exchange}
      Endpoint: #{metadata.endpoint}
      Error: #{inspect(metadata.error)}
      Operation: #{metadata.operation_type}
      """)

      # You could send to error tracking service here
      # ErrorReporter.report(metadata.error, metadata)
    end

    def handle_error([:zen_cex, :auth, :failure], _measurements, metadata, _config) do
      Logger.error("""
      Authentication failed for #{metadata.exchange}
      Method: #{metadata.auth_method}
      Reason: #{inspect(metadata.reason)}
      """)
    end
  end

  defmodule RateLimitMonitor do
    @moduledoc """
    Monitors rate limit usage and warns when approaching limits.
    """

    require Logger

    def attach do
      events = [
        [:zen_cex, :rate_limit, :exceeded],
        [:zen_cex, :rate_limit, :updated]
      ]

      :telemetry.attach_many(
        "zen-cex-rate-monitor",
        events,
        &handle_rate_limit/4,
        nil
      )
    end

    def detach do
      :telemetry.detach("zen-cex-rate-monitor")
    end

    def handle_rate_limit([:zen_cex, :rate_limit, :exceeded], _measurements, metadata, _config) do
      retry_msg =
        if metadata[:retry_after_ms] do
          " (retry after #{metadata.retry_after_ms}ms)"
        else
          ""
        end

      Logger.warning("""
      Rate limit exceeded for #{metadata.exchange}
      Endpoint: #{metadata.endpoint}#{retry_msg}
      Consider reducing request frequency
      """)
    end

    def handle_rate_limit([:zen_cex, :rate_limit, :updated], measurements, metadata, _config) do
      utilization = measurements.used / measurements.limit * 100

      if utilization > 80 do
        Logger.warning("""
        High rate limit utilization for #{metadata.exchange}
        Used: #{measurements.used}/#{measurements.limit} (#{Float.round(utilization, 1)}%)
        """)
      end
    end
  end

  defmodule PerformanceReporter do
    @moduledoc """
    Tracks performance metrics and reports statistics.

    Maintains in-memory stats that can be queried.
    """

    use GenServer

    require Logger

    # Client API

    def attach do
      # Start the GenServer
      {:ok, _pid} = start_link()

      # Attach telemetry handlers
      :telemetry.attach(
        "zen-cex-performance",
        [:zen_cex, :request, :complete],
        &handle_request/4,
        nil
      )

      :telemetry.attach(
        "zen-cex-performance-error",
        [:zen_cex, :request, :error],
        &handle_error/4,
        nil
      )
    end

    def detach do
      :telemetry.detach("zen-cex-performance")
      :telemetry.detach("zen-cex-performance-error")
      stop()
    end

    def start_link do
      GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
    end

    def stop do
      if Process.whereis(__MODULE__) do
        GenServer.stop(__MODULE__)
      end
    end

    def get_stats do
      GenServer.call(__MODULE__, :get_stats)
    end

    def reset_stats do
      GenServer.call(__MODULE__, :reset_stats)
    end

    # Telemetry handlers

    def handle_request(_event, measurements, metadata, _config) do
      GenServer.cast(__MODULE__, {:request, measurements, metadata})
    end

    def handle_error(_event, _measurements, metadata, _config) do
      GenServer.cast(__MODULE__, {:error, metadata})
    end

    # Server callbacks

    def init(_) do
      {:ok,
       %{
         requests: %{},
         errors: %{},
         start_time: System.monotonic_time(:second)
       }}
    end

    def handle_cast({:request, measurements, metadata}, state) do
      key = {metadata.exchange, metadata.endpoint}

      request_stats =
        Map.get(state.requests, key, %{
          count: 0,
          total_duration: 0,
          min_duration: nil,
          max_duration: 0,
          status_codes: %{}
        })

      updated_stats = %{
        count: request_stats.count + 1,
        total_duration: request_stats.total_duration + measurements.duration,
        min_duration: min(request_stats.min_duration || measurements.duration, measurements.duration),
        max_duration: max(request_stats.max_duration, measurements.duration),
        status_codes: Map.update(request_stats.status_codes, metadata.status, 1, &(&1 + 1))
      }

      {:noreply, %{state | requests: Map.put(state.requests, key, updated_stats)}}
    end

    def handle_cast({:error, metadata}, state) do
      key = {metadata.exchange, metadata.endpoint}
      errors = Map.update(state.errors, key, 1, &(&1 + 1))
      {:noreply, %{state | errors: errors}}
    end

    def handle_call(:get_stats, _from, state) do
      uptime_seconds = System.monotonic_time(:second) - state.start_time

      stats =
        state.requests
        |> Enum.map(fn {{exchange, endpoint}, data} ->
          error_count = Map.get(state.errors, {exchange, endpoint}, 0)
          total_requests = data.count + error_count

          %{
            exchange: exchange,
            endpoint: endpoint,
            request_count: data.count,
            error_count: error_count,
            error_rate: if(total_requests > 0, do: Float.round(error_count / total_requests * 100, 2), else: 0.0),
            avg_duration_ms: if(data.count > 0, do: div(data.total_duration, data.count * 1_000), else: 0),
            min_duration_ms: if(data.min_duration, do: div(data.min_duration, 1_000)),
            max_duration_ms: div(data.max_duration, 1_000),
            requests_per_minute: Float.round(data.count / max(uptime_seconds / 60, 1), 2),
            status_codes: data.status_codes
          }
        end)
        |> Enum.sort_by(& &1.request_count, :desc)

      summary = %{
        uptime_minutes: div(uptime_seconds, 60),
        total_requests: Enum.sum(Enum.map(state.requests, fn {_, data} -> data.count end)),
        total_errors: Enum.sum(Map.values(state.errors)),
        endpoints: stats
      }

      {:reply, summary, state}
    end

    def handle_call(:reset_stats, _from, _state) do
      {:reply, :ok,
       %{
         requests: %{},
         errors: %{},
         start_time: System.monotonic_time(:second)
       }}
    end
  end

  defmodule CircuitBreakerAlerts do
    @moduledoc """
    Monitors circuit breaker state changes and sends alerts.
    """

    require Logger

    def attach do
      events = [
        [:zen_cex, :circuit_breaker, :blown],
        [:zen_cex, :circuit_breaker, :reset],
        [:zen_cex, :circuit_breaker, :rejected]
      ]

      :telemetry.attach_many(
        "zen-cex-circuit-alerts",
        events,
        &handle_circuit_event/4,
        nil
      )
    end

    def detach do
      :telemetry.detach("zen-cex-circuit-alerts")
    end

    def handle_circuit_event([:zen_cex, :circuit_breaker, :blown], _measurements, metadata, _config) do
      Logger.error("""
      🚨 CIRCUIT BREAKER BLOWN for #{metadata.exchange}
      All requests to this exchange will be rejected
      Action required: Check exchange status and errors
      """)

      # Send critical alert
      send_alert(:critical, "Circuit breaker blown for #{metadata.exchange}")
    end

    def handle_circuit_event([:zen_cex, :circuit_breaker, :reset], _measurements, metadata, _config) do
      reset_type = if metadata.manual, do: "manually", else: "automatically"

      Logger.info("""
      ✅ Circuit breaker #{reset_type} reset for #{metadata.exchange}
      Normal operations resumed
      """)

      # Clear alert
      clear_alert("Circuit breaker for #{metadata.exchange}")
    end

    def handle_circuit_event([:zen_cex, :circuit_breaker, :rejected], _measurements, metadata, _config) do
      # Log at debug level since this is expected when circuit is open
      Logger.debug("Request rejected by circuit breaker for #{metadata.exchange}")
    end

    defp send_alert(severity, message) do
      # Implement your alerting logic here
      # Examples:
      # - Send to PagerDuty
      # - Post to Slack webhook
      # - Send email
      # - Write to monitoring service

      Logger.warning("ALERT [#{severity}]: #{message}")
    end

    defp clear_alert(identifier) do
      # Clear the alert in your monitoring service
      Logger.info("Alert cleared: #{identifier}")
    end
  end
end

defmodule ZenCex.Examples.TelemetryDashboard do
  @moduledoc """
  Example metrics for Phoenix LiveDashboard integration.

  To use these metrics in your Phoenix application:

  1. Add `telemetry_metrics` to your dependencies:
     ```elixir
     {:telemetry_metrics, "~> 1.0"}
     ```

  2. In your `MyAppWeb.Telemetry` module:
     ```elixir
     import Telemetry.Metrics
     
     def metrics do
       ZenCex.Examples.TelemetryDashboard.metric_definitions() ++
       [
         # Your other metrics...
       ]
     end
     ```
  """

  @doc """
  Returns metric definitions for Phoenix LiveDashboard.

  When telemetry_metrics is available, you can convert these to metrics:
  ```elixir
  import Telemetry.Metrics

  ZenCex.Examples.TelemetryDashboard.metric_definitions()
  |> Enum.map(fn {type, name, opts} ->
    apply(Telemetry.Metrics, type, [name, opts])
  end)
  ```
  """
  def metric_definitions do
    [
      # Request metrics
      {:summary, "zen_cex.request.complete.duration", unit: {:native, :millisecond}, tags: [:exchange, :endpoint],
       tag_values: &tag_values/1, description: "Request duration by exchange and endpoint"},
      {:counter, "zen_cex.request.complete.count", tags: [:exchange, :status], tag_values: &tag_values/1,
       description: "Total requests by exchange and status"},
      {:counter, "zen_cex.request.error.count", tags: [:exchange], description: "Total errors by exchange"},

      # Rate limit metrics
      {:counter, "zen_cex.rate_limit.exceeded.count", tags: [:exchange],
       description: "Rate limit violations by exchange"},
      {:last_value, "zen_cex.rate_limit.updated.used", tags: [:exchange], description: "Current rate limit usage"},

      # Circuit breaker metrics
      {:counter, "zen_cex.circuit_breaker.blown.count", tags: [:exchange], description: "Circuit breaker activations"},
      {:counter, "zen_cex.circuit_breaker.rejected.count", tags: [:exchange],
       description: "Requests rejected by circuit breaker"},

      # Order metrics
      {:counter, "zen_cex.order.placed.count", tags: [:exchange, :side],
       description: "Orders placed by exchange and side"},
      {:counter, "zen_cex.order.idempotency_detected.count", tags: [:exchange],
       description: "Duplicate orders prevented"},

      # Finch connection metrics
      {:summary, "finch.request.stop.duration", unit: {:native, :millisecond}, tags: [:status],
       description: "HTTP request duration"},
      {:counter, "finch.reused_connection", description: "Connection reuse count"}
    ]
  end

  # Tag value transformer to normalize endpoint paths
  defp tag_values(metadata) do
    metadata
    |> Map.update(:endpoint, nil, &normalize_endpoint/1)
    |> Map.update(:status, nil, &status_bucket/1)
  end

  # Remove query parameters and IDs from endpoints
  defp normalize_endpoint(nil), do: "unknown"

  defp normalize_endpoint(endpoint) do
    endpoint
    |> String.split("?")
    |> List.first()
    |> String.replace(~r/\/\d+/, "/:id")
  end

  # Group status codes into buckets
  defp status_bucket(nil), do: "unknown"
  defp status_bucket(status) when status < 300, do: "2xx"
  defp status_bucket(status) when status < 400, do: "3xx"
  defp status_bucket(status) when status < 500, do: "4xx"
  defp status_bucket(status) when status < 600, do: "5xx"
  defp status_bucket(_), do: "unknown"
end
