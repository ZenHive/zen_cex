defmodule ZenCex.Adapters.Binance.EndpointsRouterTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Adapters.Binance.{Common, Spot, Futures}

  describe "router delegation patterns" do
    test "common endpoints delegate to Common module" do
      # get_server_time should delegate to Common
      assert function_exported?(Endpoints, :get_server_time, 0)
      assert function_exported?(Endpoints, :get_server_time, 1)
    end

    test "spot endpoints delegate to Spot module" do
      # Spot trading functions should be available through main Endpoints
      assert function_exported?(Endpoints, :get_balances, 0)
      assert function_exported?(Endpoints, :get_balances, 1)
      assert function_exported?(Endpoints, :get_balances, 2)

      assert function_exported?(Endpoints, :place_order, 0)
      assert function_exported?(Endpoints, :place_order, 1)
      assert function_exported?(Endpoints, :place_order, 2)

      assert function_exported?(Endpoints, :cancel_order, 0)
      assert function_exported?(Endpoints, :cancel_order, 1)
      assert function_exported?(Endpoints, :cancel_order, 2)

      assert function_exported?(Endpoints, :get_order, 0)
      assert function_exported?(Endpoints, :get_order, 1)
      assert function_exported?(Endpoints, :get_order, 2)
    end

    test "futures endpoints delegate to Futures module" do
      # Futures functions should be available through main Endpoints
      assert function_exported?(Endpoints, :get_positions, 0)
      assert function_exported?(Endpoints, :get_positions, 1)
      assert function_exported?(Endpoints, :get_positions, 2)
    end

    test "complex operations are delegated correctly" do
      assert function_exported?(Endpoints, :place_oco_order, 1)
      assert function_exported?(Endpoints, :batch_cancel_orders, 1)
    end
  end

  describe "get_endpoint/1 routing" do
    test "routes common operations to Common module" do
      endpoint = Endpoints.get_endpoint(:get_server_time)
      assert endpoint != nil
      assert endpoint.operation == :get_server_time

      # Should match Common module's config
      common_endpoint = Common.get_endpoint(:get_server_time)
      assert endpoint == common_endpoint
    end

    test "routes spot operations to Spot module" do
      spot_ops = [:get_balances, :place_order, :cancel_order, :get_order]

      Enum.each(spot_ops, fn op ->
        endpoint = Endpoints.get_endpoint(op)
        assert endpoint != nil, "Failed to get endpoint for #{op}"

        # Should match Spot module's config
        spot_endpoint = Spot.get_endpoint(op)
        assert endpoint == spot_endpoint
      end)
    end

    test "routes futures operations to Futures module" do
      endpoint = Endpoints.get_endpoint(:get_positions)
      assert endpoint != nil
      assert endpoint.operation == :get_positions

      # Should match Futures module's config
      futures_endpoint = Futures.get_endpoint(:get_positions)
      assert endpoint == futures_endpoint
    end

    test "returns nil for unknown operations" do
      assert Endpoints.get_endpoint(:unknown_operation) == nil
    end
  end

  describe "all_endpoints/0 aggregation" do
    test "combines endpoints from all modules" do
      all_endpoints = Endpoints.all_endpoints()

      # Should have endpoints from Common, Spot, and Futures
      operations = Enum.map(all_endpoints, & &1.operation)

      # From Common
      assert :get_server_time in operations

      # From Spot
      assert :get_balances in operations
      assert :place_order in operations
      assert :cancel_order in operations
      assert :get_order in operations

      # From Futures
      assert :get_positions in operations
    end

    test "no duplicate operations in aggregated endpoints" do
      all_endpoints = Endpoints.all_endpoints()
      operations = Enum.map(all_endpoints, & &1.operation)

      # Check for duplicates
      unique_operations = Enum.uniq(operations)

      assert length(operations) == length(unique_operations),
             "Found duplicate operations in aggregated endpoints"
    end
  end

  describe "get_weight/1 routing" do
    test "returns correct weight for common operations" do
      assert Endpoints.get_weight(:get_server_time) == 1
    end

    test "returns correct weight for spot operations" do
      assert Endpoints.get_weight(:get_balances) == 10
      assert Endpoints.get_weight(:place_order) == 1
      assert Endpoints.get_weight(:cancel_order) == 1
      assert Endpoints.get_weight(:get_order) == 2
    end

    test "returns correct weight for futures operations" do
      assert Endpoints.get_weight(:get_positions) == 5
    end

    test "returns nil for unknown operations" do
      assert Endpoints.get_weight(:unknown_operation) == nil
    end
  end

  describe "module configuration" do
    test "__exchange__/0 returns :binance" do
      assert Endpoints.__exchange__() == :binance
    end

    test "auth/0 returns the Auth module" do
      assert Endpoints.auth() == ZenCex.Adapters.Binance.Auth
    end

    test "rate_limiter/0 returns the RateLimiter module" do
      assert Endpoints.rate_limiter() == ZenCex.Adapters.Binance.RateLimiter
    end

    test "parser/0 returns the Parser module" do
      assert Endpoints.parser() == ZenCex.Adapters.Binance.Parser
    end
  end

  describe "environment handling" do
    test "current_env/0 respects BINANCE_TESTNET env variable" do
      original = System.get_env("BINANCE_TESTNET")

      try do
        # Test production (default)
        System.delete_env("BINANCE_TESTNET")
        assert Endpoints.current_env() == :prod

        System.put_env("BINANCE_TESTNET", "false")
        assert Endpoints.current_env() == :prod

        System.put_env("BINANCE_TESTNET", "")
        assert Endpoints.current_env() == :prod

        # Test testnet
        System.put_env("BINANCE_TESTNET", "true")
        assert Endpoints.current_env() == :test

        System.put_env("BINANCE_TESTNET", "1")
        assert Endpoints.current_env() == :test

        System.put_env("BINANCE_TESTNET", "yes")
        assert Endpoints.current_env() == :test
      after
        # Restore original value
        if original do
          System.put_env("BINANCE_TESTNET", original)
        else
          System.delete_env("BINANCE_TESTNET")
        end
      end
    end
  end

  describe "base_url routing" do
    test "base_url/0 returns URL for current environment" do
      url = Endpoints.base_url()
      assert is_binary(url)
      assert url =~ "binance"
    end

    test "base_url/1 returns correct URLs for each environment" do
      assert Endpoints.base_url(:test) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:prod) == "https://api.binance.com"
    end

    test "base_url/2 returns correct URLs for different API types" do
      # Test environment
      assert Endpoints.base_url(:test, :spot) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:test, :futures) == "https://testnet.binancefuture.com"
      assert Endpoints.base_url(:test, :margin) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:test, :sapi) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:test, :dapi) == "https://testnet.binancefuture.com"
      assert Endpoints.base_url(:test, :papi) == "https://testnet.binance.vision"

      # Production environment
      assert Endpoints.base_url(:prod, :spot) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :futures) == "https://fapi.binance.com"
      assert Endpoints.base_url(:prod, :margin) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :sapi) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :dapi) == "https://dapi.binance.com"
      assert Endpoints.base_url(:prod, :papi) == "https://papi.binance.com"
    end

    test "base_url/2 has fallback for unknown API types" do
      assert Endpoints.base_url(:test, :unknown) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:prod, :unknown) == "https://api.binance.com"
    end
  end

  describe "backwards compatibility" do
    test "maintains compatibility with Core.Registry expectations" do
      # Core.Registry expects these functions to exist
      assert function_exported?(Endpoints, :__exchange__, 0)
      assert function_exported?(Endpoints, :auth, 0)
      assert function_exported?(Endpoints, :rate_limiter, 0)
      assert function_exported?(Endpoints, :parser, 0)
      assert function_exported?(Endpoints, :base_url, 0)
    end

    test "get_endpoint/1 provides registry-compatible interface" do
      # Should work for all known operations
      operations = [
        :get_server_time,
        :get_balances,
        :place_order,
        :cancel_order,
        :get_order,
        :get_positions
      ]

      Enum.each(operations, fn op ->
        config = Endpoints.get_endpoint(op)
        assert config != nil, "get_endpoint/1 failed for #{op}"
        assert is_map(config)
        assert config.operation == op
      end)
    end
  end
end
