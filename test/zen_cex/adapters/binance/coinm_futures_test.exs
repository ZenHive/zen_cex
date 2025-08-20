defmodule ZenCex.Adapters.Binance.CoinmFuturesTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.CoinmFutures

  describe "endpoint configuration" do
    test "get_positions configuration is correct" do
      config = CoinmFutures.get_endpoint(:get_positions)
      assert config.operation == :get_positions
      assert config.method == :get
      assert config.path == "/dapi/v1/positionRisk"
      assert config.api_type == :coinm_futures
      assert config.requires_auth == true
      assert config.weight == 5
      assert config.timeout == 5_000
      assert config.max_retries == 3
      assert config.retry_on == [:rate_limited, :timeout, :server_error]
      assert is_function(config.response_parser, 1)
      assert is_function(config.error_mapping, 1)
    end

    test "get_account configuration uses /dapi/ path" do
      config = CoinmFutures.get_endpoint(:get_account)
      assert config.operation == :get_account
      assert config.method == :get
      assert config.path == "/dapi/v1/account"
      assert config.api_type == :coinm_futures
      assert config.requires_auth == true
    end

    test "place_order has no retries" do
      config = CoinmFutures.get_endpoint(:place_order)
      assert config.operation == :place_order
      assert config.path == "/dapi/v1/order"
      assert config.max_retries == 0
      assert config.retry_on == []
      assert config.timeout == 2_000
    end

    test "cancel_order allows timeout retry" do
      config = CoinmFutures.get_endpoint(:cancel_order)
      assert config.operation == :cancel_order
      assert config.path == "/dapi/v1/order"
      assert config.max_retries == 1
      assert config.retry_on == [:timeout]
      assert config.timeout == 2_000
    end
  end

  describe "get_endpoint/1" do
    test "returns correct config for various operations" do
      # Account operations
      assert CoinmFutures.get_endpoint(:get_account).path == "/dapi/v1/account"
      assert CoinmFutures.get_endpoint(:get_balances).path == "/dapi/v1/balance"

      # Position operations
      assert CoinmFutures.get_endpoint(:get_positions).path == "/dapi/v1/positionRisk"

      # Order operations
      assert CoinmFutures.get_endpoint(:place_order).path == "/dapi/v1/order"
      assert CoinmFutures.get_endpoint(:get_order).path == "/dapi/v1/order"
      assert CoinmFutures.get_endpoint(:cancel_order).path == "/dapi/v1/order"

      # All operations should use coinm_futures API type
      for op <- [:get_account, :get_balances, :get_positions, :place_order] do
        config = CoinmFutures.get_endpoint(op)
        assert config.api_type == :coinm_futures
      end
    end

    test "returns nil for unknown operations" do
      assert CoinmFutures.get_endpoint(:unknown_operation) == nil
      assert CoinmFutures.get_endpoint(:fake_endpoint) == nil
      assert CoinmFutures.get_endpoint("not_an_atom") == nil
    end
  end

  describe "all_endpoints/0" do
    test "returns list with multiple COIN-M futures endpoints" do
      endpoints = CoinmFutures.all_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) == 28

      # All should use /dapi/ paths
      for endpoint <- endpoints do
        assert String.starts_with?(endpoint.path, "/dapi/")
        assert endpoint.api_type == :coinm_futures
      end

      # Check specific endpoints exist
      operations = Enum.map(endpoints, & &1.operation)
      assert :get_account in operations
      assert :get_balances in operations
      assert :get_positions in operations
      assert :place_order in operations
      assert :cancel_order in operations
      assert :get_trades in operations
    end
  end

  describe "function exports" do
    test "exports core trading functions" do
      # Account functions (arity 1 and 2, not 0)
      assert function_exported?(CoinmFutures, :get_account, 1)
      assert function_exported?(CoinmFutures, :get_account, 2)

      assert function_exported?(CoinmFutures, :get_balances, 1)
      assert function_exported?(CoinmFutures, :get_balances, 2)

      # Position functions
      assert function_exported?(CoinmFutures, :get_positions, 1)
      assert function_exported?(CoinmFutures, :get_positions, 2)

      # Order functions
      assert function_exported?(CoinmFutures, :place_order, 1)
      assert function_exported?(CoinmFutures, :place_order, 2)

      assert function_exported?(CoinmFutures, :cancel_order, 1)
      assert function_exported?(CoinmFutures, :cancel_order, 2)

      assert function_exported?(CoinmFutures, :get_order, 1)
      assert function_exported?(CoinmFutures, :get_order, 2)
    end
  end

  describe "get_weight/1" do
    test "returns correct weights for operations" do
      assert CoinmFutures.get_weight(:get_account) == 10
      assert CoinmFutures.get_weight(:get_balances) == 10
      assert CoinmFutures.get_weight(:get_positions) == 5
      assert CoinmFutures.get_weight(:place_order) == 1
      assert CoinmFutures.get_weight(:cancel_order) == 1
    end

    test "returns default weight for unknown operations" do
      # EndpointRegistry returns 1 as default weight for unknown operations
      assert CoinmFutures.get_weight(:unknown_op) == 1
    end
  end
end
