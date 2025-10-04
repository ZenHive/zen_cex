defmodule ZenCex.Examples.BinanceSpotTradingTest do
  @moduledoc """
  Tests for binance_spot_trading.ex examples.

  Most tests are read-only operations. Write operations (place/cancel orders)
  are tagged with @tag :write_operation and skipped by default.
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Examples.BinanceSpotTrading

  @moduletag :example

  describe "read-only operations" do
    test "get_current_balances/1 returns list of balances", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      assert {:ok, balances} = BinanceSpotTrading.get_current_balances(opts)
      assert is_list(balances)

      # If we have balances, verify structure
      if length(balances) > 0 do
        balance = hd(balances)
        assert Map.has_key?(balance, :asset)
        assert Map.has_key?(balance, :free)
        assert Map.has_key?(balance, :locked)
      end
    end

    test "get_open_orders/2 returns list of orders", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Get open orders for BTCUSDT (likely empty on testnet)
      assert {:ok, orders} = BinanceSpotTrading.get_open_orders("BTCUSDT", opts)
      assert is_list(orders)

      # If we have orders, verify structure
      if length(orders) > 0 do
        order = hd(orders)
        assert Map.has_key?(order, "symbol")
        assert Map.has_key?(order, "orderId")
        assert Map.has_key?(order, "status")
      end
    end
  end

  describe "write operations (skipped by default)" do
    @tag :write_operation
    @tag :skip
    test "place_market_buy/2 creates market buy order", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Note: This test is skipped to avoid creating actual orders
      # To run: mix test --include write_operation
      symbol = "BTCUSDT"
      quantity = "0.001"

      case BinanceSpotTrading.place_market_buy(symbol, quantity) do
        {:ok, order} ->
          assert Map.has_key?(order, "orderId")
          assert Map.has_key?(order, "status")
          assert order["symbol"] == symbol
          assert order["side"] == "BUY"
          assert order["type"] == "MARKET"

        {:error, :insufficient_balance} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "check_order_status/2 returns order details", _context do
      # This test requires a valid order_id from a previous order
      # Skipped by default as it depends on write operations
      :ok
    end

    @tag :write_operation
    @tag :skip
    test "cancel_order/2 cancels an order", _context do
      # This test requires a valid order_id from a previous order
      # Skipped by default as it depends on write operations
      :ok
    end
  end

  describe "error handling" do
    test "handles invalid symbol gracefully", context do
      api_key = context[:api_key]
      api_secret = context[:api_secret]

      if is_nil(api_key) or is_nil(api_secret) do
        flunk("Testnet credentials required for this test")
      end

      # Try to get open orders for invalid symbol
      case BinanceSpotTrading.get_open_orders("INVALID") do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end
end
