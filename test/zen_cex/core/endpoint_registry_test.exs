defmodule ZenCex.Core.EndpointRegistryTest do
  use ExUnit.Case, async: true

  # Test module that uses the EndpointRegistry
  defmodule TestEndpoints do
    use ZenCex.EndpointRegistry, adapter: __MODULE__

    def __exchange__, do: :test_exchange
    def base_url(:prod), do: "https://api.test.com"
    def base_url(:test), do: "https://test.api.test.com"
    def auth, do: TestAuth
    def rate_limiter, do: TestRateLimiter

    @endpoints [
      %{
        operation: :get_data,
        method: :get,
        path: "/api/v1/data",
        requires_auth: true,
        response_parser: &__MODULE__.parse_data/1,
        error_mapping: &__MODULE__.parse_error/1,
        retry_on: [:timeout],
        max_retries: 2,
        weight: 5,
        timeout: 5_000,
        doc: "Fetches test data"
      },
      %{
        operation: :place_order,
        method: :post,
        path: "/api/v1/order",
        requires_auth: true,
        response_parser: &__MODULE__.parse_order/1,
        error_mapping: &__MODULE__.parse_error/1,
        retry_on: [],
        max_retries: 0,
        weight: 1,
        timeout: 2_000,
        params_transformer: &__MODULE__.transform_order/1,
        doc: "Places a test order"
      },
      %{
        operation: :public_info,
        method: :get,
        path: "/api/v1/info",
        requires_auth: false,
        response_parser: &__MODULE__.parse_info/1,
        error_mapping: &__MODULE__.parse_error/1,
        retry_on: [:timeout, :rate_limited],
        max_retries: 3,
        weight: 1,
        timeout: 10_000,
        doc: "Gets public information"
      }
    ]

    # Parser functions for testing
    def parse_data(%{"data" => data}), do: {:ok, data}
    def parse_data(_), do: {:error, :invalid_data}

    def parse_order(%{"order_id" => id}), do: {:ok, %{order_id: id}}
    def parse_order(_), do: {:error, :invalid_order}

    def parse_info(%{"info" => info}), do: {:ok, info}
    def parse_info(_), do: {:error, :invalid_info}

    def parse_error(%{"error" => error}), do: {:error, error}
    def parse_error(_), do: {:error, :unknown_error}

    def transform_order(params), do: Map.put(params, :transformed, true)
  end

  describe "endpoint lookup functions" do
    test "get_endpoint/1 returns endpoint configuration" do
      endpoint = TestEndpoints.get_endpoint(:get_data)

      assert endpoint.operation == :get_data
      assert endpoint.method == :get
      assert endpoint.path == "/api/v1/data"
      assert endpoint.requires_auth == true
      assert endpoint.weight == 5
      assert endpoint.max_retries == 2
      assert :timeout in endpoint.retry_on
    end

    test "get_endpoint/1 returns nil for unknown operation" do
      assert TestEndpoints.get_endpoint(:unknown_op) == nil
    end

    test "all_endpoints/0 returns all configured endpoints" do
      endpoints = TestEndpoints.all_endpoints()

      assert length(endpoints) == 3
      operations = Enum.map(endpoints, & &1.operation)
      assert :get_data in operations
      assert :place_order in operations
      assert :public_info in operations
    end

    test "get_weight/1 returns correct weight" do
      assert TestEndpoints.get_weight(:get_data) == 5
      assert TestEndpoints.get_weight(:place_order) == 1
      # default
      assert TestEndpoints.get_weight(:unknown) == 1
    end
  end

  describe "generated functions" do
    test "generates function with correct arity" do
      # Should have both /1 and /2 versions
      assert function_exported?(TestEndpoints, :get_data, 0)
      assert function_exported?(TestEndpoints, :get_data, 1)
      assert function_exported?(TestEndpoints, :get_data, 2)
    end

    test "generates function for each endpoint" do
      assert function_exported?(TestEndpoints, :get_data, 2)
      assert function_exported?(TestEndpoints, :place_order, 2)
      assert function_exported?(TestEndpoints, :public_info, 2)
    end
  end

  describe "compile-time validations" do
    test "prevents retry on order placement" do
      # This test verifies that the compile-time validation works
      # by checking that place_order has no retries
      endpoint = TestEndpoints.get_endpoint(:place_order)
      assert endpoint.max_retries == 0
      assert endpoint.retry_on == []
    end

    test "validates required fields are present" do
      # All endpoints should have required fields
      for endpoint <- TestEndpoints.all_endpoints() do
        assert Map.has_key?(endpoint, :operation)
        assert Map.has_key?(endpoint, :method)
        assert Map.has_key?(endpoint, :path)
        assert Map.has_key?(endpoint, :response_parser)
        assert Map.has_key?(endpoint, :error_mapping)
      end
    end

    test "validates HTTP methods" do
      for endpoint <- TestEndpoints.all_endpoints() do
        assert endpoint.method in [:get, :post, :put, :delete, :patch]
      end
    end
  end

  describe "invalid endpoint specifications" do
    test "raises compile error for missing required fields" do
      # This would raise at compile time, not runtime
      # We can't test this directly, but we document the expected behavior
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule InvalidEndpoints do
          use ZenCex.EndpointRegistry

          @endpoints [
            %{
              operation: :test_op,
              method: :get
              # Missing: path, response_parser, error_mapping
            }
          ]
        end
        """)
      end
    end

    test "raises compile error for invalid HTTP method" do
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule InvalidMethodEndpoints do
          use ZenCex.EndpointRegistry

          @endpoints [
            %{
              operation: :test_op,
              method: :invalid_method,
              path: "/test",
              response_parser: &Function.identity/1,
              error_mapping: &Function.identity/1
            }
          ]
        end
        """)
      end
    end

    test "raises compile error for order placement with retries" do
      assert_raise CompileError, fn ->
        Code.compile_string("""
        defmodule InvalidOrderEndpoints do
          use ZenCex.EndpointRegistry

          @endpoints [
            %{
              operation: :place_order,
              method: :post,
              path: "/order",
              response_parser: &Function.identity/1,
              error_mapping: &Function.identity/1,
              max_retries: 3  # This should fail
            }
          ]
        end
        """)
      end
    end
  end

  describe "debug mode" do
    test "debug mode can be enabled" do
      # Test that debug mode doesn't break compilation
      defmodule DebugEndpoints do
        use ZenCex.EndpointRegistry, debug: true, adapter: __MODULE__

        # Required adapter functions
        def __exchange__, do: :debug_exchange
        def base_url(:prod), do: "https://debug.test.com"

        @endpoints [
          %{
            operation: :test_debug,
            method: :get,
            path: "/debug",
            response_parser: &Function.identity/1,
            error_mapping: &Function.identity/1,
            retry_on: [],
            max_retries: 0
          }
        ]
      end

      assert function_exported?(DebugEndpoints, :test_debug, 2)
    end
  end

  describe "params transformer" do
    test "applies params transformer when provided" do
      endpoint = TestEndpoints.get_endpoint(:place_order)
      assert is_function(endpoint.params_transformer, 1)

      # The transformer should add :transformed key
      result = endpoint.params_transformer.(%{test: "value"})
      assert result.transformed == true
      assert result.test == "value"
    end

    test "endpoint without transformer works correctly" do
      endpoint = TestEndpoints.get_endpoint(:get_data)
      refute Map.has_key?(endpoint, :params_transformer)
    end
  end

  describe "auth configuration" do
    test "respects requires_auth setting" do
      auth_endpoint = TestEndpoints.get_endpoint(:get_data)
      public_endpoint = TestEndpoints.get_endpoint(:public_info)

      assert auth_endpoint.requires_auth == true
      assert public_endpoint.requires_auth == false
    end
  end

  describe "timeout configuration" do
    test "uses configured timeout values" do
      assert TestEndpoints.get_endpoint(:get_data).timeout == 5_000
      assert TestEndpoints.get_endpoint(:place_order).timeout == 2_000
      assert TestEndpoints.get_endpoint(:public_info).timeout == 10_000
    end
  end
end
