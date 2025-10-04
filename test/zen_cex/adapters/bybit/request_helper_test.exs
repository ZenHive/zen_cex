defmodule ZenCex.Adapters.Bybit.RequestHelperTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.RequestHelper

  describe "base_url/1" do
    test "accepts testnet flag parameter" do
      assert RequestHelper.base_url(testnet: false) == "https://api.bybit.com"
      assert RequestHelper.base_url(testnet: true) == "https://api-testnet.bybit.com"
    end

    test "returns production URL by default" do
      url = RequestHelper.base_url()
      assert url == "https://api.bybit.com"
    end
  end

  describe "current_env/0" do
    test "returns a valid environment" do
      # Don't assume what the environment should be, just verify it's valid
      env = RequestHelper.current_env()
      assert env in [:prod, :test]
    end

    test "returns consistent environment across calls" do
      # Test that persistent_term caching works
      first_call = RequestHelper.current_env()
      second_call = RequestHelper.current_env()
      assert first_call == second_call
    end
  end

  describe "build_url/2" do
    test "builds production URL with explicit :prod env" do
      assert RequestHelper.build_url("/v5/market/time", :prod) ==
               "https://api.bybit.com/v5/market/time"
    end

    test "builds testnet URL with explicit :test env" do
      assert RequestHelper.build_url("/v5/market/time", :test) ==
               "https://api-testnet.bybit.com/v5/market/time"
    end

    test "builds URL with current environment when no env specified" do
      url = RequestHelper.build_url("/v5/order/realtime")
      assert url =~ ~r{^https://api(-testnet)?\.bybit\.com/v5/order/realtime$}
    end
  end

  describe "build_request_params/2" do
    test "builds params for GET request" do
      config = %{method: :get}
      params = %{category: "spot", symbol: "BTCUSDT"}

      assert RequestHelper.build_request_params(config, params) == %{
               params: %{category: "spot", symbol: "BTCUSDT"}
             }
    end

    test "builds params for POST request" do
      config = %{method: :post}

      params = %{
        category: "spot",
        symbol: "BTCUSDT",
        side: "Buy",
        orderType: "Limit",
        qty: "0.1",
        price: "50000"
      }

      assert RequestHelper.build_request_params(config, params) == %{
               json: params
             }
    end

    test "builds params for PUT request" do
      config = %{method: :put}
      params = %{orderId: "123", qty: "0.2"}

      assert RequestHelper.build_request_params(config, params) == %{
               json: params
             }
    end

    test "builds params for DELETE request" do
      config = %{method: :delete}
      params = %{orderId: "123"}

      assert RequestHelper.build_request_params(config, params) == %{
               json: params
             }
    end

    test "handles empty params for GET" do
      config = %{method: :get}
      params = %{}

      assert RequestHelper.build_request_params(config, params) == %{}
    end
  end

  describe "determine_operation_type/1" do
    test "returns :trading for order operations" do
      assert RequestHelper.determine_operation_type(%{operation: :place_order}) == :trading
      assert RequestHelper.determine_operation_type(%{operation: :cancel_order}) == :trading
      assert RequestHelper.determine_operation_type(%{operation: :cancel_all_orders}) == :trading
    end

    test "returns :market for market data operations" do
      assert RequestHelper.determine_operation_type(%{operation: :get_tickers}) == :market
      assert RequestHelper.determine_operation_type(%{operation: :get_orderbook}) == :market
      assert RequestHelper.determine_operation_type(%{operation: :get_trades}) == :market
    end

    test "returns :health for server time" do
      assert RequestHelper.determine_operation_type(%{operation: :server_time}) == :health
    end

    test "returns :standard for other operations" do
      assert RequestHelper.determine_operation_type(%{operation: :get_balances}) == :standard
      assert RequestHelper.determine_operation_type(%{operation: :get_positions}) == :standard
      assert RequestHelper.determine_operation_type(%{operation: :get_orders}) == :standard
    end
  end
end
