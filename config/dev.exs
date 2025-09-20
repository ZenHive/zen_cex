import Config

# Development-specific configuration
config :logger, :console, level: :debug

# Debug mode configuration - enabled for development
config :zen_cex, :debug,
  enabled: true,
  export_curl: true,
  log_level: :debug

config :zen_cex, :enable_debug_capture, true

# Enable debug features in development
config :zen_cex, :enable_debug_table, true

# Cache TTL configuration uses compile-time constants from TimeConstants module
# See lib/zen_cex/config/time_constants.ex for values
# Development uses: 24h for symbol info, 24h for min notional, 5s for prices
