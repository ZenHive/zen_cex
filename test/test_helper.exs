# Start the application for tests
Application.ensure_all_started(:zen_cex)

Logger.configure(level: :debug)

ExUnit.start()
