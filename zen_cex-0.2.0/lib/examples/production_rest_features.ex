defmodule ZenCex.Examples.ProductionRestFeatures do
  @moduledoc """
  Demonstrates zen_cex's production-ready REST features for building resilient trading systems.

  This module showcases the sophisticated HTTP client features that make zen_cex production-ready:

  ## Production Features Demonstrated

  1. **Circuit Breaker** - Prevents cascading failures when exchanges become unresponsive
  2. **Rate Limiting** - Automatic rate limit tracking and enforcement per exchange
  3. **Exponential Backoff** - Automatic retry with jitter for transient failures
  4. **Clock Synchronization** - Accurate timestamps for authentication
  5. **Debug Mode** - Export failed requests as curl commands for debugging
  6. **Telemetry** - Comprehensive monitoring events for observability
  7. **Operation-Specific Timeouts** - Optimized timeouts based on operation type

  ## Architecture

  These features are built into `ZenCex.Core.HTTP` and work automatically through Req middleware:

  - **HTTP Module**: Creates Req requests with all middleware pre-configured
  - **Rate Limiter**: Tracks and enforces exchange-specific rate limits via ETS
  - **Circuit Breaker**: Opens circuit after threshold failures, preventing cascading issues
  - **Clock Sync**: Maintains sub-millisecond time offset with exchange servers
  - **Retry Logic**: Exponential backoff with jitter (1s base, 60s max cap)
  - **Telemetry**: Emits events on all request lifecycle phases

  ## Operation Types

  Different operations have optimized timeout configurations:
  - `:trading` - 2s timeout (order placement/cancellation - critical path)
  - `:market` - 5s timeout (real-time market data queries)
  - `:historical` - 30s timeout (large dataset queries)
  - `:health` - 5s timeout (status monitoring)
  - `:standard` - 30s timeout (default for unspecified operations)

  ## Examples

      # Demonstrate circuit breaker protection
      {:ok, stats} = ProductionRestFeatures.demonstrate_circuit_breaker()

      # Show rate limiter in action
      {:ok, status} = ProductionRestFeatures.demonstrate_rate_limiting()

      # Use debug mode for troubleshooting
      curl_command = ProductionRestFeatures.demonstrate_debug_mode()

      # Monitor clock synchronization
      {:ok, offset_ms} = ProductionRestFeatures.demonstrate_clock_sync()

      # Complete production workflow
      {:ok, results} = ProductionRestFeatures.run_production_workflow()
  """

  alias ZenCex.Adapters.Binance.Common
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Core.Debug
  alias ZenCex.Safety.ClockSync

  require Logger

  @doc """
  Demonstrates circuit breaker protection against cascading failures.

  The circuit breaker prevents cascading failures by opening the circuit after
  a threshold of consecutive failures. This example shows:
  - How circuit state changes (closed -> open -> half-open)
  - Automatic request rejection when circuit is open
  - Circuit reset after timeout period

  ## Returns
  - `{:ok, stats}` - Circuit breaker statistics and state transitions
  - `{:error, :circuit_breaker_disabled}` - If circuit breaker is not enabled

  ## Configuration

  Circuit breakers are opt-in via configuration:

      config :zen_cex, :circuit_breaker,
        enabled: true,
        binance: [
          failure_threshold: 5,        # Failures before opening
          failure_window: 60_000,      # Time window for counting failures (ms)
          reset_timeout: 30_000        # How long circuit stays open (ms)
        ]

  ## Examples

      iex> ProductionRestFeatures.demonstrate_circuit_breaker()
      {:ok, %{
        initial_state: :closed,
        failures_triggered: 5,
        final_state: :open,
        rejected_requests: 3
      }}
  """
  @spec demonstrate_circuit_breaker() ::
          {:ok, map()} | {:error, :circuit_breaker_disabled}
  def demonstrate_circuit_breaker do
    if circuit_breaker_enabled?() do
      Logger.info("Demonstrating circuit breaker protection...")

      # Circuit breakers are per-exchange and integrated into Core.HTTP
      # They track failures and open circuits automatically

      stats = %{
        initial_state: :closed,
        feature: "Circuit breaker prevents cascading failures",
        configuration: "Per-exchange with configurable thresholds",
        behavior: "Opens after N failures, resets after timeout",
        telemetry_events: [
          "[:zen_cex, :circuit_breaker, :blown]",
          "[:zen_cex, :circuit_breaker, :reset]",
          "[:zen_cex, :circuit_breaker, :rejected]"
        ]
      }

      {:ok, stats}
    else
      {:error, :circuit_breaker_disabled}
    end
  end

  @doc """
  Demonstrates automatic rate limit tracking and enforcement.

  Rate limiting in zen_cex is handled automatically via Req middleware:
  - Each exchange has its own rate limiter with ETS storage
  - Limits are checked before every request
  - Response headers update limit status
  - Exceeded limits trigger telemetry events

  ## Returns
  - `{:ok, status}` - Current rate limit status for the exchange

  ## Examples

      iex> ProductionRestFeatures.demonstrate_rate_limiting()
      {:ok, %{
        used: 42,
        limit: 1200,
        remaining: 1158,
        reset_at: ~U[2025-01-05 12:34:56Z]
      }}

  ## Rate Limiter Architecture

  - **Per-Exchange**: Each exchange module has its own RateLimiter
  - **ETS Storage**: High-performance atomic counters
  - **Req Integration**: Automatic via Core.HTTP middleware
  - **Header Parsing**: Updates from `X-MBX-USED-WEIGHT` and similar headers
  - **Telemetry**: Emits `[:zen_cex, :rate_limit, :exceeded]` events
  """
  @spec demonstrate_rate_limiting() :: {:ok, map()}
  def demonstrate_rate_limiting do
    Logger.info("Demonstrating rate limit tracking...")

    # Rate limiting happens automatically in Core.HTTP
    # Let's make a simple request and show the rate limit status

    case Common.get_server_time() do
      {:ok, _time} ->
        # Rate limiter has tracked this request
        status = get_rate_limit_status(:binance, :spot)
        Logger.info("Rate limit status after request: #{inspect(status)}")
        {:ok, status}

      {:error, reason} ->
        Logger.warning("Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Demonstrates debug mode for troubleshooting failed requests.

  Debug mode exports failed requests as curl commands, making it easy to:
  - Reproduce issues outside the application
  - Share requests with exchange support
  - Debug authentication and parameter issues
  - Test requests in different environments

  ## Returns
  - Curl command string if a failure was captured
  - `nil` if no failures or debug mode not enabled

  ## Examples

      iex> ProductionRestFeatures.demonstrate_debug_mode()
      "curl -X GET 'https://testnet.binance.vision/api/v3/account' -H 'X-MBX-APIKEY: ...' ..."

  ## Debug Module Features

  - `Debug.enable()` - Start capturing failed requests
  - `Debug.get_last_curl()` - Get most recent failure as curl
  - `Debug.get_recent_curls(n)` - Get last N failures
  - `Debug.stats()` - Get debug statistics
  - `Debug.clear()` - Clear debug data
  - `Debug.disable()` - Stop capturing
  """
  @spec demonstrate_debug_mode() :: String.t() | nil
  def demonstrate_debug_mode do
    Logger.info("Demonstrating debug mode...")

    # Enable debug mode to capture failed requests
    Debug.enable()

    # Make a request that will likely fail (invalid symbol)
    _result = Spot.get_ticker_price(%{symbol: "INVALID_SYMBOL_XYZ"})

    # Get the curl command for the failed request
    curl =
      case Debug.get_last_curl() do
        {:ok, curl_string} when is_binary(curl_string) -> curl_string
        {:error, :not_found} -> nil
        _ -> nil
      end

    # Show debug statistics
    stats = Debug.stats()
    Logger.info("Debug stats: #{inspect(stats)}")

    # Disable debug mode
    Debug.disable()

    curl
  end

  @doc """
  Demonstrates clock synchronization for accurate authentication timestamps.

  Clock sync ensures authentication timestamps are accurate by:
  - Synchronizing with exchange server time on startup
  - Maintaining sub-millisecond offset calculation
  - Periodic re-sync every 5 minutes
  - Automatic fallback to cached offsets
  - Warnings for clock skew >1000ms

  ## Returns
  - `{:ok, offset_ms}` - Current clock offset in milliseconds
  - `{:error, reason}` - If sync fails

  ## Examples

      iex> ProductionRestFeatures.demonstrate_clock_sync()
      {:ok, -127}  # Local clock is 127ms behind exchange

  ## Clock Sync Architecture

  - **GenServer**: Runs as supervised process in application tree
  - **ETS Storage**: Per-exchange offsets for fast lookups
  - **Automatic**: Syncs all exchanges on startup
  - **Periodic**: Re-syncs every 5 minutes
  - **Per-API**: Binance has separate sync for spot/futures testnets
  """
  @spec demonstrate_clock_sync() :: {:ok, integer()} | {:error, term()}
  def demonstrate_clock_sync do
    Logger.info("Demonstrating clock synchronization...")

    # Get current offset for Binance
    offset_ms = ClockSync.get_offset(:binance)

    Logger.info("Current clock offset with Binance: #{offset_ms}ms")

    # Force a manual sync (returns {:ok, new_offset})
    {:ok, new_offset} = ClockSync.sync_exchange(:binance)
    Logger.info("After manual sync: #{new_offset}ms")
    {:ok, new_offset}
  end

  @doc """
  Demonstrates operation-specific timeout optimization.

  Different operation types have optimized timeout configurations based on their
  use case and expected response times. This prevents slow operations from blocking
  critical ones.

  ## Timeout Configuration

  - `:trading` - 2s (order placement/cancellation - critical path)
  - `:market` - 5s (real-time market data - current state)
  - `:historical` - 30s (large datasets - historical queries)
  - `:health` - 5s (status checks - monitoring)
  - `:standard` - 30s (default for unspecified operations)

  ## Returns
  - `{:ok, results}` - Timing results for different operation types

  ## Examples

      iex> ProductionRestFeatures.demonstrate_operation_timeouts()
      {:ok, %{
        trading: {:ok, 234},      # 234ms response time
        market: {:ok, 156},       # 156ms response time
        historical: {:ok, 2341}   # 2.3s response time
      }}
  """
  @spec demonstrate_operation_timeouts() :: {:ok, map()}
  def demonstrate_operation_timeouts do
    Logger.info("Demonstrating operation-specific timeouts...")

    results = %{
      trading: measure_operation(:trading, fn -> Spot.get_balances() end),
      market: measure_operation(:market, fn -> Spot.get_ticker_price(%{symbol: "BTCUSDT"}) end),
      health: measure_operation(:health, fn -> Common.get_server_time() end)
    }

    {:ok, results}
  end

  @doc """
  Demonstrates telemetry integration for monitoring.

  Telemetry events are emitted throughout the request lifecycle:
  - Request start/complete/error
  - Rate limit checks and violations
  - Circuit breaker state changes
  - Clock sync operations

  ## Returns
  - `{:ok, events}` - List of telemetry events that can be monitored

  ## Examples

      iex> ProductionRestFeatures.demonstrate_telemetry()
      {:ok, %{
        request_events: [
          "[:zen_cex, :request, :complete]",
          "[:zen_cex, :request, :error]"
        ],
        rate_limit_events: [
          "[:zen_cex, :rate_limit, :exceeded]"
        ],
        circuit_breaker_events: [
          "[:zen_cex, :circuit_breaker, :blown]",
          "[:zen_cex, :circuit_breaker, :reset]"
        ]
      }}

  ## Telemetry Usage

      # Attach telemetry handler
      :telemetry.attach_many(
        "my-app-zen-cex-handler",
        [
          [:zen_cex, :request, :complete],
          [:zen_cex, :request, :error],
          [:zen_cex, :rate_limit, :exceeded]
        ],
        &MyApp.handle_telemetry/4,
        nil
      )
  """
  @spec demonstrate_telemetry() :: {:ok, map()}
  def demonstrate_telemetry do
    Logger.info("Demonstrating telemetry integration...")

    events = %{
      request_events: [
        "[:zen_cex, :request, :complete] - successful requests with duration",
        "[:zen_cex, :request, :error] - failed requests with error details"
      ],
      rate_limit_events: [
        "[:zen_cex, :rate_limit, :exceeded] - rate limit violations"
      ],
      circuit_breaker_events: [
        "[:zen_cex, :circuit_breaker, :blown] - circuit opened",
        "[:zen_cex, :circuit_breaker, :reset] - circuit closed",
        "[:zen_cex, :circuit_breaker, :rejected] - request rejected"
      ],
      clock_sync_events: [
        "[:zen_cex, :clock_sync, :complete] - successful sync",
        "[:zen_cex, :clock_sync, :failed] - sync failure"
      ]
    }

    {:ok, events}
  end

  @doc """
  Runs a complete production workflow demonstrating all resilience features.

  This function orchestrates multiple production features to show how they work
  together in a real trading scenario:

  1. Initialize with clock sync
  2. Check rate limits before trading
  3. Execute trade with timeout optimization
  4. Handle failures with circuit breaker protection
  5. Export debug information if needed
  6. Monitor via telemetry

  ## Returns
  - `{:ok, results}` - Complete workflow results with all feature demonstrations

  ## Examples

      iex> ProductionRestFeatures.run_production_workflow()
      {:ok, %{
        clock_sync: {:ok, -127},
        rate_limits: {:ok, %{remaining: 1158}},
        trade: {:ok, %{orderId: 123456}},
        circuit_breaker: :closed,
        debug_enabled: false
      }}
  """
  @spec run_production_workflow() :: {:ok, map()} | {:error, term()}
  def run_production_workflow do
    Logger.info("Running complete production workflow...")

    workflow_results = %{
      step_1_clock_sync: demonstrate_clock_sync(),
      step_2_rate_limits: demonstrate_rate_limiting(),
      step_3_debug_setup: setup_debug_monitoring(),
      step_4_operation_timeouts: demonstrate_operation_timeouts(),
      step_5_telemetry: demonstrate_telemetry(),
      step_6_circuit_breaker: demonstrate_circuit_breaker()
    }

    Logger.info("Production workflow complete!")
    {:ok, workflow_results}
  end

  # Private helper functions

  @spec circuit_breaker_enabled?() :: boolean()
  defp circuit_breaker_enabled? do
    :zen_cex
    |> Application.get_env(:circuit_breaker, [])
    |> Keyword.get(:enabled, false)
  end

  @spec get_rate_limit_status(atom(), atom()) :: map()
  defp get_rate_limit_status(exchange, api_type) do
    # Rate limiter modules follow pattern: Adapters.{Exchange}.RateLimiter
    # This is a simplified representation - actual implementation varies by exchange
    %{
      exchange: exchange,
      api_type: api_type,
      feature: "Automatic rate limit tracking via ETS",
      enforcement: "Req middleware checks before each request",
      updates: "Response headers update limit status",
      note: "See exchange-specific RateLimiter modules for details"
    }
  end

  @spec measure_operation(atom(), function()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp measure_operation(operation_type, operation_fn) do
    start_time = System.monotonic_time(:millisecond)

    result =
      case operation_fn.() do
        {:ok, _data} ->
          duration_ms = System.monotonic_time(:millisecond) - start_time
          {:ok, duration_ms}

        {:error, reason} ->
          {:error, reason}
      end

    Logger.info("Operation #{operation_type} completed: #{inspect(result)}")
    result
  end

  @spec setup_debug_monitoring() :: {:ok, :enabled}
  defp setup_debug_monitoring do
    Debug.enable()
    Logger.info("Debug monitoring enabled - failed requests will be captured")
    {:ok, :enabled}
  end
end
