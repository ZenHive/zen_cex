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

    test "list_available_endpoints/1 with trading categories returns empty (not yet implemented)" do
      # These will be implemented in Ticket #8
      assert Endpoints.list_available_endpoints(:spot) == []
      assert Endpoints.list_available_endpoints(:linear) == []
      assert Endpoints.list_available_endpoints(:inverse) == []
      assert Endpoints.list_available_endpoints(:option) == []
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
  end
end
