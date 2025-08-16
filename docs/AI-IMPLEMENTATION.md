# ZenCex AI Implementation Guide

## CRITICAL: One Task Per Session Rule
**NEVER implement multiple modules in one session. Complete ONE task, update progress, then stop.**

## What This Library Does (and Does NOT Do)

### This Library DOES (REST Trading Operations):
- **Order Management**: Place, modify, cancel orders via REST
- **Position Management**: Query positions, balances, margins
- **Account Operations**: Withdrawals, deposits, transfers
- **Risk Management**: Liquidation prices, margin requirements

### This Library does NOT do:
- **No Market Data**: No price feeds, order books, or tick data (use WebSocket library)
- **No Streaming**: REST-only, no WebSocket implementation
- **No HFT**: Focus on reliability over microsecond latency
- **No Market Making**: No order book management or spread calculations

## Quick Start for AI Coders

### Your Current Status
- **Architecture**: Req-powered adapters with built-in pooling, retry, telemetry
- **Progress**: 13% complete (2/15 core tasks done)
- **Next Task**: Remove redundant OTP - Req handles pooling, retry, telemetry
- **Priority**: Proactive clock sync, circuit breakers, dynamic rate limit learning
- **Focus**: Production-ready REST-only patterns for reliable trading operations

### Navigation
1. Check "Current Task" section
2. Implement using "Essential Patterns"
3. Validate with "Success Criteria"
4. Update progress and stop

## Current Task

**Task #2**: Remove redundant OTP supervision - leverage Req's built-in features

**Why**: Req already provides connection pooling (Finch), retry logic, middleware pipeline, and telemetry. We don't need GenServers for what Req handles.

**Success Criteria**:
- [ ] Remove Core.Supervisor entirely
- [ ] Simplify Application to only start Finch
- [ ] Change RateLimiter.start_link to RateLimiter.init_tables
- [ ] Update tests to not expect supervision
- [ ] All existing tests still pass

## Essential Patterns

### Pattern 1: Req Request Step with Error Context (Auth)
```elixir
# MUST return {request, options} tuple with proper error context
def sign_request({request, options} = req_tuple) do
  with {:ok, credentials} <- get_credentials(request),
       {:ok, signed_request} <- apply_signature(request, credentials) do
    {signed_request, options}
  else
    {:error, :missing_credentials} ->
      # Use Req.Request.put_private for internal state
      request = request
      |> Req.Request.halt({:error, :missing_credentials})
      |> Req.Request.put_private(:auth_attempted_at, System.os_time(:millisecond))
      {request, options}
    
    {:error, reason} ->
      {Req.Request.halt(request, {:error, {:signature_failed, reason}}), options}
  end
end
```

### Pattern 2: Rate Limiter with Sliding Window
```elixir
def rate_limit_step({request, options}) do
  exchange = request.private[:exchange]
  weight = calculate_weight(request)

  # Sliding window with microsecond precision
  now = System.os_time(:microsecond)
  window_start = now - :timer.seconds(60)

  # Atomic check and increment
  case check_and_consume_capacity(exchange, weight, window_start) do
    :ok ->
      {request, options}
    {:error, :capacity_exceeded, retry_after} ->
      # Add retry-after header for client awareness
      request = request
      |> Req.Request.halt()
      |> Req.Request.put_private(:retry_after, retry_after)

      {request, Keyword.put(options, :error, {:rate_limited, retry_after})}
  end
end
```

### Pattern 3: Simple ETS Tables (No GenServer)
```elixir
# Just create tables at app startup, no process needed
def init_tables do
  :ets.new(:binance_rate_limits, [:named_table, :public, :set])
end

# Use atomic operations for concurrent access
:ets.update_counter(table, key, {2, increment}, {key, 0, 0})
```

### Pattern 4: Circuit Breaker as Req Middleware
```elixir
# Production pattern for fault tolerance
Req.Request.prepend_request_steps(req,
  circuit_breaker: fn {request, options} ->
    case check_circuit_state(request.url.host) do
      :closed -> {request, options}
      :open ->
        request = Req.Request.halt(request)
        {request, Keyword.put(options, :error, :circuit_open)}
      :half_open ->
        # Allow one request through for testing
        {request, Keyword.put(options, :circuit_test, true)}
    end
  end
)
```

### Pattern 5: Order State Tracking (Trading Operations)
```elixir
# Track order states to prevent duplicate operations
defmodule OrderStateTracker do
  def track_order_operation(client_order_id, operation) do
    key = {client_order_id, operation}
    
    case :ets.insert_new(:order_operations, {key, System.os_time(:millisecond)}) do
      true -> :ok
      false -> 
        [{_, timestamp}] = :ets.lookup(:order_operations, key)
        if System.os_time(:millisecond) - timestamp < 5000 do
          {:error, :duplicate_operation}
        else
          # Old operation, allow retry
          :ets.insert(:order_operations, {key, System.os_time(:millisecond)})
          :ok
        end
    end
  end
  
  def cleanup_old_operations do
    # Clean up operations older than 1 hour
    cutoff = System.os_time(:millisecond) - :timer.hours(1)
    :ets.select_delete(:order_operations, [
      {{{:"$1", :"$2"}, :"$3"}, [{:<, :"$3", cutoff}], [true]}
    ])
  end
end
```

### Pattern 6: Health Check Integration
```elixir
# Monitor exchange connectivity
def health_check_step({request, options}) do
  start_time = System.monotonic_time(:millisecond)

  # Continue with request
  result = {request, options}

  # Record health metrics in response step
  response_step = fn {request, response} ->
    duration = System.monotonic_time(:millisecond) - start_time
    record_health_metric(request.url.host, duration, response.status)
    {request, response}
  end

  options = Keyword.put(options, :response_step, response_step)
  {request, options}
end
```

### Pattern 7: Telemetry Integration
```elixir
# Hook into Req's built-in telemetry
:telemetry.attach_many(
  "zen-cex-monitoring",
  [
    [:req, :request, :start],
    [:req, :request, :stop],
    [:req, :request, :exception],
    [:finch, :recv, :start],
    [:finch, :recv, :stop]
  ],
  &handle_telemetry_event/4,
  nil
)

def handle_telemetry_event([:req, :request, :stop], measurements, metadata, _config) do
  duration = measurements.duration
  exchange = metadata.request.private[:exchange]

  # Record metrics
  :telemetry.execute(
    [:zen_cex, :api, :request],
    %{duration: duration},
    %{exchange: exchange, status: metadata.response.status}
  )
end
```

### Pattern 8: Response Validation (Critical for Trading)
```elixir
# Exchanges often return 200 with error bodies
def validate_response({request, response} = req_resp) do
  case validate_exchange_response(request.private.exchange, response) do
    :ok -> req_resp
    {:error, reason} -> 
      {request, %{response | status: 500, body: %{error: reason}}}
  end
end

defp validate_exchange_response(:binance, %{status: 200, body: %{"code" => code}}) 
  when code < 0, do: {:error, {:binance_error, code}}
defp validate_exchange_response(:kraken, %{status: 200, body: %{"error" => errors}}) 
  when errors != [], do: {:error, {:kraken_errors, errors}}
defp validate_exchange_response(_, _), do: :ok

# Exchange-specific error normalization
def normalize_error(:binance, %{"code" => -2010}), do: {:error, :insufficient_balance}
def normalize_error(:binance, %{"code" => -1021}), do: {:error, :invalid_timestamp}
def normalize_error(:kraken, ["EAPI:Rate limit exceeded"]), do: {:error, :rate_limited}
def normalize_error(:kraken, ["EGeneral:Permission denied"]), do: {:error, :unauthorized}
```

