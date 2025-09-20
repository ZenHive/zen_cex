import Config

# Suppress telemetry warnings about local functions during tests
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:endpoint, :operation]

# Configure compile-time log filtering
config :logger,
  compile_time_purge_matching: [
    [application: :telemetry, level_lower_than: :error],
    [module: ZenCex.Safety.OrderSafety.Cache, level_lower_than: :info]
  ]

# Debug mode configuration - enabled for tests
config :zen_cex, :debug,
  enabled: true,
  export_curl: true,
  log_level: :debug

config :zen_cex, :enable_debug_capture, true

# Enable debug features in test
config :zen_cex, :enable_debug_table, true

# Test-specific configuration to prevent accidentally hitting production
config :zen_cex, :enforce_testnet, true

# Testing doesn't require connection pooling
config :zen_cex, :finch_options,
  pools: %{
    :default => [size: 1, count: 1]
  }

# Cache TTL configuration uses compile-time constants from TimeConstants module
# See lib/zen_cex/config/time_constants.ex for values
# Test uses: 1m for symbol info, 1m for min notional, 1s for prices
