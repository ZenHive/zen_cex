defmodule ZenCex.Adapters.Bybit.EndpointsTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.Endpoints

  describe "module attributes" do
    test "__exchange__/0 returns :bybit" do
      assert Endpoints.__exchange__() == :bybit
    end

    test "auth/0 returns the Auth module" do
      assert Endpoints.auth() == ZenCex.Adapters.Bybit.Auth
    end

    test "rate_limiter/0 returns the RateLimiter module" do
      assert Endpoints.rate_limiter() == ZenCex.Adapters.Bybit.RateLimiter
    end

    test "parser/0 returns the Parser module" do
      assert Endpoints.parser() == ZenCex.Adapters.Bybit.Parser
    end
  end

  describe "environment handling" do
    test "current_env/0 returns :prod by default" do
      # Clear any cached value first
      key = {Endpoints, :current_env}

      try do
        :persistent_term.erase(key)
      rescue
        _ -> nil
      end

      # Without BYBIT_TESTNET set, should return :prod
      System.delete_env("BYBIT_TESTNET")
      assert Endpoints.current_env() == :prod
    end

    test "current_env/0 returns :test when BYBIT_TESTNET is set" do
      # Clear any cached value first
      key = {Endpoints, :current_env}

      try do
        :persistent_term.erase(key)
      rescue
        _ -> nil
      end

      # With BYBIT_TESTNET set to "true", should return :test
      System.put_env("BYBIT_TESTNET", "true")
      assert Endpoints.current_env() == :test

      # Clean up
      System.delete_env("BYBIT_TESTNET")
    end

    test "base_url/0 returns correct URL for current environment" do
      # Clear cache
      key = {Endpoints, :current_env}

      try do
        :persistent_term.erase(key)
      rescue
        _ -> nil
      end

      # Test production
      System.delete_env("BYBIT_TESTNET")
      assert Endpoints.base_url() == "https://api.bybit.com"

      # Clear cache again for test environment
      try do
        :persistent_term.erase(key)
      rescue
        _ -> nil
      end

      # Test testnet
      System.put_env("BYBIT_TESTNET", "true")
      assert Endpoints.base_url() == "https://api-testnet.bybit.com"

      # Clean up
      System.delete_env("BYBIT_TESTNET")
    end

    test "base_url/1 returns correct URL for specified environment" do
      assert Endpoints.base_url(:prod) == "https://api.bybit.com"
      assert Endpoints.base_url(:test) == "https://api-testnet.bybit.com"
    end
  end

  describe "endpoint listing" do
    test "list_available_endpoints/0 returns all endpoints" do
      endpoints = Endpoints.list_available_endpoints()

      assert is_list(endpoints)
      # Should have at least the common endpoints
      assert :get_server_time in endpoints
      assert :get_announcements in endpoints
    end

    test "list_available_endpoints/1 with :common returns common endpoints" do
      endpoints = Endpoints.list_available_endpoints(:common)

      assert is_list(endpoints)
      assert :get_server_time in endpoints
      assert :get_announcements in endpoints
    end

    test "list_available_endpoints/1 with :unified returns unified endpoints" do
      endpoints = Endpoints.list_available_endpoints(:unified)

      assert is_list(endpoints)
      assert :place_order in endpoints
      assert :get_positions in endpoints
      refute :get_server_time in endpoints
    end

    test "list_available_endpoints/1 with :spot returns spot-specific endpoints" do
      endpoints = Endpoints.list_available_endpoints(:spot)

      # Spot has basic trading operations
      assert :place_order in endpoints
      assert :cancel_order in endpoints
      assert :get_order in endpoints
      assert :get_wallet_balance in endpoints

      # Spot doesn't have position management
      refute :get_positions in endpoints
      refute :set_leverage in endpoints
      refute :set_trading_stop in endpoints
    end

    test "list_available_endpoints/1 with :linear returns linear futures endpoints" do
      endpoints = Endpoints.list_available_endpoints(:linear)

      # Linear has all operations
      assert :place_order in endpoints
      assert :cancel_order in endpoints
      assert :get_positions in endpoints
      assert :set_leverage in endpoints
      assert :set_trading_stop in endpoints
    end

    test "list_available_endpoints/1 with :inverse returns inverse futures endpoints" do
      endpoints = Endpoints.list_available_endpoints(:inverse)

      # Inverse has all operations like linear
      assert :place_order in endpoints
      assert :cancel_order in endpoints
      assert :get_positions in endpoints
      assert :set_leverage in endpoints
      assert :set_trading_stop in endpoints
    end

    test "list_available_endpoints/1 with :option returns options endpoints" do
      endpoints = Endpoints.list_available_endpoints(:option)

      # Options have positions but not leverage/stops
      assert :place_order in endpoints
      assert :cancel_order in endpoints
      assert :get_positions in endpoints

      # Options don't have leverage or trading stops
      refute :set_leverage in endpoints
      refute :set_trading_stop in endpoints
    end

    test "list_available_endpoints/1 with invalid category returns empty list" do
      assert Endpoints.list_available_endpoints(:invalid) == []
    end
  end

  describe "endpoint info" do
    test "get_endpoint_info/1 returns config for valid operation" do
      info = Endpoints.get_endpoint_info(:get_server_time)

      assert is_map(info)
      assert info.operation == :get_server_time
      assert info.method == :get
      assert info.path == "/v5/market/time"
      assert info.requires_auth == false
    end

    test "get_endpoint_info/1 returns config for unified operation" do
      info = Endpoints.get_endpoint_info(:place_order)

      assert is_map(info)
      assert info.operation == :place_order
      assert info.method == :post
      assert info.path == "/v5/order/create"
      assert info.requires_auth == true
    end

    test "get_endpoint_info/1 returns nil for invalid operation" do
      assert Endpoints.get_endpoint_info(:invalid_operation) == nil
    end
  end

  describe "delegation" do
    test "delegates get_server_time to Common module" do
      # The function should be available
      assert function_exported?(Endpoints, :get_server_time, 0)
      assert function_exported?(Endpoints, :get_server_time, 1)
    end

    test "delegates get_announcements to Common module" do
      # The function should be available with multiple arities
      assert function_exported?(Endpoints, :get_announcements, 0)
      assert function_exported?(Endpoints, :get_announcements, 1)
      assert function_exported?(Endpoints, :get_announcements, 2)
    end

    test "delegates unified trading endpoints" do
      assert function_exported?(Endpoints, :get_wallet_balance, 1)
      assert function_exported?(Endpoints, :get_wallet_balance, 2)
      assert function_exported?(Endpoints, :place_order, 1)
      assert function_exported?(Endpoints, :place_order, 2)
      assert function_exported?(Endpoints, :cancel_order, 1)
      assert function_exported?(Endpoints, :cancel_order, 2)
      assert function_exported?(Endpoints, :cancel_all_orders, 1)
      assert function_exported?(Endpoints, :cancel_all_orders, 2)
      assert function_exported?(Endpoints, :get_order, 1)
      assert function_exported?(Endpoints, :get_order, 2)
      assert function_exported?(Endpoints, :get_order_history, 1)
      assert function_exported?(Endpoints, :get_order_history, 2)
      assert function_exported?(Endpoints, :get_positions, 1)
      assert function_exported?(Endpoints, :get_positions, 2)
      assert function_exported?(Endpoints, :set_leverage, 1)
      assert function_exported?(Endpoints, :set_leverage, 2)
      assert function_exported?(Endpoints, :set_trading_stop, 1)
      assert function_exported?(Endpoints, :set_trading_stop, 2)
      assert function_exported?(Endpoints, :get_trades, 1)
      assert function_exported?(Endpoints, :get_trades, 2)
    end
  end

  describe "category-prefixed convenience functions" do
    test "spot convenience functions are exported" do
      assert function_exported?(Endpoints, :spot_place_order, 1)
      assert function_exported?(Endpoints, :spot_place_order, 2)
      assert function_exported?(Endpoints, :spot_cancel_order, 1)
      assert function_exported?(Endpoints, :spot_cancel_order, 2)
      assert function_exported?(Endpoints, :spot_cancel_all_orders, 0)
      assert function_exported?(Endpoints, :spot_cancel_all_orders, 1)
      assert function_exported?(Endpoints, :spot_cancel_all_orders, 2)
      assert function_exported?(Endpoints, :spot_get_order, 1)
      assert function_exported?(Endpoints, :spot_get_order, 2)
      assert function_exported?(Endpoints, :spot_get_order_history, 0)
      assert function_exported?(Endpoints, :spot_get_order_history, 1)
      assert function_exported?(Endpoints, :spot_get_order_history, 2)
      assert function_exported?(Endpoints, :spot_get_trades, 0)
      assert function_exported?(Endpoints, :spot_get_trades, 1)
      assert function_exported?(Endpoints, :spot_get_trades, 2)
    end

    test "linear convenience functions are exported" do
      assert function_exported?(Endpoints, :linear_place_order, 1)
      assert function_exported?(Endpoints, :linear_place_order, 2)
      assert function_exported?(Endpoints, :linear_cancel_order, 1)
      assert function_exported?(Endpoints, :linear_cancel_order, 2)
      assert function_exported?(Endpoints, :linear_get_positions, 0)
      assert function_exported?(Endpoints, :linear_get_positions, 1)
      assert function_exported?(Endpoints, :linear_get_positions, 2)
      assert function_exported?(Endpoints, :linear_set_leverage, 1)
      assert function_exported?(Endpoints, :linear_set_leverage, 2)
      assert function_exported?(Endpoints, :linear_set_trading_stop, 1)
      assert function_exported?(Endpoints, :linear_set_trading_stop, 2)
    end

    test "inverse convenience functions are exported" do
      assert function_exported?(Endpoints, :inverse_place_order, 1)
      assert function_exported?(Endpoints, :inverse_place_order, 2)
      assert function_exported?(Endpoints, :inverse_cancel_order, 1)
      assert function_exported?(Endpoints, :inverse_cancel_order, 2)
      assert function_exported?(Endpoints, :inverse_get_positions, 0)
      assert function_exported?(Endpoints, :inverse_get_positions, 1)
      assert function_exported?(Endpoints, :inverse_get_positions, 2)
      assert function_exported?(Endpoints, :inverse_set_leverage, 1)
      assert function_exported?(Endpoints, :inverse_set_leverage, 2)
      assert function_exported?(Endpoints, :inverse_set_trading_stop, 1)
      assert function_exported?(Endpoints, :inverse_set_trading_stop, 2)
    end

    test "option convenience functions are exported" do
      assert function_exported?(Endpoints, :option_place_order, 1)
      assert function_exported?(Endpoints, :option_place_order, 2)
      assert function_exported?(Endpoints, :option_cancel_order, 1)
      assert function_exported?(Endpoints, :option_cancel_order, 2)
      assert function_exported?(Endpoints, :option_get_positions, 0)
      assert function_exported?(Endpoints, :option_get_positions, 1)
      assert function_exported?(Endpoints, :option_get_positions, 2)
      assert function_exported?(Endpoints, :option_get_trades, 0)
      assert function_exported?(Endpoints, :option_get_trades, 1)
      assert function_exported?(Endpoints, :option_get_trades, 2)
    end
  end
end
