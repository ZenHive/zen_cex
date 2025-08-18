defmodule ZenCex.Adapters.Binance.FuturesTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Futures

  describe "endpoint configuration" do
    test "get_positions configuration is correct" do
      config = Futures.get_endpoint(:get_positions)
      assert config.operation == :get_positions
      assert config.method == :get
      assert config.path == "/fapi/v2/positionRisk"
      assert config.api_type == :futures
      assert config.requires_auth == true
      assert config.weight == 5
      assert config.timeout == 5_000
      assert config.max_retries == 2
      assert config.retry_on == [:rate_limited, :timeout]
      assert is_function(config.response_parser, 1)
      assert is_function(config.error_mapping, 1)
    end
  end

  describe "get_endpoint/1" do
    test "returns correct config for :get_positions" do
      config = Futures.get_endpoint(:get_positions)
      assert config.operation == :get_positions
      assert config.api_type == :futures
    end

    test "returns nil for unknown operations" do
      assert Futures.get_endpoint(:unknown_operation) == nil
      assert Futures.get_endpoint(:place_order) == nil
      assert Futures.get_endpoint(:get_balances) == nil
    end
  end

  describe "all_endpoints/0" do
    test "returns list with positions endpoint" do
      endpoints = Futures.all_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) == 1

      config = hd(endpoints)
      assert config.operation == :get_positions
      assert config.api_type == :futures
    end
  end

  describe "function exports" do
    test "exports get_positions function" do
      assert function_exported?(Futures, :get_positions, 0)
      assert function_exported?(Futures, :get_positions, 1)
      assert function_exported?(Futures, :get_positions, 2)
    end
  end
end
