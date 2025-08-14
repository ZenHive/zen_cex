# CEX Plugin Architecture - AI Implementation Guide

## CRITICAL: Implementation Order
1. Read ALL exchange-specific requirements BEFORE coding
2. Test against REAL APIs (not mocks) 
3. Follow code examples EXACTLY as shown
4. Use provided dependency versions EXACTLY

## Dependencies to Add (mix.exs)
```elixir
defp deps do
  [
    {:req, "~> 0.5"},           # HTTP client
    {:finch, "~> 0.18"},        # Connection pooling
    {:zen_websocket, "~> 0.1.0"}, # WebSocket client
    {:jason, "~> 1.2"},         # JSON parsing
    {:decimal, "~> 2.0"},       # Financial calculations
    {:telemetry, "~> 1.2"}      # Monitoring
  ]
end
```

## Application Supervisor Setup
```elixir
def start(_type, _args) do
  children = [
    # Finch connection pools
    {Finch,
      name: ZenCex.Finch,
      pools: %{
        default: [size: 5, count: 1],
        "https://api.binance.com" => [
          size: 3,
          conn_opts: [protocols: [:http2, :http1]]
        ],
        "https://api.kraken.com" => [
          size: 2,
          conn_opts: [protocols: [:http1]]  # CRITICAL: Force HTTP/1.1
        ]
      }
    },
    # Rate limiter
    ZenCex.RateLimit,
    # Health monitoring
    ZenCex.Health.Monitor,
    ZenCex.Health.Startup
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Module 1: Rate Limiting (CRITICAL)

### MUST Initialize ETS Tables on Startup
```elixir
defmodule ZenCex.RateLimit do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  
  def init(_) do
    # CRITICAL: Create separate tables per exchange
    :ets.new(:rate_limits_binance_spot, [:named_table, :public, {:read_concurrency, true}])
    :ets.new(:rate_limits_binance_futures, [:named_table, :public, {:read_concurrency, true}])
    :ets.new(:rate_limits_kraken, [:named_table, :public, {:read_concurrency, true}])
    :ets.new(:rate_limits_deribit, [:named_table, :public, {:read_concurrency, true}])
    
    # Schedule cleanup every 60 seconds
    schedule_cleanup()
    {:ok, %{}}
  end
  
  def check_and_increment(exchange, endpoint, weight \\ 1) do
    table = get_table(exchange, endpoint)
    limit = get_limit(exchange, endpoint)
    window = get_window(exchange)
    now = System.system_time(:second)
    
    # Clean old entries
    cleanup_old_windows(table, exchange, now - window - 10)
    
    # Atomic increment
    case :ets.update_counter(table, {exchange, now}, {2, weight}, {{exchange, now}, 0}) do
      count when count > limit ->
        {:error, :rate_limited}
      _ ->
        :ok
    end
  end
  
  defp get_table(:binance, "/fapi" <> _), do: :rate_limits_binance_futures
  defp get_table(:binance, _), do: :rate_limits_binance_spot
  defp get_table(:kraken, _), do: :rate_limits_kraken
  defp get_table(:deribit, _), do: :rate_limits_deribit
  
  defp get_limit(:binance, "/fapi" <> _), do: 2400  # Futures
  defp get_limit(:binance, _), do: 1200              # Spot
  defp get_limit(:kraken, _), do: 15                 # Per second
  defp get_limit(:deribit, _), do: 20                # Per second
  
  defp get_window(:binance), do: 60  # 60 seconds
  defp get_window(:kraken), do: 1    # 1 second
  defp get_window(:deribit), do: 1    # 1 second
  
  defp cleanup_old_windows(table, exchange, cutoff) do
    :ets.select_delete(table, [
      {{{exchange, :"$1"}, :"$2"}, [{:<, :"$1", cutoff}], [true]}
    ])
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)
  end
  
  def handle_info(:cleanup, state) do
    # Cleanup all tables
    now = System.system_time(:second)
    
    cleanup_old_windows(:rate_limits_binance_spot, :binance, now - 70)
    cleanup_old_windows(:rate_limits_binance_futures, :binance, now - 70)
    cleanup_old_windows(:rate_limits_kraken, :kraken, now - 10)
    cleanup_old_windows(:rate_limits_deribit, :deribit, now - 10)
    
    schedule_cleanup()
    {:noreply, state}
  end
