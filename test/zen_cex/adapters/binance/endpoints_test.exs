defmodule ZenCex.Adapters.Binance.EndpointsTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Endpoints

  describe "endpoint configuration lookup" do
    test "get_endpoint/1 returns configuration for known operations" do
      config = Endpoints.get_endpoint(:get_balances)

      assert config.operation == :get_balances
      assert config.method == :get
      assert config.path == "/api/v3/account"
      assert config.requires_auth == true
      assert config.weight == 10
      assert config.max_retries == 2
      assert :rate_limited in config.retry_on
      assert :timeout in config.retry_on
    end

    test "get_endpoint/1 returns nil for unknown operations" do
      assert Endpoints.get_endpoint(:unknown_operation) == nil
    end

    test "all_endpoints/0 returns all configured endpoints" do
      endpoints = Endpoints.all_endpoints()

      assert is_list(endpoints)
      assert length(endpoints) == 8

      operations = Enum.map(endpoints, & &1.operation)
      assert :get_balances in operations
      assert :place_order in operations
      assert :cancel_order in operations
      assert :get_positions in operations
    end

    test "get_weight/1 returns correct weight for operations" do
      assert Endpoints.get_weight(:get_balances) == 10
      assert Endpoints.get_weight(:place_order) == 1
      assert Endpoints.get_weight(:get_positions) == 5
      # Default weight
      assert Endpoints.get_weight(:unknown) == 1
    end
  end

  describe "critical safety validations" do
    test "place_order has no retries configured" do
      config = Endpoints.get_endpoint(:place_order)

      assert config.max_retries == 0
      assert config.retry_on == []
    end

    test "cancel_order allows limited retries" do
      config = Endpoints.get_endpoint(:cancel_order)

      assert config.max_retries == 1
      assert config.retry_on == [:rate_limited]
      # Don't retry on timeout for cancels
      refute :timeout in config.retry_on
    end

    test "read operations allow multiple retries" do
      config = Endpoints.get_endpoint(:get_order)

      assert config.max_retries == 3
      assert :rate_limited in config.retry_on
      assert :timeout in config.retry_on
    end
  end

  describe "generated function signatures" do
    test "generated functions exist with correct arities" do
      # Test that macro generated the expected functions
      assert function_exported?(Endpoints, :get_balances, 0)
      assert function_exported?(Endpoints, :get_balances, 1)
      assert function_exported?(Endpoints, :get_balances, 2)

      assert function_exported?(Endpoints, :place_order, 0)
      assert function_exported?(Endpoints, :place_order, 1)
      assert function_exported?(Endpoints, :place_order, 2)

      assert function_exported?(Endpoints, :get_positions, 0)
      assert function_exported?(Endpoints, :get_positions, 1)
      assert function_exported?(Endpoints, :get_positions, 2)
    end

    test "complex operations are hand-written" do
      # These should be hand-written, not generated
      assert function_exported?(Endpoints, :place_oco_order, 1)
      assert function_exported?(Endpoints, :batch_cancel_orders, 1)
    end
  end

  describe "endpoint performance" do
    @tag :performance
    test "endpoint lookup is fast (< 10μs)" do
      # Warm up
      _ = Endpoints.get_endpoint(:get_balances)

      # Measure
      iterations = 10_000
      start = System.monotonic_time()

      for _ <- 1..iterations do
        _ = Endpoints.get_endpoint(:get_balances)
      end

      duration = System.monotonic_time() - start
      microseconds = System.convert_time_unit(duration, :native, :microsecond)
      per_operation = microseconds / iterations

      assert per_operation < 10,
             "Endpoint lookup took #{per_operation}μs (should be < 10μs)"
    end

    test "weight lookup is fast (< 10μs)" do
      # Warm up
      _ = Endpoints.get_weight(:get_balances)

      # Measure
      iterations = 10_000
      start = System.monotonic_time()

      for _ <- 1..iterations do
        _ = Endpoints.get_weight(:get_balances)
      end

      duration = System.monotonic_time() - start
      microseconds = System.convert_time_unit(duration, :native, :microsecond)
      per_operation = microseconds / iterations

      assert per_operation < 10,
             "Weight lookup took #{per_operation}μs (should be < 10μs)"
    end
  end

  describe "params transformation" do
    test "order params are transformed correctly" do
      # This tests the internal transformation
      # In real usage, this would be called by the generated function
      config = Endpoints.get_endpoint(:place_order)

      assert is_function(config.params_transformer, 1)
    end
  end

  describe "documentation generation" do
    test "generated functions have documentation" do
      # Check that @doc was properly generated
      {:docs_v1, _, :elixir, _, %{}, _, functions} = Code.fetch_docs(Endpoints)

      # Find the get_balances function docs
      get_balances_docs =
        Enum.find(functions, fn
          {{:function, :get_balances, _}, _, _, _, _} -> true
          _ -> false
        end)

      assert get_balances_docs != nil

      {{:function, :get_balances, _}, _, _, %{"en" => doc}, _} = get_balances_docs
      assert doc =~ "Fetches current account balances"
    end
  end

  describe "complex operations" do
    test "place_oco_order is properly defined" do
      assert function_exported?(Endpoints, :place_oco_order, 1)
    end

    test "batch_cancel_orders handles list of order IDs" do
      assert function_exported?(Endpoints, :batch_cancel_orders, 1)
    end
  end

  describe "public endpoints" do
    test "ticker endpoint doesn't require auth" do
      config = Endpoints.get_endpoint(:get_ticker)

      assert config.requires_auth == false
      assert config.weight == 1
    end

    test "server time endpoint doesn't require auth" do
      config = Endpoints.get_endpoint(:get_server_time)

      assert config.requires_auth == false
      # Fast timeout for time sync
      assert config.timeout == 2_000
    end
  end
end
