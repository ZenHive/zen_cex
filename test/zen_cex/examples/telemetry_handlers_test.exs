defmodule ZenCex.Examples.TelemetryHandlersTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ZenCex.Examples.TelemetryHandlers
  alias ZenCex.Examples.TelemetryHandlers.CircuitBreakerAlerts
  alias ZenCex.Examples.TelemetryHandlers.ErrorTracker
  alias ZenCex.Examples.TelemetryHandlers.PerformanceReporter
  alias ZenCex.Examples.TelemetryHandlers.RateLimitMonitor
  alias ZenCex.Examples.TelemetryHandlers.RequestLogger

  setup do
    # Detach any existing handlers to ensure clean state
    TelemetryHandlers.detach_all()
    on_exit(fn -> TelemetryHandlers.detach_all() end)
    :ok
  end

  describe "RequestLogger" do
    test "logs successful requests" do
      RequestLogger.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :request, :complete],
            # 500ms in microseconds
            %{duration: 500_000},
            %{exchange: :binance, endpoint: "/api/v3/account", status: 200}
          )
        end)

      assert log =~ "[binance] /api/v3/account - 200 in 500ms"
      assert log =~ "[info]"
    end

    test "logs slow requests with warning" do
      RequestLogger.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :request, :complete],
            # 2 seconds
            %{duration: 2_000_000},
            %{exchange: :binance, endpoint: "/api/v3/account", status: 200}
          )
        end)

      assert log =~ "[binance] /api/v3/account - 200 in 2000ms"
      assert log =~ "[warning]"
    end

    test "can be detached" do
      RequestLogger.attach()
      RequestLogger.detach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :request, :complete],
            %{duration: 500_000},
            %{exchange: :binance, endpoint: "/api/v3/account", status: 200}
          )
        end)

      refute log =~ "[binance]"
    end
  end

  describe "ErrorTracker" do
    test "logs request errors" do
      ErrorTracker.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :request, :error],
            %{count: 1},
            %{
              exchange: :binance,
              endpoint: "/api/v3/order",
              operation_type: :trading,
              error: {:error, :timeout}
            }
          )
        end)

      assert log =~ "Request failed for binance"
      assert log =~ "Endpoint: /api/v3/order"
      assert log =~ "Error: {:error, :timeout}"
      assert log =~ "[error]"
    end

    test "logs auth failures" do
      ErrorTracker.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :auth, :failure],
            %{count: 1},
            %{
              exchange: :binance,
              auth_method: :hmac,
              reason: :invalid_signature
            }
          )
        end)

      assert log =~ "Authentication failed for binance"
      assert log =~ "Method: hmac"
      assert log =~ "Reason: :invalid_signature"
    end
  end

  describe "RateLimitMonitor" do
    test "logs rate limit exceeded" do
      RateLimitMonitor.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :rate_limit, :exceeded],
            %{count: 1},
            %{
              exchange: :binance,
              endpoint: "/api/v3/order",
              retry_after_ms: 5000
            }
          )
        end)

      assert log =~ "Rate limit exceeded for binance"
      assert log =~ "retry after 5000ms"
      assert log =~ "[warning]"
    end

    test "warns on high rate limit utilization" do
      RateLimitMonitor.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :rate_limit, :updated],
            %{used: 900, limit: 1000},
            %{exchange: :binance}
          )
        end)

      assert log =~ "High rate limit utilization for binance"
      assert log =~ "900/1000 (90.0%)"
    end

    test "does not warn on low utilization" do
      RateLimitMonitor.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :rate_limit, :updated],
            %{used: 500, limit: 1000},
            %{exchange: :binance}
          )
        end)

      assert log == ""
    end
  end

  describe "PerformanceReporter" do
    test "tracks request statistics" do
      PerformanceReporter.attach()

      # Make some requests
      :telemetry.execute(
        [:zen_cex, :request, :complete],
        # 100ms
        %{duration: 100_000},
        %{exchange: :binance, endpoint: "/api/v3/account", status: 200}
      )

      :telemetry.execute(
        [:zen_cex, :request, :complete],
        # 200ms
        %{duration: 200_000},
        %{exchange: :binance, endpoint: "/api/v3/account", status: 200}
      )

      :telemetry.execute(
        [:zen_cex, :request, :error],
        %{count: 1},
        %{exchange: :binance, endpoint: "/api/v3/account", error: :timeout}
      )

      # Give async casts time to process
      Process.sleep(50)

      stats = PerformanceReporter.get_stats()

      assert stats.total_requests == 2
      assert stats.total_errors == 1

      endpoint_stats = hd(stats.endpoints)
      assert endpoint_stats.exchange == :binance
      assert endpoint_stats.endpoint == "/api/v3/account"
      assert endpoint_stats.request_count == 2
      assert endpoint_stats.error_count == 1
      assert endpoint_stats.error_rate == 33.33
      assert endpoint_stats.avg_duration_ms == 150
      assert endpoint_stats.min_duration_ms == 100
      assert endpoint_stats.max_duration_ms == 200

      PerformanceReporter.detach()
    end

    test "can reset statistics" do
      PerformanceReporter.attach()

      :telemetry.execute(
        [:zen_cex, :request, :complete],
        %{duration: 100_000},
        %{exchange: :binance, endpoint: "/api/v3/account", status: 200}
      )

      Process.sleep(50)

      PerformanceReporter.reset_stats()
      stats = PerformanceReporter.get_stats()

      assert stats.total_requests == 0
      assert stats.total_errors == 0
      assert stats.endpoints == []

      PerformanceReporter.detach()
    end
  end

  describe "CircuitBreakerAlerts" do
    test "logs circuit breaker blown" do
      CircuitBreakerAlerts.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :circuit_breaker, :blown],
            %{count: 1},
            %{exchange: :binance}
          )
        end)

      assert log =~ "CIRCUIT BREAKER BLOWN for binance"
      assert log =~ "[error]"
    end

    test "logs circuit breaker reset" do
      CircuitBreakerAlerts.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :circuit_breaker, :reset],
            %{count: 1},
            %{exchange: :binance, manual: false}
          )
        end)

      assert log =~ "Circuit breaker automatically reset for binance"
      assert log =~ "[info]"
    end

    test "logs manual circuit breaker reset" do
      CircuitBreakerAlerts.attach()

      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :circuit_breaker, :reset],
            %{count: 1},
            %{exchange: :binance, manual: true}
          )
        end)

      assert log =~ "Circuit breaker manually reset for binance"
    end
  end

  describe "attach_all/detach_all" do
    test "attaches and detaches all handlers" do
      # Attach all handlers
      TelemetryHandlers.attach_all()

      # Verify they work
      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :request, :complete],
            %{duration: 100_000},
            %{exchange: :binance, endpoint: "/test", status: 200}
          )

          :telemetry.execute(
            [:zen_cex, :circuit_breaker, :blown],
            %{count: 1},
            %{exchange: :kraken}
          )
        end)

      assert log =~ "[binance] /test"
      assert log =~ "CIRCUIT BREAKER BLOWN for kraken"

      # Detach all
      TelemetryHandlers.detach_all()

      # Verify they're detached
      log =
        capture_log(fn ->
          :telemetry.execute(
            [:zen_cex, :request, :complete],
            %{duration: 100_000},
            %{exchange: :binance, endpoint: "/test", status: 200}
          )
        end)

      refute log =~ "[binance]"
    end
  end
end
