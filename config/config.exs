import Config

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:endpoint, :operation, :exchange, :request_id, :response]

# Circuit breaker configuration (opt-in, disabled by default)
# Uncomment and configure to enable circuit breakers per exchange
# config :zen_cex, :circuit_breaker,
#   enabled: true,
#   binance: [
#     failure_threshold: 5,     # Number of failures before opening circuit
#     failure_window: 60_000,    # Time window for counting failures (ms)
#     reset_timeout: 30_000      # Time to keep circuit open before retry (ms)
#   ],
#   kraken: [
#     failure_threshold: 5,
#     failure_window: 60_000,
#     reset_timeout: 30_000
#   ],
#   deribit: [
#     failure_threshold: 5,
#     failure_window: 60_000,
#     reset_timeout: 30_000
#   ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
