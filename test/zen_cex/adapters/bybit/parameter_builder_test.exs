defmodule ZenCex.Adapters.Bybit.ParameterBuilderTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.ParameterBuilder

  describe "build_params/3" do
    test "injects category based on spot_ prefix" do
      params = %{"symbol" => "BTCUSDT", "side" => "BUY"}
      result = ParameterBuilder.build_params(params, "spot_place_order", timestamp: "1234567890")

      assert result["category"] == "spot"
      assert result["symbol"] == "BTCUSDT"
      assert result["side"] == "BUY"
      assert result["timestamp"] == "1234567890"
      assert result["recv_window"] == "5000"
    end

    test "injects category based on linear_ prefix" do
      params = %{"symbol" => "BTCUSDT"}
      result = ParameterBuilder.build_params(params, "linear_get_positions", timestamp: "1234567890")

      assert result["category"] == "linear"
      assert result["symbol"] == "BTCUSDT"
      assert result["timestamp"] == "1234567890"
      assert result["recv_window"] == "5000"
    end

    test "injects category based on inverse_ prefix" do
      params = %{"symbol" => "BTCUSD"}
      result = ParameterBuilder.build_params(params, "inverse_get_positions", timestamp: "1234567890")

      assert result["category"] == "inverse"
      assert result["symbol"] == "BTCUSD"
    end

    test "injects category based on option_ prefix" do
      params = %{"symbol" => "BTC-25NOV22-20000-C"}
      result = ParameterBuilder.build_params(params, "option_place_order", timestamp: "1234567890")

      assert result["category"] == "option"
      assert result["symbol"] == "BTC-25NOV22-20000-C"
    end

    test "does not inject category for operations without known prefix" do
      params = %{"test" => "value"}
      result = ParameterBuilder.build_params(params, "server_time", timestamp: "1234567890")

      refute Map.has_key?(result, "category")
      assert result["test"] == "value"
    end

    test "preserves existing category if already present" do
      params = %{"symbol" => "BTCUSDT", "category" => "custom"}
      result = ParameterBuilder.build_params(params, "spot_place_order", timestamp: "1234567890")

      # Map.put_new should preserve existing category
      assert result["category"] == "custom"
    end

    test "filters out nil values" do
      params = %{"symbol" => "BTCUSDT", "type" => nil, "side" => "BUY"}
      result = ParameterBuilder.build_params(params, "spot_place_order", timestamp: "1234567890")

      refute Map.has_key?(result, "type")
      assert result["symbol"] == "BTCUSDT"
      assert result["side"] == "BUY"
    end

    test "filters out empty strings" do
      params = %{"symbol" => "BTCUSDT", "type" => "", "side" => "BUY"}
      result = ParameterBuilder.build_params(params, "spot_place_order", timestamp: "1234567890")

      refute Map.has_key?(result, "type")
      assert result["symbol"] == "BTCUSDT"
      assert result["side"] == "BUY"
    end

    test "normalizes numeric values to strings" do
      params = %{"quantity" => 1.5, "price" => 50_000}
      result = ParameterBuilder.build_params(params, "spot_place_order", timestamp: "1234567890")

      assert result["quantity"] == "1.5"
      assert result["price"] == "50000"
    end

    test "uses custom recv_window when provided" do
      params = %{"symbol" => "BTCUSDT"}

      result =
        ParameterBuilder.build_params(params, "spot_place_order",
          timestamp: "1234567890",
          recv_window: "10000"
        )

      assert result["recv_window"] == "10000"
    end

    test "generates timestamp if not provided" do
      params = %{"symbol" => "BTCUSDT"}
      result = ParameterBuilder.build_params(params, "spot_place_order")

      assert Map.has_key?(result, "timestamp")
      # Timestamp should be a numeric string
      assert String.match?(result["timestamp"], ~r/^\d+$/)
      # Should be recent (within last minute)
      timestamp = String.to_integer(result["timestamp"])
      now = System.system_time(:millisecond)
      # Within 60 seconds
      assert abs(now - timestamp) < 60_000
    end
  end

  describe "build_query_string/1" do
    test "builds alphabetically sorted query string" do
      params = %{
        "symbol" => "BTCUSDT",
        "category" => "spot",
        "side" => "BUY",
        "type" => "LIMIT"
      }

      result = ParameterBuilder.build_query_string(params)
      assert result == "category=spot&side=BUY&symbol=BTCUSDT&type=LIMIT"
    end

    test "handles URL encoding" do
      params = %{
        "symbol" => "BTC USDT",
        "message" => "hello&world"
      }

      result = ParameterBuilder.build_query_string(params)
      assert result == "message=hello%26world&symbol=BTC+USDT"
    end

    test "handles empty params" do
      result = ParameterBuilder.build_query_string(%{})
      assert result == ""
    end

    test "handles single parameter" do
      params = %{"symbol" => "BTCUSDT"}
      result = ParameterBuilder.build_query_string(params)
      assert result == "symbol=BTCUSDT"
    end
  end

  describe "format_json_body/1" do
    test "formats params as JSON string" do
      params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "category" => "spot"
      }

      result = ParameterBuilder.format_json_body(params)
      decoded = Jason.decode!(result)

      assert decoded["symbol"] == "BTCUSDT"
      assert decoded["side"] == "BUY"
      assert decoded["category"] == "spot"
    end

    test "handles nested structures" do
      params = %{
        "symbol" => "BTCUSDT",
        "orderFilter" => %{
          "orderType" => "Order",
          "limit" => 500
        }
      }

      result = ParameterBuilder.format_json_body(params)
      decoded = Jason.decode!(result)

      assert decoded["symbol"] == "BTCUSDT"
      assert decoded["orderFilter"]["orderType"] == "Order"
      assert decoded["orderFilter"]["limit"] == 500
    end

    test "handles empty params" do
      result = ParameterBuilder.format_json_body(%{})
      assert result == "{}"
    end
  end

  describe "get_category_from_operation/1" do
    test "extracts spot category" do
      assert ParameterBuilder.get_category_from_operation("spot_place_order") == "spot"
      assert ParameterBuilder.get_category_from_operation("spot_get_balances") == "spot"
    end

    test "extracts linear category" do
      assert ParameterBuilder.get_category_from_operation("linear_place_order") == "linear"
      assert ParameterBuilder.get_category_from_operation("linear_get_positions") == "linear"
    end

    test "extracts inverse category" do
      assert ParameterBuilder.get_category_from_operation("inverse_place_order") == "inverse"
      assert ParameterBuilder.get_category_from_operation("inverse_get_positions") == "inverse"
    end

    test "extracts option category" do
      assert ParameterBuilder.get_category_from_operation("option_place_order") == "option"
      assert ParameterBuilder.get_category_from_operation("option_get_positions") == "option"
    end

    test "returns nil for operations without category prefix" do
      assert ParameterBuilder.get_category_from_operation("server_time") == nil
      assert ParameterBuilder.get_category_from_operation("get_announcements") == nil
      assert ParameterBuilder.get_category_from_operation("common_operation") == nil
    end

    test "does not match partial prefixes" do
      # Should not match if prefix is not at the start
      assert ParameterBuilder.get_category_from_operation("get_spot_balance") == nil
      assert ParameterBuilder.get_category_from_operation("my_linear_function") == nil
    end
  end
end
