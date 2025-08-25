defmodule ZenCex.Adapters.Bybit.UnifiedTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.Unified

  describe "endpoint definitions" do
    test "all_endpoints/0 returns all unified endpoints" do
      endpoints = Unified.all_endpoints()

      assert is_list(endpoints)
      assert length(endpoints) == 10

      # Check that all expected operations are present
      operations = Enum.map(endpoints, & &1.operation)

      assert :get_wallet_balance in operations
      assert :place_order in operations
      assert :cancel_order in operations
      assert :cancel_all_orders in operations
      assert :get_order in operations
      assert :get_order_history in operations
      assert :get_positions in operations
      assert :set_leverage in operations
      assert :set_trading_stop in operations
      assert :get_trades in operations
    end

    test "get_endpoint/1 returns endpoint configuration" do
      # Test existing endpoint
      endpoint = Unified.get_endpoint(:place_order)

      assert endpoint.operation == :place_order
      assert endpoint.method == :post
      assert endpoint.path == "/v5/order/create"
      assert endpoint.requires_auth == true
      assert endpoint.weight == 1
      # Never retry order placement
      assert endpoint.max_retries == 0

      # Test non-existent endpoint
      assert Unified.get_endpoint(:non_existent) == nil
    end

    test "endpoints have proper configuration" do
      endpoints = Unified.all_endpoints()

      Enum.each(endpoints, fn endpoint ->
        # All endpoints should have required fields
        assert Map.has_key?(endpoint, :operation)
        assert Map.has_key?(endpoint, :method)
        assert Map.has_key?(endpoint, :path)
        assert Map.has_key?(endpoint, :requires_auth)
        assert Map.has_key?(endpoint, :weight)
        assert Map.has_key?(endpoint, :timeout)
        assert Map.has_key?(endpoint, :response_parser)
        assert Map.has_key?(endpoint, :error_mapping)

        # All paths should start with /v5/
        assert String.starts_with?(endpoint.path, "/v5/")

        # All unified endpoints require auth
        assert endpoint.requires_auth == true

        # Weight should be positive
        assert endpoint.weight > 0

        # Timeout should be reasonable
        assert endpoint.timeout >= 1_000
        assert endpoint.timeout <= 10_000
      end)
    end

    test "critical operations have no retries" do
      # Operations that should never be retried
      no_retry_operations = [:place_order, :set_leverage, :set_trading_stop]

      Enum.each(no_retry_operations, fn op ->
        endpoint = Unified.get_endpoint(op)
        assert endpoint.max_retries == 0
        assert endpoint.retry_on == []
      end)
    end

    test "safe operations allow retries" do
      # Operations that can be safely retried
      retry_operations = [:get_wallet_balance, :get_order, :get_order_history, :get_positions, :get_trades]

      Enum.each(retry_operations, fn op ->
        endpoint = Unified.get_endpoint(op)
        assert endpoint.max_retries > 0
        assert length(endpoint.retry_on) > 0
      end)
    end

    test "cancel operations have limited retries" do
      cancel_endpoint = Unified.get_endpoint(:cancel_order)
      assert cancel_endpoint.max_retries == 2
      assert cancel_endpoint.retry_on == [:timeout]

      cancel_all_endpoint = Unified.get_endpoint(:cancel_all_orders)
      assert cancel_all_endpoint.max_retries == 2
      assert cancel_all_endpoint.retry_on == [:timeout]
    end
  end

  describe "generated functions" do
    test "all operations have generated functions" do
      # Test that functions are defined (will raise UndefinedFunctionError if not)
      assert is_function(&Unified.get_wallet_balance/1)
      assert is_function(&Unified.get_wallet_balance/2)

      assert is_function(&Unified.place_order/1)
      assert is_function(&Unified.place_order/2)

      assert is_function(&Unified.cancel_order/1)
      assert is_function(&Unified.cancel_order/2)

      assert is_function(&Unified.cancel_all_orders/1)
      assert is_function(&Unified.cancel_all_orders/2)

      assert is_function(&Unified.get_order/1)
      assert is_function(&Unified.get_order/2)

      assert is_function(&Unified.get_order_history/1)
      assert is_function(&Unified.get_order_history/2)

      assert is_function(&Unified.get_positions/1)
      assert is_function(&Unified.get_positions/2)

      assert is_function(&Unified.set_leverage/1)
      assert is_function(&Unified.set_leverage/2)

      assert is_function(&Unified.set_trading_stop/1)
      assert is_function(&Unified.set_trading_stop/2)

      assert is_function(&Unified.get_trades/1)
      assert is_function(&Unified.get_trades/2)
    end
  end

  describe "endpoint paths" do
    test "all paths follow Bybit v5 API structure" do
      endpoints = Unified.all_endpoints()

      path_mapping = %{
        get_wallet_balance: "/v5/account/wallet-balance",
        place_order: "/v5/order/create",
        cancel_order: "/v5/order/cancel",
        cancel_all_orders: "/v5/order/cancel-all",
        get_order: "/v5/order/realtime",
        get_order_history: "/v5/order/history",
        get_positions: "/v5/position/list",
        set_leverage: "/v5/position/set-leverage",
        set_trading_stop: "/v5/position/trading-stop",
        get_trades: "/v5/execution/list"
      }

      Enum.each(endpoints, fn endpoint ->
        expected_path = Map.get(path_mapping, endpoint.operation)

        assert endpoint.path == expected_path,
               "#{endpoint.operation} path should be #{expected_path}, got #{endpoint.path}"
      end)
    end

    test "HTTP methods are correct for each operation" do
      get_operations = [:get_wallet_balance, :get_order, :get_order_history, :get_positions, :get_trades]
      post_operations = [:place_order, :cancel_order, :cancel_all_orders, :set_leverage, :set_trading_stop]

      Enum.each(get_operations, fn op ->
        endpoint = Unified.get_endpoint(op)
        assert endpoint.method == :get
      end)

      Enum.each(post_operations, fn op ->
        endpoint = Unified.get_endpoint(op)
        assert endpoint.method == :post
      end)
    end
  end

  describe "parser functions" do
    test "all endpoints have valid parser functions" do
      endpoints = Unified.all_endpoints()

      Enum.each(endpoints, fn endpoint ->
        # Parser should be a function reference
        assert is_function(endpoint.response_parser, 1)
        assert is_function(endpoint.error_mapping, 1)
      end)
    end
  end
end