### Pattern 9: Optimized Req Configuration per Exchange
```elixir
def create_req_client(exchange) do
  config = get_exchange_config(exchange)

  Req.new(
    base_url: config.base_url,
    # Smart retry configuration
    retry: [
      delay: &smart_backoff/1,
      max_attempts: 3,
      rescue_errors: [Mint.TransportError, Finch.Error]  # Be specific
    ],
    # Connection configuration with SNI and keepalive
    connect_options: [
      timeout: 10_000,
      protocols: [:http2, :http1],  # Prefer HTTP/2, fallback to HTTP/1
      transport_opts: [
        # SNI for exchanges using CloudFlare
        server_name_indication: String.to_charlist(exchange_hostname(exchange)),
        # Keep alive for persistent connections
        tcp_keepalive: true,
        tcp_keepidle: 30_000,
        tcp_keepintvl: 1_000,
        tcp_keepcnt: 3
      ]
    ],
    # Native caching for market data
    cache: true,
    cache_dir: System.tmp_dir!() <> "/zen_cex_#{exchange}",
    # Automatic compression and decompression
    compress_body: true,
    decode_body: true,
    # Backpressure control
    pool_timeout: 5_000,
    receive_timeout: 30_000,
    # Body size limits
    max_body: 10_485_760  # 10MB limit
  )
  |> Req.Request.register_options([:exchange, :request_priority, :idempotency_key])
  |> attach_middleware(exchange)
  |> attach_telemetry()
  |> Req.Request.prepend_error_steps(
    circuit_recovery: &handle_circuit_recovery/1
  )
end

defp smart_backoff(attempt) do
  base = Integer.pow(2, attempt) * 1000
  jitter = :rand.uniform(base)
  min(base + jitter, 30_000)  # Cap at 30 seconds
end
```

### Pattern 9: Dynamic Rate Limit Learning
```elixir
# Learn actual endpoint weights from response headers
def update_rate_limits_from_response(exchange, response) do
  endpoint = response.private[:endpoint]
  
  case exchange do
    :binance ->
      used = Req.Response.get_header(response, "x-mbx-used-weight-1m")
      limit = Req.Response.get_header(response, "x-mbx-used-weight-limit-1m")
      
      # Learn the actual weight for this endpoint
      if used && endpoint do
        actual_weight = String.to_integer(used)
        learn_endpoint_weight(endpoint, actual_weight)
      end
      
      :ets.insert(:binance_rate_limits, {:current_usage, String.to_integer(used || "0")})
      :ets.insert(:binance_rate_limits, {:current_limit, String.to_integer(limit || "1200")})
    
    :kraken ->
      # Kraken tier can change dynamically
      counter = Req.Response.get_header(response, "api-rate-limit-counter")
      tier = detect_kraken_tier(counter)
      :ets.insert(:kraken_rate_limits, {:tier, tier})
    
    :deribit ->
      remaining = Req.Response.get_header(response, "x-ratelimit-remaining")
      :ets.insert(:deribit_rate_limits, {:remaining, String.to_integer(remaining || "10")})
  end
end

# Track actual vs documented weights
defp learn_endpoint_weight(endpoint, actual_weight) do
  key = {:learned_weight, endpoint}
  :ets.insert(:rate_limit_learning, {key, actual_weight, System.os_time(:second)})
end
```

### Pattern 10: Req.Test for Unit Testing
```elixir
import Req.Test

stub(:binance, fn conn ->
  assert conn.params["signature"]  # Verify auth
  json(conn, %{status: "ok"})
end)
```

### Pattern 11: Idempotency for Order Placement
```elixir
# Critical for safe retries in production
defmodule OrderPlacer do
  def place_order(exchange, params) do
    # Generate idempotency key
    idempotency_key = generate_idempotency_key(params)

    # Check if we've sent this before
    case check_idempotency_cache(idempotency_key) do
      {:ok, previous_result} ->
        {:ok, previous_result}

      :not_found ->
        params = Map.put(params, :client_order_id, idempotency_key)

        case send_order(exchange, params) do
          {:ok, result} ->
            cache_idempotency_result(idempotency_key, result)
            {:ok, result}

          {:error, :timeout} ->
            # On timeout, query order status by client_order_id
            check_order_status(exchange, idempotency_key)

          error ->
            error
        end
    end
  end

  defp generate_idempotency_key(params) do
    # Include timestamp with 5-minute window
    window = div(System.os_time(:second), 300)
    data = {window, params[:symbol], params[:side], params[:quantity], params[:price]}
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)  # Most exchanges limit client_order_id length
  end
end
```

### Pattern 12: Trading Operation Prioritization
```elixir
# All trading operations are critical - prioritize by risk
defmodule TradingPriority do
  @priorities %{
    critical: [:cancel_all_orders, :close_all_positions],  # Emergency
    high: [:cancel_order, :close_position],                # Risk reduction
    normal: [:modify_order, :place_order],                 # Regular trading
    low: [:get_balance, :get_position]                     # Read operations
  }
  
  def check_priority(operation, current_capacity_ratio) do
    priority = get_priority(operation)
    
    case {priority, current_capacity_ratio} do
      {:critical, _} -> :ok  # Always allow emergency operations
      {:high, ratio} when ratio > 0.05 -> :ok
      {:normal, ratio} when ratio > 0.20 -> :ok
      {:low, ratio} when ratio > 0.40 -> :ok
      _ -> {:error, :rate_limited}
    end
  end
  
  defp get_priority(operation) do
    Enum.find_value(@priorities, :normal, fn {level, operations} ->
      if operation in operations, do: level
    end)
  end
end
```

### Pattern 13: Multi-Account API Key Rotation
```elixir
# Distribute load across multiple API keys
defmodule MultiAccountManager do
  def get_credentials(exchange, request_type) do
    accounts = get_exchange_accounts(exchange)

    # Round-robin with health awareness
    account = accounts
    |> Enum.filter(&account_healthy?/1)
    |> Enum.min_by(&get_account_usage(&1, request_type))

    case account do
      nil -> {:error, :no_healthy_accounts}
      acc -> {:ok, acc.api_key, acc.secret}
    end
  end

  defp account_healthy?(account) do
    case :ets.lookup(:account_health, account.id) do
      [{_, :healthy, _}] -> true
      [{_, :degraded, last_check}] ->
        # Retry degraded accounts after 5 minutes
        System.os_time(:second) - last_check > 300
      _ -> false
    end
  end
end
```

