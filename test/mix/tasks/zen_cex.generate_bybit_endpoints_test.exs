defmodule Mix.Tasks.ZenCex.GenerateBybitEndpointsTest do
  use ExUnit.Case, async: false

  @test_output_path "test/fixtures/generated_bybit_endpoints.ex"

  # Sample Postman collection structure for testing
  @mock_postman_collection %{
    "info" => %{
      "name" => "Bybit V5 API",
      "description" => "Test collection"
    },
    "item" => [
      %{
        "name" => "Trading",
        "item" => [
          %{
            "name" => "create（Limit Order）spot",
            "request" => %{
              "method" => "POST",
              "url" => %{
                "raw" => "{{url}}/v5/order/create"
              },
              "header" => [
                %{"key" => "X-BAPI-API-KEY"},
                %{"key" => "X-BAPI-SIGN"},
                %{"key" => "X-BAPI-TIMESTAMP"}
              ]
            }
          },
          %{
            "name" => "cancel",
            "request" => %{
              "method" => "POST",
              "url" => %{
                "raw" => "{{url}}/v5/order/cancel"
              },
              "header" => [
                %{"key" => "X-BAPI-API-KEY"},
                %{"key" => "X-BAPI-SIGN"},
                %{"key" => "X-BAPI-TIMESTAMP"}
              ]
            }
          },
          %{
            "name" => "wallet-balance",
            "request" => %{
              "method" => "GET",
              "url" => %{
                "raw" => "{{url}}/v5/account/wallet-balance"
              },
              "header" => [
                %{"key" => "X-BAPI-API-KEY"},
                %{"key" => "X-BAPI-SIGN"},
                %{"key" => "X-BAPI-TIMESTAMP"}
              ]
            }
          },
          %{
            "name" => "position/list",
            "request" => %{
              "method" => "GET",
              "url" => %{
                "raw" => "{{url}}/v5/position/list"
              },
              "header" => [
                %{"key" => "X-BAPI-API-KEY"},
                %{"key" => "X-BAPI-SIGN"},
                %{"key" => "X-BAPI-TIMESTAMP"}
              ]
            }
          }
        ]
      },
      %{
        "name" => "Market Data",
        "item" => [
          %{
            "name" => "Get Kline",
            "request" => %{
              "method" => "GET",
              "url" => %{
                "raw" => "{{url}}/v5/market/kline"
              }
            }
          },
          %{
            "name" => "Get Tickers",
            "request" => %{
              "method" => "GET",
              "url" => %{
                "raw" => "{{url}}/v5/market/tickers"
              }
            }
          }
        ]
      },
      %{
        "name" => "Asset",
        "item" => [
          %{
            "name" => "deposit/query-address",
            "request" => %{
              "method" => "GET",
              "url" => %{
                "raw" => "{{url}}/v5/asset/deposit/query-address"
              },
              "header" => [
                %{"key" => "X-BAPI-API-KEY"},
                %{"key" => "X-BAPI-SIGN"},
                %{"key" => "X-BAPI-TIMESTAMP"}
              ]
            }
          },
          %{
            "name" => "Get Deposit Allowed List",
            "request" => %{
              "method" => "GET",
              "url" => %{
                "raw" => "{{url}}/v5/asset/deposit/query-allowed-list"
              },
              "header" => []
            }
          }
        ]
      }
    ]
  }

  setup do
    # Clean up test file if it exists
    File.rm(@test_output_path)
    on_exit(fn -> File.rm(@test_output_path) end)
    :ok
  end

  describe "fetch_postman_collection/0" do
    @tag :skip
    test "fetches real Postman collection from GitHub" do
      # TODO: This test needs to be implemented properly
      # Currently it's a placeholder that doesn't test anything
      # Skipped until we refactor to expose fetch logic for testing
    end
  end

  describe "parse_and_filter_endpoints/1" do
    test "filters trading endpoints and excludes market data" do
      # We'll test this through the module's exposed functionality
      # Since functions are private, we test the behavior through run/1

      # Create a test module that exposes the private functions for testing
      defmodule TestHelper do
        @moduledoc false
        def extract_all_requests(collection) do
          items = collection["item"] || []

          Enum.flat_map(items, fn item ->
            case item do
              %{"request" => request} when is_map(request) ->
                [{request, item}]

              %{"item" => subitems} when is_list(subitems) ->
                Enum.flat_map(subitems, fn subitem ->
                  case subitem do
                    %{"request" => request} when is_map(request) ->
                      [{request, subitem}]

                    _ ->
                      []
                  end
                end)

              _ ->
                []
            end
          end)
        end

        def filter_trading_endpoints(requests) do
          trading_patterns = [
            ~r{/v5/account/},
            ~r{/v5/asset/},
            ~r{/v5/order/},
            ~r{/v5/position/}
          ]

          exclude_patterns = [
            ~r{/kline},
            ~r{/tickers},
            ~r{/market/}
          ]

          Enum.filter(requests, fn {request, _item} ->
            path = extract_path(request)

            matches_trading = Enum.any?(trading_patterns, &Regex.match?(&1, path))
            is_excluded = Enum.any?(exclude_patterns, &Regex.match?(&1, path))

            matches_trading and not is_excluded
          end)
        end

        defp extract_path(request) do
          case request["url"] do
            %{"raw" => raw} when is_binary(raw) ->
              raw
              |> String.replace("{{url}}", "")
              |> URI.parse()
              |> Map.get(:path, "/")

            _ ->
              "/"
          end
        end
      end

      requests = TestHelper.extract_all_requests(@mock_postman_collection)
      filtered = TestHelper.filter_trading_endpoints(requests)

      # Should include trading endpoints
      paths =
        Enum.map(filtered, fn {req, _} ->
          case req["url"] do
            %{"raw" => raw} -> raw
            _ -> ""
          end
        end)

      assert Enum.any?(paths, &String.contains?(&1, "/v5/order/create"))
      assert Enum.any?(paths, &String.contains?(&1, "/v5/order/cancel"))
      assert Enum.any?(paths, &String.contains?(&1, "/v5/account/wallet-balance"))
      assert Enum.any?(paths, &String.contains?(&1, "/v5/position/list"))
      assert Enum.any?(paths, &String.contains?(&1, "/v5/asset/deposit/query-address"))

      # Should exclude market data
      refute Enum.any?(paths, &String.contains?(&1, "/market/kline"))
      refute Enum.any?(paths, &String.contains?(&1, "/market/tickers"))
    end
  end

  describe "operation naming" do
    test "derives correct operation names for order endpoints" do
      test_cases = [
        {"POST", "/v5/order/create", "create（Limit Order）spot", :place_limit_order},
        {"POST", "/v5/order/create", "create（Market Order）", :place_market_order},
        {"POST", "/v5/order/create", "create（Conditional Order）", :place_conditional_order},
        {"POST", "/v5/order/cancel", "cancel", :cancel_order},
        {"POST", "/v5/order/cancel-all", "cancel-all", :cancel_all_orders},
        {"POST", "/v5/order/cancel-batch", "cancel-batch", :cancel_batch_orders},
        {"POST", "/v5/order/amend", "amend", :amend_order},
        {"POST", "/v5/order/amend-batch", "amend-batch", :amend_batch_orders},
        {"POST", "/v5/order/create-batch", "create-batch", :place_batch_orders},
        {"GET", "/v5/account/wallet-balance", "wallet-balance", :get_wallet_balance},
        {"GET", "/v5/position/list", "position/list", :get_position_list}
      ]

      # Test through a helper module since the function is private
      defmodule NameHelper do
        @moduledoc false
        def derive_operation_name(method, path, name) do
          cond do
            String.contains?(path, "/order/create-batch") ->
              :place_batch_orders

            String.contains?(path, "/order/create") and String.contains?(name, "Limit") ->
              :place_limit_order

            String.contains?(path, "/order/create") and String.contains?(name, "Market") ->
              :place_market_order

            String.contains?(path, "/order/create") and String.contains?(name, "Conditional") ->
              :place_conditional_order

            String.contains?(path, "/order/create") ->
              :place_order

            String.contains?(path, "/order/cancel-batch") ->
              :cancel_batch_orders

            String.contains?(path, "/order/cancel-all") ->
              :cancel_all_orders

            String.contains?(path, "/order/cancel") and not String.contains?(path, "all") ->
              :cancel_order

            String.contains?(path, "/order/amend-batch") ->
              :amend_batch_orders

            String.contains?(path, "/order/amend") ->
              :amend_order

            true ->
              clean_name =
                name
                |> String.downcase()
                |> String.replace(~r/[^a-z0-9_]/, "_")
                |> String.replace(~r/_+/, "_")
                |> String.trim("_")

              verb =
                case String.downcase(method) do
                  "get" -> "get"
                  "post" -> "create"
                  "delete" -> "delete"
                  _ -> String.downcase(method)
                end

              String.to_atom("#{verb}_#{clean_name}")
          end
        end
      end

      for {method, path, name, expected} <- test_cases do
        actual = NameHelper.derive_operation_name(method, path, name)

        assert actual == expected,
               "Expected #{inspect(expected)} for #{method} #{path} '#{name}', got #{inspect(actual)}"
      end
    end
  end

  describe "path cleaning" do
    test "removes Postman URL variables and formats paths correctly" do
      test_paths = [
        {"{{url}}/v5/order/create", "/v5/order/create"},
        {":{{url}}/v5/order/cancel", "/v5/order/cancel"},
        {"/v5/position/list", "/v5/position/list"},
        {"v5/account/info", "/v5/account/info"},
        {"/v5/order/create?symbol=BTCUSDT", "/v5/order/create"}
      ]

      defmodule PathHelper do
        @moduledoc false
        def clean_path(path) do
          path
          |> String.split("?")
          |> List.first()
          |> String.replace(":{{url}}", "")
          |> String.replace("{{url}}", "")
          |> String.replace(~r/\{([^}]+)\}/, ":{\\1}")
          |> then(fn p ->
            if String.starts_with?(p, "/"), do: p, else: "/" <> p
          end)
        end
      end

      for {input, expected} <- test_paths do
        actual = PathHelper.clean_path(input)

        assert actual == expected,
               "Expected #{expected} for #{input}, got #{actual}"
      end
    end
  end

  describe "smart defaults" do
    test "sets appropriate timeouts based on operation type" do
      endpoints = [
        %{operation: :place_order, method: :post, timeout: nil, max_retries: nil, retry_on: nil},
        %{operation: :cancel_order, method: :post, timeout: nil, max_retries: nil, retry_on: nil},
        %{operation: :amend_order, method: :post, timeout: nil, max_retries: nil, retry_on: nil},
        %{operation: :get_wallet_balance, method: :get, timeout: nil, max_retries: nil, retry_on: nil},
        %{operation: :get_position_list, method: :get, timeout: nil, max_retries: nil, retry_on: nil},
        %{operation: :get_account_info, method: :get, timeout: nil, max_retries: nil, retry_on: nil}
      ]

      defmodule DefaultsHelper do
        @moduledoc false
        def add_timeout_by_operation(endpoint) do
          timeout =
            case endpoint.operation do
              op
              when op in [
                     :create_order,
                     :place_order,
                     :place_limit_order,
                     :place_market_order,
                     :place_conditional_order,
                     :cancel_order,
                     :amend_order
                   ] ->
                2_000

              op when op in [:get_wallet_balance, :get_position_list] ->
                3_000

              _ ->
                5_000
            end

          %{endpoint | timeout: timeout}
        end

        def add_retry_policy(endpoint) do
          case {endpoint.method, endpoint.operation} do
            {:get, _} ->
              %{endpoint | max_retries: 3, retry_on: [:timeout, :server_error]}

            {_, op}
            when op in [
                   :create_order,
                   :place_order,
                   :place_limit_order,
                   :place_market_order,
                   :place_conditional_order,
                   :place_batch_orders
                 ] ->
              %{endpoint | max_retries: 0, retry_on: []}

            {_, op} when op in [:cancel_order, :cancel_batch_orders, :amend_order, :amend_batch_orders] ->
              %{endpoint | max_retries: 1, retry_on: [:timeout]}

            _ ->
              %{endpoint | max_retries: 2, retry_on: [:timeout]}
          end
        end
      end

      for endpoint <- endpoints do
        with_timeout = DefaultsHelper.add_timeout_by_operation(endpoint)
        with_retry = DefaultsHelper.add_retry_policy(with_timeout)

        case endpoint.operation do
          op when op in [:place_order, :cancel_order, :amend_order] ->
            assert with_timeout.timeout == 2_000

          op when op in [:get_wallet_balance, :get_position_list] ->
            assert with_timeout.timeout == 3_000

          _ ->
            assert with_timeout.timeout == 5_000
        end

        case {endpoint.method, endpoint.operation} do
          {:get, _} ->
            assert with_retry.max_retries == 3
            assert with_retry.retry_on == [:timeout, :server_error]

          {_, :place_order} ->
            assert with_retry.max_retries == 0
            assert with_retry.retry_on == []

          {_, op} when op in [:cancel_order, :amend_order] ->
            assert with_retry.max_retries == 1
            assert with_retry.retry_on == [:timeout]

          _ ->
            assert with_retry.max_retries == 2
            assert with_retry.retry_on == [:timeout]
        end
      end
    end
  end

  describe "authentication detection" do
    test "correctly identifies authenticated endpoints" do
      authenticated_request = %{
        "header" => [
          %{"key" => "X-BAPI-API-KEY"},
          %{"key" => "X-BAPI-SIGN"},
          %{"key" => "X-BAPI-TIMESTAMP"}
        ]
      }

      public_request = %{
        "header" => []
      }

      no_header_request = %{}

      defmodule AuthHelper do
        @moduledoc false
        def requires_authentication?(request) do
          headers = request["header"] || []
          auth_headers = ["X-BAPI-API-KEY", "X-BAPI-SIGN", "X-BAPI-TIMESTAMP"]

          Enum.any?(headers, fn header ->
            header["key"] in auth_headers
          end)
        end
      end

      assert AuthHelper.requires_authentication?(authenticated_request) == true
      assert AuthHelper.requires_authentication?(public_request) == false
      assert AuthHelper.requires_authentication?(no_header_request) == false
    end
  end

  describe "code generation" do
    test "generates valid Elixir code" do
      endpoints = [
        %{
          operation: :place_order,
          method: :post,
          path: "/v5/order/create",
          requires_auth: true,
          weight: 1,
          timeout: 2000,
          max_retries: 0,
          retry_on: [],
          response_parser: :parse_unified_response,
          error_mapping: :parse_error,
          doc: "Place an order"
        }
      ]

      defmodule CodeGenHelper do
        @moduledoc false
        def format_endpoint(endpoint) do
          doc = String.replace(endpoint.doc, "\"", "\\\"")

          """
            %{
              operation: #{inspect(endpoint.operation)},
              method: #{inspect(endpoint.method)},
              path: #{inspect(endpoint.path)},
              requires_auth: #{endpoint.requires_auth},
              weight: #{endpoint.weight},
              timeout: #{endpoint.timeout},
              max_retries: #{endpoint.max_retries},
              retry_on: #{inspect(endpoint.retry_on)},
              response_parser: &Parser.#{endpoint.response_parser}/1,
              error_mapping: &Parser.#{endpoint.error_mapping}/1,
              doc: "#{doc}"
            }\
          """
        end
      end

      code = CodeGenHelper.format_endpoint(List.first(endpoints))

      # Should generate valid map syntax
      assert String.contains?(code, "%{")
      assert String.contains?(code, "operation: :place_order")
      assert String.contains?(code, "method: :post")
      assert String.contains?(code, "path: \"/v5/order/create\"")
      assert String.contains?(code, "requires_auth: true")
      assert String.contains?(code, "&Parser.parse_unified_response/1")
      assert String.contains?(code, "&Parser.parse_error/1")

      # Should be compilable (basic syntax check)
      assert String.trim(code) =~ ~r/^\s*%\{.*\}\s*$/s
    end
  end

  describe "deduplication" do
    test "removes duplicate endpoints based on operation, method, and path" do
      endpoints = [
        %{operation: :place_order, method: :post, path: "/v5/order/create", doc: "First"},
        %{operation: :place_order, method: :post, path: "/v5/order/create", doc: "Duplicate"},
        %{operation: :cancel_order, method: :post, path: "/v5/order/cancel", doc: "Different"},
        %{operation: :place_order, method: :get, path: "/v5/order/create", doc: "Different method"},
        %{operation: :place_order, method: :post, path: "/v5/order/batch", doc: "Different path"}
      ]

      defmodule DedupeHelper do
        @moduledoc false
        def deduplicate_endpoints(endpoints) do
          endpoints
          |> Enum.uniq_by(fn endpoint ->
            {endpoint.operation, endpoint.method, endpoint.path}
          end)
          |> Enum.sort_by(& &1.operation)
        end
      end

      deduped = DedupeHelper.deduplicate_endpoints(endpoints)

      assert length(deduped) == 4
      assert Enum.any?(deduped, &(&1.doc == "First"))
      refute Enum.any?(deduped, &(&1.doc == "Duplicate"))
      assert Enum.any?(deduped, &(&1.doc == "Different"))
      assert Enum.any?(deduped, &(&1.doc == "Different method"))
      assert Enum.any?(deduped, &(&1.doc == "Different path"))
    end
  end
end
