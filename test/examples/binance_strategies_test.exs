defmodule ZenCex.Examples.BinanceStrategiesTest do
  use ExUnit.Case, async: false

  alias ZenCex.Examples.BinanceStrategies

  @moduletag :strategy
  @moduletag :write_operation
  @moduletag :skip

  # TODO: Tests currently skipped - Portfolio Margin strategies require real API credentials
  # with Portfolio Margin mode enabled on Binance. Our current testnet credentials do not
  # have this feature enabled. To implement these tests properly:
  #
  # 1. Obtain API credentials for an account with Portfolio Margin enabled
  # 2. Test against real Portfolio Margin endpoints first to understand actual behavior
  # 3. Document observed response structures and error cases
  # 4. Only then create mocks based on real API behavior
  #
  # NEVER create tests that hide failures or accept errors without validation.
  # If we can't test it properly against real APIs, it's better to skip than to lie.

  describe "auto_hedge_spot_positions/2" do
    @tag :skip
    test "TODO: requires Portfolio Margin credentials" do
      :ok
    end
  end

  describe "hedge_with_paxg_long/1" do
    @tag :skip
    test "TODO: requires Portfolio Margin credentials" do
      :ok
    end
  end

  describe "rebalance_portfolio/2" do
    @tag :skip
    test "TODO: requires Portfolio Margin credentials" do
      :ok
    end
  end

  describe "run_complete_example/0" do
    test "executes without crashing" do
      # This runs all strategies in dry-run mode
      # It will show errors if PM is not enabled, but won't crash
      assert :ok = BinanceStrategies.run_complete_example()
    end
  end
end
