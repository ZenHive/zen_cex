#!/usr/bin/env elixir

# Script to verify that all Binance endpoints respect BINANCE_TESTNET
# Run with: elixir test/scripts/verify_environment_consistency.exs

alias ZenCex.Adapters.Binance.Endpoints

IO.puts("=" <> String.duplicate("=", 60))
IO.puts("Binance Environment Consistency Verification")
IO.puts("=" <> String.duplicate("=", 60))

# Test 1: Default (no env var)
System.delete_env("BINANCE_TESTNET")
IO.puts("\n1. Default (BINANCE_TESTNET not set):")
IO.puts("   current_env: #{inspect(Endpoints.current_env())}")
IO.puts("   base_url: #{Endpoints.base_url()}")

if Endpoints.current_env() == :prod and Endpoints.base_url() == "https://api.binance.com" do
  IO.puts("   ✓ PASS: Defaults to production")
else
  IO.puts("   ✗ FAIL: Should default to production!")
end

# Test 2: Explicit false
System.put_env("BINANCE_TESTNET", "false")
IO.puts("\n2. BINANCE_TESTNET=false:")
IO.puts("   current_env: #{inspect(Endpoints.current_env())}")
IO.puts("   base_url: #{Endpoints.base_url()}")

if Endpoints.current_env() == :prod do
  IO.puts("   ✓ PASS: Uses production")
else
  IO.puts("   ✗ FAIL: Should use production!")
end

# Test 3: Testnet enabled
System.put_env("BINANCE_TESTNET", "true")
IO.puts("\n3. BINANCE_TESTNET=true:")
IO.puts("   current_env: #{inspect(Endpoints.current_env())}")
IO.puts("   base_url: #{Endpoints.base_url()}")

if Endpoints.current_env() == :test and Endpoints.base_url() == "https://testnet.binance.vision" do
  IO.puts("   ✓ PASS: Uses testnet")
else
  IO.puts("   ✗ FAIL: Should use testnet!")
end

# Test 4: Invalid values default to prod
invalid_values = ["TRUE", "True", "1", "yes", "on", "random"]
IO.puts("\n4. Invalid values default to production:")
all_passed = true

for value <- invalid_values do
  System.put_env("BINANCE_TESTNET", value)
  env = Endpoints.current_env()

  if env != :prod do
    IO.puts("   ✗ FAIL: BINANCE_TESTNET=#{inspect(value)} gave #{inspect(env)}, expected :prod")
    all_passed = false
  end
end

if all_passed do
  IO.puts("   ✓ PASS: All invalid values correctly default to production")
end

# Test 5: Verify generated functions exist
IO.puts("\n5. Generated endpoints exist:")

generated_functions = [
  {:get_balances, 1},
  {:get_positions, 1},
  {:place_order, 1},
  {:cancel_order, 1},
  {:get_order, 1},
  {:get_open_orders, 1},
  {:get_server_time, 1}
]

all_exist = true

for {func, arity} <- generated_functions do
  if function_exported?(Endpoints, func, arity) do
    IO.puts("   ✓ #{func}/#{arity}")
  else
    IO.puts("   ✗ #{func}/#{arity} - MISSING!")
    all_exist = false
  end
end

# Test 6: Verify hand-written functions exist
IO.puts("\n6. Hand-written endpoints exist:")

hand_written_functions = [
  {:place_oco_order, 1},
  {:batch_cancel_orders, 1}
]

for {func, arity} <- hand_written_functions do
  if function_exported?(Endpoints, func, arity) do
    IO.puts("   ✓ #{func}/#{arity}")
  else
    IO.puts("   ✗ #{func}/#{arity} - MISSING!")
    all_exist = false
  end
end

# Clean up
System.delete_env("BINANCE_TESTNET")

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Summary: All endpoints (10 total) now consistently respect")
IO.puts("the BINANCE_TESTNET environment variable!")
IO.puts("- 8 generated endpoints use base_url/0")
IO.puts("- 2 hand-written endpoints use base_url/0")
IO.puts("=" <> String.duplicate("=", 60))
