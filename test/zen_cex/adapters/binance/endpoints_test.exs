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
    test "returns production URL by default" do
      url = Endpoints.base_url()
      assert is_binary(url)
      assert String.starts_with?(url, "https://")
      # base_url/0 always returns production spot URL
      assert url == "https://api.binance.com"
    end
  end

  describe "base_url/1" do
    test "returns correct URLs with testnet flag" do
      assert Endpoints.base_url(:spot, testnet: true) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:spot, testnet: false) == "https://api.binance.com"
      # defaults to production
      assert Endpoints.base_url(:spot) == "https://api.binance.com"
    end
  end

  describe "base_url/2" do
    test "returns correct testnet URLs for different API types" do
      # Spot and Margin use the same testnet
      assert Endpoints.base_url(:spot, testnet: true) == "https://testnet.binance.vision"
      assert Endpoints.base_url(:margin, testnet: true) == "https://testnet.binance.vision"

      # Futures APIs use different testnet
      assert Endpoints.base_url(:usdm_futures, testnet: true) == "https://testnet.binancefuture.com"
      assert Endpoints.base_url(:coinm_futures, testnet: true) == "https://testnet.binancefuture.com"

      # SAPI and Portfolio have no testnet
      assert Endpoints.base_url(:sapi, testnet: true) == {:error, :no_testnet_for_sapi}
      assert Endpoints.base_url(:portfolio, testnet: true) == {:error, :no_testnet_for_portfolio_margin}

      # Unknown API types default to spot testnet
      assert Endpoints.base_url(:unknown, testnet: true) == "https://testnet.binance.vision"
    end

    test "returns correct production URLs for different API types" do
      # Spot, Margin, and SAPI use the main API
      assert Endpoints.base_url(:spot, testnet: false) == "https://api.binance.com"
      assert Endpoints.base_url(:margin, testnet: false) == "https://api.binance.com"
      assert Endpoints.base_url(:sapi, testnet: false) == "https://api.binance.com"

      # Futures APIs have their own domains
      assert Endpoints.base_url(:usdm_futures, testnet: false) == "https://fapi.binance.com"
      assert Endpoints.base_url(:coinm_futures, testnet: false) == "https://dapi.binance.com"
      assert Endpoints.base_url(:portfolio, testnet: false) == "https://papi.binance.com"

      # Unknown API types default to main API
      assert Endpoints.base_url(:unknown, testnet: false) == "https://api.binance.com"
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
      # Registry and discovery functions
      assert {:get_module, 1} in exports
      assert {:list_api_types, 0} in exports
      assert {:list_available_endpoints, 0} in exports
      assert {:list_available_endpoints, 1} in exports
      assert {:get_endpoint_info, 2} in exports
    end
  end

  describe "discovery functions" do
    test "get_module/1 returns correct modules" do
      assert Endpoints.get_module(:spot) == ZenCex.Adapters.Binance.Spot
      assert Endpoints.get_module(:margin) == ZenCex.Adapters.Binance.Margin
      assert Endpoints.get_module(:usdm_futures) == ZenCex.Adapters.Binance.UsdmFutures
      assert Endpoints.get_module(:coinm_futures) == ZenCex.Adapters.Binance.CoinmFutures
      assert Endpoints.get_module(:portfolio) == ZenCex.Adapters.Binance.PortfolioMargin
      assert Endpoints.get_module(:common) == ZenCex.Adapters.Binance.Common
      assert Endpoints.get_module(:market_data) == ZenCex.Adapters.Binance.MarketData
      assert Endpoints.get_module(:unknown) == nil
    end

    test "list_api_types/0 returns all API types" do
      api_types = Endpoints.list_api_types()
      assert :spot in api_types
      assert :margin in api_types
      assert :usdm_futures in api_types
      assert :coinm_futures in api_types
      assert :portfolio in api_types
      assert :common in api_types
      assert :market_data in api_types
    end

    test "list_available_endpoints/0 returns endpoints from all modules" do
      endpoints = Endpoints.list_available_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) > 0

      # Check that endpoints are atoms
      Enum.each(endpoints, fn operation ->
        assert is_atom(operation)
      end)

      # Should include endpoints from various modules
      # from Common
      assert :get_server_time in endpoints
      # from Spot
      assert :get_balances in endpoints
    end

    test "list_available_endpoints/1 filters by API type" do
      spot_endpoints = Endpoints.list_available_endpoints(:spot)
      assert is_list(spot_endpoints)
      assert length(spot_endpoints) > 0

      # All endpoints should be atoms
      Enum.each(spot_endpoints, fn operation ->
        assert is_atom(operation)
      end)

      # Should include spot-specific endpoints
      assert :get_balances in spot_endpoints
      assert :place_order in spot_endpoints
    end

    test "get_endpoint_info/2 returns endpoint details" do
      # Test with Common module's get_server_time
      info = Endpoints.get_endpoint_info(:get_server_time, :common)
      assert is_map(info)
      assert info.path == "/api/v3/time"
      assert info.method == :get
      assert info.requires_auth == false

      # Test with unknown endpoint
      assert Endpoints.get_endpoint_info(:unknown, :spot) == nil
    end
  end
end
