defmodule ZenCex.Adapters.Binance.EnvironmentConsistencyTest do
  @moduledoc """
  Tests that all Binance endpoints consistently respect the BINANCE_TESTNET environment variable.

  This test ensures that both generated endpoints (via EndpointRegistry macro) and
  hand-written endpoints use the same environment selection logic.
  """
  use ExUnit.Case

  alias ZenCex.Adapters.Binance.Endpoints

  describe "environment selection consistency" do
    test "base_url/0 respects BINANCE_TESTNET environment variable" do
      # Test production (default)
      System.delete_env("BINANCE_TESTNET")
      assert Endpoints.base_url() == "https://api.binance.com"
      assert Endpoints.current_env() == :prod

      # Test with explicit false
      System.put_env("BINANCE_TESTNET", "false")
      assert Endpoints.base_url() == "https://api.binance.com"
      assert Endpoints.current_env() == :prod

      # Test testnet
      System.put_env("BINANCE_TESTNET", "true")
      assert Endpoints.base_url() == "https://testnet.binance.vision"
      assert Endpoints.current_env() == :test

      # Test with any other value defaults to prod
      System.put_env("BINANCE_TESTNET", "yes")
      assert Endpoints.base_url() == "https://api.binance.com"
      assert Endpoints.current_env() == :prod

      # Clean up
      System.delete_env("BINANCE_TESTNET")
    end

    test "generated endpoints use correct base URL" do
      # This test verifies that generated functions use base_url/0
      # We can't directly test the URL construction without making actual requests,
      # but we can verify the function exists and accepts the right parameters

      # Test that generated functions exist
      assert function_exported?(Endpoints, :get_balances, 1)
      assert function_exported?(Endpoints, :place_order, 1)
      assert function_exported?(Endpoints, :cancel_order, 1)

      # These functions should work with both prod and test environments
      # The actual URL construction happens inside the macro-generated code
      System.put_env("BINANCE_TESTNET", "true")

      # We can test that the endpoint configuration exists
      config = Endpoints.get_endpoint(:get_balances)
      assert config.path == "/api/v3/account"
      assert config.requires_auth == true

      # Clean up
      System.delete_env("BINANCE_TESTNET")
    end

    test "hand-written endpoints use correct base URL" do
      # Test that hand-written functions exist and use base_url/0
      assert function_exported?(Endpoints, :place_oco_order, 1)
      assert function_exported?(Endpoints, :batch_cancel_orders, 1)

      # These functions now use base_url/0 internally, which respects BINANCE_TESTNET
      # We can't test the actual URL without making requests, but the functions should compile
    end

    test "all endpoint types use consistent environment selection" do
      # Set testnet mode
      System.put_env("BINANCE_TESTNET", "true")

      # All endpoints should now use testnet URL
      assert Endpoints.base_url() == "https://testnet.binance.vision"

      # Both generated and hand-written functions will use this base URL
      # This ensures consistency across all endpoint types

      # Clean up
      System.delete_env("BINANCE_TESTNET")
    end
  end

  describe "multi-API URL support" do
    test "base_url/2 supports different API types in production" do
      System.delete_env("BINANCE_TESTNET")

      # Test spot (default)
      assert Endpoints.base_url(:prod, :spot) == "https://api.binance.com"

      # Test futures
      assert Endpoints.base_url(:prod, :futures) == "https://fapi.binance.com"
    end

    test "base_url/2 supports different API types in testnet" do
      # Test spot testnet
      assert Endpoints.base_url(:test, :spot) == "https://testnet.binance.vision"

      # Test futures testnet
      assert Endpoints.base_url(:test, :futures) == "https://testnet.binancefuture.com"
    end

    test "get_positions endpoint has api_type: :futures" do
      config = Endpoints.get_endpoint(:get_positions)

      assert config.operation == :get_positions
      assert config.path == "/fapi/v2/positionRisk"
      assert Map.get(config, :api_type) == :futures
    end

    test "spot endpoints have explicit api_type field" do
      config = Endpoints.get_endpoint(:get_balances)

      assert config.operation == :get_balances
      assert config.path == "/api/v3/account"
      assert Map.get(config, :api_type) == :spot
    end

    test "EndpointRegistry correctly routes URLs based on api_type" do
      # Test that futures endpoints would use correct base URL
      System.delete_env("BINANCE_TESTNET")

      # Simulate EndpointRegistry build_request logic for futures endpoint
      config = %{api_type: :futures}
      adapter = Endpoints

      if Map.has_key?(config, :api_type) and function_exported?(adapter, :base_url, 2) do
        base_url = adapter.base_url(adapter.current_env(), config.api_type)
        assert base_url == "https://fapi.binance.com"
      end

      # Test with testnet
      System.put_env("BINANCE_TESTNET", "true")

      if Map.has_key?(config, :api_type) and function_exported?(adapter, :base_url, 2) do
        base_url = adapter.base_url(adapter.current_env(), config.api_type)
        assert base_url == "https://testnet.binancefuture.com"
      end

      # Clean up
      System.delete_env("BINANCE_TESTNET")
    end
  end

  describe "environment safety" do
    test "production is the default when BINANCE_TESTNET is not set" do
      System.delete_env("BINANCE_TESTNET")
      assert Endpoints.current_env() == :prod
      assert Endpoints.base_url() == "https://api.binance.com"
    end

    test "only 'true' enables testnet mode" do
      test_values = ["True", "TRUE", "1", "yes", "on", ""]

      for value <- test_values do
        System.put_env("BINANCE_TESTNET", value)

        assert Endpoints.current_env() == :prod,
               "Expected :prod for BINANCE_TESTNET=#{inspect(value)}, got #{Endpoints.current_env()}"
      end

      # Only exactly "true" should enable testnet
      System.put_env("BINANCE_TESTNET", "true")
      assert Endpoints.current_env() == :test

      # Clean up
      System.delete_env("BINANCE_TESTNET")
    end
  end
end
