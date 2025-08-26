import Config

# Development-specific configuration
config :logger, :console, level: :debug

# Debug mode configuration - enabled for development
config :zen_cex, :debug,
  enabled: true,
  export_curl: true,
  log_level: :debug
