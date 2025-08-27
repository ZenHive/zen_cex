defmodule ZenCex.Adapters.Binance.EndpointsRouterTest do
  use ExUnit.Case, async: true

  import ZenCex.IntegrationCase, only: [with_env: 2]
  import ZenCex.TestHelpers, only: [clear_environment_cache: 1]

  alias ZenCex.Adapters.Binance.Common
  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Adapters.Binance.UsdmFutures

  describe "router delegation patterns" do
    test "common endpoints delegate to Common module without prefix" do
      # get_server_time should delegate to Common (no prefix needed)
      assert function_exported?(Endpoints, :get_server_time, 0)
      assert function_exported?(Endpoints, :get_server_time, 1)
    end

    test "spot endpoints delegate to Spot module with spot_ prefix" do
      # Spot trading functions should be available with spot_ prefix
      assert function_exported?(Endpoints, :spot_get_balances, 0)
      assert function_exported?(Endpoints, :spot_get_balances, 1)
      assert function_exported?(Endpoints, :spot_get_balances, 2)

      assert function_exported?(Endpoints, :spot_place_order, 0)
      assert function_exported?(Endpoints, :spot_place_order, 1)
      assert function_exported?(Endpoints, :spot_place_order, 2)

      assert function_exported?(Endpoints, :spot_cancel_order, 0)
      assert function_exported?(Endpoints, :spot_cancel_order, 1)
      assert function_exported?(Endpoints, :spot_cancel_order, 2)

      assert function_exported?(Endpoints, :spot_get_order, 0)
      assert function_exported?(Endpoints, :spot_get_order, 1)
      assert function_exported?(Endpoints, :spot_get_order, 2)
    end

    test "futures endpoints delegate to UsdmFutures module with usdm_ prefix" do
      # USD-M Futures functions should be available with usdm_ prefix
      assert function_exported?(Endpoints, :usdm_get_positions, 0)
      assert function_exported?(Endpoints, :usdm_get_positions, 1)
      assert function_exported?(Endpoints, :usdm_get_positions, 2)
    end

    test "portfolio margin endpoints delegate with portfolio_ prefix" do
      # Portfolio Margin functions should be available with portfolio_ prefix
      assert function_exported?(Endpoints, :portfolio_get_unified_account, 0)
      assert function_exported?(Endpoints, :portfolio_get_unified_account, 1)
      assert function_exported?(Endpoints, :portfolio_get_unified_account, 2)

      assert function_exported?(Endpoints, :portfolio_place_unified_order, 1)
      assert function_exported?(Endpoints, :portfolio_place_unified_order, 2)

      assert function_exported?(Endpoints, :portfolio_get_all_positions, 0)
      assert function_exported?(Endpoints, :portfolio_get_all_positions, 1)
      assert function_exported?(Endpoints, :portfolio_get_all_positions, 2)

      # Portfolio Margin endpoint registry functions should also be available
      assert function_exported?(Endpoints, :portfolio_account_information, 0)
      assert function_exported?(Endpoints, :portfolio_account_information, 1)
      assert function_exported?(Endpoints, :portfolio_account_information, 2)

      assert function_exported?(Endpoints, :portfolio_account_balance, 0)
      assert function_exported?(Endpoints, :portfolio_account_balance, 1)
      assert function_exported?(Endpoints, :portfolio_account_balance, 2)
    end

    test "complex spot operations are delegated correctly with prefix" do
      assert function_exported?(Endpoints, :spot_place_oco_order, 1)
      assert function_exported?(Endpoints, :spot_batch_cancel_orders, 1)
    end
  end

  describe "get_endpoint/1 routing with prefixes" do
    test "routes common operations to Common module (no prefix)" do
      endpoint = Endpoints.get_endpoint(:get_server_time)
      assert endpoint
      assert endpoint.operation == :get_server_time

      # Should match Common module's config
      common_endpoint = Common.get_endpoint(:get_server_time)
      assert endpoint == common_endpoint
    end

    test "routes spot_ prefixed operations to Spot module" do
      spot_ops = [:spot_get_balances, :spot_place_order, :spot_cancel_order, :spot_get_order]

      Enum.each(spot_ops, fn prefixed_op ->
        endpoint = Endpoints.get_endpoint(prefixed_op)
        assert endpoint != nil, "Failed to get endpoint for #{prefixed_op}"

        # Extract the base operation name
        base_op = prefixed_op |> Atom.to_string() |> String.replace_prefix("spot_", "") |> String.to_atom()

        # Should match Spot module's config for the base operation
        spot_endpoint = Spot.get_endpoint(base_op)
        assert endpoint == spot_endpoint, "Mismatch for #{prefixed_op}"
      end)
    end

    test "routes usdm_ prefixed operations to UsdmFutures module" do
      endpoint = Endpoints.get_endpoint(:usdm_get_positions)
      assert endpoint
      assert endpoint.operation == :get_positions

      # Should match UsdmFutures module's config
      futures_endpoint = UsdmFutures.get_endpoint(:get_positions)
      assert endpoint == futures_endpoint
    end

    test "routes portfolio_ prefixed operations to PortfolioMargin module" do
      # Test with actual endpoint registry operations from PortfolioMargin
      portfolio_ops = [:portfolio_account_information, :portfolio_account_balance]

      Enum.each(portfolio_ops, fn prefixed_op ->
        endpoint = Endpoints.get_endpoint(prefixed_op)
        assert endpoint != nil, "Failed to get endpoint for #{prefixed_op}"

        # Extract the base operation name
        base_op = prefixed_op |> Atom.to_string() |> String.replace_prefix("portfolio_", "") |> String.to_atom()

        # Should match PortfolioMargin module's config for the base operation
        portfolio_endpoint = ZenCex.Adapters.Binance.PortfolioMargin.get_endpoint(base_op)
        assert endpoint == portfolio_endpoint, "Mismatch for #{prefixed_op}"
      end)
    end

    test "returns nil for unknown operations" do
      assert Endpoints.get_endpoint(:unknown_operation) == nil
      assert Endpoints.get_endpoint(:invalid_prefix_operation) == nil
    end
  end

  describe "all_endpoints/0 aggregation" do
    test "combines endpoints from all modules" do
      all_endpoints = Endpoints.all_endpoints()

      # Should have endpoints from Common, Spot, and UsdmFutures
      operations = Enum.map(all_endpoints, & &1.operation)

      # From Common
      assert :get_server_time in operations

      # From Spot
      assert :get_balances in operations
      assert :place_order in operations
      assert :cancel_order in operations
      assert :get_order in operations

      # From UsdmFutures
      assert :get_positions in operations
    end

    test "duplicate operations from different API types are allowed" do
      all_endpoints = Endpoints.all_endpoints()

      # Group by operation and API type to ensure duplicates are from different APIs
      # Use :common as default for endpoints without api_type
      grouped =
        Enum.group_by(all_endpoints, fn e ->
          api_type = Map.get(e, :api_type, :common)
          {e.operation, api_type}
        end)

      # Check that each operation+api_type combination is unique
      for {key, endpoints} <- grouped do
        assert length(endpoints) == 1,
               "Found duplicate endpoint for #{inspect(key)}: #{inspect(endpoints)}"
      end

      # Verify we do have some operations that exist in multiple API types (like get_balances)
      operations_by_name = Enum.group_by(all_endpoints, & &1.operation)
      multi_api_ops = Enum.filter(operations_by_name, fn {_op, endpoints} -> length(endpoints) > 1 end)

      assert length(multi_api_ops) > 0,
             "Expected some operations to exist in multiple API types"
    end
  end

  describe "get_weight/1 routing with prefixes" do
    test "returns correct weight for common operations (no prefix)" do
      assert Endpoints.get_weight(:get_server_time) == 1
    end

    test "returns correct weight for spot operations with prefix" do
      # Correctly extracted from OpenAPI docs
      assert Endpoints.get_weight(:spot_get_balances) == 20
      assert Endpoints.get_weight(:spot_place_order) == 1
      assert Endpoints.get_weight(:spot_cancel_order) == 1
      # Correctly extracted from OpenAPI docs
      assert Endpoints.get_weight(:spot_get_order) == 4
    end

    test "returns correct weight for futures operations with prefix" do
      assert Endpoints.get_weight(:usdm_get_positions) == 5
    end

    test "returns nil for unknown operations" do
      assert Endpoints.get_weight(:unknown_operation) == nil
      assert Endpoints.get_weight(:invalid_prefix_operation) == nil
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
    test "current_env/0 respects BINANCE_TESTNET env variable for production (default)" do
      # Test production (default)
      with_env [{"BINANCE_TESTNET", nil}] do
        clear_environment_cache(Endpoints)
        assert Endpoints.current_env() == :prod
      end

      with_env [{"BINANCE_TESTNET", "false"}] do
        clear_environment_cache(Endpoints)
        assert Endpoints.current_env() == :prod
      end

      with_env [{"BINANCE_TESTNET", ""}] do
        clear_environment_cache(Endpoints)
        assert Endpoints.current_env() == :prod
      end
    end

    test "current_env/0 respects BINANCE_TESTNET env variable for testnet" do
      with_env [{"BINANCE_TESTNET", "true"}] do
        clear_environment_cache(Endpoints)
        assert Endpoints.current_env() == :test
      end

      with_env [{"BINANCE_TESTNET", "1"}] do
        clear_environment_cache(Endpoints)
        assert Endpoints.current_env() == :test
      end

      with_env [{"BINANCE_TESTNET", "TRUE"}] do
        clear_environment_cache(Endpoints)
        assert Endpoints.current_env() == :test
      end
    end

    test "current_env/0 raises error for invalid BINANCE_TESTNET values" do
      with_env [{"BINANCE_TESTNET", "yes"}] do
        clear_environment_cache(Endpoints)

        assert_raise ArgumentError, ~r/Invalid value for BINANCE_TESTNET: "yes"/, fn ->
          Endpoints.current_env()
        end
      end

      with_env [{"BINANCE_TESTNET", "maybe"}] do
        clear_environment_cache(Endpoints)

        assert_raise ArgumentError, ~r/Invalid value for BINANCE_TESTNET: "maybe"/, fn ->
          Endpoints.current_env()
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
      assert Endpoints.base_url(:test, :usdm_futures) == "https://testnet.binancefuture.com"
      assert Endpoints.base_url(:test, :margin) == "https://testnet.binance.vision"
      # SAPI endpoints are not available on testnet
      assert Endpoints.base_url(:test, :sapi) == {:error, :no_testnet_for_sapi}
      assert Endpoints.base_url(:test, :coinm_futures) == "https://testnet.binancefuture.com"
      # Portfolio Margin has no testnet
      assert Endpoints.base_url(:test, :portfolio) == {:error, :no_testnet_for_portfolio_margin}

      # Production environment
      assert Endpoints.base_url(:prod, :spot) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :usdm_futures) == "https://fapi.binance.com"
      assert Endpoints.base_url(:prod, :margin) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :sapi) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :coinm_futures) == "https://dapi.binance.com"
      assert Endpoints.base_url(:prod, :portfolio) == "https://papi.binance.com"
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

    test "get_endpoint/1 provides registry-compatible interface with prefixes" do
      # Should work for all known operations with prefixes
      operations = [
        # common (no prefix)
        {:get_server_time, :get_server_time},
        {:spot_get_balances, :get_balances},
        {:spot_place_order, :place_order},
        {:spot_cancel_order, :cancel_order},
        {:spot_get_order, :get_order},
        {:usdm_get_positions, :get_positions},
        # Use actual endpoint registry operations from PortfolioMargin
        {:portfolio_account_information, :account_information},
        {:portfolio_account_balance, :account_balance}
      ]

      Enum.each(operations, fn {prefixed_op, base_op} ->
        config = Endpoints.get_endpoint(prefixed_op)
        assert config != nil, "get_endpoint/1 failed for #{prefixed_op}"
        assert is_map(config)
        assert config.operation == base_op, "Expected operation #{base_op}, got #{config.operation}"
      end)
    end
  end
end