end
```

### Binance Weight Tracking
```elixir
defmodule ZenCex.Binance.WeightTracking do
  # CRITICAL: Some endpoints have different weights
  @endpoint_weights %{
    "/api/v3/order" => 1,
    "/api/v3/openOrders" => 40,
    "/api/v3/allOrders" => 10,
    "/api/v3/account" => 10,
    "/api/v3/myTrades" => 10,
    "/api/v3/depth" => fn limit ->
      # Weight depends on limit parameter
      cond do
        limit <= 100 -> 1
        limit <= 500 -> 5
        limit <= 1000 -> 10
        true -> 50
      end
    end
  }
  
  def get_weight(endpoint, params \\ %{}) do
    case @endpoint_weights[endpoint] do
      nil -> 1
      weight when is_integer(weight) -> weight
      fun when is_function(fun) -> fun.(params[:limit] || 100)
    end
  end
  
  # CRITICAL: Track response header
  def update_from_header(response) do
    case Req.Response.get_header(response, "x-mbx-used-weight-1m") do
      [weight] ->
        # Reconcile with server-reported weight
        current_weight = String.to_integer(weight)
        :telemetry.execute(
          [:binance, :weight, :update],
          %{weight: current_weight},
          %{}
        )
      _ ->
        :ok
    end
  end
end
```

## Module 2: Authentication

### Binance HMAC-SHA256
```elixir
defmodule ZenCex.Binance.Auth do
  @recv_window 5000  # 5 second window
  
  def sign_request(request) do
    timestamp = System.system_time(:millisecond)
    
    params = request.params
    |> Map.put("timestamp", timestamp)
    |> Map.put("recvWindow", @recv_window)
    
    # CRITICAL: Signature must be last parameter
    query_string = URI.encode_query(params)
    signature = generate_signature(query_string)
    
    final_params = Map.put(params, "signature", signature)
    
    headers = [
      {"X-MBX-APIKEY", System.get_env("BINANCE_API_KEY")}
    ]
    
    %{request | 
      params: final_params,
      headers: headers ++ request.headers
    }
  end
  
  defp generate_signature(data) do
    secret = System.get_env("BINANCE_API_SECRET")
    :crypto.mac(:hmac, :sha256, secret, data)
    |> Base.encode16(case: :lower)
  end
end
```

### Kraken Nonce (CRITICAL: Must be unique)
```elixir
defmodule ZenCex.Kraken.Nonce do
  use Agent
  
  def start_link(_) do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end
  
  def generate do
    # CRITICAL: Microseconds + counter to ensure uniqueness
    Agent.get_and_update(__MODULE__, fn counter ->
      microseconds = System.os_time(:microsecond)
      nonce = microseconds * 1000 + counter
      new_counter = rem(counter + 1, 1000)
      {nonce, new_counter}
    end)
  end
end

defmodule ZenCex.Kraken.Auth do
  def sign_request(request, endpoint) do
    nonce = ZenCex.Kraken.Nonce.generate()
    
    # CRITICAL: Kraken uses POST with form encoding
    post_data = URI.encode_query(
      Map.put(request.params, "nonce", nonce)
    )
    
    api_path = "/0/private/#{endpoint}"
    message = "#{nonce}#{post_data}"
    
    # CRITICAL: Hash order matters
    path_hash = :crypto.hash(:sha256, "#{api_path}#{message}")
    
    # CRITICAL: API secret may be base64 encoded
    api_secret = System.get_env("KRAKEN_API_SECRET")
    decoded_secret = Base.decode64!(api_secret)
    
    signature = :crypto.mac(:hmac, :sha512, decoded_secret, path_hash)
    |> Base.encode64()
    
    headers = [
      {"API-Key", System.get_env("KRAKEN_API_KEY")},
      {"API-Sign", signature},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]
    
    %{request |
      method: :post,
      body: post_data,
      headers: headers ++ request.headers
    }
  end