### Pattern 14: Per-Endpoint Health Monitoring
```elixir
# Track health at endpoint granularity
defmodule HealthMonitor do
  def record_request(exchange, endpoint, duration, status) do
    key = {exchange, endpoint, div(System.os_time(:second), 60)}

    :ets.update_counter(:health_metrics, key, [
      {2, 1},                          # request count
      {3, duration},                   # total duration
      {4, if(status < 400, do: 1, else: 0)}, # success count
      {5, if(status == 429, do: 1, else: 0)}  # rate limit count
    ], {key, 0, 0, 0, 0})
  end

  def get_endpoint_health(exchange, endpoint) do
    # Last 5 minutes
    keys = for i <- 0..4, do: {exchange, endpoint, div(System.os_time(:second), 60) - i}

    stats = keys
    |> Enum.flat_map(&:ets.lookup(:health_metrics, &1))
    |> Enum.reduce({0, 0, 0, 0}, fn {_, count, duration, success, rate_limited}, acc ->
      {elem(acc, 0) + count,
       elem(acc, 1) + duration,
       elem(acc, 2) + success,
       elem(acc, 3) + rate_limited}
    end)

    case stats do
      {0, _, _, _} -> :no_data
      {count, duration, success, rate_limited} ->
        %{
          avg_latency: div(duration, count),
          success_rate: success / count,
          rate_limit_rate: rate_limited / count,
          requests_per_minute: count / 5
        }
    end
  end
end
```

### Pattern 15: Graceful Shutdown and State Persistence
```elixir
# Critical for production - don't lose learned state
defmodule ZenCex.Application do
  def stop(_state) do
    # Drain in-flight requests
    Logger.info("Draining in-flight requests...")
    Finch.close(ZenCex.Finch)
    
    # Persist learned rate limits
    persist_rate_limit_knowledge()
    
    # Save nonce state for Kraken
    persist_nonce_state()
    
    # Save clock sync offsets
    persist_clock_offsets()
    
    Logger.info("Graceful shutdown complete")
    :ok
  end
  
  defp persist_rate_limit_knowledge do
    learned_weights = :ets.tab2list(:rate_limit_learning)
    File.write!("priv/learned_weights.etf", :erlang.term_to_binary(learned_weights))
  end
  
  defp persist_nonce_state do
    case :ets.lookup(:nonces, :kraken) do
      [{:kraken, nonce}] -> 
        File.write!("priv/kraken_nonce", to_string(nonce))
      _ -> :ok
    end
  end
  
  defp persist_clock_offsets do
    offsets = :ets.match(:clock_sync, {{:"$1", :offset}, :"$2"})
    File.write!("priv/clock_offsets.etf", :erlang.term_to_binary(offsets))
  end
end
```

### Pattern 16: Position Reconciliation (Trading Operations)
```elixir
# Critical for ensuring position state consistency
defmodule PositionReconciliation do
  def reconcile_after_order(exchange, symbol, expected_change) do
    # Get position before and after
    {:ok, position_before} = get_position(exchange, symbol)
    
    # Wait for settlement
    Process.sleep(exchange_settlement_delay(exchange))
    
    {:ok, position_after} = get_position(exchange, symbol)
    
    actual_change = position_after.quantity - position_before.quantity
    
    if abs(actual_change - expected_change) > 0.0001 do
      Logger.error("Position reconciliation failed: expected #{expected_change}, got #{actual_change}")
      :telemetry.execute([:zen_cex, :reconciliation, :mismatch], 
        %{expected: expected_change, actual: actual_change},
        %{exchange: exchange, symbol: symbol})
    end
  end
  
  defp exchange_settlement_delay(:binance), do: 100
  defp exchange_settlement_delay(:kraken), do: 500  # Slower settlement
  defp exchange_settlement_delay(:deribit), do: 200
end
```

### Pattern 17: Pre-Trade Validation
```elixir
defmodule PreTradeValidation do
  def validate_before_order(exchange, order) do
    with :ok <- check_symbol_active?(exchange, order.symbol),
         :ok <- check_balance_sufficient?(exchange, order),
         :ok <- check_margin_available?(exchange, order),
         :ok <- check_position_limits?(exchange, order),
         :ok <- check_order_rate_limit?(exchange),
         :ok <- check_daily_loss_limit?(order) do
      :ok
    else
      {:error, reason} = error ->
        Logger.warning("Pre-trade validation failed: #{inspect(reason)}")
        error
    end
  end
  
  # Validate notional minimum (Binance: price * quantity > minNotional)
  def validate_notional_minimum(:binance, %{price: p, quantity: q, symbol: symbol}) do
    min_notional = get_symbol_filter(symbol, :MIN_NOTIONAL)
    if Decimal.mult(p, q) |> Decimal.compare(min_notional) == :lt do
      {:error, {:below_minimum_notional, min_notional}}
    else
      :ok
    end
  end
end
```

### Pattern 18: Order Lifecycle Management
```elixir
# Each exchange has different order states
defmodule OrderLifecycle do
  @order_states %{
    binance: ~w(NEW PARTIALLY_FILLED FILLED CANCELED REJECTED EXPIRED)a,
    kraken: ~w(pending open closed canceled expired)a,
    deribit: ~w(open filled rejected cancelled untriggered triggered)a
  }

  # Terminal states where no further action needed
  @terminal_states %{
    binance: ~w(FILLED CANCELED REJECTED EXPIRED)a,
    kraken: ~w(closed canceled expired)a,
    deribit: ~w(filled rejected cancelled)a
  }

  def is_terminal_state?(exchange, state) do
    state in @terminal_states[exchange]
  end
  
  # Handle stuck orders
  def monitor_order(exchange, order_id, placed_at) do
    max_duration = max_pending_duration(exchange)
    Process.send_after(self(), {:check_order, order_id}, max_duration)
    
    receive do
      {:check_order, ^order_id} ->
        case get_order_status(exchange, order_id) do
          {:ok, %{state: state}} when state in [:new, :pending] ->
            Logger.warning("Order #{order_id} stuck in #{state} state")
            cancel_order(exchange, order_id)
            {:error, :order_stuck}
          _ -> :ok
        end
    end
  end
  
  defp max_pending_duration(:binance), do: :timer.seconds(30)
  defp max_pending_duration(:kraken), do: :timer.minutes(2)  # Kraken can be slow
  defp max_pending_duration(:deribit), do: :timer.seconds(45)
end
```

### Pattern 19: Partial Fill Handling
```elixir
# Handle partial fills properly
defmodule PartialFillHandler do
  def handle_partial_fill(exchange, order) do
    filled_qty = order.executed_quantity
    remaining_qty = Decimal.sub(order.quantity, filled_qty)
    fill_ratio = Decimal.div(filled_qty, order.quantity)
    
    cond do
      # If mostly filled (>95%), accept it
      Decimal.compare(fill_ratio, "0.95") == :gt ->
        {:ok, :mostly_filled}
      
      # If barely filled (<10%), cancel and replace
      Decimal.compare(fill_ratio, "0.10") == :lt ->
        cancel_order(exchange, order.id)
        place_order(exchange, %{order | quantity: remaining_qty})
      
      # Otherwise wait for more fills
      true ->
        {:ok, :waiting_for_fills}
    end
  end
end
```

