require Logger
# Start the application for tests
Application.ensure_all_started(:zen_cex)

Logger.configure(level: :warninmfg)

# Exclude slow WebSocket tests by default
exclude_tags = [:ws_slow]

# Check if we're explicitly running WebSocket tests
if "--only ws_slow" in System.argv() do
  # Running only WebSocket tests, don't exclude them
  ExUnit.start()
else
  # Log warning about excluded tests
  Logger.warning("""

  ⚠️  Excluding slow WebSocket tests (tagged with :ws_slow)
  To run ALL tests including slow WebSocket tests: mix test --include ws_slow
  To run ONLY WebSocket tests: mix test --only ws_slow
  """)

  ExUnit.start(exclude: exclude_tags)
end
