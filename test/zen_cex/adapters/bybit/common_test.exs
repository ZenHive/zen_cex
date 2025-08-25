defmodule ZenCex.Adapters.Bybit.CommonTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.Common

  describe "endpoint definitions" do
    test "all_endpoints/0 returns list of endpoint configs" do
      endpoints = Common.all_endpoints()

      assert is_list(endpoints)
      assert length(endpoints) == 2

      # Check that we have the expected endpoints
      operations = Enum.map(endpoints, & &1.operation)
      assert :get_server_time in operations
      assert :get_announcements in operations
    end

    test "get_endpoint/1 returns config for valid operation" do
      config = Common.get_endpoint(:get_server_time)

      assert config.operation == :get_server_time
      assert config.method == :get
      assert config.path == "/v5/market/time"
      assert config.requires_auth == false
      assert config.weight == 1
    end

    test "get_endpoint/1 returns nil for invalid operation" do
      assert Common.get_endpoint(:invalid_operation) == nil
    end
  end

  describe "server time endpoint" do
    test "get_server_time has correct configuration" do
      config = Common.get_endpoint(:get_server_time)

      assert config.method == :get
      assert config.path == "/v5/market/time"
      assert config.requires_auth == false
      assert config.weight == 1
      assert config.timeout == 2_000
      assert config.retry_on == [:timeout]
      assert is_function(config.response_parser, 1)
      assert is_function(config.error_mapping, 1)
    end
  end

  describe "announcements endpoint" do
    test "get_announcements has correct configuration" do
      config = Common.get_endpoint(:get_announcements)

      assert config.method == :get
      assert config.path == "/v5/announcements/index"
      assert config.requires_auth == false
      assert config.weight == 1
      assert config.timeout == 5_000
      assert config.retry_on == [:timeout]
      assert is_function(config.response_parser, 1)
      assert is_function(config.error_mapping, 1)
    end
  end
end