### Pattern 20: Proactive Clock Synchronization (Critical for Auth)
```elixir
# Sync on startup and periodically - prevents auth failures
defmodule ClockSync do
  @ntp_servers ~w(time.google.com time.cloudflare.com pool.ntp.org)
  @sync_interval :timer.minutes(5)

  # Call this on application startup
  def init_sync do
    # Proactively sync with all exchanges on startup
    [:binance, :kraken, :deribit]
    |> Enum.each(&sync_with_exchange/1)
    
    # Schedule periodic sync
    Process.send_after(self(), :periodic_sync, @sync_interval)
  end

  def ensure_time_sync(exchange) do
    case :ets.lookup(:clock_sync, {exchange, :last_sync}) do
      [{_, last_sync}] when System.os_time(:second) - last_sync < @sync_interval ->
        :ok  # Recent sync, use cached offset
      
      _ ->
        # Proactively sync with NTP first, fallback to exchange
        sync_with_ntp() || sync_with_exchange(exchange)
    end
  end

  defp sync_with_ntp do
    # Try multiple NTP servers for resilience
    Enum.find_value(@ntp_servers, fn server ->
      case get_ntp_time(server) do
        {:ok, ntp_time} ->
          offset = ntp_time - System.os_time(:millisecond)
          store_offset(:global, offset)
          {:ok, offset}
        _ -> nil
      end
    end)
  end

  defp sync_with_exchange(exchange) do
    case get_server_time(exchange) do
      {:ok, server_time} ->
        local_time = System.os_time(:millisecond)
        offset = server_time - local_time
        
        if abs(offset) > 1000 do
          Logger.warning("Clock skew detected for #{exchange}: #{offset}ms")
        end
        
        store_offset(exchange, offset)
        {:ok, offset}
      
      {:error, reason} ->
        use_cached_offset(exchange, reason)
    end
  end

  # Apply offset when signing requests
  def apply_time_offset(timestamp, exchange) do
    case :ets.lookup(:clock_sync, {exchange, :offset}) do
      [{_, offset}] -> timestamp + offset
      [] -> timestamp
    end
  end
end
```

## Exchange Requirements Table

| Exchange | Auth Method | Critical Requirement | Common Error | Production Gotcha |
|----------|------------|---------------------|-------------|-------------------|
| Binance | HMAC-SHA256 | Signature LAST in params | Wrong param order | Spot vs Futures have different URLs/limits; listenKey expires 60m (not 30m); OCO orders = 2x weight |
| Kraken | Nonce + HMAC | Microsecond + counter; Base64 secret | Using only microseconds | "EOrder:Insufficient funds" can occur AFTER acceptance; Edit = cancel+new; "Busy" errors need backoff |
| Deribit | OAuth2 | Refresh 120s before expiry | Token expiration | Mark price lags during volatility; Weekly test reset Sunday 08:00 UTC; Portfolio margin different endpoints |
| Bybit | HMAC-SHA256 | timestamp within 5s; Different base URLs | Clock skew | api.bybit.com (spot) vs api-testnet.bybit.com (derivatives); Different signatures per product |
| OKX | HMAC + Passphrase | passphrase required in headers | Missing passphrase | Demo trading affects production rate limits; Requires OK-ACCESS-PASSPHRASE header |
| Coinbase | JWT | JWT token with RS256 | HMAC instead of JWT | Completely different auth than other exchanges; Uses JWT not HMAC |

### Critical Exchange Quirks (Trading Operations)

**Binance:**
- **CRITICAL**: Spot (api.binance.com) vs Futures (fapi.binance.com) have completely different rate limits
- IP weight limits differ from UID (user) limits - track both separately
- Weight system: simple requests = 1, complex = 5-50, OCO orders consume 2x weight when partially filled
- Order rate limits separate from request rate limits (can be rate limited on orders but not requests)
- `recvWindow` default 5000ms, max 60000ms for timestamp validation
- Clock synchronization critical (±1000ms tolerance)
- Test orders (`test=true`) still consume rate limit weight
- Order Response Type (ACK, RESULT, FULL) affects rate limit weight
- `/sapi/*` endpoints have separate rate limits from `/api/*`
- Notional value (price * quantity) must exceed minimum for each pair

**Kraken:**
- **CRITICAL**: "EOrder:Insufficient funds" can occur AFTER order acceptance due to async margin check
- Nonce must be STRICTLY increasing (no duplicates ever) - persist across restarts
- Rate limit tiers: Starter (15/sec), Intermediate (20/sec), Pro (20/sec + higher burst)
- "EGeneral:Busy" errors require exponential backoff - NOT counted as rate limit
- Ledger exports are async - returns job ID, must poll for completion
- Different decimal precision per pair (XBTUSD: 1, ADAUSD: 5) - cache per pair
- Edit orders count as cancel + new for rate limiting purposes
- Some endpoints return CSV format (trades export) - need special parsing
- All private endpoints use POST with `application/x-www-form-urlencoded`
- API secret can be base64-encoded or raw (handle both)
- Some pairs use inverted pricing (XXBTZUSD vs XBTUSD)
- Withdrawals require 2FA token in API call (not just API key)

**Deribit:**
- **CRITICAL**: Mark price updates can lag during high volatility - causes incorrect liquidation calculations
- Test environment: test.deribit.com (completely separate, resets positions weekly Sunday 08:00 UTC)
- OAuth tokens work across REST - single token for all operations
- Portfolio margin vs standard margin use different endpoints and calculations entirely
- Options assignment happens daily at 08:00 UTC, API unavailable for ~1 minute
- Index price != mark price (critical for liquidation calculations)
- Matching engine rate limits separate from API rate limits
- JSON-RPC style API even for REST endpoints (wrap all calls)
- Single-flight protection critical for OAuth token refresh
- "maintenance" field in ticker response can halt trading without warning
- Combo orders (multi-leg) have different margin requirements than individual legs

### Exchange-Specific Authentication Patterns
```elixir
# OKX requires passphrase beyond standard HMAC
def sign_okx_request({request, options}) do
  with {:ok, api_key} <- fetch_credentials(:okx_api_key),
       {:ok, secret} <- fetch_credentials(:okx_api_secret),
       {:ok, passphrase} <- fetch_credentials(:okx_passphrase) do
    
    timestamp = System.os_time(:second) |> to_string()
    method = to_string(request.method) |> String.upcase()
    path = request.url.path <> format_query_string(request.options[:params])
    body = request.body || ""
    
    # OKX signature: timestamp + method + path + body
    prehash = timestamp <> method <> path <> body
    signature = :crypto.mac(:hmac, :sha256, secret, prehash) |> Base.encode64()
    
    request = request
    |> Req.Request.put_header("ok-access-key", api_key)
    |> Req.Request.put_header("ok-access-sign", signature)
    |> Req.Request.put_header("ok-access-timestamp", timestamp)
    |> Req.Request.put_header("ok-access-passphrase", passphrase)  # CRITICAL
    
    {request, options}
  else
    error -> {Req.Request.halt(request, error), options}
  end
end

# Kraken requires careful secret handling
def normalize_kraken_secret(secret) do
  case Base.decode64(secret) do
    {:ok, decoded} -> decoded  # Already base64, use decoded bytes
    :error -> secret  # Raw bytes, use as-is
  end
end

# Bybit requires different base URLs
def get_bybit_base_url(:spot), do: "https://api.bybit.com"
def get_bybit_base_url(:derivatives), do: "https://api-testnet.bybit.com"
def get_bybit_base_url(:options), do: "https://api.bybit.com"  # Same as spot
```

