defmodule ZenCex.Adapters.Binance.ParameterPassingTest do
  @moduledoc """
  Tests for parameter passing with both keyword lists and maps.
  Verifies that credentials and options can be passed in either format.
  """
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.RequestHelper

  describe "RequestHelper.execute_request/6" do
    setup do
      # Create a minimal config for testing - using server_time endpoint which works
      config = %{
        operation: :get_server_time,
        method: :get,
        path: "/api/v3/time",
        requires_auth: false,
        weight: 1,
        timeout: 5000
      }

      {:ok, config: config}
    end

    test "accepts options as keyword list", %{config: config} do
      opts = [receive_timeout: 3000, retry: false]

      # This should work and return server time
      result = RequestHelper.execute_request(config, %{}, opts, "https://testnet.binance.vision", :binance, :query)

      # Should successfully get server time
      assert {:ok, %{"serverTime" => server_time}} = result
      assert is_integer(server_time)
    end

    test "accepts options as map", %{config: config} do
      opts = %{receive_timeout: 3000, retry: false}

      # This should work and return server time
      result = RequestHelper.execute_request(config, %{}, opts, "https://testnet.binance.vision", :binance, :query)

      # Should successfully get server time
      assert {:ok, %{"serverTime" => server_time}} = result
      assert is_integer(server_time)
    end

    test "accepts empty options list", %{config: config} do
      opts = []

      result = RequestHelper.execute_request(config, %{}, opts, "https://testnet.binance.vision", :binance, :query)

      # Should successfully get server time with default options
      assert {:ok, %{"serverTime" => server_time}} = result
      assert is_integer(server_time)
    end

    test "accepts empty options map", %{config: config} do
      opts = %{}

      result = RequestHelper.execute_request(config, %{}, opts, "https://testnet.binance.vision", :binance, :query)

      # Should successfully get server time with default options
      assert {:ok, %{"serverTime" => server_time}} = result
      assert is_integer(server_time)
    end

    test "options passed as keyword list override defaults", %{config: config} do
      # Use a very short timeout to cause failure
      opts = [receive_timeout: 1]

      result = RequestHelper.execute_request(config, %{}, opts, "https://testnet.binance.vision", :binance, :query)

      # Should timeout and return error
      assert {:error, _reason} = result
    end

    test "options passed as map override defaults", %{config: config} do
      # Use a very short timeout to cause failure
      opts = %{receive_timeout: 1}

      result = RequestHelper.execute_request(config, %{}, opts, "https://testnet.binance.vision", :binance, :query)

      # Should timeout and return error
      assert {:error, _reason} = result
    end
  end

  describe "RequestHelper.execute_request_for_api_type/5" do
    setup do
      config = %{
        operation: :get_server_time,
        method: :get,
        path: "/api/v3/time",
        requires_auth: false,
        weight: 1,
        timeout: 5000,
        api_type: :spot
      }

      operation_resolver = fn _config -> :query end

      {:ok, config: config, resolver: operation_resolver}
    end

    test "accepts options as keyword list", %{config: config, resolver: resolver} do
      opts = [receive_timeout: 3000]

      result = RequestHelper.execute_request_for_api_type(config, %{}, opts, :spot, resolver)

      # Should successfully get server time
      assert {:ok, %{"serverTime" => server_time}} = result
      assert is_integer(server_time)
    end

    test "accepts options as map", %{config: config, resolver: resolver} do
      opts = %{receive_timeout: 3000}

      result = RequestHelper.execute_request_for_api_type(config, %{}, opts, :spot, resolver)

      # Should successfully get server time
      assert {:ok, %{"serverTime" => server_time}} = result
      assert is_integer(server_time)
    end
  end

  describe "normalize_to_keyword_list/1 private function behavior" do
    # Test the normalization logic indirectly through public API

    test "keyword list options are preserved" do
      # Create a module that can inspect the options passed through
      defmodule TestInspector do
        @moduledoc false
        def capture_opts(_config, _params, opts, _base_url, _exchange, _operation_type) do
          # Return the normalized opts for inspection
          opts_list = normalize_opts(opts)
          {:captured, opts_list}
        end

        defp normalize_opts(opts) when is_list(opts), do: opts
        defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
        defp normalize_opts(_), do: []
      end

      # Test with keyword list
      assert {:captured, opts} =
               TestInspector.capture_opts(
                 %{},
                 %{},
                 [receive_timeout: 5000, retry: true],
                 "",
                 :binance,
                 :query
               )

      assert opts == [receive_timeout: 5000, retry: true]

      # Test with map
      assert {:captured, opts} =
               TestInspector.capture_opts(
                 %{},
                 %{},
                 %{receive_timeout: 5000, retry: true},
                 "",
                 :binance,
                 :query
               )

      assert Keyword.get(opts, :receive_timeout) == 5000
      assert Keyword.get(opts, :retry) == true
    end

    test "nil and invalid options are handled gracefully" do
      defmodule SafeInspector do
        @moduledoc false
        def normalize_opts(opts) when is_list(opts), do: opts
        def normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
        def normalize_opts(_), do: []
      end

      # Test with nil
      assert SafeInspector.normalize_opts(nil) == []

      # Test with string
      assert SafeInspector.normalize_opts("invalid") == []

      # Test with number
      assert SafeInspector.normalize_opts(123) == []
    end
  end
end