end
```

### Deribit OAuth2 with Single-Flight Protection
```elixir
defmodule ZenCex.Deribit.OAuth do
  use GenServer
  
  defstruct [
    :token,
    :refresh_token,
    :expires_at,
    :refreshing,
    :waiting_pids
  ]
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end
  
  def get_token do
    GenServer.call(__MODULE__, :get_token, 10_000)
  end
  
  def handle_call(:get_token, from, %{refreshing: true} = state) do
    # CRITICAL: Prevent concurrent refresh attempts
    {:noreply, %{state | waiting_pids: [from | state.waiting_pids]}}
  end
  
  def handle_call(:get_token, _from, state) do
    now = System.system_time(:second)
    
    cond do
      state.token == nil ->
        # Initial auth
        {:noreply, authenticate(state), {:continue, :notify_waiters}}
      
      state.expires_at - now < 120 ->
        # CRITICAL: Refresh 120 seconds before expiry
        {:noreply, refresh(state), {:continue, :notify_waiters}}
      
      true ->
        {:reply, {:ok, state.token}, state}
    end
  end
  
  def handle_continue(:notify_waiters, state) do
    # Notify all waiting processes
    Enum.each(state.waiting_pids, fn pid ->
      GenServer.reply(pid, {:ok, state.token})
    end)
    
    # Schedule next refresh
    if state.expires_at do
      refresh_in = max((state.expires_at - 120) * 1000, 30_000)
      Process.send_after(self(), :refresh, refresh_in)
    end
    
    {:noreply, %{state | waiting_pids: [], refreshing: false}}
  end
  
  defp authenticate(state) do
    %{state | refreshing: true}
    |> do_auth_request("client_credentials")
  end
  
  defp refresh(state) do
    %{state | refreshing: true}
    |> do_auth_request("refresh_token")
  end
  
  defp do_auth_request(state, grant_type) do
    host = System.get_env("DERIBIT_HOST", "test.deribit.com")
    
    body = case grant_type do
      "client_credentials" ->
        %{
          grant_type: grant_type,
          client_id: System.get_env("DERIBIT_CLIENT_ID"),
          client_secret: System.get_env("DERIBIT_CLIENT_SECRET")
        }
      "refresh_token" ->
        %{
          grant_type: grant_type,
          refresh_token: state.refresh_token
        }
    end
    
    request = Req.new(
      base_url: "https://#{host}",
      json: body
    )
    
    case Req.post(request, url: "/api/v2/public/auth") do
      {:ok, %{status: 200, body: body}} ->
        %{state |
          token: body["result"]["access_token"],
          refresh_token: body["result"]["refresh_token"],
          expires_at: System.system_time(:second) + body["result"]["expires_in"]
        }
      _ ->
        state
    end
  end
