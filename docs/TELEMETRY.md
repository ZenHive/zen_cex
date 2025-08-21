# Telemetry Guide

ZenCex provides comprehensive telemetry events for monitoring, debugging, and observability. The library leverages Req's built-in telemetry and adds domain-specific events for exchange operations.

## Quick Start

```elixir
# Attach default handlers (logs slow requests, errors, rate limits)
ZenCex.Core.Telemetry.attach_default_handlers()

# Make requests - telemetry events are automatically emitted
{:ok, balances} = ZenCex.request(:binance, :spot_get_balances)
```

## Event Architecture

ZenCex uses a three-tier telemetry architecture:

1. **Finch Events** (Connection layer) - HTTP connection metrics
2. **Req Events** (Request layer) - HTTP request/response metrics  
3. **ZenCex Events** (Application layer) - Exchange-specific metrics

```
┌─────────────────┐
│  ZenCex Events  │ <- Order placement, rate limits, auth
├─────────────────┤
│   Req Events    │ <- HTTP requests, retries
├─────────────────┤
│  Finch Events   │ <- Connection pooling, reuse
└─────────────────┘
```

## ZenCex Events

### Request Events

#### `[:zen_cex, :request, :start]`
Emitted when a request to an exchange starts.

**Measurements:**
- `system_time` - System time when request started

**Metadata:**
- `exchange` - Exchange name (`:binance`, `:kraken`, etc.)
- `operation_type` - Type of operation (`:trading`, `:market`, `:historical`)
- `endpoint` - API endpoint path

#### `[:zen_cex, :request, :complete]`
Emitted when a request completes successfully.

**Measurements:**
- `duration` - Request duration in microseconds
- `count` - Always 1 (for aggregation)

**Metadata:**
- `exchange` - Exchange name
- `operation_type` - Type of operation
- `endpoint` - API endpoint path
- `status` - HTTP status code

#### `[:zen_cex, :request, :error]`
Emitted when a request fails.

**Measurements:**
- `count` - Always 1 (for aggregation)

**Metadata:**
- `exchange` - Exchange name
- `operation_type` - Type of operation
- `endpoint` - API endpoint path
- `error` - Error term

### Rate Limit Events

#### `[:zen_cex, :rate_limit, :exceeded]`
Emitted when rate limit is exceeded.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name
- `endpoint` - API endpoint
- `retry_after_ms` - Milliseconds to wait (optional)

#### `[:zen_cex, :rate_limit, :updated]`
Emitted when rate limit is updated from response headers.

**Measurements:**
- `used` - Rate limit points used
- `limit` - Total rate limit

**Metadata:**
- `exchange` - Exchange name

### Authentication Events

#### `[:zen_cex, :auth, :success]`
Emitted on successful authentication.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name
- `auth_method` - Authentication method (`:hmac`, `:oauth`, etc.)

#### `[:zen_cex, :auth, :failure]`
Emitted on authentication failure.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name
- `auth_method` - Authentication method
- `reason` - Failure reason

### Order Events

#### `[:zen_cex, :order, :placed]`
Emitted when an order is placed.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name
- `order_id` - Order ID
- `side` - Order side (`:buy`, `:sell`)
- `amount` - Order amount (Decimal)

#### `[:zen_cex, :order, :cancelled]`
Emitted when an order is cancelled.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name
- `order_id` - Order ID

#### `[:zen_cex, :order, :idempotency_detected]`
Emitted when duplicate order is detected.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name
- `client_order_id` - Client order ID

### Circuit Breaker Events

#### `[:zen_cex, :circuit_breaker, :blown]`
Emitted when circuit breaker opens.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name

#### `[:zen_cex, :circuit_breaker, :reset]`
Emitted when circuit breaker closes.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name
- `manual` - Boolean indicating manual reset

#### `[:zen_cex, :circuit_breaker, :rejected]`
Emitted when request is rejected by open circuit.

**Measurements:**
- `count` - Always 1

**Metadata:**
- `exchange` - Exchange name

## Req Events (Bridged)

ZenCex bridges Req events for unified monitoring:

#### `[:zen_cex, :req, :bridged]`
Bridged from Req's `[:req, :request, :stop]` event.

**Measurements:**
- `duration` - Request duration in native units

**Metadata:**
- `exchange` - Exchange name
- `status` - HTTP status code
- `method` - HTTP method
- `url` - Request URL

## Finch Events

Finch emits low-level connection events:

- `[:finch, :request, :start/stop/exception]` - Request lifecycle
- `[:finch, :connect, :start]` - New connection opened
- `[:finch, :reused_connection]` - Connection reused
- `[:finch, :recv, :exception]` - Receive error
- `[:finch, :conn_max_idle_time_exceeded]` - Connection expired
- `[:finch, :pool_max_idle_time_exceeded]` - Pool expired

## Example Handlers

### Basic Logger

```elixir
defmodule MyApp.TelemetryLogger do
  require Logger

  def attach do
    events = [
      [:zen_cex, :request, :complete],
      [:zen_cex, :request, :error],
      [:zen_cex, :rate_limit, :exceeded]
    ]

    :telemetry.attach_many(
      "myapp-logger",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event([:zen_cex, :request, :complete], measurements, metadata, _config) do
    duration_ms = div(measurements.duration, 1_000)
    Logger.info("[#{metadata.exchange}] #{metadata.endpoint} completed in #{duration_ms}ms")
  end

  def handle_event([:zen_cex, :request, :error], _measurements, metadata, _config) do
    Logger.error("[#{metadata.exchange}] Request failed: #{inspect(metadata.error)}")
  end

  def handle_event([:zen_cex, :rate_limit, :exceeded], _measurements, metadata, _config) do
    Logger.warning("[#{metadata.exchange}] Rate limit exceeded")
  end
end
```

### Metrics Reporter

```elixir
defmodule MyApp.MetricsReporter do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    attach_handlers()
    {:ok, %{requests: %{}, errors: %{}, rate_limits: %{}}}
  end

  def attach_handlers do
    :telemetry.attach(
      "metrics-requests",
      [:zen_cex, :request, :complete],
      &handle_request/4,
      nil
    )

    :telemetry.attach(
      "metrics-errors",
      [:zen_cex, :request, :error],
      &handle_error/4,
      nil
    )
  end

  def handle_request(_event, measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:request, measurements, metadata})
  end

  def handle_error(_event, _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:error, metadata})
  end

  def handle_cast({:request, measurements, metadata}, state) do
    key = {metadata.exchange, metadata.endpoint}
    
    requests = Map.update(state.requests, key, 
      %{count: 1, total_duration: measurements.duration},
      fn stats -> 
        %{count: stats.count + 1, 
          total_duration: stats.total_duration + measurements.duration}
      end
    )
    
    {:noreply, %{state | requests: requests}}
  end

  def handle_cast({:error, metadata}, state) do
    key = {metadata.exchange, metadata.endpoint}
    errors = Map.update(state.errors, key, 1, &(&1 + 1))
    {:noreply, %{state | errors: errors}}
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def handle_call(:get_stats, _from, state) do
    stats = Enum.map(state.requests, fn {{exchange, endpoint}, data} ->
      avg_duration = div(data.total_duration, data.count * 1_000)
      error_count = get_in(state.errors, [{exchange, endpoint}]) || 0
      
      %{
        exchange: exchange,
        endpoint: endpoint,
        request_count: data.count,
        error_count: error_count,
        avg_duration_ms: avg_duration,
        error_rate: Float.round(error_count / data.count * 100, 2)
      }
    end)
    
    {:reply, stats, state}
  end
end
```

### Circuit Breaker Monitor

```elixir
defmodule MyApp.CircuitBreakerMonitor do
  require Logger

  def attach do
    events = [
      [:zen_cex, :circuit_breaker, :blown],
      [:zen_cex, :circuit_breaker, :reset],
      [:zen_cex, :circuit_breaker, :rejected]
    ]

    :telemetry.attach_many(
      "circuit-monitor",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event([:zen_cex, :circuit_breaker, :blown], _measurements, metadata, _config) do
    Logger.error("⚠️  Circuit breaker OPEN for #{metadata.exchange}")
    # Send alert to monitoring service
    send_alert(:circuit_open, metadata.exchange)
  end

  def handle_event([:zen_cex, :circuit_breaker, :reset], _measurements, metadata, _config) do
    reset_type = if metadata.manual, do: "manually", else: "automatically"
    Logger.info("✅ Circuit breaker closed #{reset_type} for #{metadata.exchange}")
  end

  def handle_event([:zen_cex, :circuit_breaker, :rejected], _measurements, metadata, _config) do
    Logger.warning("Request rejected by circuit breaker for #{metadata.exchange}")
  end

  defp send_alert(type, exchange) do
    # Implement your alerting logic here
    # e.g., send to PagerDuty, Slack, etc.
  end
end
```

## Phoenix LiveDashboard Integration

Add telemetry metrics to your LiveDashboard:

```elixir
defmodule MyAppWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # ZenCex metrics
      summary("zen_cex.request.complete.duration",
        unit: {:native, :millisecond},
        tags: [:exchange, :endpoint]
      ),
      
      counter("zen_cex.request.complete.count",
        tags: [:exchange, :status]
      ),
      
      counter("zen_cex.request.error.count",
        tags: [:exchange]
      ),
      
      counter("zen_cex.rate_limit.exceeded.count",
        tags: [:exchange]
      ),
      
      counter("zen_cex.circuit_breaker.rejected.count",
        tags: [:exchange]
      ),

      # Finch connection metrics
      summary("finch.request.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status]
      ),
      
      counter("finch.reused_connection",
        tags: [:name]
      ),
      
      counter("finch.conn_max_idle_time_exceeded",
        tags: [:name]
      )
    ]
  end

  defp periodic_measurements do
    []
  end
end
```

## Production Monitoring

### Key Metrics to Track

1. **Request Performance**
   - P50, P95, P99 latencies per exchange/endpoint
   - Request rate and throughput
   - Error rates and types

2. **Rate Limiting**
   - Rate limit utilization percentage
   - Rate limit violations per minute
   - Time until rate limit reset

3. **Circuit Breaker**
   - Circuit state transitions
   - Rejection rates
   - Time in open state

4. **Connection Pool**
   - Connection reuse rate
   - Pool saturation
   - Idle timeout occurrences

### Alert Thresholds

```elixir
defmodule MyApp.AlertRules do
  @rules [
    # High error rate
    %{
      metric: "error_rate",
      threshold: 5.0,  # 5% error rate
      window: :rolling_5min,
      severity: :warning
    },
    
    # Circuit breaker open
    %{
      metric: "circuit_breaker_open",
      threshold: 1,
      window: :instant,
      severity: :critical
    },
    
    # High latency
    %{
      metric: "p99_latency_ms",
      threshold: 5000,  # 5 seconds
      window: :rolling_1min,
      severity: :warning
    },
    
    # Rate limit exhaustion
    %{
      metric: "rate_limit_utilization",
      threshold: 90.0,  # 90% utilized
      window: :rolling_1min,
      severity: :info
    }
  ]
end
```

## Custom Handler Example

```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    # Attach telemetry handlers on application start
    MyApp.TelemetryLogger.attach()
    MyApp.CircuitBreakerMonitor.attach()
    
    children = [
      MyApp.MetricsReporter,
      # ... other children
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Performance Considerations

1. **Handler Performance** - Keep handlers fast and non-blocking
2. **Sampling** - For high-volume endpoints, consider sampling
3. **Aggregation** - Aggregate metrics before sending to external services
4. **Async Processing** - Use GenServer or Task for expensive operations

```elixir
# Example: Async metric processing
def handle_event(event, measurements, metadata, config) do
  Task.start(fn ->
    # Expensive operation (e.g., send to external service)
    MetricsService.send(event, measurements, metadata)
  end)
end
```

## Debugging with Telemetry

Enable debug logging for specific exchanges:

```elixir
# Attach debug handler for Binance only
:telemetry.attach(
  "debug-binance",
  [:zen_cex, :request, :complete],
  fn _event, measurements, metadata, _config ->
    if metadata.exchange == :binance do
      IO.inspect({measurements, metadata}, label: "BINANCE REQUEST")
    end
  end,
  nil
)
```

## Testing with Telemetry

```elixir
defmodule MyApp.TelemetryTest do
  use ExUnit.Case

  test "emits telemetry events on successful request" do
    self = self()
    
    :telemetry.attach(
      "test-handler",
      [:zen_cex, :request, :complete],
      fn _event, measurements, metadata, _config ->
        send(self, {:telemetry, measurements, metadata})
      end,
      nil
    )

    # Make request
    {:ok, _} = ZenCex.request(:binance, :spot_get_balances)

    # Assert telemetry was emitted
    assert_receive {:telemetry, measurements, metadata}
    assert measurements.duration > 0
    assert metadata.exchange == :binance
    
    :telemetry.detach("test-handler")
  end
end
```

## See Also

- [Telemetry.Metrics](https://hexdocs.pm/telemetry_metrics) - Metric definitions
- [Phoenix LiveDashboard](https://hexdocs.pm/phoenix_live_dashboard) - Real-time metrics
- [Finch Telemetry](https://hexdocs.pm/finch/Finch.Telemetry.html) - Connection metrics
- [OpenTelemetry](https://opentelemetry.io/docs/instrumentation/erlang/) - Distributed tracing