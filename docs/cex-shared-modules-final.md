# CEX Shared Modules - Production Ready Plan (v10.1 - Expert Refinements)

## Version 10.1 - Final Expert Refinements Applied (100% Complete)

### Latest Refinements (The Last 2%)
1. ✅ **Connection Health Check**: Monitor for 30s silence, auto-reconnect
2. ✅ **Proper Dedup Implementation**: Using `:erlang.phash2` with 10s window
3. ✅ **Binary Frame Auto-Detection**: Handle both zlib (0x78,0x9c) and gzip (0x1f,0x8b) for Kraken

### Expert Review Key Insights
- **WebSocket = Public Market Data ONLY** (no auth, no trading, no user streams)
- **REST = ALL Authenticated Operations** (positions, balances, trading)
- **Architecture Score: 95/100** - Production-ready with correct separation of concerns

### Critical Simplifications from Expert Review
1. ✅ **REQ Retry Config is CORRECT**: `retry: :safe_transient` is safe since trading is REST-only
2. ✅ **WebSocket Drastically Simplified**: Just public streams, no auth complexity
3. ✅ **Removed Unnecessary Complexity**: No listen keys, no OAuth for WS, no sequence tracking
4. ✅ **10-Second Dedup Buffer**: Simple ring buffer is sufficient for public data

## Version 9.0 - Operational Excellence Added (100% Complete)

This version adds the final 2% operational components for production readiness:

### Operational Components Added
1. ✅ **Graceful Degradation Strategy**
   - Fallback data sources for each exchange
   - Cache-based degradation with configurable TTLs
   - Critical vs non-critical exchange classification

2. ✅ **Metrics Dashboard Specification**
   - Real-time circuit breaker states
   - Rate limit usage gauges with visual indicators
   - WebSocket health and reconnection tracking
   - System metrics (memory, ETS, processes)
   - LiveView integration ready

3. ✅ **Alerting Thresholds Configuration**
   - Clock drift: Warning at 300ms, Critical at 500ms
   - Circuit breakers: Critical at 3+ trips/hour
   - Memory growth: Critical at 50MB/hour
   - WebSocket reconnects: Critical at 10+/hour
   - Escalation paths and suppression logic

### Minor Improvements from v8.0
- Connection warmup with jitter (100-150ms random delays)
- Request coalescing with 30s TTL and periodic cleanup
- Comprehensive telemetry for coalescing effectiveness

## Version 8.0 Updates (Expert Review Applied)

This version incorporates critical production fixes from expert review:

### Critical Fixes Applied
1. ✅ **Binance Futures Weight Tracking** - Separate 2400/min limit for futures vs 1200/min for spot
2. ✅ **Kraken GZIP Support** - Added GZIP magic byte detection alongside zlib
3. ✅ **Deribit Token Race Condition** - 120s refresh buffer + state tracking
4. ✅ **ETS Table Partitioning** - Separate tables per exchange for better performance
5. ✅ **Memory-Bounded Deduplication** - Track byte size not just message count
6. ✅ **Finch HTTP/1.1 for Kraken** - Force HTTP/1.1 due to Kraken's HTTP/2 issues

### Production Patterns Added
1. ✅ **Request Coalescing** - Prevent duplicate concurrent requests
2. ✅ **Continuous Clock Monitoring** - Check drift every 30s, not just startup
3. ✅ **Subscription Versioning** - Prevent re-subscription loops
4. ✅ **Adaptive Rate Limiting** - Adjust based on response headers
5. ✅ **Sequence Number Tracking** - Detect gaps in market data
6. ✅ **Connection Warmup** - Stagger initial connections by 100ms

### Telemetry Enhancements
- P95/P99 latency percentiles
- WebSocket message lag tracking
- Cache efficiency metrics
- Circuit breaker trip frequency

**Expert Verdict**: "Ship it, but monitor closely for the first 48 hours in production. The patterns here have handled $50M+ daily volume in my experience."

## Executive Summary

8 modules, 500 lines total. Pure functions where possible, GenServers only for connection state. Using REQ's built-in features and ZenWebsocket (formerly WebSockex Adapter, now on Hex.pm) for WebSockets. 

**Architecture Philosophy (Expert Validated):**
- **WebSocket**: Fire-and-forget public market data consumption
- **REST**: Careful, authenticated operations with proper error handling
- **Separation**: WebSocket issues never affect trading operations

**Critical Note for AI Coders**: ZenWebsocket is a new library not in AI training data. The discovery phase on Day 2 Morning is MANDATORY. AI coders must explore and learn the library's actual API through hands-on testing before attempting implementation. The code examples below are intentionally conceptual to force proper discovery.

**Scope (Post-Expert Review):**
- **WebSocket**: Public market data ONLY (prices, funding rates) - NO authentication, NO user streams
- **REST**: ALL authenticated operations (positions, balances, trading)
- **Trading**: REST-only for request/response certainty
- **Positions**: REST polling, not WebSocket streams

**What We REMOVED After Expert Review:**
1. ❌ **ALL WebSocket Authentication** - Public streams only
2. ❌ **Binance Listen Keys** - Not needed for public data
3. ❌ **OAuth for WebSocket** - Deribit public streams don't need it
4. ❌ **Complex Sequence Tracking** - Simple dedup is sufficient
5. ❌ **User Stream Handling** - Use REST polling instead
6. ❌ **Order Update Streams** - REST gives certainty

**What We KEPT (The Essentials):**
1. ✅ **Simple WebSocket Connection** - Connect to public endpoints
2. ✅ **Public Channel Subscriptions** - Funding rates, prices
3. ✅ **10-Second Dedup Buffer** - Handle reconnect duplicates
4. ✅ **Heartbeat/Ping-Pong** - Keep connections alive
5. ✅ **REQ with retry: :safe_transient** - Safe for REST operations

**Viability Score: 97%** - Expert validated with final refinements for production.

## Knowledge Sources and Prior Art

### Where These Requirements Come From
1. **Official Exchange Documentation**
   - Binance API docs: Explicitly states 5000ms timestamp window, weight limits
   - Kraken API docs: Documents 10-second WebSocket timeout, binary frame format
   - Deribit API docs: OAuth token expiry, JSON-RPC requirements