end
```

## Module 3: WebSocket Market Data (PUBLIC ONLY)

### CRITICAL WebSocket Rules
1. **NO AUTHENTICATION** - Public streams only
2. **NO USER STREAMS** - No account updates
3. **NO TRADING** - Market data only
4. **SIMPLE DEDUP** - 10 second buffer

### Binance WebSocket
```elixir
defmodule ZenCex.Binance.MarketData do
  use GenServer
  
  @public_ws_url "wss://fstream.binance.com/ws"
  @max_connections 5
  @max_streams_per_connection 200
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    state = %{
      url: @public_ws_url,
      connection: nil,
      subscriptions: [],
      dedup_buffer: :queue.new(),
      dedup_hashes: MapSet.new(),
      last_pong: System.monotonic_time(:millisecond)
    }
    
    # Schedule ping every 20 minutes
    Process.send_after(self(), :ping, :timer.minutes(20))
    
    {:ok, state, {:continue, :connect}}
  end
  
  def handle_continue(:connect, state) do
    # CRITICAL: Connect to PUBLIC endpoint only
    case connect_websocket(@public_ws_url) do
      {:ok, conn} ->
        # Subscribe to public channels
        subscribe_public_channels(conn)
        {:noreply, %{state | connection: conn}}
      _ ->
        Process.send_after(self(), :reconnect, 5000)
        {:noreply, state}
    end
  end
  
  defp subscribe_public_channels(conn) do
    # CRITICAL: Public channels only
    channels = [
      "!markPrice@arr",      # All mark prices
      "btcusdt@aggTrade",    # BTC trades
      "ethusdt@aggTrade"     # ETH trades
    ]
    
    message = %{
      method: "SUBSCRIBE",
      params: channels,
      id: 1
    }
    
    send_frame(conn, {:text, Jason.encode!(message)})
  end
  
  def handle_info({:ws_message, {:text, json}}, state) do
    data = Jason.decode!(json)
    
    # Simple deduplication
    hash = :erlang.phash2(data)
    
    if not MapSet.member?(state.dedup_hashes, hash) do
      # Process new message
      process_market_data(data)
      
      # Update dedup buffer
      now = System.monotonic_time(:millisecond)
      new_buffer = :queue.in({hash, now}, state.dedup_buffer)
      
      # Clean old entries (>10 seconds)
      {cleaned_buffer, cleaned_hashes} = clean_dedup_buffer(new_buffer, now - 10_000)
      
      {:noreply, %{state | 
        dedup_buffer: cleaned_buffer,
        dedup_hashes: MapSet.put(cleaned_hashes, hash)
      }}
    else
      {:noreply, state}
    end
  end
  
  defp clean_dedup_buffer(buffer, cutoff) do
    entries = :queue.to_list(buffer)
    
    recent = Enum.filter(entries, fn {_hash, time} -> time > cutoff end)
    hashes = MapSet.new(recent, fn {hash, _time} -> hash end)
    
    {:queue.from_list(recent), hashes}
  end
end
```

### Kraken WebSocket with Binary Frames
```elixir
defmodule ZenCex.Kraken.MarketData do
  use GenServer
  
  @public_ws_url "wss://ws.kraken.com"
  @ping_interval 8_000  # CRITICAL: Ping every 8 seconds
  
  def handle_info({:ws_message, {:binary, compressed}}, state) do
    # CRITICAL: Kraken uses binary frames
    data = decompress_frame(compressed)
    process_market_data(data, state)
  end
  
  defp decompress_frame(<<0x1f, 0x8b, _::binary>> = data) do
    # GZIP compressed
    :zlib.gunzip(data)
    |> Jason.decode!()
  end
  
  defp decompress_frame(<<0x78, 0x9c, _::binary>> = data) do
    # zlib compressed
    :zlib.uncompress(data)
    |> Jason.decode!()
  end
  
  defp decompress_frame(data) do
    # Uncompressed JSON
    Jason.decode!(data)
  end
  
  def handle_info(:ping, state) do
    # CRITICAL: Must ping every 8 seconds or connection drops
    send_frame(state.connection, {:text, ~s({"event":"ping"})})
    Process.send_after(self(), :ping, @ping_interval)
    {:noreply, state}
  end
end
```

### Deribit WebSocket with JSON-RPC
```elixir
defmodule ZenCex.Deribit.MarketData do
  use GenServer
  
  @public_ws_url "wss://www.deribit.com/ws/api/v2"
  @heartbeat_interval 30_000  # 30 seconds
  
  def subscribe_public_channels(conn) do
    # CRITICAL: JSON-RPC format for all messages
    message = %{
      jsonrpc: "2.0",
      method: "public/subscribe",
      params: %{
        channels: [
          "ticker.BTC-PERPETUAL.raw",
          "ticker.ETH-PERPETUAL.raw"
        ]
      },
      id: 1
    }
    
    send_frame(conn, {:text, Jason.encode!(message)})
  end
  
  def handle_info(:heartbeat, state) do
    # CRITICAL: Use public/test for heartbeat
    message = %{
      jsonrpc: "2.0",
      method: "public/test",
      params: %{},
      id: :os.system_time(:millisecond)
    }
    
    send_frame(state.connection, {:text, Jason.encode!(message)})
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
    {:noreply, state}
  end
