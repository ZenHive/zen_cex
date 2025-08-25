defmodule ZenCex.Adapters.Bybit.RequestHelperTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.RequestHelper

  describe "base_url/1" do
    test "returns production URL by default" do
      System.delete_env("BYBIT_TESTNET")
      assert RequestHelper.base_url() == "https://api.bybit.com"
    end

    test "returns testnet URL when BYBIT_TESTNET is true" do
      System.put_env("BYBIT_TESTNET", "true")
      assert RequestHelper.base_url() == "https://api-testnet.bybit.com"
      System.delete_env("BYBIT_TESTNET")
    end

    test "accepts explicit environment parameter" do
      assert RequestHelper.base_url(:prod) == "https://api.bybit.com"
      assert RequestHelper.base_url(:test) == "https://api-testnet.bybit.com"
    end
  end

  describe "current_env/0" do
    test "returns :prod when BYBIT_TESTNET is not set" do
      System.delete_env("BYBIT_TESTNET")
      assert RequestHelper.current_env() == :prod
    end

    test "returns :test when BYBIT_TESTNET is true" do
      System.put_env("BYBIT_TESTNET", "true")
      assert RequestHelper.current_env() == :test
      System.delete_env("BYBIT_TESTNET")
    end

    test "returns :prod when BYBIT_TESTNET is false" do
      System.put_env("BYBIT_TESTNET", "false")
      assert RequestHelper.current_env() == :prod
      System.delete_env("BYBIT_TESTNET")
    end
  end

  describe "build_url/2" do
    test "builds production URL by default" do
      System.delete_env("BYBIT_TESTNET")
      assert RequestHelper.build_url("/v5/market/time") == "https://api.bybit.com/v5/market/time"
    end

    test "builds testnet URL when env is test" do
      assert RequestHelper.build_url("/v5/market/time", :test) ==
               "https://api-testnet.bybit.com/v5/market/time"
    end

    test "builds URL with query parameters" do
      assert RequestHelper.build_url("/v5/order/realtime", :prod) ==
               "https://api.bybit.com/v5/order/realtime"
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

      assert RequestHelper.build_request_params(config, params) == %{params: %{}}
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
