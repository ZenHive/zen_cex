# CEX Implementation Tasks - AI Coder Reference

## CRITICAL: Read This First
This document is optimized for AI/LLM code generation. Follow instructions EXACTLY as written.

## Project Context
- **Type**: Elixir library for cryptocurrency exchange integration
- **Exchanges**: Binance, Kraken, Deribit
- **Architecture**: Plugin-based with isolated adapters
- **Status**: Reference implementation exists, building new plugin architecture

## File Structure Requirements
```
lib/zen_cex/
├── core/                    # Create these directories
│   ├── http.ex             # ~50 lines
│   ├── registry.ex         # ~30 lines
│   ├── supervisor.ex       # ~40 lines
│   ├── circuit.ex          # ~150 lines
│   └── health.ex           # ~120 lines
├── behaviors/              # Create these directories
│   ├── adapter.ex          # Define callbacks
│   ├── auth.ex            # Authentication contract
│   ├── rate_limiter.ex    # Rate limiting contract
│   ├── market_data.ex     # WebSocket contract
│   └── parser.ex          # Parsing contract
└── adapters/              # Create these directories
    ├── binance/           # Binance implementation
    ├── kraken/            # Kraken implementation
    └── deribit/           # Deribit implementation
```

## Day 1: Foundation Implementation

### Task 1.1: Create Core.Registry Module
**File**: `lib/zen_cex/core/registry.ex`
**Lines**: ~30
**Dependencies**: None

```elixir
defmodule ZenCex.Core.Registry do
  @moduledoc """
  Compile-time adapter registry with validation.
  """
  
  @adapters %{
    binance: ZenCex.Adapters.Binance.Adapter,
    kraken: ZenCex.Adapters.Kraken.Adapter,
    deribit: ZenCex.Adapters.Deribit.Adapter
  }
  
  # Validate at compile time
  for {name, module} <- @adapters do
    unless Code.ensure_loaded?(module) do
      raise "Adapter #{module} for #{name} not found"
    end
  end
  
  def get_adapter!(exchange) do
    @adapters[exchange] || raise "Unknown exchange: #{exchange}"
  end
  
  def list_exchanges, do: Map.keys(@adapters)
end
```

### Task 1.2: Create Core.HTTP Module
**File**: `lib/zen_cex/core/http.ex`
**Lines**: ~50
**Dependencies**: `{:req, "~> 0.5"}`, `{:finch, "~> 0.18"}`

```elixir
defmodule ZenCex.Core.HTTP do
  @moduledoc """
  Thin REQ coordinator. Adapters handle specifics.
  """
  
  def base_request(exchange, operation_type \\ :standard) do
    adapter = ZenCex.Core.Registry.get_adapter!(exchange)
    
    receive_timeout = case operation_type do
      :trading -> 2_000
      :market -> 5_000
      :historical -> 30_000
      _ -> 5_000
    end
    
    Req.new(
      base_url: adapter.base_url(:prod),
      finch: ZenCex.Finch,
      retry: :safe_transient,
      retry_delay: &exponential_backoff_with_jitter/1,
      max_retries: 3,
      receive_timeout: receive_timeout
    )
    |> Req.Request.register_options([:exchange, :operation_type])
    |> Req.Request.merge(exchange: exchange, operation_type: operation_type)
  end
  
  defp exponential_backoff_with_jitter(n) do
    base_ms = min(1000 * (2 ** min(n, 10)), 60_000)
    jitter_ms = :rand.uniform(500)
    min(base_ms + jitter_ms, 60_000)
  end
end
```

### Task 1.3: Define Behaviors
**File**: `lib/zen_cex/behaviors/adapter.ex`
**Lines**: ~20

```elixir
defmodule ZenCex.Behaviors.Adapter do
  @callback base_url(atom()) :: String.t()
  @callback get_positions(map()) :: {:ok, list()} | {:error, term()}
  @callback get_balances(map()) :: {:ok, list()} | {:error, term()}
  
  @optional_callbacks place_order: 4, cancel_order: 2
end
```