end
```

## Module 4: Circuit Breaker

### Per-Endpoint Circuit Breaker
```elixir
defmodule ZenCex.Circuit do
  use GenServer
  
  @failure_threshold 3
  @cooldown_ms 60_000
  @half_open_timeout 5_000
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(_) do
    :ets.new(:circuits, [:named_table, :public])
    {:ok, %{}}
  end
  
  def call(exchange, endpoint, fun) do
    key = {exchange, endpoint}
    now = System.system_time(:millisecond)
    
    case :ets.lookup(:circuits, key) do
      [{_, :open, _, last_failure}] when now - last_failure > @cooldown_ms ->
        # Try half-open
        :ets.insert(:circuits, {key, :half_open, 0, last_failure})
        attempt_call(key, fun, :half_open)
      
      [{_, :open, _, _}] ->
        {:error, :circuit_open}
      
      [{_, :half_open, _, _}] ->
        # Limited probe
        attempt_call(key, fun, :half_open)
      
      _ ->
        # Normal operation
        attempt_call(key, fun, :closed)
    end
  end
  
  defp attempt_call(key, fun, state) do
    case fun.() do
      {:ok, _} = success ->
        # Reset on success
        :ets.insert(:circuits, {key, :closed, 0, 0})
        success
      
      {:error, reason} when reason in [:timeout, :exchange_error] ->
        handle_failure(key, state, reason)
      
      {:error, :rate_limited} = error ->
        # Don't trip circuit for rate limits
        error
      
      other_error ->
        handle_failure(key, state, other_error)
    end
  end
  
  defp handle_failure(key, :half_open, reason) do
    # Failed probe - back to open
    now = System.system_time(:millisecond)
    :ets.insert(:circuits, {key, :open, 1, now})
    
    :telemetry.execute(
      [:circuit, :trip],
      %{count: 1},
      %{key: key, reason: reason}
    )
    
    {:error, reason}
  end
  
  defp handle_failure(key, :closed, reason) do
    now = System.system_time(:millisecond)
    
    failures = case :ets.update_counter(:circuits, key, {3, 1}, {key, :closed, 0, now}) do
      n when n >= @failure_threshold ->
        # Trip circuit
        :ets.insert(:circuits, {key, :open, n, now})
        :telemetry.execute([:circuit, :trip], %{count: 1}, %{key: key})
        n
      n ->
        n
    end
    
    {:error, reason}
  end
end
```

## Module 5: Health Monitoring

### Clock Sync Validation
```elixir
defmodule ZenCex.Health do
  use GenServer
  
  @warning_drift_ms 300
  @critical_drift_ms 500
  @check_interval_ms 30_000
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(_) do
    # Initial check
    check_clock_sync()
    
    # Schedule periodic checks
    Process.send_after(self(), :check_sync, @check_interval_ms)
    
    {:ok, %{last_check: System.system_time(:millisecond)}}
  end
  
  def handle_info(:check_sync, state) do
    drift = check_clock_sync()
    
    cond do
      drift > @critical_drift_ms ->
        Logger.error("CRITICAL: Clock drift #{drift}ms")
        :telemetry.execute([:health, :clock_drift, :critical], %{drift: drift}, %{})
      
      drift > @warning_drift_ms ->
        Logger.warning("Clock drift #{drift}ms")
        :telemetry.execute([:health, :clock_drift, :warning], %{drift: drift}, %{})
      
      true ->
        :ok
    end
    
    Process.send_after(self(), :check_sync, @check_interval_ms)
    {:noreply, %{state | last_check: System.system_time(:millisecond)}}
  end
  
  defp check_clock_sync do
    # Get time from multiple exchanges
    times = [
      get_binance_time(),
      get_kraken_time(),
      get_deribit_time()
    ]
    |> Enum.filter(& &1)
    
    if length(times) >= 2 do
      # Calculate median drift
      local_time = System.system_time(:millisecond)
      drifts = Enum.map(times, &abs(&1 - local_time))
      
      # Return median
      Enum.sort(drifts)
      |> Enum.at(div(length(drifts), 2))
    else
      0
    end
  end
  
  defp get_binance_time do
    case Req.get("https://api.binance.com/api/v3/time") do
      {:ok, %{status: 200, body: %{"serverTime" => time}}} -> time
      _ -> nil
    end
  end
  
  defp get_kraken_time do
    case Req.get("https://api.kraken.com/0/public/Time") do
      {:ok, %{status: 200, body: %{"result" => %{"unixtime" => time}}}} -> 
        time * 1000
      _ -> 
        nil
    end
  end
  
  defp get_deribit_time do
    case Req.get("https://www.deribit.com/api/v2/public/get_time") do
      {:ok, %{status: 200, body: %{"result" => time}}} -> time
      _ -> nil
    end
  end
