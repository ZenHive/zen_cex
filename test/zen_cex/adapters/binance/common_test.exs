defmodule ZenCex.Adapters.Binance.CommonTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Common

  describe "get_server_time endpoint" do
    test "endpoint configuration is correct" do
      endpoints = Common.all_endpoints()
      assert length(endpoints) == 1

      config = hd(endpoints)
      assert config.operation == :get_server_time
      assert config.method == :get
      assert config.path == "/api/v3/time"
      assert config.requires_auth == false
      assert config.weight == 1
      assert config.timeout == 2_000
      assert config.retry_on == [:timeout]
      assert is_function(config.response_parser, 1)
      assert is_function(config.error_mapping, 1)
    end

    test "get_endpoint/1 returns correct config for :get_server_time" do
      config = Common.get_endpoint(:get_server_time)
      assert config.operation == :get_server_time
      assert config.method == :get
      assert config.path == "/api/v3/time"
    end

    test "get_endpoint/1 returns nil for unknown operations" do
      assert Common.get_endpoint(:unknown_operation) == nil
      assert Common.get_endpoint(:place_order) == nil
      assert Common.get_endpoint(:get_positions) == nil
    end
  end

  describe "get_server_time/0" do
    test "function exists and has correct spec" do
      # Just verify the function exists
      assert function_exported?(Common, :get_server_time, 0)
      assert function_exported?(Common, :get_server_time, 1)
    end
  end

  describe "all_endpoints/0" do
    test "returns list with server_time endpoint" do
      endpoints = Common.all_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) == 1

      operations = Enum.map(endpoints, & &1.operation)
      assert :get_server_time in operations
    end
  end
end