### Finch Pool Configuration
```elixir
# Optimal pool configuration per exchange characteristics
defp pool_config do
  %{
    # Binance: High volume, supports HTTP/2
    {:https, "api.binance.com", 443} => [
      size: 50,                # Concurrent connections
      count: 2,                # Number of pools (load balancing)
      protocol: :http2,        # Use HTTP/2 if supported
      conn_opts: [
        transport_opts: [
          timeout: 30_000,
          # TCP keepalive for persistent connections
          tcp_keepalive: [
            tcp_keepidle: :timer.seconds(60),
            tcp_keepintvl: :timer.seconds(30),
            tcp_keepcnt: 3
          ]
        ]
      ]
    ],

    # Kraken: More conservative, HTTP/1.1
    {:https, "api.kraken.com", 443} => [
      size: 30,
      count: 1,
      protocol: :http1,       # Kraken doesn't support HTTP/2 well
      conn_opts: [
        transport_opts: [timeout: 60_000]  # Kraken can be slow
      ]
    ],

    # Deribit: OAuth-based, moderate volume
    {:https, "www.deribit.com", 443} => [
      size: 20,
      count: 1,
      protocol: :http2,
      conn_opts: [
        transport_opts: [timeout: 30_000]
      ]
    ]
  }
end
```

## Task Implementation Sequence (REST-Optimized: 15 Tasks)

### Phase 1: Core Foundation (4 tasks)
```bash
[✅] Task 1: Core.Registry - Adapter registration and validation
[🔄] Task 2: Remove Core.Supervisor - Use Req's built-in features  # <- CURRENT
[ ] Task 3: Proactive clock sync with NTP (critical for auth)
[ ] Task 4: Basic telemetry hooks with Req events
```

### Phase 2: Binance Reference Implementation (3 tasks)
```bash
[ ] Task 5: Core.HTTP with Req patterns and middleware
[ ] Task 6: Binance complete adapter (Auth, RateLimiter, Parser)
[ ] Task 7: Integration tests with real API + fixture capture
```

### Phase 3: Production Essentials (4 tasks)
```bash
[ ] Task 8: Circuit breaker as Req error step
[ ] Task 9: Idempotency for order operations
[ ] Task 10: Dynamic rate limit learning from headers
[ ] Task 11: Health monitoring with per-endpoint tracking
```

### Phase 4: Additional Exchanges (4 tasks)
```bash
[ ] Task 12: Kraken adapter (nonce management, CSV parsing)
[ ] Task 13: Deribit OAuth adapter (token refresh, JSON-RPC)
[ ] Task 14: Multi-account rotation for resilience
[ ] Task 15: Production runbook and troubleshooting guide
```

## Common AI Coder Mistakes

### Mistake 1: Manual Request Manipulation
**Wrong**: `request = %{request | headers: [...]}`
**Right**: `Req.Request.put_header(request, key, value)`
**Why**: Use Req functions for proper pipeline integration

### Mistake 2: GenServer State for Counters
**Wrong**: `{:reply, count + 1, %{state | count: count + 1}}`
**Right**: `:ets.update_counter(:table, :key, 1)`
**Why**: Atomic operations prevent bottlenecks

### Mistake 3: Creating Mocks Without Real API Testing
**Wrong**: Writing Req.Test stubs based on API documentation
**Right**: Test real API first, capture responses, then create mocks
**Why**: Docs lie; real APIs have quirks, headers, edge cases

### Mistake 4: Testing Rate Limits Against Real API
**Wrong**: `Enum.each(1..1000, fn _ -> Req.get!(url) end)`
**Right**: Manipulate ETS tables: `:ets.insert(:table, {:weight, 1199})`
**Why**: Test the logic, not the API's patience

### Mistake 5: Implementing Everything at Once
**Wrong**: Creating all modules in one session
**Right**: One module per session with tests
**Why**: Incremental progress ensures quality

### Mistake 6: Testing Market Data Fetching via REST
**Wrong**: Fetching price feeds, order books via REST
**Right**: Trading operations only - use WebSocket library for market data
**Why**: This library is for trading operations, not market data

### Mistake 7: Missing Circuit Breaker Protection
**Wrong**: Continuing to hammer failing endpoints
**Right**: Implement circuit breaker with exponential backoff
**Why**: Failed exchanges can cascade failures

### Mistake 8: Request Coalescing for Trading Operations
**Wrong**: Coalescing order operations or trade requests
**Right**: Only coalesce read operations (balances, positions)
**Why**: Every trade operation must be independent

### Mistake 9: Ignoring Clock Synchronization
**Wrong**: Assuming local time matches exchange time
**Right**: Check and adjust for clock skew per exchange
**Why**: Many exchanges reject requests with >1s time difference

### Mistake 10: Not Using Req's Telemetry
**Wrong**: Custom logging and metrics throughout code
**Right**: Hook into [:req, :request, :*] events
**Why**: Req already emits comprehensive telemetry

### Mistake 11: Hardcoding Connection Pool Sizes
**Wrong**: Same pool configuration for all exchanges
**Right**: Tune pools based on exchange characteristics
**Why**: Binance handles 50+ concurrent, Kraken prefers fewer

### Mistake 12: No Idempotency for Orders
**Wrong**: Retrying order placement without client_order_id
**Right**: Generate deterministic client_order_id for safe retries
**Why**: Network timeout + retry = potential duplicate orders

### Mistake 13: Ignoring Partial Fills
**Wrong**: Assuming orders are fully filled or cancelled
**Right**: Track fill quantity and handle partial execution
**Why**: Large orders often partially fill in volatile markets

### Mistake 14: Static Rate Limit Assumptions
**Wrong**: Hardcoding rate limits from documentation
**Right**: Read actual limits from response headers dynamically
**Why**: Exchanges adjust limits based on tier/load/time

### Mistake 15: Ignoring Req's Built-in Features
**Wrong**: Implementing custom retry, caching, compression
**Right**: Use `retry: :safe_transient`, `compress_body: true`
**Why**: Req already handles these optimally

### Mistake 16: Missing Exchange-Specific Requirements
**Wrong**: Assuming all exchanges use same auth pattern
**Right**: Handle OKX passphrase, Bybit URL split, Kraken POST-only
**Why**: Each exchange has unique quirks that break auth

### Mistake 17: Missing Graceful Shutdown
**Wrong**: Letting supervisor terminate processes immediately
**Right**: Implement `terminate/2` to drain requests and persist state
**Why**: In-flight requests fail and learned rate limits are lost

### Mistake 18: Testing Rate Limits Against Real API
**Wrong**: `Enum.each(1..1000, fn _ -> make_request() end)`
**Right**: Manipulate ETS tables to simulate rate limit scenarios
**Why**: Gets you banned and wastes time

### Mistake 19: Not Learning Actual Endpoint Weights
**Wrong**: Using documented weights from API docs
**Right**: Track actual weights from response headers
**Why**: Documentation often wrong or outdated

### Mistake 20: Reactive Clock Sync Only
**Wrong**: Syncing time only after auth failures
**Right**: Proactive sync on startup and every 5 minutes
**Why**: Prevents auth failures instead of reacting to them