### Task 1.4: Implement Binance Adapter
**Directory**: Create `lib/zen_cex/adapters/binance/`
**Files to create**:

#### `lib/zen_cex/adapters/binance/adapter.ex`
```elixir
defmodule ZenCex.Adapters.Binance.Adapter do
  @behaviour ZenCex.Behaviors.Adapter
  
  @impl true
  def base_url(:prod), do: "https://api.binance.com"
  def base_url(:test), do: "https://testnet.binance.vision"
  
  @impl true
  def get_positions(params) do
    # Implementation here
  end
  
  @impl true
  def get_balances(params) do
    # Implementation here
  end
end
```

#### `lib/zen_cex/adapters/binance/auth.ex`
```elixir
defmodule ZenCex.Adapters.Binance.Auth do
  @behaviour ZenCex.Behaviors.Auth
  
  @impl true
  def sign_request(request, _opts) do
    timestamp = System.system_time(:millisecond)
    params = Map.put(request.params, "timestamp", timestamp)
    
    query_string = URI.encode_query(params)
    signature = generate_signature(query_string)
    
    params = Map.put(params, "signature", signature)
    headers = [{"X-MBX-APIKEY", get_api_key()}]
    
    %{request | params: params, headers: headers ++ request.headers}
  end
  
  defp generate_signature(data) do
    secret = System.get_env("BINANCE_API_SECRET")
    :crypto.mac(:hmac, :sha256, secret, data)
    |> Base.encode16(case: :lower)
  end
  
  defp get_api_key do
    System.get_env("BINANCE_API_KEY")
  end
end
```

#### `lib/zen_cex/adapters/binance/rate_limiter.ex`
```elixir
defmodule ZenCex.Adapters.Binance.RateLimiter do
  @behaviour ZenCex.Behaviors.RateLimiter
  
  @spot_limit 1200
  @futures_limit 2400
  @window_seconds 60
  
  @impl true
  def check_and_increment(endpoint, weight \\ 1) do
    table = get_table(endpoint)
    limit = get_limit(endpoint)
    now = System.system_time(:second)
    
    cleanup_old_windows(table, now - @window_seconds - 10)
    
    case :ets.update_counter(table, now, {2, weight}, {now, 0}) do
      count when count > limit -> {:error, :rate_limited}
      _ -> :ok
    end
  end
  
  defp get_table("/fapi" <> _), do: :binance_futures_limits
  defp get_table(_), do: :binance_spot_limits
  
  defp get_limit("/fapi" <> _), do: @futures_limit
  defp get_limit(_), do: @spot_limit
  
  defp cleanup_old_windows(table, cutoff) do
    :ets.select_delete(table, [
      {{:"$1", :"$2"}, [{:<, :"$1", cutoff}], [true]}
    ])
  end
end
```

## Day 2: Kraken and Deribit Adapters

### Task 2.1: Kraken Adapter Implementation
**Directory**: Create `lib/zen_cex/adapters/kraken/`

#### Critical Kraken Requirements:
1. **MUST use microsecond + counter for nonce** (not just microseconds)
2. **MUST force HTTP/1.1** (Kraken has HTTP/2 issues)
3. **MUST handle binary WebSocket frames** (zlib/gzip compression)

#### `lib/zen_cex/adapters/kraken/auth.ex`
```elixir
defmodule ZenCex.Adapters.Kraken.Auth do
  use Agent
  
  def start_link(_) do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end
  
  def generate_nonce do
    Agent.get_and_update(__MODULE__, fn counter ->
      nonce = System.os_time(:microsecond) * 1000 + counter
      {nonce, rem(counter + 1, 1000)}
    end)
  end
  
  def sign_request(request, endpoint) do
    nonce = generate_nonce()
    api_key = System.get_env("KRAKEN_API_KEY")
    api_secret = System.get_env("KRAKEN_API_SECRET")
    
    post_data = "nonce=#{nonce}" <> URI.encode_query(request.params)
    message = "#{nonce}#{post_data}"
    
    path_hash = :crypto.hash(:sha256, "/0/private/#{endpoint}#{message}")
    decoded_secret = Base.decode64!(api_secret)
    signature = :crypto.mac(:hmac, :sha512, decoded_secret, path_hash)
    |> Base.encode64()
    
    headers = [
      {"API-Key", api_key},
      {"API-Sign", signature}
    ]
    
    %{request | 
      body: post_data,
      headers: headers ++ request.headers,
      method: :post
    }
  end
end
```

