defmodule ZenCex.Examples.BinanceQuickStartTest do
  @moduledoc """
  Tests for binance_quick_start.ex examples.

  These tests verify that the quick start guide examples work correctly.
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Examples.BinanceQuickStart

  @moduletag :example

  describe "connectivity (no auth required)" do
    test "check_connectivity/0 returns server time" do
      assert {:ok, %{server_time: time}} = BinanceQuickStart.check_connectivity()
      assert is_integer(time)
      assert time > 0
    end
  end

  describe "authenticated operations" do
    test "get_account_balances/1 with opts from context", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      assert {:ok, balances} = BinanceQuickStart.get_account_balances(opts)
      assert is_list(balances)

      # Verify structure if we have balances
      if length(balances) > 0 do
        balance = hd(balances)
        assert Map.has_key?(balance, :asset)
        assert Map.has_key?(balance, :free)
        assert Map.has_key?(balance, :locked)
      end
    end

    test "get_balances_with_credentials/1 with custom credentials", context do
      credentials = %{
        api_key: context[:api_key],
        api_secret: context[:api_secret],
        testnet: context[:testnet]
      }

      assert {:ok, balances} = BinanceQuickStart.get_balances_with_credentials(credentials)
      assert is_list(balances)
    end
  end
end
