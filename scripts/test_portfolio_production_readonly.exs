#!/usr/bin/env elixir

# CRITICAL: This script tests Portfolio Margin endpoints against PRODUCTION API
# ONLY READ-ONLY endpoints are tested - NO TRADES, NO ORDERS, NO MODIFICATIONS
#
# Usage: elixir scripts/test_portfolio_production_readonly.exs

IO.puts("\n⚠️  WARNING: This script will connect to PRODUCTION Binance API")
IO.puts("⚠️  Only READ-ONLY operations will be performed")
IO.puts("⚠️  No orders, trades, or account modifications will be made")
IO.puts("\nPress Enter to continue or Ctrl+C to abort...")
IO.gets("")

# Save original environment variables
original_env = %{
  "BINANCE_TESTNET" => System.get_env("BINANCE_TESTNET"),
  "BINANCE_TESTNET_API_KEY" => System.get_env("BINANCE_TESTNET_API_KEY"),
  "BINANCE_TESTNET_API_SECRET" => System.get_env("BINANCE_TESTNET_API_SECRET")
}

# CRITICAL: Temporarily unset testnet environment to use production
System.delete_env("BINANCE_TESTNET")
System.delete_env("BINANCE_TESTNET_API_KEY")
System.delete_env("BINANCE_TESTNET_API_SECRET")

# Start the application
{:ok, _} = Application.ensure_all_started(:zen_cex)

alias ZenCex.Adapters.Binance.PortfolioMargin
alias ZenCex.Adapters.Binance.Endpoints

require Logger

# Clear any cached environment
try do
  :persistent_term.erase({Endpoints, :current_env})
rescue
  _ -> nil
end

IO.puts("Current environment: #{Endpoints.current_env()}")
IO.puts("Base URL should be: https://papi.binance.com")
IO.puts("Actual base URL: #{Endpoints.base_url(:prod, :portfolio)}")

# ONLY test READ-ONLY endpoints
read_only_endpoints = [
  # Account information - READ ONLY
  {:account_information, fn -> PortfolioMargin.account_information() end},
  {:account_balance, fn -> PortfolioMargin.account_balance() end},

  # Account details - READ ONLY
  {:get_um_account_detail, fn -> PortfolioMargin.get_um_account_detail() end},
  {:get_cm_account_detail, fn -> PortfolioMargin.get_cm_account_detail() end},

  # Position information - READ ONLY
  {:query_um_position_information, fn -> PortfolioMargin.query_um_position_information() end},
  {:query_cm_position_information, fn -> PortfolioMargin.query_cm_position_information() end},

  # Current modes - READ ONLY
  {:get_um_current_position_mode, fn -> PortfolioMargin.get_um_current_position_mode() end},
  {:get_cm_current_position_mode, fn -> PortfolioMargin.get_cm_current_position_mode() end},

  # Commission rates - READ ONLY
  {:get_user_commission_rate_for_um, fn ->
    PortfolioMargin.get_user_commission_rate_for_um(%{symbol: "BTCUSDT"})
  end},
  {:get_user_commission_rate_for_cm, fn ->
    PortfolioMargin.get_user_commission_rate_for_cm(%{symbol: "BTCUSD_PERP"})
  end},

  # Income history - READ ONLY
  {:get_um_income_history, fn -> PortfolioMargin.get_um_income_history() end},
  {:get_cm_income_history, fn -> PortfolioMargin.get_cm_income_history() end},

  # Account configuration - READ ONLY
  {:um_futures_account_configuration, fn -> PortfolioMargin.um_futures_account_configuration() end},

  # Max withdrawable - READ ONLY
  {:query_margin_max_withdraw, fn ->
    PortfolioMargin.query_margin_max_withdraw(%{asset: "USDT"})
  end}
]

IO.puts("\n📊 Testing #{length(read_only_endpoints)} READ-ONLY Portfolio Margin endpoints in PRODUCTION\n")

results = Enum.map(read_only_endpoints, fn {name, endpoint_fn} ->
  IO.write("Testing #{name}... ")

  try do
    case endpoint_fn.() do
      {:ok, response} ->
        IO.puts("✅ SUCCESS")
        response_type = if is_map(response) and Map.has_key?(response, :__struct__),
                          do: response.__struct__,
                          else: "map"
        IO.puts("  Response type: #{inspect(response_type)}")

        # Show first few fields of response (safely)
        case response do
          %{} = map when map_size(map) > 0 ->
            keys = Map.keys(map) |> Enum.take(5)
            IO.puts("  Fields: #{inspect(keys)}")
          list when is_list(list) ->
            IO.puts("  List with #{length(list)} items")
          _ ->
            IO.puts("  Response: #{inspect(response) |> String.slice(0, 100)}")
        end

        {name, :success}

      {:error, reason} ->
        IO.puts("❌ ERROR: #{inspect(reason)}")
        {name, {:error, reason}}
    end
  rescue
    e ->
      IO.puts("💥 EXCEPTION: #{Exception.message(e)}")
      {name, {:exception, e}}
  end
end)

# Summary
IO.puts("\n" <> String.duplicate("=", 50))
IO.puts("SUMMARY - PRODUCTION Portfolio Margin API Test")
IO.puts(String.duplicate("=", 50))

successful = Enum.filter(results, fn {_, status} -> status == :success end)
errors = Enum.filter(results, fn {_, status} -> match?({:error, _}, status) end)
exceptions = Enum.filter(results, fn {_, status} -> match?({:exception, _}, status) end)

IO.puts("✅ Successful: #{length(successful)}/#{length(read_only_endpoints)}")
IO.puts("❌ Errors: #{length(errors)}/#{length(read_only_endpoints)}")
IO.puts("💥 Exceptions: #{length(exceptions)}/#{length(read_only_endpoints)}")

if length(successful) > 0 do
  IO.puts("\n✅ Working endpoints:")
  Enum.each(successful, fn {name, _} -> IO.puts("   • #{name}") end)
end

if length(errors) > 0 do
  IO.puts("\n❌ Error endpoints:")
  Enum.each(errors, fn {name, {:error, reason}} ->
    IO.puts("   • #{name}: #{inspect(reason) |> String.slice(0, 80)}")
  end)
end

if length(exceptions) > 0 do
  IO.puts("\n💥 Exception endpoints:")
  Enum.each(exceptions, fn {name, _} -> IO.puts("   • #{name}") end)
end

IO.puts("\n⚠️  Note: This test only checked READ-ONLY endpoints")
IO.puts("⚠️  Trading endpoints were NOT tested for safety reasons")

# Restore original environment variables
IO.puts("\n🔄 Restoring original environment variables...")
Enum.each(original_env, fn {key, value} ->
  if value do
    System.put_env(key, value)
  end
end)

# Also reload .zprofile to ensure complete restoration
IO.puts("🔄 Reloading shell profile...")
System.cmd("bash", ["-c", "source ~/.zprofile"], into: IO.stream())

IO.puts("✅ Environment restored")