### Task 2.2: Deribit OAuth Implementation
**File**: `lib/zen_cex/adapters/deribit/auth.ex`

#### Critical Deribit Requirements:
1. **MUST refresh OAuth token 120 seconds before expiry**
2. **MUST implement single-flight protection** (prevent concurrent refreshes)
3. **ALL endpoints use JSON-RPC format**

```elixir
defmodule ZenCex.Adapters.Deribit.Auth do
  use GenServer
  
  defstruct [:token, :expires_at, :refreshing, :waiting_pids]
  
  def get_token do
    GenServer.call(__MODULE__, :get_token)
  end
  
  def handle_call(:get_token, from, %{refreshing: true} = state) do
    # Add to waiting list if already refreshing
    {:noreply, %{state | waiting_pids: [from | state.waiting_pids]}}
  end
  
  def handle_call(:get_token, _from, %{token: token, expires_at: expires_at} = state) do
    now = System.system_time(:second)
    
    if expires_at - now < 120 do
      # Refresh if less than 120 seconds remaining
      {:noreply, refresh_token(state), {:continue, :notify_waiters}}
    else
      {:reply, {:ok, token}, state}
    end
  end
  
  defp refresh_token(state) do
    %{state | refreshing: true}
    |> do_refresh()
  end
  
  defp do_refresh(state) do
    # OAuth refresh logic here
    client_id = System.get_env("DERIBIT_CLIENT_ID")
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")
    
    # Make OAuth request...
    # Return updated state with new token
  end
end
```

## Day 3: WebSocket Implementation

### CRITICAL: ZenWebsocket Discovery Required
**WARNING**: ZenWebsocket is NOT in AI training data. You MUST:
1. Read the actual library documentation
2. Test with echo servers first
3. Document the actual API before implementing

### Task 3.1: WebSocket Discovery Phase
```bash
# Add to mix.exs
{:zen_websocket, "~> 0.1.0"}

# Test connection
iex> {:ok, conn} = ZenWebsocket.connect("wss://echo.websocket.org")
# Document actual response format

# Test message sending
iex> ZenWebsocket.send_frame(conn, {:text, "test"})
# Document actual API

# Test callbacks
# Document how the library handles callbacks
```

### Task 3.2: Market Data Implementation
**File**: `lib/zen_cex/adapters/binance/market_data.ex`

```elixir
defmodule ZenCex.Adapters.Binance.MarketData do
  use GenServer
  
  @public_ws_url "wss://fstream.binance.com/ws"
  
  def init(opts) do
    state = %{
      url: @public_ws_url,
      subscriptions: [],
      dedup_buffer: :queue.new(),
      last_message_time: System.monotonic_time(:millisecond)
    }
    
    {:ok, state, {:continue, :connect}}
  end
  
  def handle_continue(:connect, state) do
    # Use actual ZenWebsocket API discovered in Task 3.1
    {:noreply, state}
  end
  
  def handle_frame({:text, json}, state) do
    data = Jason.decode!(json)
    
    # Simple deduplication
    hash = :erlang.phash2(data)
    {is_dup, new_buffer} = check_duplicate(hash, state.dedup_buffer)
    
    unless is_dup do
      # Broadcast to subscribers
      broadcast_update(data, state)
    end
    
    {:noreply, %{state | 
      dedup_buffer: new_buffer,
      last_message_time: System.monotonic_time(:millisecond)
    }}
  end
  
  defp check_duplicate(hash, buffer) do
    now = System.monotonic_time(:millisecond)
    cutoff = now - 10_000  # 10 second window
    
    # Clean old entries
    cleaned = drop_old_entries(buffer, cutoff)
    
    # Check if hash exists
    entries = :queue.to_list(cleaned)
    is_dup = Enum.any?(entries, fn {h, _t} -> h == hash end)
    
    if is_dup do
      {true, cleaned}
    else
      new_buffer = :queue.in({hash, now}, cleaned)
      # Limit to 1000 entries
      final = if :queue.len(new_buffer) > 1000 do
        {_, smaller} = :queue.out(new_buffer)
        smaller
      else
        new_buffer
      end
      {false, final}
    end
  end
end
```

