IO.puts "BINANCE_TESTNET env var: #{inspect System.get_env("BINANCE_TESTNET")}"
IO.puts "current_env() returns: #{inspect ZenCex.Adapters.Binance.Endpoints.current_env()}"
IO.puts "base_url() returns: #{inspect ZenCex.Adapters.Binance.Endpoints.base_url()}"