## Troubleshooting Guide

### Common Production Errors

#### Error: Rate Limited (429)
**Symptoms**: `{:error, :rate_limited}` or HTTP 429 responses
**Diagnosis**:
```elixir
# Check current rate limit usage
:ets.tab2list(:binance_rate_limits)
# Look for: {:weight, current_usage}
```
**Solutions**:
- Reduce request frequency
- Check if multiple processes using same API key
- Verify rate limit calculations are correct
- Implement exponential backoff

#### Error: Authentication Failed (401)
**Symptoms**: `{:error, :unauthorized}` or signature validation errors
**Diagnosis**:
```elixir
# Verify signature generation
signature = Binance.Auth.sign_request(params, secret)
# Check parameter order (signature must be LAST for Binance)
```
**Solutions**:
- Verify API key and secret are correct
- Check system clock synchronization (±5 seconds)
- Ensure signature is generated with correct parameter order
- Validate recvWindow parameter

#### Error: Circuit Breaker Open
**Symptoms**: `{:error, :circuit_open}` without attempting request
**Diagnosis**:
```elixir
# Check circuit breaker state
:ets.lookup(:circuit_breakers, "api.binance.com")
# Look for: {host, :open, failure_count, last_failure_time}
```
**Solutions**:
- Wait for circuit breaker reset time
- Check if external issue resolved
- Manually reset circuit if needed: `reset_circuit_breaker(host)`

#### Error: Connection Timeout
**Symptoms**: Slow responses or timeout errors
**Diagnosis**:
```elixir
# Check connection pool status
:sys.get_state(ZenCex.Finch)
# Monitor pool utilization and queue sizes
```
**Solutions**:
- Increase connection pool size
- Check network connectivity to exchange
- Verify firewall settings
- Monitor DNS resolution

### Trading-Specific Production Issues

#### Issue: Order Stuck in NEW State
**Symptoms**: Order remains in NEW/PENDING state beyond normal time
**Root Cause**: Exchange matching engine delays or connectivity issues
**Solution**:
```elixir
# Monitor orders with timeouts
Process.send_after(self(), {:check_order, order_id}, :timer.seconds(30))
# Cancel and retry if stuck
```

#### Issue: Position Drift After Partial Fills
**Symptoms**: Local position state doesn't match exchange
**Root Cause**: Partial fills not properly tracked
**Solution**:
```elixir
# Always reconcile after orders
reconcile_position(exchange, symbol, expected_change)
# Alert on mismatches > 0.0001
```

#### Issue: Double Order Execution on Timeout
**Symptoms**: Order times out but actually executes
**Root Cause**: Network timeout shorter than exchange processing
**Solution**:
```elixir
# Always check order status after timeout
case place_order_with_timeout(params, timeout: 5_000) do
  {:error, :timeout} ->
    # Order might have succeeded - check by client_order_id
    check_order_status(params.client_order_id)
end
```

### Common Production Failures (Not in Exchange Docs)

#### Issue: Order Rejected After Timeout
**Symptoms**: Timeout on order placement, but order actually executed
**Root Cause**: Network timeout shorter than exchange processing time
**Solution**:
```elixir
# Always check order status after timeout
case place_order_with_timeout(params, timeout: 5_000) do
  {:error, :timeout} ->
    # Order might have succeeded - check by client_order_id
    check_order_status(params.client_order_id)
  result ->
    result
end
```

#### Issue: Nonce Already Used (Kraken)
**Symptoms**: "Invalid nonce" errors after restart
**Root Cause**: Nonce must always increase, even across restarts
**Solution**:
```elixir
# Persist last nonce and add buffer on startup
def init_nonce do
  last_nonce = read_persisted_nonce()
  buffer = 1000  # Safety buffer
  :ets.insert(:nonces, {:kraken, last_nonce + buffer})
end
```

#### Issue: Decimal Precision Errors
**Symptoms**: Orders rejected for invalid quantity/price
**Root Cause**: Each trading pair has specific decimal requirements
**Solution**:
```elixir
# Cache and apply pair-specific precision
def format_quantity(pair, quantity) do
  precision = get_pair_precision(pair, :quantity)
  Decimal.round(quantity, precision, :down)  # Always round down for quantities
end
```

#### Issue: IP Whitelist Changes
**Symptoms**: Sudden authentication failures in production
**Root Cause**: Cloud provider IP rotation or failover
**Solution**: Use API key restrictions by API permissions, not IP whitelist

#### Issue: Exchange Maintenance Without Notice
**Symptoms**: Sudden spike in timeouts or 503 errors
**Root Cause**: Unannounced exchange maintenance
**Solution**:
```elixir
# Monitor maintenance field in responses
def check_maintenance(response) do
  case response.body["maintenance"] do
    true -> {:error, :exchange_maintenance}
    _ -> :ok
  end
end
```

#### Issue: Decimal Truncation Causing Rejections
**Symptoms**: Orders rejected for "invalid quantity" despite seeming correct
**Root Cause**: Different precision requirements per trading pair
**Solution**:
```elixir
# Cache precision per pair and always round DOWN for quantities
def format_for_pair(pair, quantity, price) do
  %{qty_precision: qp, price_precision: pp} = get_pair_info(pair)
  qty = Decimal.round(quantity, qp, :down)  # Always round down
  price = Decimal.round(price, pp, :half_up)  # Normal rounding for price
  {qty, price}
end
```

#### Issue: Rate Limit Death Spiral
**Symptoms**: Once rate limited, keeps getting worse
**Root Cause**: Retries consuming more rate limit capacity
**Solution**: Implement backpressure and request prioritization (Pattern 12)

### Health Check Monitoring

#### Setting Up Health Checks
```elixir
# Check exchange connectivity
def health_status do
  exchanges = [:binance, :kraken, :deribit]

  results = Enum.map(exchanges, fn exchange ->
    case test_connectivity(exchange) do
      {:ok, latency} -> {exchange, :healthy, latency}
      {:error, reason} -> {exchange, :unhealthy, reason}
    end
  end)

  healthy_count = Enum.count(results, fn {_, status, _} -> status == :healthy end)
  {healthy_count, length(exchanges), results}
end
```

#### Health Metrics to Track
- Response time percentiles (p50, p95, p99)
- Error rates by exchange and endpoint
- Circuit breaker state changes
- Rate limit utilization
- Connection pool statistics

## Production Readiness Checklist

### Configuration
- [ ] Environment variables configured for all exchanges
- [ ] Rate limits properly calibrated per exchange
- [ ] Connection pool sizes optimized
- [ ] Circuit breaker thresholds set
- [ ] Health check intervals configured

### Monitoring
- [ ] Telemetry events captured
- [ ] Error tracking implemented
- [ ] Performance metrics collected
- [ ] Alerting rules defined
- [ ] Dashboard created for operational visibility

### Error Handling
- [ ] All error cases tested
- [ ] Circuit breaker tested under load
- [ ] Rate limit recovery verified
- [ ] Authentication failure handling
- [ ] Network timeout handling

### Performance
- [ ] Load testing completed
- [ ] Memory usage under sustained load verified
- [ ] Rate limiter performance validated
- [ ] Connection pool sizing optimized
- [ ] Request coalescing effectiveness measured

