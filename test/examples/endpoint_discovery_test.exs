defmodule ZenCex.Examples.EndpointDiscoveryTest do
  use ExUnit.Case, async: true

  alias ZenCex.Examples.EndpointDiscovery

  @moduletag :example

  describe "list_all_endpoints/0" do
    test "returns list of all available operations" do
      assert {:ok, endpoints} = EndpointDiscovery.list_all_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) > 0
    end

    test "includes common operations across API types" do
      assert {:ok, endpoints} = EndpointDiscovery.list_all_endpoints()

      # Should include spot operations
      assert :get_balances in endpoints
      assert :place_order in endpoints

      # Should include futures operations
      assert :get_positions in endpoints
    end

    test "returns sorted unique list" do
      assert {:ok, endpoints} = EndpointDiscovery.list_all_endpoints()

      # Should be sorted
      assert endpoints == Enum.sort(endpoints)

      # Should be unique (no duplicates)
      assert length(endpoints) == length(Enum.uniq(endpoints))
    end

    test "operations are atoms" do
      assert {:ok, endpoints} = EndpointDiscovery.list_all_endpoints()
      assert Enum.all?(endpoints, &is_atom/1)
    end
  end

  describe "list_spot_endpoints/0" do
    test "returns list of spot trading operations" do
      assert {:ok, endpoints} = EndpointDiscovery.list_spot_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) > 0
    end

    test "includes expected spot operations" do
      assert {:ok, endpoints} = EndpointDiscovery.list_spot_endpoints()

      # Core account operations
      assert :get_balances in endpoints

      # Order operations
      assert :place_order in endpoints
      assert :cancel_order in endpoints

      # Query operations
      assert :get_order in endpoints
      assert :get_open_orders in endpoints
    end

    test "returns sorted list" do
      assert {:ok, endpoints} = EndpointDiscovery.list_spot_endpoints()
      assert endpoints == Enum.sort(endpoints)
    end

    test "spot list is subset of all endpoints" do
      assert {:ok, all_endpoints} = EndpointDiscovery.list_all_endpoints()
      assert {:ok, spot_endpoints} = EndpointDiscovery.list_spot_endpoints()

      # Every spot endpoint should be in all endpoints
      assert Enum.all?(spot_endpoints, fn op -> op in all_endpoints end)
    end
  end

  describe "list_futures_endpoints/0" do
    test "returns list of futures trading operations" do
      assert {:ok, endpoints} = EndpointDiscovery.list_futures_endpoints()
      assert is_list(endpoints)
      assert length(endpoints) > 0
    end

    test "includes expected futures operations" do
      assert {:ok, endpoints} = EndpointDiscovery.list_futures_endpoints()

      # Position management
      assert :get_positions in endpoints

      # Order operations
      assert :place_order in endpoints
      assert :cancel_order in endpoints
    end

    test "returns sorted list" do
      assert {:ok, endpoints} = EndpointDiscovery.list_futures_endpoints()
      assert endpoints == Enum.sort(endpoints)
    end

    test "futures list is subset of all endpoints" do
      assert {:ok, all_endpoints} = EndpointDiscovery.list_all_endpoints()
      assert {:ok, futures_endpoints} = EndpointDiscovery.list_futures_endpoints()

      # Every futures endpoint should be in all endpoints
      assert Enum.all?(futures_endpoints, fn op -> op in all_endpoints end)
    end

    test "spot and futures have different operations" do
      assert {:ok, spot_endpoints} = EndpointDiscovery.list_spot_endpoints()
      assert {:ok, futures_endpoints} = EndpointDiscovery.list_futures_endpoints()

      # Both have some common operations (like place_order)
      assert :place_order in spot_endpoints
      assert :place_order in futures_endpoints

      # :get_positions is futures-specific
      assert :get_positions in futures_endpoints
      refute :get_positions in spot_endpoints
    end
  end

  describe "get_endpoint_details/2" do
    test "returns detailed info for valid spot endpoint" do
      assert {:ok, info} = EndpointDiscovery.get_endpoint_details(:get_balances, :spot)

      # Required fields
      assert info[:operation] == :get_balances
      assert info[:method] in [:get, :post, :delete, :put]
      assert is_binary(info[:path])
      assert is_boolean(info[:requires_auth])
      assert is_integer(info[:weight])
      assert info[:api_type] == :spot

      # Module should be Binance.Spot
      assert info[:module] == ZenCex.Adapters.Binance.Spot

      # Should have available arities
      assert is_list(info[:available_arities])
      assert length(info[:available_arities]) > 0
    end

    test "returns detailed info for valid futures endpoint" do
      assert {:ok, info} = EndpointDiscovery.get_endpoint_details(:get_positions, :usdm_futures)

      assert info[:operation] == :get_positions
      assert info[:api_type] == :usdm_futures
      assert info[:module] == ZenCex.Adapters.Binance.UsdmFutures
      assert is_boolean(info[:requires_auth])
    end

    test "returns error for nonexistent operation" do
      assert {:error, :not_found} =
               EndpointDiscovery.get_endpoint_details(:nonexistent_operation, :spot)
    end

    test "returns error for operation in wrong API type" do
      # :get_positions exists in futures but not in spot
      assert {:error, :not_found} =
               EndpointDiscovery.get_endpoint_details(:get_positions, :spot)
    end

    test "get_balances requires authentication" do
      assert {:ok, info} = EndpointDiscovery.get_endpoint_details(:get_balances, :spot)
      assert info[:requires_auth] == true
    end

    test "place_order is POST method" do
      assert {:ok, info} = EndpointDiscovery.get_endpoint_details(:place_order, :spot)
      assert info[:method] == :post
    end

    test "operations have rate limit weights" do
      assert {:ok, spot_info} = EndpointDiscovery.get_endpoint_details(:get_balances, :spot)
      assert is_integer(spot_info[:weight])
      assert spot_info[:weight] > 0

      assert {:ok, futures_info} =
               EndpointDiscovery.get_endpoint_details(:get_positions, :usdm_futures)

      assert is_integer(futures_info[:weight])
      assert futures_info[:weight] > 0
    end

    test "available_arities reflects actual function exports" do
      assert {:ok, info} = EndpointDiscovery.get_endpoint_details(:get_balances, :spot)

      # Should have multiple arities (typically 0, 1, 2)
      arities = info[:available_arities]
      assert is_list(arities)

      # Verify these arities are actually exported
      module = info[:module]
      operation = info[:operation]

      Enum.each(arities, fn arity ->
        assert function_exported?(module, operation, arity),
               "#{inspect(module)}.#{operation}/#{arity} should be exported"
      end)
    end
  end

  describe "integration examples" do
    test "discover all endpoints and inspect details" do
      # List all endpoints
      assert {:ok, all_endpoints} = EndpointDiscovery.list_all_endpoints()
      assert length(all_endpoints) > 0

      # Pick a known endpoint and get details
      assert :place_order in all_endpoints
      assert {:ok, info} = EndpointDiscovery.get_endpoint_details(:place_order, :spot)

      # Verify we got useful information
      assert info[:operation] == :place_order
      assert info[:method] == :post
      assert info[:requires_auth] == true
      assert is_binary(info[:path])
    end

    test "compare spot and futures endpoints" do
      assert {:ok, spot} = EndpointDiscovery.list_spot_endpoints()
      assert {:ok, futures} = EndpointDiscovery.list_futures_endpoints()

      # Both should have order operations (but different implementations)
      assert :place_order in spot
      assert :place_order in futures

      # Get details for both
      assert {:ok, spot_order} = EndpointDiscovery.get_endpoint_details(:place_order, :spot)
      assert {:ok, futures_order} = EndpointDiscovery.get_endpoint_details(:place_order, :usdm_futures)

      # Same operation name, different API types
      assert spot_order[:operation] == futures_order[:operation]
      assert spot_order[:api_type] != futures_order[:api_type]

      # Different modules
      assert spot_order[:module] != futures_order[:module]
    end
  end
end
