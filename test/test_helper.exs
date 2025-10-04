require Logger
# Start the application for tests
Application.ensure_all_started(:zen_cex)

Logger.configure(level: :warning)

# Exclude WebSocket tests by default (they're slow and require network)
exclude_tags = [:websocket, :ws_slow]

# Check if we're explicitly running WebSocket tests
if "--only websocket" in System.argv() or "--only ws_slow" in System.argv() do
  # Running only WebSocket tests, don't exclude them
  ExUnit.start()
else
  # Log warning about excluded tests
  Logger.warning("""

  ⚠️  Excluding WebSocket tests (tagged with :websocket and :ws_slow)
  To run ALL tests including WebSocket tests: mix test --include websocket
  To run ONLY WebSocket tests: mix test --only websocket
  To run ONLY extra slow WebSocket tests: mix test --only ws_slow
  """)

  ExUnit.start(exclude: exclude_tags)
end
