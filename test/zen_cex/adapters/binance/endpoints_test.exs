defmodule ZenCex.Adapters.Binance.EndpointsTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Auth
  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RateLimiter

  describe "__exchange__/0" do
    test "returns :binance" do
      assert Endpoints.__exchange__() == :binance
    end
  end

  describe "auth/0" do
    test "returns the Auth module" do
      assert Endpoints.auth() == Auth
    end
  end

  describe "rate_limiter/0" do
    test "returns the RateLimiter module" do
      assert Endpoints.rate_limiter() == RateLimiter
    end
  end

  describe "parser/0" do
    test "returns the Parser module" do
      assert Endpoints.parser() == Parser
    end
  end

  describe "current_env/0" do
    test "returns environment based on BINANCE_TESTNET" do
      # The test environment is determined by BINANCE_TESTNET env var
      # which is likely set to "true" in test environment
      env = Endpoints.current_env()
      assert env in [:test, :prod]
    end
  end

  describe "base_url/0" do
    test "returns URL based on current environment" do
      url = Endpoints.base_url()
      assert is_binary(url)
      assert String.starts_with?(url, "https://")

      # Should match the current environment
      env = Endpoints.current_env()
      expected = if env == :test, do: "https://testnet.binance.vision", else: "https://api.binance.com"
      assert url == expected
    end
  end

  describe "base_url/1" do
    test "returns correct URLs for test environment" do
      assert Endpoints.base_url(:test) == "https://testnet.binance.vision"
    end

    test "returns correct URLs for prod environment" do
      assert Endpoints.base_url(:prod) == "https://api.binance.com"
    end
  end

  describe "base_url/2" do
    test "returns correct testnet URLs for different API types" do
      # Spot and Margin use the same testnet
      assert Endpoints.base_url(:test, :spot) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:test, :margin) == "https://testnet.binance.vision"

      # Futures APIs use different testnet
      assert Endpoints.base_url(:test, :usdm_futures) == "https://testnet.binancefuture.com"
      assert Endpoints.base_url(:test, :coinm_futures) == "https://testnet.binancefuture.com"
      assert Endpoints.base_url(:test, :portfolio) == "https://testnet.binancefuture.com"

      # SAPI has no testnet
      assert Endpoints.base_url(:test, :sapi) == {:error, :no_testnet_for_sapi}

      # Unknown API types default to spot testnet
      assert Endpoints.base_url(:test, :unknown) == "https://testnet.binance.vision"
    end

    test "returns correct production URLs for different API types" do
      # Spot, Margin, and SAPI use the main API
      assert Endpoints.base_url(:prod, :spot) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :margin) == "https://api.binance.com"
      assert Endpoints.base_url(:prod, :sapi) == "https://api.binance.com"

      # Futures APIs have their own domains
      assert Endpoints.base_url(:prod, :usdm_futures) == "https://fapi.binance.com"
      assert Endpoints.base_url(:prod, :coinm_futures) == "https://dapi.binance.com"
      assert Endpoints.base_url(:prod, :portfolio) == "https://papi.binance.com"

      # Unknown API types default to main API
      assert Endpoints.base_url(:prod, :unknown) == "https://api.binance.com"
    end
  end

  describe "get_endpoint/1" do
    test "returns endpoint configuration for known operations" do
      # Test common endpoint (we know this exists)
      endpoint = Endpoints.get_endpoint(:get_server_time)
      assert is_map(endpoint)
      assert endpoint.path == "/api/v3/time"
      assert endpoint.method == :get
      assert endpoint.requires_auth == false
      assert endpoint.weight == 1
    end

    test "returns nil for unknown operations" do
      assert Endpoints.get_endpoint(:unknown_operation) == nil
      assert Endpoints.get_endpoint(:not_defined) == nil
    end
  end

  describe "all_endpoints/0" do
    test "returns all registered endpoints as a list" do
      endpoints = Endpoints.all_endpoints()

      # Should be a list
      assert is_list(endpoints)
      assert length(endpoints) > 0

      # Each endpoint should be a map with required fields
      Enum.each(endpoints, fn config ->
        assert is_map(config)
        assert Map.has_key?(config, :path)
        assert Map.has_key?(config, :method)
        assert Map.has_key?(config, :operation)
        # Note: uses requires_auth, not auth
        assert Map.has_key?(config, :requires_auth)
      end)
    end

    test "endpoints have valid method values" do
      endpoints = Endpoints.all_endpoints()

      valid_methods = [:get, :post, :delete, :put]

      Enum.each(endpoints, fn config ->
        assert config.method in valid_methods,
               "Endpoint #{config.operation} has invalid method: #{config.method}"
      end)
    end

    test "endpoints have valid requires_auth values" do
      endpoints = Endpoints.all_endpoints()

      Enum.each(endpoints, fn config ->
        assert is_boolean(config.requires_auth),
               "Endpoint #{config.operation} has invalid requires_auth value: #{config.requires_auth}"
      end)
    end

    test "endpoints have weight values" do
      endpoints = Endpoints.all_endpoints()

      Enum.each(endpoints, fn config ->
        if Map.has_key?(config, :weight) do
          assert is_integer(config.weight) and config.weight > 0,
                 "Endpoint #{config.operation} has invalid weight: #{config.weight}"
        end
      end)
    end
  end

  describe "get_weight/1" do
    test "returns weight for operations with defined weights" do
      # Test with an operation we know exists
      weight = Endpoints.get_weight(:get_server_time)
      assert weight == 1
    end

    test "returns nil for unknown operations" do
      assert Endpoints.get_weight(:unknown_operation) == nil
      assert Endpoints.get_weight(:not_defined) == nil
    end
  end

  describe "module exports" do
    test "module implements required callbacks" do
      # Verify the module exports the required functions
      exports = Endpoints.__info__(:functions)

      assert {:__exchange__, 0} in exports
      assert {:auth, 0} in exports
      assert {:rate_limiter, 0} in exports
      assert {:parser, 0} in exports
      assert {:current_env, 0} in exports
      assert {:base_url, 0} in exports
      assert {:base_url, 1} in exports
      assert {:base_url, 2} in exports
      assert {:get_endpoint, 1} in exports
      assert {:all_endpoints, 0} in exports
      assert {:get_weight, 1} in exports
    end
  end

  describe "edge cases and error handling" do
    test "handles nil operation names gracefully" do
      assert Endpoints.get_endpoint(nil) == nil
      assert Endpoints.get_weight(nil) == nil
    end

    test "handles atom operations that don't match any pattern" do
      assert Endpoints.get_endpoint(:some_random_atom) == nil
      assert Endpoints.get_weight(:some_random_atom) == nil
    end

    test "all_endpoints returns consistent structure" do
      endpoints1 = Endpoints.all_endpoints()
      endpoints2 = Endpoints.all_endpoints()

      # Should return the same list each time
      assert endpoints1 == endpoints2
    end
  end
end
