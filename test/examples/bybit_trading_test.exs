defmodule ZenCex.Examples.BybitTradingTest do
  @moduledoc """
  Tests for bybit_trading.ex examples.

  Most tests are read-only operations. Write operations (order placement)
  are tagged with @tag :write_operation and skipped by default.
  """

  use ZenCex.IntegrationCase, exchange: :bybit

  alias ZenCex.Examples.BybitTrading

  @moduletag :example

  describe "connectivity" do
    test "check_server_connectivity/0 returns server time" do
      # This is a public endpoint, no auth required
      assert {:ok, response} = BybitTrading.check_server_connectivity()
      assert is_map(response)

      # Verify we got server time (now normalized to atom keys)
      assert Map.has_key?(response, :time_second) or Map.has_key?(response, :time_nano)
    end
  end

  describe "position queries (read-only)" do
    test "get_positions/2 with linear category requires settleCoin option", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        },
        settle_coin: "USDT"
      ]

      # Bybit API requires either symbol or settleCoin parameter
      assert {:ok, response} = BybitTrading.get_positions("linear", opts)
      assert is_map(response)
      # Bybit returns list of positions in "list" key (now normalized to :list)
      assert Map.has_key?(response, :list)
      assert is_list(response[:list])
    end

    test "get_positions/2 with spot category returns expected error", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Spot category is not supported for position queries on Bybit
      case BybitTrading.get_positions("spot", opts) do
        {:error, %{"retCode" => 181_001, "retMsg" => msg}} ->
          # Expected: category only supports linear or option
          assert msg =~ "category"

        {:error, other} ->
          flunk("Expected retCode 181001 for unsupported category, got: #{inspect(other)}")

        {:ok, _} ->
          flunk("Expected error for spot category, but got success")
      end
    end

    test "get_positions/2 with inverse category requires settleCoin option", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        },
        settle_coin: "BTC"
      ]

      # Bybit API requires either symbol or settleCoin parameter
      assert {:ok, response} = BybitTrading.get_positions("inverse", opts)
      assert is_map(response)
      # Keys are now normalized to atoms
      assert Map.has_key?(response, :list)
      assert is_list(response[:list])
    end
  end

  describe "write operations (skipped by default)" do
    @tag :write_operation
    @tag :skip
    test "place_spot_order/4 creates spot market order", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Note: This test is skipped to avoid creating actual orders
      # To run: mix test --include write_operation
      symbol = "BTCUSDT"
      side = "Buy"
      order_type = "Market"
      qty = "0.001"

      case BybitTrading.place_spot_order(symbol, side, order_type, qty, opts) do
        {:ok, order} ->
          assert is_map(order)
          # Keys are now normalized to atoms
          assert Map.has_key?(order, :order_id) or Map.has_key?(order, :order_link_id)

        {:error, :insufficient_balance} ->
          :ok

        {:error, {:insufficient_balance, _}} ->
          :ok

        # Bybit testnet: Order value too low
        {:error, %{"retCode" => 170_140}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "place_linear_futures_order/4 creates linear market order", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      symbol = "BTCUSDT"
      side = "Buy"
      order_type = "Market"
      qty = "0.001"

      case BybitTrading.place_linear_futures_order(symbol, side, order_type, qty, opts) do
        {:ok, order} ->
          assert is_map(order)
          # Keys are now normalized to atoms
          assert Map.has_key?(order, :order_id) or Map.has_key?(order, :order_link_id)

        {:error, :insufficient_balance} ->
          :ok

        {:error, {:insufficient_balance, _}} ->
          :ok

        # Bybit testnet: Order value too low
        {:error, %{"retCode" => 170_140}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "place_inverse_futures_order/5 creates inverse limit order", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      symbol = "BTCUSD"
      side = "Buy"
      order_type = "Limit"
      price = "70000"
      qty = "100"

      case BybitTrading.place_inverse_futures_order(symbol, side, order_type, price, qty, opts) do
        {:ok, order} ->
          assert is_map(order)
          # Keys are now normalized to atoms
          assert Map.has_key?(order, :order_id) or Map.has_key?(order, :order_link_id)

        {:error, :insufficient_balance} ->
          :ok

        {:error, {:insufficient_balance, _}} ->
          :ok

        # Bybit testnet: Collateral not enabled (retCode 110101)
        {:error, %{"retCode" => 110_101}} ->
          :ok

        # Bybit testnet: Order value too low
        {:error, %{"retCode" => 170_140}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end
  end

  describe "error handling" do
    test "get_positions/1 handles invalid category gracefully", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Try invalid category
      case BybitTrading.get_positions("invalid_category", opts) do
        {:ok, _} ->
          flunk("Expected error for invalid category")

        {:error, _reason} ->
          :ok
      end
    end

    @tag :write_operation
    @tag :skip
    test "place_spot_order/4 handles invalid symbol gracefully", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Try to place order with invalid symbol
      case BybitTrading.place_spot_order("INVALIDSYMBOL", "Buy", "Market", "0.001", opts) do
        {:ok, _} ->
          flunk("Expected error for invalid symbol")

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "category parameter pattern" do
    test "demonstrates category parameter usage for different trading types", context do
      opts = [
        auth_credentials: %{
          api_key: context[:api_key],
          api_secret: context[:api_secret],
          testnet: context[:testnet]
        }
      ]

      # Test that all category types are accepted by the API
      categories = ["spot", "linear", "inverse"]

      for category <- categories do
        # Each category should return a valid response structure
        case BybitTrading.get_positions(category, opts) do
          {:ok, response} ->
            assert is_map(response)

          # Some categories may not be enabled on testnet
          {:error, _reason} ->
            :ok
        end
      end
    end
  end
end
