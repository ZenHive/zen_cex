defmodule ZenCex.Adapters.Binance.SpotTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Spot

  describe "endpoint configurations" do
    test "all endpoints have required fields" do
      endpoints = Spot.all_endpoints()
      assert length(endpoints) == 4

      Enum.each(endpoints, fn config ->
        assert Map.has_key?(config, :operation)
        assert Map.has_key?(config, :method)
        assert Map.has_key?(config, :path)
        assert Map.has_key?(config, :requires_auth)
        assert Map.has_key?(config, :weight)
        assert Map.has_key?(config, :timeout)
        assert Map.has_key?(config, :retry_on)
        assert Map.has_key?(config, :response_parser)
        assert Map.has_key?(config, :error_mapping)
      end)
    end

    test "get_balances configuration" do
      config = Spot.get_endpoint(:get_balances)
      assert config.operation == :get_balances
      assert config.method == :get
      assert config.path == "/api/v3/account"
      assert config.requires_auth == true
      assert config.weight == 10
      assert config.timeout == 5_000
      assert config.retry_on == [:rate_limited, :timeout]
    end

    test "place_order configuration has no retries" do
      config = Spot.get_endpoint(:place_order)
      assert config.operation == :place_order
      assert config.method == :post
      assert config.path == "/api/v3/order"
      assert config.requires_auth == true
      assert config.max_retries == 0
      assert config.retry_on == []
      assert config.timeout == 2_000
    end

    test "cancel_order configuration has limited retries" do
      config = Spot.get_endpoint(:cancel_order)
      assert config.operation == :cancel_order
      assert config.method == :delete
      assert config.path == "/api/v3/order"
      assert config.requires_auth == true
      assert config.max_retries == 1
      assert config.retry_on == [:timeout]
      assert config.timeout == 2_000
    end

    test "get_order configuration" do
      config = Spot.get_endpoint(:get_order)
      assert config.operation == :get_order
      assert config.method == :get
      assert config.path == "/api/v3/order"
      assert config.requires_auth == true
      assert config.weight == 2
      assert config.timeout == 5_000
      assert config.retry_on == [:rate_limited, :timeout, :server_error]
    end
  end

  describe "get_endpoint/1" do
    test "returns correct config for known operations" do
      assert Spot.get_endpoint(:get_balances).operation == :get_balances
      assert Spot.get_endpoint(:place_order).operation == :place_order
      assert Spot.get_endpoint(:cancel_order).operation == :cancel_order
      assert Spot.get_endpoint(:get_order).operation == :get_order
    end

    test "returns nil for unknown operations" do
      assert Spot.get_endpoint(:unknown_operation) == nil
      assert Spot.get_endpoint(:get_positions) == nil
      assert Spot.get_endpoint(:get_server_time) == nil
    end
  end

  describe "all_endpoints/0" do
    test "returns all spot endpoints" do
      endpoints = Spot.all_endpoints()
      operations = Enum.map(endpoints, & &1.operation)

      assert :get_balances in operations
      assert :place_order in operations
      assert :cancel_order in operations
      assert :get_order in operations
    end
  end

  describe "function exports" do
    test "exports all endpoint functions" do
      assert function_exported?(Spot, :get_balances, 0)
      assert function_exported?(Spot, :get_balances, 1)
      assert function_exported?(Spot, :get_balances, 2)

      assert function_exported?(Spot, :place_order, 0)
      assert function_exported?(Spot, :place_order, 1)
      assert function_exported?(Spot, :place_order, 2)

      assert function_exported?(Spot, :cancel_order, 0)
      assert function_exported?(Spot, :cancel_order, 1)
      assert function_exported?(Spot, :cancel_order, 2)

      assert function_exported?(Spot, :get_order, 0)
      assert function_exported?(Spot, :get_order, 1)
      assert function_exported?(Spot, :get_order, 2)
    end

    test "exports complex operation functions" do
      assert function_exported?(Spot, :place_oco_order, 1)
      assert function_exported?(Spot, :batch_cancel_orders, 1)
    end
  end

  describe "complex operations" do
    test "place_oco_order returns not_implemented" do
      assert Spot.place_oco_order(%{}) == {:error, :not_implemented}
    end

    test "batch_cancel_orders returns not_implemented" do
      assert Spot.batch_cancel_orders(%{}) == {:error, :not_implemented}
    end
  end
end