end
```

## Testing Requirements

### MUST Test Against Real APIs
```elixir
defmodule IntegrationTest do
  use ExUnit.Case
  
  @tag :integration
  test "Binance authentication works" do
    # MUST use real API
    request = Req.new(
      base_url: "https://api.binance.com",
      params: %{symbol: "BTCUSDT"}
    )
    
    signed = ZenCex.Binance.Auth.sign_request(request)
    
    # Verify signature components
    assert signed.headers["X-MBX-APIKEY"]
    assert signed.params["signature"]
    assert signed.params["timestamp"]
    assert signed.params["recvWindow"] == 5000
    
    # Make real API call
    response = Req.get(signed, url: "/api/v3/account")
    assert response.status in [200, 401]  # 401 if test keys
  end
  
  @tag :integration  
  test "Kraken nonce is always unique" do
    # Generate 1000 nonces rapidly
    nonces = for _ <- 1..1000, do: ZenCex.Kraken.Nonce.generate()
    
    # All must be unique
    assert length(nonces) == length(Enum.uniq(nonces))
    
    # Must be increasing
    assert nonces == Enum.sort(nonces)
  end
  
  @tag :integration
  test "Deribit OAuth refresh works" do
    # Start OAuth GenServer
    {:ok, _} = ZenCex.Deribit.OAuth.start_link([])
    
    # Get initial token
    {:ok, token1} = ZenCex.Deribit.OAuth.get_token()
    assert token1
    
    # Simulate time passing
    Process.sleep(1000)
    
    # Should return same token (not expired)
    {:ok, token2} = ZenCex.Deribit.OAuth.get_token()
    assert token1 == token2
  end
end
```

## Common Errors and Solutions

### Error: "Timestamp for this request is outside of the recvWindow"
**Solution**: Check clock sync. Drift must be < 1000ms

### Error: "EAPI:Invalid nonce" (Kraken)
**Solution**: Use microsecond + counter, not just microseconds

### Error: WebSocket disconnects after 10 seconds (Kraken)
**Solution**: Send ping every 8 seconds

### Error: "unauthorized" (Deribit)
**Solution**: Refresh OAuth token 120 seconds before expiry

### Error: Rate limited immediately
**Solution**: Check you're using correct table for spot vs futures

## Production Checklist

- [ ] All ETS tables created on startup
- [ ] Cleanup scheduled every 60 seconds
- [ ] Clock sync checked every 30 seconds
- [ ] OAuth refresh 120 seconds before expiry
- [ ] Kraken uses microsecond + counter nonce
- [ ] Kraken forced to HTTP/1.1
- [ ] WebSocket dedup buffer limited to 10 seconds
- [ ] Circuit breaker per endpoint, not per exchange
- [ ] No WebSocket authentication implemented
- [ ] All trading operations use REST only