### Security
- [ ] API keys stored securely in environment variables
- [ ] No credentials in logs or error messages
- [ ] TLS certificate validation enabled
- [ ] Request signing verified with test mode
- [ ] Rate limiting protects against abuse
- [ ] Idempotency keys prevent duplicate orders
- [ ] Multi-account rotation for resilience
- [ ] Clock sync prevents auth failures

## Validation Checklist

### Before Marking Task Complete
```elixir
# Run these commands:
mix test path/to/test.exs        # Unit tests pass
mix dialyzer                      # No type errors
mix credo --strict               # Code quality
mix test --cover                 # >80% coverage
```

### Memory & Performance Targets (Trading Operations)
- **Order placement latency**: <500ms p99 (reliability over speed)
- **Order cancellation latency**: <200ms p99 (cancels must be fast)
- **Position query latency**: <1000ms p95 (reads can be slower)
- **Rate limit check**: <100μs (must be instant)
- **Idempotency check**: <50μs (critical for safety)
- **Concurrent orders per exchange**: 20 max (don't spam orders)
- **Connection pool**: 10-30 per exchange (optimal for trading)
- **Circuit breaker decision**: <10μs (must be instant)
- **Memory growth**: <10MB under sustained load
- **ETS cleanup**: Every 60 seconds for sliding windows
- **Clock sync**: Proactive NTP + exchange sync every 5 min
- **OAuth refresh**: 120 seconds before expiry (Deribit)
- **Idempotency window**: 5 minutes for order operations
- **Graceful shutdown**: Max 30 seconds to drain requests
- **Nonce persistence**: Required for Kraken continuity
- **Order state tracking**: 1 hour retention
- **Position reconciliation**: Within 100ms of settlement

## Architecture: Leveraging Req's Built-in Capabilities

### Why We Don't Need OTP Supervision
- **Connection Pooling**: Req uses Finch - no custom pool supervision needed
- **Retry & Circuit Breaking**: Req has built-in retry with exponential backoff
- **Middleware Pipeline**: Req's steps handle auth, rate limiting, telemetry
- **Observability**: Req emits comprehensive telemetry events automatically

### What Actually Needs GenServers (Trading Operations)
- **Deribit.Auth** - OAuth token state management with single-flight refresh
- **That's it!** Everything else uses Req features or ETS atomic operations
- **NO coalescing for trading** - Every order/trade must be independent

### What Req Handles For Us
- **Connection pooling** - Finch integration with HTTP/2 support
- **Retry logic** - `:safe_transient` handles 429, 5xx, timeouts automatically
- **Compression** - Automatic gzip/deflate/br with `compress_body: true`
- **Caching** - Native caching with `cache: true` and custom keys
- **Telemetry** - Built-in `[:req, :request, :*]` events
- **Backpressure** - Pool and receive timeouts prevent overload
- **Error steps** - `prepend_error_steps/2` for circuit breaker recovery
- **Response parsing** - Automatic JSON with `decode_body: true`

### Application Supervisor
```elixir
def start(_type, _args) do
  # Initialize ETS tables for rate limiting and caching
  init_ets_tables()

  # Exchange-specific connection pools
  pools = %{
    "api.binance.com" => [size: 50, count: 2, protocol: :http2],
    "api.kraken.com" => [size: 30, count: 1, protocol: :http1],
    "www.deribit.com" => [size: 20, count: 1, protocol: :http2],
    "test.deribit.com" => [size: 10, count: 1, protocol: :http2]
  }

  children = [
    # Finch provides connection pooling for Req
    {Finch, name: ZenCex.Finch, pools: pools},
    # Telemetry reporter for metrics
    {Telemetry.Metrics.ConsoleReporter, metrics: metrics()},
    # Only Deribit OAuth needs state (when using Deribit)
    # {ZenCex.Adapters.Deribit.Auth, []}
  ]

  # Attach telemetry handlers
  attach_telemetry_handlers()

  # Minimal supervision - Req handles the complexity
  Supervisor.start_link(children, strategy: :one_for_one)
end

defp init_ets_tables do
  # Rate limiting tables per exchange
  :ets.new(:binance_rate_limits, [:named_table, :public, :set, {:write_concurrency, true}])
  :ets.new(:kraken_rate_limits, [:named_table, :public, :set, {:write_concurrency, true}])
  :ets.new(:deribit_rate_limits, [:named_table, :public, :set, {:write_concurrency, true}])

  # Request coalescing cache
  :ets.new(:request_cache, [:named_table, :public, :set])

  # Circuit breaker states
  :ets.new(:circuit_breakers, [:named_table, :public, :set])

  # Clock synchronization offsets
  :ets.new(:clock_sync, [:named_table, :public, :set])
end
```

## File Creation Template

```elixir
defmodule ZenCex.Adapters.Exchange.Module do
  @moduledoc """
  One-line description.
  """

  @behaviour ZenCex.Behaviors.Something

  # For stateless modules (most cases)
  def init_tables do
    :ets.new(:table_name, [:named_table, :public, :set])
  end

  # Public API (5-10 functions max)
  @impl true
  def callback_function(args) do
    # Implementation
  end

  # Private functions last
  defp helper_function(args), do: :ok
end
```

## CRITICAL: Testing Philosophy

**[!] ALWAYS TEST AGAINST REAL APIs FIRST [!]**
```
1. Write integration tests against REAL exchange APIs (sparse, strategic)
2. Verify actual behavior before creating any mocks
3. Create Req.Test stubs based on captured real responses
4. Keep minimal integration tests to validate mock accuracy
```

**Smart Testing Strategy:**
- **Integration tests**: 1-2 real API calls per endpoint (capture responses)
- **Unit tests**: Fast, comprehensive using verified mocks
- **Rate limit tests**: Use ETS table manipulation, not real API hammering
- **Error tests**: Req.Test to simulate timeouts, 429s, 503s

## Test File Template (Trading Operations)

```elixir
defmodule ZenCex.Adapters.Binance.OrderTest do
  use ExUnit.Case, async: true
  import Req.Test

  # ONE strategic integration test per trading operation
  @tag :integration
  @tag :requires_api_key
  @tag :skip  # Run manually: mix test --include integration
  test "verify order placement and cancellation flow" do
    # Use minimum possible size to avoid real fills
    min_order = %{
      symbol: "BTCUSDT",
      side: :buy,
      type: :limit,
      quantity: "0.001",  # Minimum for BTC
      price: "10000",     # Far from market to avoid fill
      client_order_id: "test_#{System.unique_integer()}"
    }

    # Place order
    assert {:ok, %{order_id: order_id}} = Binance.place_order(min_order)

    # Immediately cancel to avoid fill
    assert {:ok, _} = Binance.cancel_order(order_id)

    # Verify it was cancelled
    assert {:ok, %{status: "CANCELED"}} = Binance.get_order(order_id)
  end

  # FAST unit tests using ETS manipulation
  describe "rate limiting logic" do
    setup do
      # Initialize ETS table for tests
      Binance.RateLimiter.init_tables()

      # Mock Req to return saved headers
      stub(:binance, fn conn ->
        conn
        |> put_resp_header("x-mbx-used-weight-1m", "50")
        |> json(%{serverTime: System.os_time(:millisecond)})
      end)
    end

    test "allows requests under limit" do
      # Manually set ETS counter
      :ets.insert(:binance_rate_limits, {:weight, 500})

      assert {:ok, _} = Binance.HTTP.get("/api/v3/time")
    end

    test "blocks requests over limit" do
      # Fill the bucket manually - NO REAL API CALLS
      :ets.insert(:binance_rate_limits, {:weight, 1199})

      assert {:error, :rate_limited} = Binance.HTTP.get("/api/v3/time")
    end

    test "sliding window cleanup" do
      # Insert old entries
      now = System.os_time(:millisecond)
      :ets.insert(:binance_rate_limits, {{:window, now - 61_000}, 100})

      # Trigger cleanup
      Binance.RateLimiter.cleanup_old_entries()

      # Verify old entries removed
      assert [] = :ets.lookup(:binance_rate_limits, {:window, now - 61_000})
    end
  end

  # Test error scenarios with Req.Test
  describe "error handling" do
    test "handles 429 Too Many Requests" do
      stub(:binance, fn conn ->
        conn
        |> put_status(429)
        |> json(%{code: -1003, msg: "Too many requests"})
      end)

      assert {:error, :rate_limited} = Binance.HTTP.get("/api/v3/time")
    end
  end
end
```

## Environment Setup

```bash
# Required for tests
export BINANCE_API_KEY="test_key"
export BINANCE_API_SECRET="test_secret"
export TEST_MODE="true"  # Uses Req.Test stubs
```

## Production Deployment Patterns

### Multi-Tier Rate Limiting
```elixir
defmodule ZenCex.RateLimiter do
  @windows [
    {:second, 1_000},
    {:minute, 60_000},
    {:hour, 3_600_000}
  ]

  def check_limits(exchange, endpoint, weight) do
    limits = get_limits(exchange, endpoint)
    now = System.os_time(:millisecond)

    Enum.all?(@windows, fn {window, duration} ->
      window_start = now - duration
      current = get_usage(exchange, window, window_start)
      current + weight <= limits[window]
    end)
  end

  defp get_usage(exchange, window, start_time) do
    # Sum weights in sliding window
    table = :"#{exchange}_rate_limits"
    :ets.select(table, [
      {{{:request, :"$1"}, :"$2"},
       [{:>, :"$1", start_time}],
       [:"$2"]}
    ])
    |> Enum.sum()
  end
end
```

### Connection Manager Pattern
```elixir
defmodule ZenCex.ConnectionManager do
  def create_client(exchange) do
    config = get_exchange_config(exchange)

    Req.new()
    |> attach_base_config(config)
    |> attach_middleware(exchange)
    |> attach_telemetry()
    |> attach_circuit_breaker()
  end

  defp attach_middleware(req, exchange) do
    req
    |> Req.Request.prepend_request_steps(
      clock_sync: &ensure_time_sync/1,
      auth: get_auth_module(exchange),
      rate_limit: get_rate_limiter(exchange),
      validate: &validate_request/1
    )
    |> Req.Request.append_response_steps(
      parse: get_parser(exchange),
      record_metrics: &record_metrics/1,
      check_health: &update_health_status/1
    )
  end

  defp attach_telemetry(req) do
    Req.Request.register_options(req, [
      :exchange,
      :endpoint_weight,
      :request_id
    ])
  end
end
```

### Production Monitoring Setup
```elixir
defmodule ZenCex.Telemetry do
  def metrics do
    [
      # Request metrics
      counter("zen_cex.request.count", tags: [:exchange, :status]),
      summary("zen_cex.request.duration", tags: [:exchange, :endpoint]),

      # Rate limit metrics
      gauge("zen_cex.rate_limit.usage", tags: [:exchange, :window]),
      counter("zen_cex.rate_limit.rejected", tags: [:exchange]),

      # Circuit breaker metrics
      counter("zen_cex.circuit_breaker.opened", tags: [:exchange]),
      gauge("zen_cex.circuit_breaker.state", tags: [:exchange]),

      # Health metrics
      gauge("zen_cex.health.latency", tags: [:exchange]),
      gauge("zen_cex.health.success_rate", tags: [:exchange]),

      # Connection pool metrics
      gauge("zen_cex.pool.size", tags: [:exchange]),
      gauge("zen_cex.pool.queue_length", tags: [:exchange])
    ]
  end

  def attach_handlers do
    :telemetry.attach_many(
      "zen-cex-req",
      [
        [:req, :request, :start],
        [:req, :request, :stop],
        [:req, :request, :exception],
        [:finch, :queue, :start],
        [:finch, :queue, :stop],
        [:finch, :connect, :start],
        [:finch, :connect, :stop]
      ],
      &handle_event/4,
      nil
    )
  end
end
```

## After Completing Current Task

1. Run validation checklist
2. Update this file's "Current Task" section
3. Mark task complete in sequence
4. Report: "Task N complete. Next: Task N+1"
5. **STOP** - Do not continue

## Key Production Improvements Summary

### Critical Additions from Review
1. **Proactive Clock Sync**: Sync on startup, not just on failure
2. **Rate Limit Learning**: Track actual vs documented weights
3. **Graceful Shutdown**: Persist learned state (Pattern 15)
4. **Exchange Quirks**: Detailed production gotchas per exchange
5. **Partial Fill Handling**: Essential for large orders
6. **Decimal Precision Cache**: Per-pair requirements
7. **Maintenance Detection**: Monitor for unannounced downtime

### REST-Only Optimizations
- Reduced from 25 to 15 focused tasks
- Relaxed performance targets (100-500 concurrent requests)
- Simplified request prioritization (high/normal/low)
- Market data coalescing only (not for orders)
- Smaller connection pools (10-30 per exchange)

### Architecture Confirmation
- Current REST design won't block future WebSocket additions
- WebSocket can be completely independent module when needed
- No preparatory work required now for future streaming

## Quick Reference

- **Req steps**: Return `{request, options}` tuple
- **Halt pipeline**: `Req.Request.halt(request, error)`
- **Private state**: `Req.Request.put_private/3`
- **ETS atomic**: `:ets.update_counter/3`
- **Test stubs**: `import Req.Test; stub/2`
- **Clock sync**: Proactive on startup + every 5 min
- **One task**: Complete, validate, stop

## Final Summary: Trading Operations Library

### What We're Building
A **REST-only trading operations library** for cryptocurrency exchanges that:
- Places, modifies, and cancels orders reliably
- Manages positions and account balances
- Handles risk management and margin requirements
- Provides fault-tolerant, production-ready trading infrastructure

### What We're NOT Building
- **NO market data fetching** (use WebSocket library)
- **NO price feeds or order books** (use WebSocket library)
- **NO high-frequency trading** (focus on reliability)
- **NO WebSocket implementation** (REST-only scope)

### Key Architecture Decisions
- **Req-centric**: Leverage Req's built-in features, don't reinvent
- **Minimal GenServers**: Only Deribit OAuth needs state
- **ETS for performance**: Atomic operations for rate limiting
- **Trading safety first**: Idempotency, validation, reconciliation

---
**Remember**: This guide is for building a production-ready REST trading operations library. Test against real APIs first, mock second. Focus on reliability over speed.
