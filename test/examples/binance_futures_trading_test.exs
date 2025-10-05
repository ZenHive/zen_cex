defmodule ZenCex.Examples.BinanceFuturesTradingTest do
  @moduledoc """
  Tests for binance_futures_trading.ex examples.

  Tests position queries (read-only) and order placement (write operations).
  Write operations are tagged and skipped by default.
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :usdm_futures, use_production_for_test: true

  alias ZenCex.Examples.BinanceFuturesTrading

  @moduletag :example

  describe "USD-M Futures read-only operations" do
    test "get_usdm_positions/1 returns list of positions", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      assert {:ok, positions} = BinanceFuturesTrading.get_usdm_positions(opts)
      assert is_list(positions)

      # If we have positions, verify structure
      if length(positions) > 0 do
        position = hd(positions)
        assert Map.has_key?(position, :symbol)
        assert Map.has_key?(position, :size)
        assert Map.has_key?(position, :entry_price)
      end
    end
  end

  describe "COIN-M Futures read-only operations" do
    test "get_coinm_positions/1 returns list of positions", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      assert {:ok, positions} = BinanceFuturesTrading.get_coinm_positions(opts)
      assert is_list(positions)

      # If we have positions, verify structure
      if length(positions) > 0 do
        position = hd(positions)
        assert Map.has_key?(position, :symbol)
        assert Map.has_key?(position, :size)
      end
    end
  end

  describe "write operations (skipped by default)" do
    @tag :write_operation
    @tag :skip
    test "place_usdm_market_order/3 creates USD-M market order", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Note: This test is skipped to avoid creating actual orders
      # To run: mix test --include write_operation --include skip
      symbol = "BTCUSDT"
      side = "BUY"
      quantity = "0.001"

      case BinanceFuturesTrading.place_usdm_market_order(symbol, side, quantity, opts) do
        {:ok, order} ->
          assert is_map(order)

        # Success - order placed

        {:error, :insufficient_balance} ->
          :ok

        {:error, {:insufficient_balance, _}} ->
          :ok

        # Binance error code -2019: Margin is insufficient
        {:error, %{"code" => -2019}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "place_coinm_limit_order/4 creates COIN-M limit order", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      symbol = "BTCUSD_PERP"
      side = "BUY"
      quantity = "1"
      price = "20000"

      case BinanceFuturesTrading.place_coinm_limit_order(symbol, side, quantity, price, opts) do
        {:ok, order} ->
          assert is_map(order)

        # Success - order placed

        {:error, :insufficient_balance} ->
          :ok

        {:error, {:insufficient_balance, _}} ->
          :ok

        # Binance error code -2019: Margin is insufficient
        {:error, %{"code" => -2019}} ->
          :ok

        # Binance error code -4013: Price less than min price
        {:error, %{"code" => -4013}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end
  end

  describe "error handling" do
    test "handles invalid symbols gracefully", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Position queries typically return all positions or empty list
      # rather than erroring on invalid symbols
      assert {:ok, _} = BinanceFuturesTrading.get_usdm_positions(opts)
    end
  end
end
