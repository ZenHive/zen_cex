# TDD Helper for Elixir Libraries

You are helping to implement Test-Driven Development (TDD) for the ZenCex library following its testing philosophy.

**IMPORTANT**: Refer to AGENTS.md for essential testing requirements - especially the mandate to test against real testnet APIs only.

The user wants TDD for the following functionality: $ARGUMENTS. Ask for more clarity if not enough is provided.

## Instructions

1. **TDD Workflow**:
   - **Red**: Write failing test first
   - **Green**: Write minimal code to make test pass
   - **Refactor**: Improve code while keeping tests passing

2. **Test-First Approach**:
   - Start with business requirements
   - Write tests that describe expected behavior
   - Test against REAL testnet APIs first
   - Implement features to satisfy tests
   - Refactor with confidence

3. **ZenCex TDD Patterns**:

### **Integration Testing (Real APIs First)**
```elixir
# Test against REAL testnet API first
test "get_balances returns real testnet balances" do
  # This calls the REAL Binance testnet API
  assert {:ok, balances} = Binance.Spot.get_balances()
  assert is_list(balances)
  
  # Document actual response structure from TESTNET
  # Binance testnet returns: [%{"asset" => "BTC", "free" => "0.0", "locked" => "0.0"}, ...]
end

test "place_order with invalid symbol returns real error" do
  # This gets REAL error from Binance TESTNET
  assert {:error, reason} = Binance.Spot.place_order(%{
    symbol: "INVALID",
    side: "BUY",
    quantity: "1"
  })

  # Document what Binance TESTNET actually returns
  # Binance testnet error: {"code": -1121, "msg": "Invalid symbol."}
  assert reason =~ "Invalid symbol" or reason == {:invalid_symbol, _}
end
```

### **Unit Testing (Pure Functions)**
```elixir
# Test pure functions without API calls
test "normalize_symbol/1 formats trading pairs correctly" do
  assert Parser.normalize_symbol("BTC-USDT") == "BTCUSDT"
  assert Parser.normalize_symbol("btc_usdt") == "BTCUSDT"
  assert Parser.normalize_symbol("BTC/USDT") == "BTCUSDT"
end

test "calculate_order_value/2 computes correct values" do
  assert Calculator.order_value("100.5", "25.50") == Decimal.new("2562.75")
  assert Calculator.order_value("0.001", "50000") == Decimal.new("50")
end
```

### **Rate Limiter Testing**
```elixir
# Test rate limiting with real behavior
test "rate limiter enforces limits" do
  # Reset rate limiter
  RateLimiter.reset(:spot_request)
  
  # Make requests up to limit
  for _ <- 1..1200 do
    assert :ok = RateLimiter.check_and_increment(:spot_request)
  end
  
  # Next request should be rate limited
  assert {:error, :rate_limited} = RateLimiter.check_and_increment(:spot_request)
end
```

4. **TDD Best Practices**:

### **Start with Integration Tests**
- Test against real testnet APIs first
- Document actual API responses
- Understand real error conditions
- Only then create unit tests

### **Work from Outside-In**
- Start with adapter endpoint tests
- Move to core module tests
- End with helper function tests

### **Test Real Behavior**
- Never mock without testing real API first
- Document actual response formats
- Test actual error messages
- Verify rate limit behavior

### **Test Error Cases**
```elixir
# Test authentication errors
test "invalid API key returns proper error" do
  with_env [{"BINANCE_TESTNET_API_KEY", "invalid"}] do
    assert {:error, reason} = Binance.Spot.get_balances()
    # Document actual error from testnet
  end
end

# Test network errors
test "handles connection timeout" do
  # Configure short timeout
  opts = [timeout: 1]
  assert {:error, :timeout} = Binance.Spot.get_ticker("BTCUSDT", opts)
end
```

5. **Library-Specific TDD Patterns**:

### **Endpoint Discovery Testing**
```elixir
# Test endpoint registration and discovery
test "lists all available endpoints" do
  endpoints = Binance.Endpoints.list_available_endpoints()
  assert :spot_get_balances in endpoints
  assert :margin_get_account in endpoints
end

test "provides endpoint metadata" do
  info = Binance.Endpoints.get_endpoint_info(:spot_place_order)
  assert info.method == :post
  assert info.auth_required == true
  assert info.rate_weight == 1
end
```

### **Clock Sync Testing**
```elixir
# Test time synchronization
test "syncs with exchange server time" do
  assert :ok = ClockSync.sync(:binance, :spot)
  
  # Verify offset is reasonable (< 1 second)
  offset = ClockSync.get_offset(:binance, :spot)
  assert abs(offset) < 1000
end
```

### **Debug Module Testing**
```elixir
# Test debug capabilities
test "captures failed requests as curl commands" do
  Debug.enable()
  
  # Make a failing request
  {:error, _} = Binance.Spot.place_order(%{invalid: "params"})
  
  # Get the curl command
  {:ok, curl} = Debug.get_last_curl()
  assert curl =~ "curl"
  assert curl =~ "testnet.binance.vision"
end
```

6. **TDD Workflow Helper**:

### **Step 1: Write Integration Test**
- Test against real testnet API
- Document actual responses
- Capture real error messages

### **Step 2: Run Tests (Red)**
- Ensure test fails correctly
- Verify testnet is being used
- Check credentials are configured

### **Step 3: Implement (Green)**
- Write minimal code to pass
- Handle actual API responses
- Process real error formats

### **Step 4: Refactor**
- Extract common patterns
- Improve error messages
- Add telemetry events
- Optimize performance

### **Step 5: Add Unit Tests**
- Test pure functions
- Test edge cases
- Test calculations and parsing

## Example Usage

Tell me:
- What exchange/API are you integrating?
- What endpoint/operation are you implementing?
- What are the expected parameters?
- What errors should be handled?

I'll help you write tests against real testnet APIs first, then implement the feature following TDD principles and ZenCex patterns.