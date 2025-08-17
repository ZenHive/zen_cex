defmodule ZenCex.Core.EndpointRegistryMacroTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests for macro expansion and code generation of EndpointRegistry.
  These tests ensure the macro generates correct code and prevents regressions.
  """

  describe "macro expansion validation" do
    test "generates correct function signatures" do
      # Compile a test module and capture the generated code
      {:module, TestMacroExpansion, _bytecode, _} =
        defmodule TestMacroExpansion do
          use ZenCex.EndpointRegistry, adapter: __MODULE__

          def __exchange__, do: :test
          def base_url(_), do: "https://test.com"
          def auth, do: TestAuth
          def rate_limiter, do: TestRateLimiter

          @endpoints [
            %{
              operation: :test_function,
              method: :get,
              path: "/test",
              requires_auth: true,
              response_parser: &Function.identity/1,
              error_mapping: &Function.identity/1,
              retry_on: [],
              max_retries: 0
            }
          ]
        end

      # Verify the generated functions exist with correct arities
      assert function_exported?(TestMacroExpansion, :test_function, 0)
      assert function_exported?(TestMacroExpansion, :test_function, 1)
      assert function_exported?(TestMacroExpansion, :test_function, 2)

      # Verify helper functions are generated
      assert function_exported?(TestMacroExpansion, :get_endpoint, 1)
      assert function_exported?(TestMacroExpansion, :all_endpoints, 0)
      assert function_exported?(TestMacroExpansion, :get_weight, 1)
    end

    test "generates telemetry events in functions" do
      # Create a telemetry handler to capture events
      handler_id = :test_telemetry_handler

      :telemetry.attach_many(
        handler_id,
        [
          [:zen_cex, :endpoint, :start],
          [:zen_cex, :endpoint, :success],
          [:zen_cex, :endpoint, :error]
        ],
        fn event, measurements, metadata, config ->
          send(config.test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{test_pid: self()}
      )

      # Clean up after test
      on_exit(fn -> :telemetry.detach(handler_id) end)

      # Define helper module with parser functions (must be outside the test module)
      defmodule TelemetryTestParser do
        def parse_response(_), do: {:ok, :parsed}
        def parse_error(_), do: {:error, :mapped}
      end

      # Define test module with telemetry
      defmodule TelemetryTestModule do
        use ZenCex.EndpointRegistry, adapter: __MODULE__

        def __exchange__, do: :telemetry_test
        def base_url(_), do: "https://test.com"
        def auth, do: TestAuth
        def rate_limiter, do: TestRateLimiter

        @endpoints [
          %{
            operation: :telemetry_test_op,
            method: :get,
            path: "/telemetry",
            requires_auth: false,
            response_parser: &TelemetryTestParser.parse_response/1,
            error_mapping: &TelemetryTestParser.parse_error/1,
            retry_on: [],
            max_retries: 0
          }
        ]

        # Mock the execute_endpoint_request to return success
        defp execute_endpoint_request(_config, _params, _adapter) do
          {:ok, %{test: "data"}}
        end
      end

      # Call the generated function
      result = TelemetryTestModule.telemetry_test_op(%{})

      # Verify we got the expected result
      assert result == {:ok, :parsed}

      # Verify telemetry events were emitted
      assert_receive {:telemetry_event, [:zen_cex, :endpoint, :start], %{system_time: _},
                      metadata}

      assert metadata.exchange == :telemetry_test
      assert metadata.operation == :telemetry_test_op
      assert metadata.endpoint == "/telemetry"

      assert_receive {:telemetry_event, [:zen_cex, :endpoint, :success], %{duration: _}, metadata}
      assert metadata.status == :ok
    end

    test "prevents dangerous patterns at compile time" do
      # Test that order placement with retries raises compile error
      assert_raise CompileError, ~r/Order placement operations MUST NOT have retries/, fn ->
        Code.compile_string("""
        defmodule DangerousPattern do
          use ZenCex.EndpointRegistry
          
          @endpoints [
            %{
              operation: :place_order,
              method: :post,
              path: "/order",
              response_parser: &Function.identity/1,
              error_mapping: &Function.identity/1,
              max_retries: 2  # This should trigger compile error
            }
          ]
        end
        """)
      end
    end

    test "validates required fields at compile time" do
      # Missing response_parser should raise
      assert_raise CompileError, ~r/missing required key: response_parser/, fn ->
        Code.compile_string("""
        defmodule MissingField do
          use ZenCex.EndpointRegistry
          
          @endpoints [
            %{
              operation: :test_op,
              method: :get,
              path: "/test",
              error_mapping: &Function.identity/1
            }
          ]
        end
        """)
      end
    end

    test "validates HTTP methods at compile time" do
      assert_raise CompileError, ~r/Invalid HTTP method/, fn ->
        Code.compile_string("""
        defmodule InvalidMethod do
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

    test "params transformer is applied correctly" do
      # Define helper module with transformer functions
      defmodule TransformerTestHelpers do
        def parse_response(params), do: {:ok, params}
        def parse_error(error), do: error
        def transform_params(params), do: Map.put(params, :transformed, true)
      end

      defmodule TransformerTest do
        use ZenCex.EndpointRegistry, adapter: __MODULE__

        def __exchange__, do: :transformer_test
        def base_url(_), do: "https://test.com"
        def auth, do: TestAuth
        def rate_limiter, do: TestRateLimiter

        @endpoints [
          %{
            operation: :with_transformer,
            method: :post,
            path: "/transform",
            requires_auth: false,
            response_parser: &TransformerTestHelpers.parse_response/1,
            error_mapping: &TransformerTestHelpers.parse_error/1,
            params_transformer: &TransformerTestHelpers.transform_params/1,
            retry_on: [],
            max_retries: 0
          }
        ]

        # Capture the params that were passed
        defp execute_endpoint_request(_config, params, _adapter) do
          {:ok, params}
        end
      end

      # Call with original params
      {:ok, result} = TransformerTest.with_transformer(%{original: "value"})

      # Verify transformer was applied
      assert result.transformed == true
      assert result.original == "value"
    end

    test "helper function generation is idempotent" do
      # This tests that the Module.defines? check works correctly
      # by defining multiple endpoints and ensuring helpers are only generated once
      defmodule MultiEndpointTest do
        use ZenCex.EndpointRegistry, adapter: __MODULE__

        def __exchange__, do: :multi_test
        def base_url(_), do: "https://test.com"
        def auth, do: TestAuth
        def rate_limiter, do: TestRateLimiter

        @endpoints [
          %{
            operation: :first_op,
            method: :get,
            path: "/first",
            requires_auth: false,
            response_parser: &Function.identity/1,
            error_mapping: &Function.identity/1,
            retry_on: [],
            max_retries: 0
          },
          %{
            operation: :second_op,
            method: :get,
            path: "/second",
            requires_auth: false,
            response_parser: &Function.identity/1,
            error_mapping: &Function.identity/1,
            retry_on: [],
            max_retries: 0
          },
          %{
            operation: :third_op,
            method: :get,
            path: "/third",
            requires_auth: false,
            response_parser: &Function.identity/1,
            error_mapping: &Function.identity/1,
            retry_on: [],
            max_retries: 0
          }
        ]
      end

      # All functions should exist
      assert function_exported?(MultiEndpointTest, :first_op, 2)
      assert function_exported?(MultiEndpointTest, :second_op, 2)
      assert function_exported?(MultiEndpointTest, :third_op, 2)

      # Helper functions should exist
      assert function_exported?(MultiEndpointTest, :get_endpoint, 1)
      assert function_exported?(MultiEndpointTest, :all_endpoints, 0)

      # And they should work correctly
      assert length(MultiEndpointTest.all_endpoints()) == 3
    end

    test "debug mode doesn't break compilation" do
      # Capture IO to verify debug output
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Code.compile_string("""
          defmodule DebugModeTest do
            use ZenCex.EndpointRegistry, debug: true, adapter: __MODULE__
            
            # Required adapter functions
            def __exchange__, do: :debug_test
            def base_url(:prod), do: "https://debug.test.com"
            
            @endpoints [
              %{
                operation: :debug_op,
                method: :get,
                path: "/debug",
                response_parser: &Function.identity/1,
                error_mapping: &Function.identity/1,
                retry_on: [],
                max_retries: 0
              }
            ]
          end
          """)
        end)

      # Verify debug output was generated
      assert output =~ "Generated code for"
      assert output =~ "DebugModeTest"
      assert output =~ "debug_op"
    end
  end

  describe "edge cases" do
    test "empty endpoints list generates only helper functions" do
      defmodule EmptyEndpoints do
        use ZenCex.EndpointRegistry, adapter: __MODULE__

        def __exchange__, do: :empty
        def base_url(_), do: "https://test.com"
        def auth, do: TestAuth
        def rate_limiter, do: TestRateLimiter

        @endpoints []
      end

      # Helper functions should still exist
      assert function_exported?(EmptyEndpoints, :get_endpoint, 1)
      assert function_exported?(EmptyEndpoints, :all_endpoints, 0)
      assert function_exported?(EmptyEndpoints, :get_weight, 1)

      # And return expected values
      assert EmptyEndpoints.all_endpoints() == []
      assert EmptyEndpoints.get_endpoint(:anything) == nil
      assert EmptyEndpoints.get_weight(:anything) == 1
    end

    test "special characters in operation names" do
      # This should work as atoms can contain special chars
      defmodule SpecialCharsTest do
        use ZenCex.EndpointRegistry, adapter: __MODULE__

        def __exchange__, do: :special
        def base_url(_), do: "https://test.com"
        def auth, do: TestAuth
        def rate_limiter, do: TestRateLimiter

        @endpoints [
          %{
            operation: :"get-data!",
            method: :get,
            path: "/data",
            requires_auth: false,
            response_parser: &Function.identity/1,
            error_mapping: &Function.identity/1,
            retry_on: [],
            max_retries: 0
          }
        ]
      end

      assert function_exported?(SpecialCharsTest, :"get-data!", 2)
    end
  end
end
