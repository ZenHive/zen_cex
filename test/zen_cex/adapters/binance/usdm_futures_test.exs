defmodule ZenCex.Adapters.Binance.UsdmFuturesTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.UsdmFutures

  describe "endpoint configuration" do
    test "get_positions configuration is correct" do
      config = UsdmFutures.get_endpoint(:get_positions)
      assert config.operation == :get_positions
      assert config.method == :get
      assert config.path == "/fapi/v3/positionRisk"
      assert config.api_type == :usdm_futures
      assert config.requires_auth == true
      assert config.weight == 5
      assert config.timeout == 5_000
      assert config.max_retries == 3
      assert config.retry_on == [:rate_limited, :timeout, :server_error]
      assert is_function(config.response_parser, 1)
      assert is_function(config.error_mapping, 1)
    end
  end

  describe "get_endpoint/1" do
    test "returns correct config for :get_positions" do
      config = UsdmFutures.get_endpoint(:get_positions)
      assert config.operation == :get_positions
      assert config.api_type == :usdm_futures
    end

    test "returns nil for unknown operations" do
      assert UsdmFutures.get_endpoint(:unknown_operation) == nil
      assert UsdmFutures.get_endpoint(:fake_endpoint) == nil
      assert UsdmFutures.get_endpoint("not_an_atom") == nil
    end
  end

  describe "all_endpoints/0" do
    test "returns list with multiple futures endpoints" do
      endpoints = UsdmFutures.all_endpoints()
      assert is_list(endpoints)
      # After removing filtering: 37 -> 48 endpoints (comprehensive coverage)
      assert length(endpoints) == 54

      # Check that get_positions endpoint exists
      positions_endpoint = Enum.find(endpoints, fn e -> e.operation == :get_positions end)
      assert positions_endpoint
      assert positions_endpoint.api_type == :usdm_futures
    end
  end

  describe "function exports" do
    test "exports get_positions function" do
      # Functions with optional params have arity 1 and 2, not 0
      assert function_exported?(UsdmFutures, :get_positions, 1)
      assert function_exported?(UsdmFutures, :get_positions, 2)
    end
  end
end
