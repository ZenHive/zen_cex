# Code Review Prompt for AI Coders

## How to Review ZenCex Implementation

### Review Process
As an AI code reviewer, follow this systematic review process:

1. **Read Architecture Docs First**
   - Read `cex-shared-modules-ai.md` for technical requirements
   - Read `cex-implementation-tasks-ai.md` for expected implementation

2. **Check Implementation Against Requirements**
   - Verify all CRITICAL markers are implemented
   - Confirm exchange-specific quirks are handled
   - Validate file structure matches specification

3. **Rate Each Module 1-5**
   - 5/5: Perfect implementation, all requirements met
   - 4/5: Good implementation, minor improvements possible
   - 3/5: Functional but missing important features
   - 2/5: Major issues or missing critical requirements
   - 1/5: Fundamentally broken or wrong approach

## Review Checklist for Each Module

### Core Modules Review

#### Core.Registry (Expected: ~30 lines)
- [ ] Compile-time validation of adapters
- [ ] get_adapter!/1 raises on unknown exchange
- [ ] list_exchanges/0 returns all supported exchanges
- [ ] Rating: _/5

#### Core.HTTP (Expected: ~50 lines)
- [ ] Exponential backoff with jitter implemented
- [ ] Operation-specific timeouts (trading: 2s, market: 5s, historical: 30s)
- [ ] Uses Finch connection pooling
- [ ] Retry-After header support
- [ ] Rating: _/5

### Authentication Review

#### Binance Auth
- [ ] HMAC-SHA256 signature generation
- [ ] Timestamp within 5000ms window
- [ ] recvWindow parameter included
- [ ] Signature as LAST parameter
- [ ] API key in X-MBX-APIKEY header
- [ ] Rating: _/5

#### Kraken Auth
- [ ] Microsecond + counter nonce (NOT just microseconds)
- [ ] Uses Agent or ETS for counter state
- [ ] Forces POST with form encoding
- [ ] Base64 decode of API secret
- [ ] Rating: _/5

#### Deribit Auth
- [ ] OAuth2 token management
- [ ] Refreshes 120 seconds BEFORE expiry
- [ ] Single-flight protection (no concurrent refreshes)
- [ ] Handles both test and production endpoints
- [ ] Rating: _/5

### Rate Limiting Review

#### General Requirements
- [ ] Separate ETS tables per exchange
- [ ] Atomic operations (no GenServer for incrementing)
- [ ] Cleanup runs every 60 seconds
- [ ] No memory leaks after extended running
- [ ] Rating: _/5

#### Exchange-Specific Limits
- [ ] Binance: 1200/min spot, 2400/min futures (separate tracking)
- [ ] Kraken: 15/sec with 1-second window
- [ ] Deribit: 20/sec with 1-second window
- [ ] Proper window cleanup for each exchange
- [ ] Rating: _/5

### WebSocket Review

#### MUST Have
- [ ] PUBLIC endpoints only (no authentication)
- [ ] 10-second deduplication buffer using :queue
- [ ] Heartbeat/ping for each exchange
- [ ] Binary frame handling for Kraken
- [ ] JSON-RPC format for Deribit
- [ ] Rating: _/5

#### MUST NOT Have
- [ ] NO WebSocket authentication
- [ ] NO user streams or private channels
- [ ] NO trading operations
- [ ] NO complex sequence tracking
- [ ] Rating: Pass/Fail

### Health Monitoring Review

#### Clock Sync
- [ ] Checks every 30 seconds
- [ ] Gets time from 3+ exchanges
- [ ] Uses median for consensus
- [ ] Warns at 300ms drift
- [ ] Critical at 500ms drift
- [ ] Rating: _/5

### Circuit Breaker Review

#### Implementation
- [ ] Per-endpoint tracking (not just per-exchange)
- [ ] Three states: closed, open, half-open
- [ ] 60-second cooldown after trip
- [ ] Doesn't trip on rate limits
- [ ] Telemetry on state changes
- [ ] Rating: _/5

## Integration Test Review

### Test Coverage
- [ ] Tests against REAL APIs (not mocks)
- [ ] Uses test credentials
- [ ] Handles both success and error cases
- [ ] Verifies rate limiting works
- [ ] Confirms caching reduces API calls
- [ ] Rating: _/5

## Common Implementation Mistakes to Check

1. **Kraken nonce**: Using only System.os_time(:microsecond) without counter
2. **Binance limits**: Not separating spot vs futures rate limits
3. **Deribit OAuth**: Not refreshing 120 seconds before expiry
4. **WebSocket**: Implementing authentication or private streams
5. **Circuit breaker**: Tripping on rate limits (shouldn't)
6. **ETS cleanup**: Not scheduling periodic cleanup
7. **HTTP/2 with Kraken**: Not forcing HTTP/1.1

## Overall Rating Calculation

```elixir
# Calculate overall rating
modules = [
  core_registry: 4.5,
  core_http: 4.0,
  binance_auth: 5.0,
  kraken_auth: 4.5,
  deribit_auth: 4.0,
  rate_limiting: 4.5,
  websocket: 4.0,
  health: 5.0,
  circuit_breaker: 4.5,
  integration_tests: 4.0
]

average = Enum.sum(Keyword.values(modules)) / length(modules)
# => 4.4/5
```

## Review Output Template

```markdown
## Code Review Results

### Overall Rating: X.X/5

### Module Ratings:
- Core.Registry: X/5
- Core.HTTP: X/5
- Binance.Auth: X/5
- Kraken.Auth: X/5
- Deribit.Auth: X/5
- RateLimit: X/5
- WebSocket: X/5
- Health: X/5
- Circuit: X/5
- Tests: X/5

### Critical Issues Found:
1. [Issue description and location]
2. [Issue description and location]

### Recommendations:
1. [Specific improvement]
2. [Specific improvement]

### Strengths:
1. [What was done well]
2. [What was done well]
```

## Review Commands

```bash
# Check if all required files exist
find lib/zen_cex -name "*.ex" | wc -l
# Should be ~18 files

# Check for CRITICAL markers handled
grep -r "CRITICAL" lib/zen_cex/

# Run dialyzer for type checking
mix dialyzer

# Check for memory leaks
iex -S mix
:observer.start()
# Monitor ETS tables and process memory

# Run integration tests
mix test --only integration
```