## Testing Requirements

### Integration Test Template
```elixir
defmodule ZenCex.Adapters.Binance.IntegrationTest do
  use ExUnit.Case
  
  @tag :integration
  test "real API authentication" do
    # MUST test against real Binance API
    request = build_test_request()
    signed = ZenCex.Adapters.Binance.Auth.sign_request(request, [])
    
    assert signed.headers["X-MBX-APIKEY"]
    assert signed.params["signature"]
    assert signed.params["timestamp"]
  end
  
  @tag :integration
  test "rate limiting with real endpoints" do
    # MUST verify rate limit tracking
    endpoint = "/api/v3/account"
    
    assert :ok = ZenCex.Adapters.Binance.RateLimiter.check_and_increment(endpoint)
    
    # Simulate hitting limit
    for _ <- 1..1200 do
      ZenCex.Adapters.Binance.RateLimiter.check_and_increment(endpoint)
    end
    
    assert {:error, :rate_limited} = 
      ZenCex.Adapters.Binance.RateLimiter.check_and_increment(endpoint)
  end
end
```

## Environment Variables Required
```bash
# Binance
export BINANCE_API_KEY="your_key"
export BINANCE_API_SECRET="your_secret"

# Kraken
export KRAKEN_API_KEY="your_key"
export KRAKEN_API_SECRET="your_secret"

# Deribit
export DERIBIT_CLIENT_ID="your_client_id"
export DERIBIT_CLIENT_SECRET="your_secret"
export DERIBIT_HOST="test.deribit.com"  # or www.deribit.com
```

## Critical Implementation Rules

### MUST IMPLEMENT:
1. **Deduplication buffer**: 10-second window using :queue
2. **Kraken nonce**: Microsecond + counter (NOT just microseconds)
3. **ETS cleanup**: Every 60 seconds to prevent memory leaks
4. **Clock sync check**: Reject if drift > 1000ms
5. **Exponential backoff**: With jitter for REST retries
6. **OAuth refresh**: 120 seconds before expiry for Deribit

### MUST NOT IMPLEMENT:
1. **NO WebSocket authentication** - Public streams only
2. **NO listen keys** - Not needed for public data
3. **NO user streams** - Use REST polling instead
4. **NO order updates via WebSocket** - REST only for certainty
5. **NO complex sequence tracking** - Simple dedup is sufficient
6. **NO trading over WebSocket** - ALL trading via REST

## Validation Checklist

### Before marking Day 1 complete:
- [ ] Core.Registry compiles and validates adapters
- [ ] Core.HTTP creates REQ requests with backoff
- [ ] All behaviors defined with @callback
- [ ] Binance adapter implements all behaviors
- [ ] Binance auth generates valid HMAC-SHA256
- [ ] Binance rate limiter tracks spot vs futures
- [ ] Integration tests pass against real API

### Before marking Day 2 complete:
- [ ] Kraken uses microsecond + counter nonce
- [ ] Kraken forces HTTP/1.1 connections
- [ ] Deribit OAuth refreshes 120s before expiry
- [ ] Deribit implements single-flight protection
- [ ] All adapters have integration tests

### Before marking Day 3 complete:
- [ ] ZenWebsocket API documented from testing
- [ ] WebSocket connects to public endpoints only
- [ ] Deduplication buffer limits to 10 seconds
- [ ] Binary frames handled for Kraken
- [ ] Heartbeat/ping implemented for all exchanges