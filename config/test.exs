import Config

# Suppress telemetry warnings about local functions during tests
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:endpoint, :operation]

# Suppress specific logger warnings for tests
config :logger,
  compile_time_purge_matching: [
    # Suppress telemetry local function warnings
    [application: :telemetry, level_lower_than: :error],
    # Suppress OrderSafety cache clearing warnings
    [module: ZenCex.Safety.OrderSafety, level_lower_than: :error]
  ]

# Debug mode configuration - enabled for testing
config :zen_cex, :debug,
  enabled: true,
  export_curl: true,
  log_level: :debug
