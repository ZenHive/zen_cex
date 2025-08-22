import Config

# Development-specific configuration
config :logger, :console, level: :debug

# Debug mode configuration
config :zen_cex, :debug,
  enabled: false,
  export_curl: true,
  log_level: :debug