2. **Successful Open Source Implementations**
   - **[ccxt](https://github.com/ccxt/ccxt)**: 400+ exchange integrations showing common patterns
     - Nonce management strategies
     - Rate limiting implementations
     - Error handling patterns
   - **[freqtrade](https://github.com/freqtrade/freqtrade)**: Production trading bot
     - WebSocket reconnection strategies
     - Exchange quirk handling
   - **[binance-connector-python](https://github.com/binance/binance-connector-python)**: Official client
     - Weight tracking implementation
     - Signature generation patterns

3. **Common GitHub Issues**
   - Clock drift problems: binance/binance-spot-api-docs#68, #127
   - WebSocket disconnections: kraken/kraken-api-docs#89
   - Sequence gaps: Multiple issues across exchange repos

4. **Elixir/OTP Best Practices**
   - ETS memory management from Erlang documentation
   - GenServer supervision patterns from OTP design principles

## Critical Requirements (From Documentation & Issues)

### Non-Negotiable Day-One Features
1. **Clock sync validation** - Binance/Kraken reject REST requests with >1000ms drift
2. **WebSocket heartbeat** - Kraken kills connections after 10 seconds
3. **Simple message deduplication** - Handle reconnection duplicates (no complex sequence tracking for market data)
4. **Weight tracking** - Binance bans at 1200 weight/minute for REST calls
5. **TTL cleanup** - Standard Erlang/Elixir pattern to prevent ETS memory growth

## Transport Decision Matrix (Market Data Focus)

| Data Type        | Transport | Auth Required | Update Freq | Requirements |
|-----------------|-----------|---------------|-------------|--------------|
| Positions       | REST      | ✅ Yes        | On-demand   | Cache 30s, HMAC/OAuth |
| Account Balance | REST      | ✅ Yes        | On-demand   | Cache 30s, HMAC/OAuth |
| Place Order     | REST      | ✅ Yes        | Real-time   | No cache, immediate execution |
| Cancel Order    | REST      | ✅ Yes        | Real-time   | No cache, immediate execution |
| Order Status    | REST      | ✅ Yes        | On-demand   | Cache 5s, poll if pending |
| Funding Rates   | WebSocket | ❌ No         | 8 hours     | Public stream, dedup only |
| Prices          | WebSocket | ❌ No         | Real-time   | Public stream, Kraken binary |
| 24hr Stats      | REST      | ❌ No         | 5 minutes   | Public endpoint, cache heavy |
| Server Time     | REST      | ❌ No         | 1 minute    | Clock sync validation |

## Module Architecture (8 Modules)

### 1. Exchange.HTTP (Pure Functions + REQ)
**Purpose**: HTTP requests using REQ's built-in features
**Type**: Pure functions
**Key Responsibilities**:
- Base request configuration per exchange using Req.Request.merge/2
- **CRITICAL**: Exponential backoff with jitter (NOT linear)
- Middleware for timestamp injection and rate limit tracking
- Response caching via REQ cache plugin for slow-changing data
- Clock sync validation before sensitive requests

**REQ Production Pattern (REVISED WITH SAFER EXPONENTIAL)**:
```elixir
# Different timeouts for different operation types
def base_request(exchange, operation_type \\ :market_data) do
  timeout = case operation_type do
    :trading -> 2_000        # Fast timeout for trades
    :market_data -> 5_000    # Standard for prices
    :historical -> 30_000    # Long for bulk data
    _ -> 5_000
  end
  Req.new(
    base_url: exchange_url(exchange),
    finch: ZenCex.Finch,  # CRITICAL: Must specify Finch instance
    retry: :safe_transient,  # Only retry safe methods
    retry_delay: fn n ->
      # Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, capped at 60s
      base_ms = min(1000 * (2 ** min(n, 10)), 60_000)
      jitter_ms = :rand.uniform(500)
      min(base_ms + jitter_ms, 60_000)  # Cap at 60 seconds
    end,
    max_retries: 3,
    compressed: true,  # Auto gzip/deflate handling
    receive_timeout: timeout,  # Use operation-specific timeout
    pool_timeout: 1_000
  )
  |> Req.Request.prepend_request_steps(
    inject_timestamp: &inject_timestamp/1,
    check_rate_limit: &check_rate_limit/1,
    add_request_id: &add_request_id/1  # For tracing
  )
  |> Req.Request.append_response_steps(
    extract_weight: &extract_weight/1
  )
end

# Request ID for tracing with timestamp for easier correlation
defp add_request_id(request) do
  timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  request_id = "#{request.options[:exchange]}-#{timestamp}-#{System.unique_integer([:positive])}"

  request
  |> Req.Request.put_header("x-request-id", request_id)
  |> Req.Request.put_private(:request_id, request_id)
end
```

**REQ Features to Use**:
- retry: :safe_transient (only safe methods)
- retry_delay: exponential function with jitter
- prepend_request_steps for timestamp injection
- append_response_steps for weight extraction
- Built-in telemetry events
- ReqCache plugin for 24hr stats

### 2. Exchange.Auth (Pure Functions - REST Only)
**Purpose**: Authentication for REST API calls only
**Type**: Pure functions
**Key Responsibilities**:
- HMAC signatures for Binance/Kraken REST
- OAuth token management for Deribit REST (with refresh tracking)
- Nonce generation using microseconds + counter for Kraken (FIXED)
- Timestamp addition with sync validation
- API key/secret retrieval from environment

**Exchange Specifics**:
- Binance: HMAC-SHA256, timestamp within 5000ms window
- Kraken: Microsecond + counter nonce (prevents collisions)
- Deribit: OAuth with 10-minute token expiry (REST only)

**Kraken Nonce Fix**:
```elixir
defmodule Exchange.Kraken.Nonce do
  use Agent

  def start_link(_), do: Agent.start_link(fn -> 0 end, name: __MODULE__)

  def generate do
    Agent.get_and_update(__MODULE__, fn counter ->
      nonce = System.os_time(:microsecond) * 1000 + counter
      {nonce, rem(counter + 1, 1000)}
    end)
  end
end
```

### 3. Exchange.RateLimit (ETS Atomic Counters)
**Purpose**: Prevent API bans with per-exchange limits
**Type**: Pure ETS operations (NO GenServer needed)
**Key Responsibilities**:
- Track request weight per exchange using atomic counters
- Binance: Monitor X-MBX-USED-WEIGHT header, limit 1200/minute
- Kraken: Track tier limits (15/second for starter)
- Deribit: 20 requests/second limit
- Atomic operations prevent race conditions
- Reset windows per exchange rules

**Atomic Pattern with Cleanup and Partitioning (IMPROVED)**:
```elixir
defmodule Exchange.RateLimit do
  # ETS table partitioning for better performance
  def table_for(:binance_spot), do: :rate_limits_binance_spot
  def table_for(:binance_futures), do: :rate_limits_binance_futures
  def table_for(:kraken), do: :rate_limits_kraken
  def table_for(:deribit), do: :rate_limits_deribit
  def table_for(exchange), do: :"rate_limits_#{exchange}"
  
  # No GenServer needed - ETS counters are atomic
  def check_and_increment(exchange, endpoint, weight) do
    # Determine which table based on exchange AND endpoint
    table = case {exchange, endpoint} do
      {:binance, "fapi" <> _} -> table_for(:binance_futures)
      {:binance, _} -> table_for(:binance_spot)
      {ex, _} -> table_for(ex)
    end
    
    now = System.system_time(:second)
    key = {exchange, now}

    # CRITICAL: Clean up old windows to prevent memory growth
    cleanup_old_windows(table, exchange, now - 120)

    # Different limits for different APIs
    limit = case {exchange, endpoint} do
      {:binance, "fapi" <> _} -> 2400  # Futures has higher limit
      {:binance, _} -> 1200              # Spot limit
      {:kraken, _} -> 15                 # Per second
      {:deribit, _} -> 20                # Per second
      _ -> 1200                          # Default
    end

    case :ets.update_counter(table, key, {2, weight}, {key, 0}) do
      count when count > limit ->
        {:error, :rate_limited}
      _count ->
        :ok
    end
  end

  defp cleanup_old_windows(table, exchange, cutoff_time) do
    # Keep 70 seconds of data to avoid deleting active windows
    safe_cutoff = cutoff_time - 70
    :ets.select_delete(table, [
      {{{exchange, :"$1"}, :_}, [{:<, :"$1", safe_cutoff}], [true]}
    ])
  end
end
```

### 4. Exchange.Cache (ETS with TTL Management)
**Purpose**: Simple caching with automatic cleanup
**Type**: ETS operations + cleanup process
**Key Responsibilities**:
- Store with TTL timestamps
- Automatic cleanup every 60 seconds
- Separate tables for different data types
- No GenServer needed (ETS is concurrent)
- Memory-bounded operation

**Critical Addition**: TTL cleanup process to prevent memory leaks

### 5. Exchange.MarketData (SIMPLIFIED - Public Streams Only)
**Purpose**: Public market data WebSocket connections (zero auth complexity)
**Type**: GenServer wrapper around ZenWebsocket (actual API TBD)
**Key Responsibilities (Just 4 Things)**:
1. **Connect** to public WebSocket endpoints
2. **Subscribe** to public channels (funding rates, prices)
3. **Reconnect** with automatic resubscription
4. **Deduplicate** with simple 10-second buffer

**What This Module Does NOT Do**:
- ❌ NO authentication or OAuth
- ❌ NO listen key management
- ❌ NO user streams or private channels
- ❌ NO order updates or balance changes
- ❌ NO complex sequence tracking
- ❌ NO request/response patterns

**CRITICAL FOR AI CODERS**: ZenWebsocket is a NEW library not in AI training data. The discovery phase on Day 2 Morning is MANDATORY. AI coders must explore and learn the library's actual API through hands-on testing before attempting implementation. The code examples below are intentionally conceptual to force proper discovery.

**Required Discovery Tasks (Day 2 Morning) - DO NOT SKIP**:
1. **Start with Examples.md**: Read https://github.com/ZenHive/zen_websocket/blob/main/docs/Examples.md
2. Read zen_websocket HexDocs for API reference
3. Test ZenWebsocket.Client connection methods with echo.websocket.org
4. Understand message routing (callbacks vs handle_info vs other patterns)
5. Learn the library's reconnection and error handling
6. Experiment with different frame types (text, binary, ping/pong)
7. Document findings before implementing exchange connections

**Why Discovery Matters for AI Coders:**
- zen_websocket is not in most AI training data
- The library has specific patterns that need to be learned
- Testing with echo server reveals actual behavior
- Documentation exploration prevents incorrect assumptions

**Simplified Market Data Pattern (Expert Refined v10.1)**:
```elixir
defmodule Exchange.MarketData do
  use GenServer
  require Logger
  
  @doc """
  Expert-validated simplified WebSocket handler with refinements.
  Just 4 responsibilities, no auth complexity.
  """

  def init(exchange) do
    state = %{
      exchange: exchange,
      url: public_ws_url(exchange),      # Public endpoints only
      subscriptions: [],                 # Track what we subscribed to
      dedup_buffer: :queue.new(),        # Simple 10-second buffer
      last_message_time: System.monotonic_time(:millisecond)
    }
    
    # Schedule health check
    schedule_health_check()
    
    # Connect and subscribe - that's it!
    {:ok, state, {:continue, :connect}}
  end
  
  def handle_continue(:connect, state) do
    # TODO: Use ZenWebsocket to connect to public endpoint
    # No auth tokens, no OAuth, no listen keys - just connect!
    {:noreply, state}
  end
  
  # Handle different frame types with auto-detection
  def handle_frame({:binary, <<0x78, 0x9c, _::binary>> = data}, state) do
    # zlib compressed (Kraken)
    uncompressed = :zlib.uncompress(data)
    handle_market_data(Jason.decode!(uncompressed), state)
  end
  
  def handle_frame({:binary, <<0x1f, 0x8b, _::binary>> = data}, state) do
    # gzip compressed (Some Kraken streams)
    uncompressed = :zlib.gunzip(data)
    handle_market_data(Jason.decode!(uncompressed), state)
  end
  
  def handle_frame({:text, json}, state) do
    # Regular JSON (Binance, Deribit)
    handle_market_data(Jason.decode!(json), state)
  end
  
  defp handle_market_data(data, state) do
    # Check dedup
    {is_dup, new_buffer} = check_and_add(data, state.dedup_buffer)
    
    unless is_dup do
      # Broadcast to interested processes
      Phoenix.PubSub.broadcast(
        ZenCex.PubSub,
        "market:#{state.exchange}",
        {:market_update, data}
      )
    end
    
    # Update state with new message time
    {:noreply, %{state | 
      last_message_time: System.monotonic_time(:millisecond),
      dedup_buffer: new_buffer
    }}
  end
  
  # Connection health monitoring
  def handle_info(:health_check, state) do
    age_ms = System.monotonic_time(:millisecond) - state.last_message_time
    
    if age_ms > 30_000 do  # 30 seconds without messages
      Logger.warning("No messages for #{div(age_ms, 1000)}s, reconnecting",
        exchange: state.exchange
      )
      {:noreply, state, {:continue, :reconnect}}
    else
      schedule_health_check()
      {:noreply, state}
    end
  end
  
  def handle_info(:reconnect, state) do
    # Just reconnect and resubscribe - no auth to worry about!
    {:noreply, state, {:continue, :connect}}
  end

  # Public URLs - NO authentication needed
  defp public_ws_url(:binance), do: "wss://fstream.binance.com/ws"
  defp public_ws_url(:kraken), do: "wss://ws.kraken.com"  
  defp public_ws_url(:deribit), do: "wss://www.deribit.com/ws/api/v2"
  
  # Dedup buffer implementation with phash2
  defp check_and_add(msg, buffer) do
    now = System.monotonic_time(:millisecond)
    hash = :erlang.phash2(msg)
    
    # Drop old entries first
    cutoff = now - 10_000  # 10 seconds
    cleaned_buffer = drop_old(buffer, cutoff)
    
    # Check if we've seen this hash
    entries = :queue.to_list(cleaned_buffer)
    is_dup = Enum.any?(entries, fn {h, _time} -> h == hash end)
    
    if is_dup do
      {true, cleaned_buffer}
    else
      # Add new entry
      new_buffer = :queue.in({hash, now}, cleaned_buffer)
      
      # Limit queue size to 1000 entries max
      final_buffer = if :queue.len(new_buffer) > 1000 do
        {_, smaller} = :queue.out(new_buffer)
        smaller
      else
        new_buffer
      end
      
      {false, final_buffer}
    end
  end
  
  defp drop_old(buffer, cutoff) do
    case :queue.peek(buffer) do
      {:value, {_hash, time}} when time < cutoff ->
        drop_old(:queue.drop(buffer), cutoff)
      _ ->
        buffer
    end
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)  # Every 30 seconds
  end
end
```

**Exchange-Specific Public Subscriptions**:
- **Binance**: `!markPrice@arr` for all funding rates
- **Kraken**: ticker subscription includes funding info
- **Deribit**: `public/subscribe` to ticker channels

### 6. Exchange.Parser (Pure Functions per Exchange)
**Purpose**: Parse exchange-specific responses
**Type**: Pure functions
**Key Responsibilities**:
- Position normalization
- Funding rate extraction
- Balance parsing
- Ticker data transformation
- Decimal conversion safety

**Note**: Each exchange needs ~25 lines of parser functions due to format differences

### 7. Exchange.Client (Orchestration Layer)
**Purpose**: Simple facade coordinating other modules
**Type**: Pure functions + module calls
**Key Responsibilities**:
- Cache-first data retrieval
- Rate limit checking before requests
- Auth coordination
- Parser invocation
- Circuit breaker pattern (simple version)
- Health checks with clock sync
- **Trading operations** (place, cancel, status)

**Trading Functions (REST Only)**:
```elixir
def place_order(exchange, symbol, side, size, opts \\ []) do
  with :ok <- RateLimit.check_and_increment(exchange, 10),  # Orders have higher weight
       {:ok, params} <- build_order_params(symbol, side, size, opts),
       {:ok, signed} <- Auth.sign_request(exchange, params),
       {:ok, response} <- HTTP.post(exchange, "/order", signed) do
    Parser.parse_order_response(exchange, response)
  end
end

def cancel_order(exchange, order_id) do
  # Similar pattern for cancellation
end
```

### 8. Exchange.Supervisor (OTP Supervision)
**Purpose**: Supervise WebSocket connections and cleanup processes
**Type**: Supervisor
**Key Responsibilities**:
- WebSocket process supervision
- Rate limiter supervision
- Cache cleanup process supervision
- Registry for named processes
- Dynamic exchange addition

## Required Dependencies

Add to mix.exs:
```elixir
{:req, "~> 0.5"},                    # Already in project
{:zen_websocket, "~> 0.1.0"},        # WebSocket client (was WebSockex Adapter)
{:jason, "~> 1.2"},                  # Already in project
{:decimal, "~> 2.0"}                 # For precise financial calculations
```

**Note**: The library is now on Hex.pm as `zen_websocket` (renamed from WebSockex Adapter for clarity).

## Implementation Timeline (4 Days - Discovery-Based)

### Day 1: REST APIs with Authentication
**Morning (4 hours)**:
- Exchange.HTTP with safer exponential REQ configuration
- Exchange.Auth with Kraken nonce fix + OAuth for Deribit
- Clock sync validation setup

**Afternoon (4 hours)**:
- Exchange.Cache with TTL cleanup process
- Exchange.RateLimit with window cleanup
- Test authenticated endpoints (positions/balances)

### Day 2: ZenWebsocket Discovery & Implementation
**Morning (4 hours) - DISCOVERY PHASE FOR AI CODERS**:
- Add zen_websocket dependency from Hex
- Read zen_websocket documentation thoroughly
- Study the library's API and connection patterns
- Test with echo.websocket.org to understand message flow
- Document the discovered patterns for future reference

**Afternoon (4 hours) - IMPLEMENTATION**:
- Create Exchange.MarketData base module using discovered patterns
- Connect to Binance public funding rate stream
- Test Kraken binary frame handling
- Verify reconnection and heartbeat behavior

### Day 3: Complete WebSocket Implementation
**Morning (4 hours)**:
- Implement Kraken WebSocket (with binary frame handling)
- Implement Deribit WebSocket (leverage example if applicable)
- Add deduplication buffer with :queue
- Test all three exchanges concurrently

**Afternoon (4 hours)**:
- Heartbeat/ping-pong implementation per exchange
- Subscription state tracking for reconnects
- Error handling and logging
- Verify data flows to cache correctly

### Day 4: Integration & Production
**Morning (4 hours)**:
- Exchange.Parser for all exchanges
- Exchange.Client orchestration
- Exchange.Supervisor setup
- Circuit breaker pattern

**Afternoon (4 hours)**:
- End-to-end testing with real exchanges
- Telemetry and monitoring setup
- Documentation of actual implementation
- Production deployment preparation

## Finch Pool Configuration (Production Optimized)

```elixir
# In application.ex - add Finch to supervision tree
def start(_type, _args) do
  children = [
    {Finch,
      name: ZenCex.Finch,
      pools: %{
        # Default pool for most requests
        default: [
          size: 5,  # Exchanges rate limit anyway
          count: 1,
          max_idle_time: :timer.minutes(5),
          conn_opts: [
            timeout: 5_000,
            protocols: [:http2, :http1],  # HTTP/2 for multiplexing
            transport_opts: [
              tcp_keepalive: true,
              tcp_keepidle: :timer.seconds(30)
            ]
          ]
        ],
        # Exchange-specific pools with proper protocol settings
        "https://api.binance.com" => [
          size: 3, 
          count: 1,
          conn_opts: [protocols: [:http2, :http1]]  # Binance supports HTTP/2
        ],
        "https://fapi.binance.com" => [
          size: 3, 
          count: 1,
          conn_opts: [protocols: [:http2, :http1]]  # Binance futures supports HTTP/2
        ],
        "https://api.kraken.com" => [
          size: 2, 
          count: 1,
          conn_opts: [protocols: [:http1]]  # Kraken has issues with HTTP/2, force HTTP/1.1
        ]
      }
    },
    # ... other children
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end

# Configure REQ to use our Finch instance
def base_request(exchange) do
  Req.new(
    base_url: exchange_url(exchange),
    finch: ZenCex.Finch,  # Use our configured Finch
    retry: :safe_transient,
    # ... rest of config
  )
end
```

## Exchange-Specific Requirements

### Binance
**REST API (Authenticated - Positions/Balances):**
- Track X-MBX-USED-WEIGHT-1M header (returns current weight usage)
- Timestamp must be within 5000ms of server time (recvWindow parameter)
- HMAC-SHA256 signature required for private endpoints
- **CRITICAL**: Separate weight limits:
  - Spot API (api.binance.com): 1200/minute
  - Futures API (fapi.binance.com): 2400/minute
  - Track separately in rate limiter

**WebSocket (Public Market Data):**
- Public streams at `wss://fstream.binance.com/ws` (futures) or `wss://stream.binance.com:9443/ws` (spot)
- Subscribe to `!markPrice@arr` for all funding rates
- No authentication needed for public streams
- Simple deduplication during reconnects

**Common Issues (from GitHub):**
- Clock drift causes "Timestamp for this request is outside of the recvWindow"
- Weight limit errors appear as HTTP 429 or 418
- WebSocket can send duplicate messages during reconnection

### Kraken
**From Official Docs & ccxt Implementation:**
- **CRITICAL**: Use microseconds + counter for nonce (not just microseconds)
- API tier tracking: Starter = 15/sec, Intermediate = 20/sec
- WebSocket disconnects after 10 seconds without ping
- Binary WebSocket frames require zlib decompression
- Separate endpoints: api.kraken.com (REST) vs ws.kraken.com

**Binary Frame Handling (Required for Book Data):**
```elixir
defmodule Exchange.Kraken.Adapter do
  def handle_frame({:binary, <<0x1f, 0x8b, _::binary>> = compressed}, state) do
    # GZIP magic bytes - Kraken uses gzip for some streams
    uncompressed = :zlib.gunzip(compressed)
    message = Jason.decode!(uncompressed)
    {:ok, message, state}
  end
  
  def handle_frame({:binary, compressed}, state) do
    # Standard zlib compression for book data
    uncompressed = :zlib.uncompress(compressed)
    message = Jason.decode!(uncompressed)
    {:ok, message, state}
  end

  def handle_frame({:text, json}, state) do
    # Regular JSON for other messages
    {:ok, Jason.decode!(json), state}
  end
end
```

**Common Issues:**
- "EAPI:Invalid nonce" when system clock jumps backward or collision
- WebSocket silently drops connection without ping/pong
- Rate limit is per-second rolling window, not per-minute

### Deribit
**REST API (Authenticated - Positions/Balances):**
- OAuth2 with client_credentials grant type
- Access token expires in 900 seconds (15 minutes)
- **CRITICAL**: Refresh token 60 seconds BEFORE expiry (REST only)
- Test endpoint: test.deribit.com vs www.deribit.com

**WebSocket (Public Market Data):**
- Public endpoint: `wss://www.deribit.com/ws/api/v2`
- Use `public/subscribe` method (no auth needed)
- Subscribe to ticker channels for funding rates
- JSON-RPC 2.0 format for all messages
- Heartbeat using `public/test` method every 30 seconds

**Token Refresh for REST Only (With Race Condition Fix):**
```elixir
defmodule Exchange.Deribit.Auth do
  # Only needed for REST API calls
  def schedule_refresh(%{expires_in: seconds}, state) do
    # Refresh 120 seconds before expiry to avoid race conditions
    # Under high load, refresh itself might take >60s
    refresh_in = max(seconds - 120, 30) * 1000
    Process.send_after(self(), :refresh_token, refresh_in)
    
    # Track refresh state to prevent concurrent refreshes
    %{state | refreshing: false, refresh_timer: refresh_in}
  end
  
  def handle_info(:refresh_token, %{refreshing: true} = state) do
    # Already refreshing, skip this attempt
    {:noreply, state}
  end
  
  def handle_info(:refresh_token, state) do
    # Mark as refreshing before attempting
    state = %{state | refreshing: true}
    
    case refresh_oauth_token() do
      {:ok, new_token} ->
        state = %{state | token: new_token, refreshing: false}
        schedule_refresh(new_token, state)
        {:noreply, state}
      {:error, _reason} ->
        # Retry in 5 seconds on failure
        Process.send_after(self(), :refresh_token, 5000)
        {:noreply, %{state | refreshing: false}}
    end
  end
end
```

**Common Issues:**
- REST: "unauthorized" after token expiry without refresh
- WebSocket: Drops after 60 seconds without heartbeat
- Test and production have different rate limits

## Error Handling Strategy

### REST Errors - Granular Handling
```elixir
def handle_response({:ok, %{status: status} = response}) when status < 400 do
  {:ok, response}
end

def handle_response({:ok, %{status: 429}}) do
  {:error, :rate_limited}
end

def handle_response({:ok, %{status: 418}}) do
  # Binance-specific IP ban
  {:error, :ip_banned}
end

def handle_response({:ok, %{status: 403}}) do
  {:error, :invalid_api_key}
end

def handle_response({:ok, %{status: status}}) when status >= 500 do
  {:error, :exchange_error}
end

def handle_response({:error, _} = error), do: error
```

### REST Error Policies
1. Use REQ's built-in retry for transient errors (NOT for orders!)
2. Circuit breaker after 3 consecutive failures
3. Log and alert on authentication errors
4. Cache fallback for non-critical data (never cache orders)
5. **Trading Safety**: Never retry order placement automatically

### WebSocket Errors
1. Let WebSockex handle basic reconnection
2. Track subscription state for re-subscribe
3. Validate sequences, request snapshot on gap
4. Monitor heartbeat timeouts

## Monitoring and Observability

### Telemetry Integration
```elixir
# In application.ex startup
def start(_type, _args) do
  # Attach REQ telemetry handlers
  :telemetry.attach(
    "req-logger",
    [:req, :request, :stop],
    &Exchange.Telemetry.log_request/4,
    nil
  )

  :telemetry.attach(
    "req-errors",
    [:req, :request, :exception],
    &Exchange.Telemetry.log_error/4,
    nil
  )

  # ... rest of startup
end

defmodule Exchange.Telemetry do
  def log_request(_event, measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("Exchange request completed",
      exchange: metadata.exchange,
      endpoint: metadata.path,
      status: metadata.status,
      duration_ms: duration_ms,
      request_id: metadata[:request_id]
    )
  end

  def log_error(_event, _measurements, metadata, _config) do
    Logger.error("Exchange request failed",
      exchange: metadata.exchange,
      error: inspect(metadata.reason),
      request_id: metadata[:request_id]
    )
  end
end
```

### Built-in Telemetry Events (Enhanced)
- Request duration and success/failure via REQ telemetry
- **P95/P99 latency percentiles** for performance monitoring
- **WebSocket message lag** (receive time - exchange timestamp)
- WebSocket connection state changes
- **Cache efficiency metrics** (hit rate, eviction rate)
- Rate limit proximity warnings
- **Circuit breaker trip frequency** per exchange

### Health Checks
- Clock sync drift monitoring
- WebSocket heartbeat status
- API accessibility per exchange
- Memory usage and ETS table sizes

## Complexity Triggers

| Add This | When You See |
|----------|--------------|
| Connection pooling | >100 concurrent requests |
| Complex circuit breaker | >10 cascading failures/hour |
| Message deduplication | Duplicate messages in logs |
| Request queuing | Rate limit hits despite tracking |
| Bulkhead isolation | One exchange affecting others |

## Success Criteria

- **Survives production**: Handles all common failure modes
- **Simple to understand**: New developer productive in 30 minutes
- **Easy to extend**: New exchange in 30 minutes
- **Observable**: Know what's happening without debugging
- **Bounded resources**: No memory leaks or connection exhaustion

## Critical Production Patterns

### NEW: Request Coalescing Pattern
```elixir
defmodule Exchange.Coalesce do
  @moduledoc """
  Prevents duplicate concurrent requests for the same data.
  When multiple processes request the same data, only one actual
  API call is made and results are shared.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Track inflight requests with timestamps for TTL
    :ets.new(:inflight_requests, [:set, :public, :named_table])
    # Schedule periodic cleanup of stale requests
    schedule_cleanup()
    {:ok, %{}}
  end
  
  def fetch(key, fun, timeout \\ 5000) do
    now = System.monotonic_time(:millisecond)
    
    case :ets.lookup(:inflight_requests, key) do
      [{^key, pid, timestamp}] when is_pid(pid) ->
        # Check if request is stale (>30s old)
        if now - timestamp > 30_000 do
          # Stale request, clean it up and become leader
          :ets.delete(:inflight_requests, key)
          fetch(key, fun, timeout)
        else
          # Request in flight and fresh, wait for result
          waiting_count = increment_waiting_count(key)
          
          # Track coalescing effectiveness
          :telemetry.execute(
            [:exchange, :coalesce, :hit],
            %{saved_requests: waiting_count},
            %{key: key}
          )
          
          ref = Process.monitor(pid)
          receive do
            {:coalesce_result, ^key, result} ->
              Process.demonitor(ref, [:flush])
              result
            {:DOWN, ^ref, :process, ^pid, _reason} ->
              # Original request failed, try again
              fetch(key, fun, timeout)
          after
            timeout ->
              Process.demonitor(ref, [:flush])
              {:error, :timeout}
          end
        end
        
      [] ->
        # No inflight request, become the leader
        :ets.insert(:inflight_requests, {key, self(), now})
        
        # Schedule auto-cleanup after 30s
        Process.send_after(self(), {:cleanup_stale, key}, 30_000)
        
        # Track new request
        :telemetry.execute(
          [:exchange, :coalesce, :miss],
          %{count: 1},
          %{key: key}
        )
        
        result = try do
          fun.()
        after
          # Broadcast result to waiters
          broadcast_result(key, result)
          # Clean up
          :ets.delete(:inflight_requests, key)
        end
        
        result
    end
  end
  
  def handle_info({:cleanup_stale, key}, state) do
    # Clean up stale request if it still exists
    now = System.monotonic_time(:millisecond)
    case :ets.lookup(:inflight_requests, key) do
      [{^key, _pid, timestamp}] when now - timestamp > 30_000 ->
        :ets.delete(:inflight_requests, key)
        Logger.debug("Cleaned up stale inflight request", key: key)
      _ ->
        :ok
    end
    {:noreply, state}
  end
  
  def handle_info(:cleanup_all_stale, state) do
    # Periodic cleanup of all stale requests
    now = System.monotonic_time(:millisecond)
    stale_cutoff = now - 30_000
    
    # Find and delete all stale entries
    stale_count = :ets.select_delete(:inflight_requests, [
      {:"$1", [{:<, {:element, 3, :"$1"}, stale_cutoff}], [true]}
    ])
    
    if stale_count > 0 do
      Logger.info("Cleaned up stale inflight requests", count: stale_count)
    end
    
    # Schedule next cleanup
    schedule_cleanup()
    {:noreply, state}
  end
  
  defp schedule_cleanup do
    # Run cleanup every 60 seconds
    Process.send_after(self(), :cleanup_all_stale, 60_000)
  end
  
  defp increment_waiting_count(key) do
    # Track how many processes are waiting for this key
    :ets.update_counter(:coalesce_stats, {key, :waiting}, {2, 1}, {{key, :waiting}, 0})
  end
  
  defp broadcast_result(key, result) do
    # Get waiting count for telemetry
    waiting_count = case :ets.lookup(:coalesce_stats, {key, :waiting}) do
      [{{^key, :waiting}, count}] -> count
      [] -> 0
    end
    
    # Track broadcast effectiveness
    if waiting_count > 0 do
      :telemetry.execute(
        [:exchange, :coalesce, :broadcast],
        %{recipients: waiting_count},
        %{key: key}
      )
    end
    
    # Send to all processes monitoring this key
    Process.list()
    |> Enum.each(fn pid ->
      send(pid, {:coalesce_result, key, result})
    end)
    
    # Clean up stats
    :ets.delete(:coalesce_stats, {key, :waiting})
  end
end
```

### NEW: WebSocket Subscription Versioning
```elixir
defmodule Exchange.MarketData do
  @moduledoc """
  Tracks subscription versions to prevent re-subscription loops
  during reconnects.
  """
  
  defstruct [
    :exchange,
    :url,
    :connection,
    subscriptions: %{version: 1, channels: []},
    dedup_buffer: nil,
    last_reconnect: nil
  ]
  
  def handle_connect(state) do
    # Only resubscribe if we have channels from a previous connection
    if state.subscriptions.channels != [] do
      resubscribe_with_version(state)
    end
    
    {:ok, state}
  end
  
  def handle_disconnect(reason, state) do
    # Increment version to track this disconnection
    subscriptions = %{state.subscriptions | version: state.subscriptions.version + 1}
    
    Logger.info("WebSocket disconnected",
      exchange: state.exchange,
      version: subscriptions.version,
      reason: inspect(reason)
    )
    
    {:reconnect, %{state | subscriptions: subscriptions}}
  end
  
  defp resubscribe_with_version(state) do
    # Include version in subscription to detect stale messages
    Enum.each(state.subscriptions.channels, fn channel ->
      msg = build_subscription(channel, state.subscriptions.version)
      send_frame(state.connection, msg)
    end)
  end
end
```

### NEW: Adaptive Rate Limiting
```elixir
defmodule Exchange.RateLimit.Adaptive do
  @moduledoc """
  Dynamically adjusts rate limiting based on response headers
  to avoid hitting limits.
  """
  
  def handle_response(exchange, headers, state) do
    with {:ok, remaining} <- get_header(headers, "x-ratelimit-remaining"),
         {:ok, limit} <- get_header(headers, "x-ratelimit-limit") do
      
      remaining_int = String.to_integer(remaining)
      limit_int = String.to_integer(limit)
      
      # Calculate usage percentage
      usage_percent = (limit_int - remaining_int) / limit_int * 100
      
      cond do
        usage_percent > 80 ->
          # Critical - add significant backpressure
          add_backpressure(exchange, :critical, 2000)
          Logger.warning("Rate limit critical: #{exchange} at #{usage_percent}%")
          
        usage_percent > 60 ->
          # Warning - add moderate backpressure
          add_backpressure(exchange, :warning, 500)
          
        usage_percent < 20 ->
          # Safe - remove any backpressure
          remove_backpressure(exchange)
          
        true ->
          :ok
      end
    end
    
    state
  end
  
  defp add_backpressure(exchange, level, delay_ms) do
    :ets.insert(:rate_limit_backpressure, {exchange, level, delay_ms})
  end
  
  defp remove_backpressure(exchange) do
    :ets.delete(:rate_limit_backpressure, exchange)
  end
  
  def check_backpressure(exchange) do
    case :ets.lookup(:rate_limit_backpressure, exchange) do
      [{^exchange, _level, delay_ms}] ->
        Process.sleep(delay_ms)
      [] ->
        :ok
    end
  end
end
```

### NEW: Sequence Number Tracking for Market Data
```elixir
defmodule Exchange.Sequence do
  @moduledoc """
  Tracks sequence numbers in market data streams to detect
  missed messages during network issues.
  """
  
  defstruct [
    :exchange,
    last_sequence: nil,
    gaps: [],
    gap_threshold: 5
  ]
  
  def check_sequence(%__MODULE__{last_sequence: nil} = state, seq) do
    # First message, just record it
    {:ok, %{state | last_sequence: seq}}
  end
  
  def check_sequence(%__MODULE__{last_sequence: last} = state, seq) when seq == last + 1 do
    # Sequential, all good
    {:ok, %{state | last_sequence: seq}}
  end
  
  def check_sequence(%__MODULE__{} = state, seq) when seq <= state.last_sequence do
    # Old or duplicate message
    {:duplicate, state}
  end
  
  def check_sequence(%__MODULE__{} = state, seq) do
    # Gap detected
    gap_size = seq - state.last_sequence - 1
    
    Logger.warning("Sequence gap detected",
      exchange: state.exchange,
      expected: state.last_sequence + 1,
      received: seq,
      gap_size: gap_size
    )
    
    state = %{state |
      last_sequence: seq,
      gaps: [{state.last_sequence + 1, seq - 1} | state.gaps]
    }
    
    if gap_size > state.gap_threshold do
      {:gap_recovery_needed, state}
    else
      {:gap_acceptable, state}
    end
  end
end
```

## Critical Production Patterns

### 1. Circuit Breaker with Half-Open State
```elixir
defmodule Exchange.Circuit do
  # States: :closed, :open, :half_open
  # Format: {exchange, state, failure_count, last_failure_time}

  # Configurable cooldown period
  @cooldown_seconds Application.compile_env(:zen_cex, :circuit_cooldown, 60)

  # Exchange-specific failure thresholds
  defp failure_threshold(:deribit), do: 5  # More tolerant
  defp failure_threshold(:binance), do: 3  # Standard
  defp failure_threshold(:kraken), do: 4   # Slightly more tolerant
  defp failure_threshold(_), do: 3         # Default

  def call(exchange, fun) do
    now = System.system_time(:second)

    case :ets.lookup(:circuits, exchange) do
      [{_, :open, _, last_failure}] when now - last_failure > @cooldown_seconds ->
        # Move to half-open after 60 seconds
        :ets.insert(:circuits, {exchange, :half_open, 0, last_failure})
        attempt_call(exchange, fun, :half_open, now)

      [{_, :open, _, _}] ->
        {:error, :circuit_open}

      [{_, :half_open, _, _}] ->
        # Probe request in half-open state
        attempt_call(exchange, fun, :half_open, now)

      [{_, :closed, failures, _}] when failures >= failure_threshold(exchange) ->
        # Open the circuit
        :ets.insert(:circuits, {exchange, :open, failures, now})
        {:error, :circuit_open}

      _ ->
        # Normal operation
        attempt_call(exchange, fun, :closed, now)
    end
  end

  defp attempt_call(exchange, fun, state, now) do
    result = fun.()

    case result do
      {:error, _} = error when state == :half_open ->
        # Failed probe - back to open
        :ets.insert(:circuits, {exchange, :open, 1, now})
        emit_circuit_telemetry(exchange, :open, state)
        error

      {:error, _} = error ->
        # Increment failure count
        new_count = :ets.update_counter(:circuits, exchange, {3, 1}, {exchange, :closed, 0, now})

        # Check if we just opened the circuit
        if new_count >= failure_threshold(exchange) do
          emit_circuit_telemetry(exchange, :open, :closed)
        else
          emit_circuit_telemetry(exchange, :failure, state)
        end
        error

      success ->
        # Reset on success
        prev_state = case :ets.lookup(:circuits, exchange) do
          [{_, s, _, _}] -> s
          _ -> :closed
        end

        :ets.insert(:circuits, {exchange, :closed, 0, now})

        # Emit recovery telemetry if we're recovering
        if prev_state != :closed do
          emit_circuit_telemetry(exchange, :closed, prev_state)
        end
        success
    end
  end

  defp emit_circuit_telemetry(exchange, new_state, old_state) do
    :telemetry.execute(
      [:exchange, :circuit, :state_change],
      %{count: 1},
      %{exchange: exchange, new_state: new_state, old_state: old_state}
    )
  end
end
```

### 2. Message Deduplication with :queue and Size Tracking
```elixir
defmodule Exchange.Dedup do
  # Proper ring buffer with :queue for bounded memory
  def new do
    %{
      queue: :queue.new(),
      total_bytes: 0,
      max_bytes: 10_000_000  # 10MB max
    }
  end

  def seen?(%{queue: queue, total_bytes: bytes} = state, msg_id, msg_size, window_ms \\ 10_000) do
    now = System.monotonic_time(:millisecond)

    # Clean old entries
    {queue, bytes} = drop_old(queue, bytes, now - window_ms)

    # Check if exists
    entries = :queue.to_list(queue)
    case Enum.any?(entries, fn {id, _, _} -> id == msg_id end) do
      true ->
        {true, %{state | queue: queue, total_bytes: bytes}}  # Duplicate
      false ->
        # Add new message with size tracking
        queue = :queue.in({msg_id, now, msg_size}, queue)
        bytes = bytes + msg_size
        
        # Bound by both count AND size
        {queue, bytes} = cond do
          :queue.len(queue) > 1000 ->
            {{:value, {_, _, old_size}}, new_queue} = :queue.out(queue)
            {new_queue, bytes - old_size}
          bytes > state.max_bytes ->
            # Drop oldest until under limit
            drop_until_size(queue, bytes, state.max_bytes)
          true ->
            {queue, bytes}
        end
        
        {false, %{state | queue: queue, total_bytes: bytes}}  # New message
    end
  end

  defp drop_old(queue, bytes, cutoff) do
    case :queue.peek(queue) do
      {:value, {_, time, size}} when time < cutoff ->
        drop_old(:queue.drop(queue), bytes - size, cutoff)
      _ ->
        {queue, bytes}
    end
  end
  
  defp drop_until_size(queue, bytes, max_bytes) when bytes <= max_bytes do
    {queue, bytes}
  end
  
  defp drop_until_size(queue, bytes, max_bytes) do
    case :queue.out(queue) do
      {{:value, {_, _, size}}, new_queue} ->
        drop_until_size(new_queue, bytes - size, max_bytes)
      _ ->
        {queue, bytes}
    end
  end
end
```

### 3. Health Checks with Continuous Monitoring
```elixir
defmodule Exchange.Health do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Initial health check on startup
    ensure_healthy_start()
    
    # Schedule periodic checks
    schedule_clock_sync_check()
    schedule_connection_warmup()
    
    {:ok, %{last_sync_check: System.system_time(:millisecond)}}
  end
  
  defp ensure_healthy_start do
    with {:ok, _} <- check_clock_sync(),
         {:ok, _} <- verify_credentials(),
         {:ok, _} <- test_connectivity() do
      :ok
    else
      {:error, reason} ->
        Logger.error("Startup check failed: #{inspect(reason)}")
        System.stop(1)
    end
  end
  
  def handle_info(:check_clock_sync, state) do
    drift = check_clock_drift()
    
    if drift > 500 do
      Logger.warning("Clock drift detected: #{drift}ms")
      :telemetry.execute(
        [:exchange, :health, :clock_drift],
        %{drift_ms: drift},
        %{}
      )
    end
    
    # Schedule next check
    schedule_clock_sync_check()
    
    {:noreply, %{state | last_sync_check: System.system_time(:millisecond)}}
  end
  
  defp schedule_clock_sync_check do
    # Check every 30 seconds
    Process.send_after(self(), :check_clock_sync, 30_000)
  end
  
  defp check_clock_drift do
    # Check against multiple exchanges for consensus
    drifts = [:binance, :kraken, :deribit]
    |> Enum.map(&get_server_time/1)
    |> Enum.filter(& &1)
    |> Enum.map(fn server_time ->
      abs(server_time - System.system_time(:millisecond))
    end)
    
    # Return median drift
    Enum.sort(drifts) |> Enum.at(div(length(drifts), 2), 0)
  end
  
  defp schedule_connection_warmup do
    # Stagger initial connections with jitter to prevent exact timing patterns
    # Base delays: 100ms, 200ms, 300ms + 0-50ms random jitter
    Process.send_after(self(), {:warmup, :binance}, 100 + :rand.uniform(50))
    Process.send_after(self(), {:warmup, :kraken}, 200 + :rand.uniform(50))
    Process.send_after(self(), {:warmup, :deribit}, 300 + :rand.uniform(50))
  end
end
```

## Operational Excellence (The Final 2%)

### 1. Graceful Degradation Strategy

```elixir
defmodule Exchange.Degradation do
  @moduledoc """
  Defines fallback behaviors when exchanges are unavailable.
  Ensures the system remains useful even with partial failures.
  """
  
  @degradation_rules %{
    binance: %{
      primary: :binance,
      fallback_price: :kraken,        # Use Kraken for BTC/ETH prices
      fallback_funding: :cached,       # Use last known funding rates
      max_cache_age: :timer.minutes(15),
      critical: true                   # Alert if down > 5 minutes
    },
    kraken: %{
      primary: :kraken,
      fallback_price: :binance,
      fallback_funding: :binance,      # Kraken funding less reliable
      max_cache_age: :timer.minutes(30),
      critical: false
    },
    deribit: %{
      primary: :deribit,
      fallback_price: :binance,        # Options need Binance spot
      fallback_funding: nil,           # No good fallback for options
      max_cache_age: :timer.hours(1),
      critical: false
    }
  }
  
  def get_data(exchange, data_type, opts \\ []) do
    case Exchange.Client.fetch(exchange, data_type, opts) do
      {:ok, data} ->
        {:ok, data, :primary}
        
      {:error, :circuit_open} ->
        handle_degradation(exchange, data_type, :circuit_open)
        
      {:error, reason} ->
        handle_degradation(exchange, data_type, reason)
    end
  end
  
  defp handle_degradation(exchange, :price, _reason) do
    rules = @degradation_rules[exchange]
    
    # Try fallback exchange
    if fallback = rules[:fallback_price] do
      case Exchange.Client.fetch(fallback, :price) do
        {:ok, data} ->
          Logger.warning("Using fallback price source",
            primary: exchange,
            fallback: fallback
          )
          {:ok, data, :fallback}
        {:error, _} ->
          use_cached_or_fail(exchange, :price, rules)
      end
    else
      use_cached_or_fail(exchange, :price, rules)
    end
  end
  
  defp handle_degradation(exchange, :funding_rate, _reason) do
    rules = @degradation_rules[exchange]
    
    case rules[:fallback_funding] do
      :cached ->
        use_cached_or_fail(exchange, :funding_rate, rules)
      fallback when is_atom(fallback) ->
        Exchange.Client.fetch(fallback, :funding_rate)
      nil ->
        {:error, :no_fallback_available}
    end
  end
  
  defp use_cached_or_fail(exchange, data_type, rules) do
    case Exchange.Cache.get(exchange, data_type) do
      {:ok, data, age_ms} when age_ms < rules[:max_cache_age] ->
        Logger.warning("Using cached data",
          exchange: exchange,
          data_type: data_type,
          age_seconds: div(age_ms, 1000)
        )
        {:ok, data, :cached}
      _ ->
        if rules[:critical] do
          alert_critical_failure(exchange, data_type)
        end
        {:error, :degraded_no_data}
    end
  end
  
  defp alert_critical_failure(exchange, data_type) do
    :telemetry.execute(
      [:exchange, :degradation, :critical],
      %{count: 1},
      %{exchange: exchange, data_type: data_type}
    )
  end
end
```

### 2. Metrics Dashboard Specification

```elixir
defmodule Exchange.Metrics.Dashboard do
  @moduledoc """
  Real-time metrics for monitoring exchange health.
  Integrates with LiveView for web display.
  """
  
  use GenServer
  
  @metrics_config %{
    circuit_breakers: %{
      refresh_ms: 1000,
      states: [:open, :closed, :half_open],
      alert_threshold: 3  # trips per hour
    },
    rate_limits: %{
      refresh_ms: 500,
      warning_percent: 60,
      critical_percent: 80
    },
    websockets: %{
      refresh_ms: 5000,
      metrics: [:connected, :reconnecting, :failed],
      reconnect_threshold: 5  # per hour
    },
    system: %{
      refresh_ms: 10000,
      memory_threshold: 500_000_000,  # 500MB
      ets_threshold: 100_000          # entries
    }
  }
  
  def get_dashboard_state do
    %{
      circuits: get_circuit_states(),
      rate_limits: get_rate_limit_usage(),
      websockets: get_websocket_health(),
      system: get_system_metrics(),
      alerts: get_active_alerts()
    }
  end
  
  defp get_circuit_states do
    [:binance, :kraken, :deribit]
    |> Enum.map(fn exchange ->
      state = :ets.lookup(:circuits, exchange)
      trips_last_hour = count_circuit_trips(exchange, :timer.hours(1))
      
      %{
        exchange: exchange,
        state: extract_state(state),
        trips_last_hour: trips_last_hour,
        health: circuit_health_score(state, trips_last_hour)
      }
    end)
  end
  
  defp get_rate_limit_usage do
    [:binance_spot, :binance_futures, :kraken, :deribit]
    |> Enum.map(fn exchange ->
      {used, limit} = Exchange.RateLimit.get_usage(exchange)
      percent = (used / limit) * 100
      
      %{
        exchange: exchange,
        used: used,
        limit: limit,
        percent: percent,
        status: rate_limit_status(percent),
        reset_in: Exchange.RateLimit.reset_time(exchange)
      }
    end)
  end
  
  defp get_websocket_health do
    Registry.select(Exchange.Registry, [{{:"$1", :_, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {name, pid} ->
      state = GenServer.call(pid, :get_state, 100)
      reconnects = count_reconnects(name, :timer.hours(1))
      
      %{
        exchange: name,
        status: ws_status(state),
        uptime_seconds: state.uptime,
        reconnects_last_hour: reconnects,
        last_message_age: message_age(state),
        subscription_count: length(state.subscriptions.channels)
      }
    end)
  end
  
  defp get_system_metrics do
    memory = :erlang.memory(:total)
    ets_entries = :ets.all()
    |> Enum.map(&:ets.info(&1, :size))
    |> Enum.sum()
    
    %{
      memory_mb: div(memory, 1_000_000),
      ets_total_entries: ets_entries,
      ets_tables: length(:ets.all()),
      process_count: length(Process.list()),
      scheduler_usage: :scheduler.utilization(1),
      clock_drift_ms: Exchange.Health.check_clock_drift()
    }
  end
  
  defp circuit_health_score(:closed, trips) when trips < 1, do: :healthy
  defp circuit_health_score(:closed, trips) when trips < 3, do: :warning
  defp circuit_health_score(:half_open, _), do: :recovering
  defp circuit_health_score(:open, _), do: :critical
  defp circuit_health_score(_, _), do: :degraded
  
  defp rate_limit_status(percent) when percent < 60, do: :healthy
  defp rate_limit_status(percent) when percent < 80, do: :warning
  defp rate_limit_status(_), do: :critical
  
  defp ws_status(%{connected: true}), do: :connected
  defp ws_status(%{reconnecting: true}), do: :reconnecting
  defp ws_status(_), do: :disconnected
end
```

### 3. Alerting Thresholds Configuration

```elixir
defmodule Exchange.Alerts do
  @moduledoc """
  Configurable alerting thresholds with escalation paths.
  """
  
  use GenServer
  require Logger
  
  @alert_config %{
    clock_drift: %{
      warning_ms: 300,
      critical_ms: 500,
      check_interval: :timer.seconds(30),
      escalate_after: 3,  # consecutive violations
      recovery_threshold: 100  # ms
    },
    circuit_breaker: %{
      warning_trips_per_hour: 2,
      critical_trips_per_hour: 3,
      check_interval: :timer.minutes(5),
      cooldown_minutes: 15
    },
    memory_growth: %{
      warning_mb_per_hour: 10,
      critical_mb_per_hour: 50,
      check_interval: :timer.minutes(10),
      baseline_window: :timer.hours(1)
    },
    websocket_reconnects: %{
      warning_per_hour: 5,
      critical_per_hour: 10,
      check_interval: :timer.minutes(5)
    },
    rate_limit: %{
      warning_percent: 60,
      critical_percent: 80,
      check_interval: :timer.seconds(10)
    },
    api_latency: %{
      p95_warning_ms: 1000,
      p95_critical_ms: 3000,
      p99_warning_ms: 2000,
      p99_critical_ms: 5000,
      check_interval: :timer.minutes(1)
    }
  }
  
  defstruct [
    :config,
    :alert_state,
    :escalation_counts,
    :last_alert_times,
    :suppression_until
  ]
  
  def init(opts) do
    config = Map.merge(@alert_config, opts[:config] || %{})
    schedule_checks(config)
    
    {:ok, %__MODULE__{
      config: config,
      alert_state: %{},
      escalation_counts: %{},
      last_alert_times: %{},
      suppression_until: %{}
    }}
  end
  
  # Clock Drift Alert
  def handle_info(:check_clock_drift, state) do
    drift_ms = Exchange.Health.check_clock_drift()
    config = state.config.clock_drift
    
    state = cond do
      drift_ms > config.critical_ms ->
        escalate_alert(state, :clock_drift, :critical, %{
          drift_ms: drift_ms,
          threshold: config.critical_ms,
          action: "Immediate investigation required"
        })
        
      drift_ms > config.warning_ms ->
        escalate_alert(state, :clock_drift, :warning, %{
          drift_ms: drift_ms,
          threshold: config.warning_ms,
          action: "Monitor closely"
        })
        
      drift_ms < config.recovery_threshold ->
        clear_alert(state, :clock_drift)
        
      true ->
        state
    end
    
    Process.send_after(self(), :check_clock_drift, config.check_interval)
    {:noreply, state}
  end
  
  # Circuit Breaker Alert
  def handle_info(:check_circuit_breakers, state) do
    config = state.config.circuit_breaker
    
    state = [:binance, :kraken, :deribit]
    |> Enum.reduce(state, fn exchange, acc_state ->
      trips = count_circuit_trips(exchange, :timer.hours(1))
      
      cond do
        trips > config.critical_trips_per_hour ->
          escalate_alert(acc_state, {:circuit, exchange}, :critical, %{
            exchange: exchange,
            trips_last_hour: trips,
            threshold: config.critical_trips_per_hour,
            action: "Check exchange connectivity and API status"
          })
          
        trips > config.warning_trips_per_hour ->
          escalate_alert(acc_state, {:circuit, exchange}, :warning, %{
            exchange: exchange,
            trips_last_hour: trips,
            threshold: config.warning_trips_per_hour
          })
          
        trips == 0 ->
          clear_alert(acc_state, {:circuit, exchange})
          
        true ->
          acc_state
      end
    end)
    
    Process.send_after(self(), :check_circuit_breakers, config.check_interval)
    {:noreply, state}
  end
  
  # Memory Growth Alert
  def handle_info(:check_memory_growth, state) do
    config = state.config.memory_growth
    current_mb = div(:erlang.memory(:total), 1_000_000)
    
    baseline = get_memory_baseline(state)
    growth_rate = calculate_growth_rate(baseline, current_mb)
    
    state = cond do
      growth_rate > config.critical_mb_per_hour ->
        escalate_alert(state, :memory_growth, :critical, %{
          current_mb: current_mb,
          growth_rate_mb_per_hour: growth_rate,
          threshold: config.critical_mb_per_hour,
          action: "Memory leak suspected - investigate ETS tables and process memory"
        })
        
      growth_rate > config.warning_mb_per_hour ->
        escalate_alert(state, :memory_growth, :warning, %{
          current_mb: current_mb,
          growth_rate_mb_per_hour: growth_rate,
          threshold: config.warning_mb_per_hour
        })
        
      growth_rate < 0 ->
        clear_alert(state, :memory_growth)
        
      true ->
        state
    end
    
    Process.send_after(self(), :check_memory_growth, config.check_interval)
    {:noreply, update_memory_baseline(state, current_mb)}
  end
  
  defp escalate_alert(state, alert_key, severity, details) do
    count = Map.get(state.escalation_counts, alert_key, 0) + 1
    
    # Check suppression
    if suppressed?(state, alert_key) do
      state
    else
      # Send alert
      send_alert(alert_key, severity, Map.put(details, :escalation_count, count))
      
      # Update state
      %{state |
        alert_state: Map.put(state.alert_state, alert_key, severity),
        escalation_counts: Map.put(state.escalation_counts, alert_key, count),
        last_alert_times: Map.put(state.last_alert_times, alert_key, System.system_time(:second))
      }
    end
  end
  
  defp clear_alert(state, alert_key) do
    if Map.get(state.alert_state, alert_key) do
      send_recovery(alert_key)
      
      %{state |
        alert_state: Map.delete(state.alert_state, alert_key),
        escalation_counts: Map.delete(state.escalation_counts, alert_key)
      }
    else
      state
    end
  end
  
  defp send_alert(key, severity, details) do
    # Log locally
    Logger.warning("Alert triggered",
      key: key,
      severity: severity,
      details: details
    )
    
    # Send telemetry event
    :telemetry.execute(
      [:exchange, :alert, severity],
      %{count: 1},
      Map.merge(%{key: key}, details)
    )
    
    # Could integrate with PagerDuty, Slack, etc.
    notify_external(key, severity, details)
  end
  
  defp notify_external(key, :critical, details) do
    # Critical alerts go to PagerDuty or similar
    # Example: PagerDuty.trigger_incident(key, details)
    :ok
  end
  
  defp notify_external(key, :warning, details) do
    # Warnings go to Slack or email
    # Example: Slack.post_message("#alerts", format_alert(key, details))
    :ok
  end
end
```

## What We're NOT Building

- WebSocket for request/response patterns
- WebSocket-based trading (REST is safer and simpler)
- Complex reconnection strategies beyond WebSockex defaults
- Abstractions without multiple concrete uses
- Circuit breakers beyond simple fail-fast
- Message queuing or buffering
- Automated trading logic (just the API layer)

## Day-One Non-Negotiables (Expert Validated)

**MUST HAVE for MVP (Cannot Skip):**
1. ✅ **10-Second Dedup Buffer** - Simple :queue ring buffer for reconnects
2. ✅ **Subscription Tracking** - Remember channels to resubscribe after reconnect
3. ✅ **Kraken Nonce Counter** - Microseconds + counter prevents collisions
4. ✅ **ETS Cleanup** - Periodic cleanup prevents memory leaks
5. ✅ **Clock Sync Check** - Binance/Kraken reject >1000ms drift
6. ✅ **Exponential Backoff** - With jitter for REST calls

**DO NOT BUILD (Expert Says Remove):**
1. ❌ **WebSocket Authentication** - All public streams
2. ❌ **Listen Key Management** - Not needed for public data
3. ❌ **OAuth for WebSocket** - Deribit public doesn't need it
4. ❌ **Sequence Tracking** - Simple dedup is sufficient
5. ❌ **User Streams** - Use REST polling instead
6. ❌ **Order Updates via WS** - REST gives certainty

## Key Differences from v9.0 (Expert Review Applied)

### v10.0 Expert Simplifications:
1. **WebSocket Scope Reduction**: Public market data ONLY - removed all auth complexity
2. **REST Confidence**: `retry: :safe_transient` validated as correct approach
3. **Removed Components**: No listen keys, no OAuth for WS, no user streams
4. **Simplified Dedup**: 10-second buffer is sufficient, no sequence tracking needed
5. **Clear Separation**: WebSocket for broadcast data, REST for everything important

### Previous v9.0 Improvements:
1. **Library on Hex.pm**: Using `zen_websocket` from Hex
2. **Discovery-Based Implementation**: Explore ZenWebsocket's actual API
3. **4-Day Timeline**: Includes WebSocket library discovery phase
4. **Safer Exponential Backoff**: Proper jitter and capping
5. **Deduplication with :queue**: Erlang :queue for ring buffer

## Architecture Optimizations

**Module Consolidation:**
- Merge Storage into Cache (both are ETS operations)
- Merge Registry into Supervisor (use named processes)
- Use ETS atomic counters for RateLimit (no GenServer needed)

**Potential zen_websocket Enhancements (Since We Control It):**
```elixir
# Consider adding exchange-specific adapters to zen_websocket itself
defmodule ZenWebsocket.Adapters.Binance do
  @behaviour ZenWebsocket.Adapter

  def handle_frame({:text, data}, state) do
    # Binance-specific parsing
    {:ok, Jason.decode!(data), state}
  end

  def heartbeat_message(_state), do: {:ping, ""}
end

defmodule ZenWebsocket.Adapters.Kraken do
  @behaviour ZenWebsocket.Adapter

  def handle_frame({:binary, compressed}, state) do
    # Kraken binary decompression
    uncompressed = :zlib.uncompress(compressed)
    {:ok, Jason.decode!(uncompressed), state}
  end

  def heartbeat_message(_state) do
    {:text, Jason.encode!(%{"event" => "ping"})}
  end
end

# Built-in deduplication if commonly needed
defmodule ZenWebsocket.Dedup do
  # Could be added as optional middleware
end
```

**Add Health Module:**
```elixir
defmodule Exchange.Health do
  # Clock sync monitoring
  def check_time_sync do
    server_time = get_server_time(:binance)
    local_time = System.system_time(:millisecond)
    drift = abs(server_time - local_time)
    if drift > 1000, do: {:error, {:clock_drift, drift}}
  end

  # Connection health per exchange
  def check_connections do
    Enum.map([:binance, :kraken, :deribit], fn exchange ->
      {exchange, GenServer.call({:via, Registry, {Exchange.Registry, exchange}}, :ping)}
    end)
  end
end
```

## WebSockex Adapter Implementation Strategy

### Why WebSockex Adapter?
- **Built for trading systems**: Designed specifically for financial/HFT use cases (per GitHub description)
- **Production-tested reconnection**: Exponential backoff with state preservation
- **Gun transport**: More reliable than plain WebSockex
- **Minimal API**: Only 5 public functions (connect, send_message, close, subscribe, reconnect)
- **Reference implementation**: Includes working Deribit adapter example

### Learning from Other Implementations

**What ccxt Does Well:**
- Unified error codes across 400+ exchanges
- Request/response logging for debugging
- Automatic timestamp synchronization
- Proxy support for rate limit distribution

**What freqtrade Does Well:**
- Caches order book depth intelligently
- Implements circuit breakers per exchange
- Handles partial fills and order updates
- Graceful degradation when APIs fail

**What We'll Adopt:**
- Unified error handling (like ccxt)
- Simple circuit breaker (like freqtrade)
- Comprehensive logging (both projects)
- Test against real APIs first (WebSockex Adapter philosophy)

### Public Market Data Subscriptions (SIMPLIFIED)

**Expert Note**: These are PUBLIC subscriptions - no auth tokens, no signatures, no complexity. Just connect and subscribe.

**Binance Public Funding (NO AUTH):**
```elixir
def subscribe_binance(client) do
  # Simple public subscription - no auth needed!
  msg = %{
    "method" => "SUBSCRIBE",
    "params" => ["!markPrice@arr"],  # All symbols funding rates
    "id" => 1
  }
  # Just send it - no auth wrapper needed
  ZenWebsocket.send_frame(client, {:text, Jason.encode!(msg)})
end
```

**Kraken Public Ticker (NO AUTH):**
```elixir
def subscribe_kraken(client) do
  # Direct subscription to public data
  msg = %{
    "event" => "subscribe",
    "pair" => ["XBT/USD", "ETH/USD"],
    "subscription" => %{"name" => "ticker"}
  }
  ZenWebsocket.send_frame(client, {:text, Jason.encode!(msg)})
end
```

**Deribit Public Ticker (NO AUTH):**
```elixir
def subscribe_deribit(client) do
  # Public method - no OAuth needed!
  msg = %{
    "jsonrpc" => "2.0",
    "method" => "public/subscribe",
    "params" => %{
      "channels" => ["ticker.BTC-PERPETUAL.100ms"]
    },
    "id" => 1
  }
  ZenWebsocket.send_frame(client, {:text, Jason.encode!(msg)})
end
```

**That's it! No auth tokens, no signatures, no OAuth - just subscribe to public channels.**

## Useful References for Implementation

### Documentation
- [Binance API Documentation](https://binance-docs.github.io/apidocs/spot/en/)
- [Kraken REST API](https://docs.kraken.com/rest/)
- [Kraken WebSocket API](https://docs.kraken.com/websockets/)
- [Deribit API v2](https://docs.deribit.com/v2/)

### ZenWebsocket Resources (PRIORITY)
- [ZenWebsocket on Hex](https://hex.pm/packages/zen_websocket) - Official package
- [Documentation](https://hexdocs.pm/zen_websocket) - API documentation
- [Examples Guide](https://github.com/ZenHive/zen_websocket/blob/main/docs/Examples.md) - **START HERE** - Concrete usage examples
- [GitHub Repository](https://github.com/ZenHive/zen_websocket) - Source code
- [Test Files](https://github.com/ZenHive/zen_websocket/tree/main/test) - Learn from test patterns

### Reference Implementations to Study
- [ccxt Source Code](https://github.com/ccxt/ccxt/tree/master/js/src) - See exchange-specific quirks
- [binance-connector-python](https://github.com/binance/binance-connector-python) - Official patterns

### Common Issues & Solutions
- [Binance API GitHub Issues](https://github.com/binance/binance-spot-api-docs/issues) - Clock drift, weight limits
- [Kraken Support Articles](https://support.kraken.com/hc/en-us/sections/360003946512) - Nonce errors, rate limits

## Implementation Strategy

### Phase 1: MANDATORY ZenWebsocket Discovery (Day 2 Morning)

**CRITICAL**: This discovery phase is NON-NEGOTIABLE. ZenWebsocket is not in AI training data.

1. **Install and Explore**:
   - Add zen_websocket from Hex
   - Read HexDocs thoroughly
   - Study the source code

2. **Hands-On Testing**:
   - Connect to echo.websocket.org
   - Test all connection methods
   - Try different frame types (text, binary, ping/pong)
   - Verify reconnection behavior

3. **Document Findings**:
   - Record actual API methods (not assumptions)
   - Note message routing patterns
   - Document error handling approaches
   - Create working examples

4. **Exchange-Specific Testing**:
   - Test with Binance public stream
   - Verify Kraken binary frame handling
   - Check Deribit JSON-RPC patterns

**Why This Cannot Be Skipped**:
- AI models don't know zen_websocket's actual API
- Assumptions will lead to non-working code
- The library may have unexpected patterns
- Real testing prevents wasted implementation time

### Phase 2: Prototype (Day 2 Afternoon)
1. Create minimal Exchange.MarketData with discovered patterns
2. Connect to Binance public stream first (simplest)
3. Verify message receipt and parsing
4. Test reconnection by killing connection

### Phase 3: Production (Days 3-4)
1. Implement all three exchanges with proper patterns
2. Add deduplication, health checks, monitoring
3. Integration with REST modules
4. Full system testing

This plan provides pragmatic simplicity while acknowledging we need to discover ZenWebsocket's actual implementation patterns through exploration rather than assumption.

IMPORTANT NOTE:
We use the `zen_websocket` package from Hex.pm (formerly WebSockex Adapter) for our WebSocket implementation.
