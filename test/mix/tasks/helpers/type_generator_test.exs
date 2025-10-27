defmodule Mix.Tasks.Helpers.TypeGeneratorTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Helpers.TypeGenerator

  describe "openapi_type_to_elixir/2 - primitives" do
    test "converts integer type" do
      schema = %{"type" => "integer"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "integer()"
    end

    test "converts integer with format int64" do
      schema = %{"type" => "integer", "format" => "int64"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "integer()"
    end

    test "converts number type" do
      schema = %{"type" => "number"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "float()"
    end

    test "converts string type" do
      schema = %{"type" => "string"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "String.t()"
    end

    test "converts boolean type" do
      schema = %{"type" => "boolean"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "boolean()"
    end

    test "returns term() for unknown type" do
      schema = %{"type" => "unknown"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "term()"
    end

    test "returns term() for missing type" do
      schema = %{}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "term()"
    end
  end

  describe "openapi_type_to_elixir/2 - enums" do
    test "converts string enum to atom union" do
      schema = %{"type" => "string", "enum" => ["BUY", "SELL"]}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == ":buy | :sell"
    end

    test "converts enum without type" do
      schema = %{"enum" => ["LIMIT", "MARKET", "STOP_LOSS"]}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == ":limit | :market | :stop_loss"
    end
  end

  describe "openapi_type_to_elixir/2 - arrays" do
    test "converts array of primitives" do
      schema = %{"type" => "array", "items" => %{"type" => "string"}}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "list(String.t())"
    end

    test "converts array of integers" do
      schema = %{"type" => "array", "items" => %{"type" => "integer"}}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "list(integer())"
    end

    test "converts array without items schema" do
      schema = %{"type" => "array"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "list(term())"
    end

    test "converts nested arrays" do
      schema = %{
        "type" => "array",
        "items" => %{"type" => "array", "items" => %{"type" => "integer"}}
      }

      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "list(list(integer()))"
    end
  end

  describe "openapi_type_to_elixir/2 - objects" do
    test "converts simple object with required fields" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "serverTime" => %{"type" => "integer"}
        },
        "required" => ["serverTime"]
      }

      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "%{server_time: integer()}"
    end

    test "converts object with multiple fields" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "symbol" => %{"type" => "string"},
          "price" => %{"type" => "string"},
          "quantity" => %{"type" => "string"}
        },
        "required" => ["symbol", "price", "quantity"]
      }

      result = TypeGenerator.openapi_type_to_elixir(schema, %{})
      assert String.contains?(result, "symbol: String.t()")
      assert String.contains?(result, "price: String.t()")
      assert String.contains?(result, "quantity: String.t()")
    end

    test "converts object with optional fields" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "symbol" => %{"type" => "string"},
          "orderId" => %{"type" => "integer"}
        },
        "required" => ["symbol"]
      }

      result = TypeGenerator.openapi_type_to_elixir(schema, %{})
      assert String.contains?(result, "symbol: String.t()")
      assert String.contains?(result, "optional(:order_id) => integer()")
    end

    test "converts empty object to map()" do
      schema = %{"type" => "object"}
      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "map()"
    end

    test "converts nested objects" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "data" => %{
            "type" => "object",
            "properties" => %{
              "value" => %{"type" => "integer"}
            },
            "required" => ["value"]
          }
        },
        "required" => ["data"]
      }

      result = TypeGenerator.openapi_type_to_elixir(schema, %{})
      assert String.contains?(result, "data: %{value: integer()}")
    end
  end

  describe "openapi_type_to_elixir/2 - edge cases" do
    test "returns term() for oneOf" do
      schema = %{
        "oneOf" => [
          %{"type" => "string"},
          %{"type" => "integer"}
        ]
      }

      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "term()"
    end

    test "returns term() for anyOf" do
      schema = %{
        "anyOf" => [
          %{"type" => "string"},
          %{"type" => "integer"}
        ]
      }

      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "term()"
    end

    test "returns term() for allOf" do
      schema = %{
        "allOf" => [
          %{"type" => "object", "properties" => %{"a" => %{"type" => "string"}}},
          %{"type" => "object", "properties" => %{"b" => %{"type" => "integer"}}}
        ]
      }

      assert TypeGenerator.openapi_type_to_elixir(schema, %{}) == "term()"
    end
  end

  describe "resolve_ref/2" do
    test "resolves parameter reference" do
      components = %{
        "parameters" => %{
          "symbol" => %{
            "name" => "symbol",
            "schema" => %{"type" => "string"}
          }
        }
      }

      schema = %{"$ref" => "#/components/parameters/symbol"}
      resolved = TypeGenerator.resolve_ref(schema, components)

      assert resolved == %{"name" => "symbol", "schema" => %{"type" => "string"}}
    end

    test "resolves schema reference" do
      components = %{
        "schemas" => %{
          "Order" => %{
            "type" => "object",
            "properties" => %{
              "orderId" => %{"type" => "integer"}
            }
          }
        }
      }

      schema = %{"$ref" => "#/components/schemas/Order"}
      resolved = TypeGenerator.resolve_ref(schema, components)

      assert resolved["type"] == "object"
      assert resolved["properties"]["orderId"]["type"] == "integer"
    end

    test "resolves nested references" do
      components = %{
        "schemas" => %{
          "OrderRef" => %{"$ref" => "#/components/schemas/Order"},
          "Order" => %{
            "type" => "object",
            "properties" => %{"orderId" => %{"type" => "integer"}}
          }
        }
      }

      schema = %{"$ref" => "#/components/schemas/OrderRef"}
      resolved = TypeGenerator.resolve_ref(schema, components)

      assert resolved["type"] == "object"
    end

    test "returns schema unchanged when no $ref" do
      schema = %{"type" => "string"}
      resolved = TypeGenerator.resolve_ref(schema, %{})
      assert resolved == schema
    end

    test "returns empty map for invalid reference" do
      schema = %{"$ref" => "#/components/invalid/path"}
      resolved = TypeGenerator.resolve_ref(schema, %{})
      assert resolved == %{}
    end
  end

  describe "extract_param_types/2" do
    test "extracts types from inline parameter schemas" do
      spec = %{
        "parameters" => [
          %{"name" => "symbol", "schema" => %{"type" => "string"}},
          %{"name" => "orderId", "schema" => %{"type" => "integer"}}
        ]
      }

      result = TypeGenerator.extract_param_types(spec, %{})

      assert result == [
               {:symbol, "String.t()"},
               {:order_id, "integer()"}
             ]
    end

    test "extracts types from referenced parameters" do
      spec = %{
        "parameters" => [
          %{"$ref" => "#/components/parameters/symbol"}
        ]
      }

      components = %{
        "parameters" => %{
          "symbol" => %{
            "name" => "symbol",
            "schema" => %{"type" => "string"}
          }
        }
      }

      result = TypeGenerator.extract_param_types(spec, components)
      assert result == [{:symbol, "String.t()"}]
    end

    test "converts camelCase parameter names to snake_case" do
      spec = %{
        "parameters" => [
          %{"name" => "recvWindow", "schema" => %{"type" => "integer"}},
          %{"name" => "timeInForce", "schema" => %{"type" => "string"}}
        ]
      }

      result = TypeGenerator.extract_param_types(spec, %{})

      assert result == [
               {:recv_window, "integer()"},
               {:time_in_force, "String.t()"}
             ]
    end

    test "returns empty list when no parameters" do
      spec = %{}
      assert TypeGenerator.extract_param_types(spec, %{}) == []
    end
  end

  describe "extract_response_type/2" do
    test "extracts type from 200 response" do
      spec = %{
        "responses" => %{
          "200" => %{
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{
                    "serverTime" => %{"type" => "integer"}
                  },
                  "required" => ["serverTime"]
                }
              }
            }
          }
        }
      }

      result = TypeGenerator.extract_response_type(spec, %{})
      assert result == "%{server_time: integer()}"
    end

    test "extracts type from 201 response when 200 missing" do
      spec = %{
        "responses" => %{
          "201" => %{
            "content" => %{
              "application/json" => %{
                "schema" => %{"type" => "string"}
              }
            }
          }
        }
      }

      result = TypeGenerator.extract_response_type(spec, %{})
      assert result == "String.t()"
    end

    test "resolves referenced response schemas" do
      spec = %{
        "responses" => %{
          "200" => %{
            "content" => %{
              "application/json" => %{
                "schema" => %{"$ref" => "#/components/schemas/Order"}
              }
            }
          }
        }
      }

      components = %{
        "schemas" => %{
          "Order" => %{
            "type" => "object",
            "properties" => %{
              "orderId" => %{"type" => "integer"}
            },
            "required" => ["orderId"]
          }
        }
      }

      result = TypeGenerator.extract_response_type(spec, components)
      assert result == "%{order_id: integer()}"
    end

    test "returns term() when no success response" do
      spec = %{"responses" => %{"400" => %{"description" => "Bad request"}}}
      assert TypeGenerator.extract_response_type(spec, %{}) == "term()"
    end

    test "returns term() when no content in response" do
      spec = %{"responses" => %{"200" => %{"description" => "Success"}}}
      assert TypeGenerator.extract_response_type(spec, %{}) == "term()"
    end
  end

  describe "generate_spec/3" do
    test "generates spec with simple response type" do
      result = TypeGenerator.generate_spec(:get_server_time, [], "integer()")

      assert result ==
               "@spec get_server_time(map(), keyword()) :: {:ok, integer()} | {:error, term()}"
    end

    test "generates spec with complex response type" do
      result =
        TypeGenerator.generate_spec(:get_account, [], "%{balances: list(%{asset: String.t()})}")

      assert result ==
               "@spec get_account(map(), keyword()) :: {:ok, %{balances: list(%{asset: String.t()})}} | {:error, term()}"
    end

    test "generates spec ignoring param_types (all functions take map, keyword)" do
      param_types = [{:symbol, "String.t()"}, {:order_id, "integer()"}]
      result = TypeGenerator.generate_spec(:query_order, param_types, "map()")

      assert result ==
               "@spec query_order(map(), keyword()) :: {:ok, map()} | {:error, term()}"
    end
  end
end
