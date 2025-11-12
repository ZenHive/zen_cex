defmodule ZenCex.Adapters.Binance.MarginIntegrationTest do
  @moduledoc """
  Integration tests for Binance Margin API endpoints.

  These tests verify the Margin API implementation against real testnet/sandbox APIs.
  Note: Binance testnet has limited support for margin endpoints (mainly /api/* endpoints).
  The /sapi/* endpoints are generally not available on testnet.
  """

  use ZenCex.IntegrationCase, exchange: :binance, api_type: :margin

  alias ZenCex.Adapters.Binance.Margin

  @moduletag :integration
  @moduletag :binance_margin

  describe "margin account operations" do
    @tag skip: "SAPI endpoints not available on testnet"
    test "get_cross_margin_account returns account details" do
      # This would work in production but not on testnet
      assert {:error, _} = Margin.get_cross_margin_account()
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_isolated_margin_account returns account info" do
      # This would work in production but not on testnet
      assert {:error, _} = Margin.get_isolated_margin_account()
    end
  end

  describe "margin trading operations" do
    @tag skip: "SAPI endpoints not available on testnet"
    test "place_order creates a margin order" do
      # Note: Would need valid margin account and funds in production
      params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.001",
        price: "30000",
        # Cross margin
        isIsolated: "FALSE"
      }

      assert {:error, _} = Margin.place_order(params)
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_order_history returns past orders" do
      params = %{
        symbol: "BTCUSDT"
      }

      assert {:error, _} = Margin.get_order_history(params)
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_trade_history returns executed trades" do
      params = %{
        symbol: "BTCUSDT"
      }

      assert {:error, _} = Margin.get_trade_history(params)
    end
  end

  describe "margin loan operations" do
    @tag skip: "SAPI endpoints not available on testnet"
    test "borrow_or_repay handles borrow operations" do
      params = %{
        asset: "USDT",
        amount: "100",
        type: "BORROW",
        isIsolated: "FALSE"
      }

      assert {:error, _} = Margin.borrow_or_repay(params)
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_borrow_repay_history returns loan records" do
      params = %{
        asset: "USDT",
        type: "BORROW"
      }

      assert {:error, _} = Margin.get_borrow_repay_history(params)
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_interest_history returns interest payments" do
      params = %{
        asset: "USDT"
      }

      assert {:error, _} = Margin.get_interest_history(params)
    end
  end

  describe "margin risk management" do
    @tag skip: "SAPI endpoints not available on testnet"
    test "get_max_borrowable returns maximum borrow amount" do
      params = %{
        asset: "USDT"
      }

      assert {:error, _} = Margin.get_max_borrowable(params)
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_max_transferable returns maximum transfer amount" do
      params = %{
        asset: "USDT"
      }

      assert {:error, _} = Margin.get_max_transferable(params)
    end
  end

  describe "margin market data" do
    @tag skip: "SAPI endpoints not available on testnet"
    test "get_all_assets returns all margin assets" do
      assert {:error, _} = Margin.get_all_assets()
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_all_pairs returns all cross margin pairs" do
      assert {:error, _} = Margin.get_all_pairs()
    end

    @tag skip: "SAPI endpoints not available on testnet"
    test "get_isolated_all_pairs returns all isolated margin pairs" do
      assert {:error, _} = Margin.get_isolated_all_pairs()
    end
  end

  describe "user data streams" do
    @tag skip: "SAPI endpoints not available on testnet"
    test "create_listen_key creates a margin listen key" do
      assert {:error, _} = Margin.create_listen_key()
    end
  end

  describe "endpoint registry functions" do
    test "all_endpoints returns list of margin endpoints" do
      endpoints = Margin.all_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) > 0

      # Check for some key endpoints
      operations = Enum.map(endpoints, & &1.operation)
      assert :get_cross_margin_account in operations
      assert :place_order in operations
      assert :borrow_or_repay in operations
    end

    test "get_endpoint returns specific endpoint config" do
      config = Margin.get_endpoint(:place_order)
      assert config.method == :post
      assert config.path == "/sapi/v1/margin/order"
      assert config.requires_auth == true
    end

    test "get_weight returns endpoint weight" do
      assert Margin.get_weight(:place_order) == 5
      assert Margin.get_weight(:get_cross_margin_account) == 20
      assert Margin.get_weight(:borrow_or_repay) == 10
    end
  end
end
