defmodule ZenCex.ParserMacrosTest do
  use ExUnit.Case, async: true

  import ZenCex.ParserMacros

  describe "safe_decimal_field/2" do
    test "converts nil to default decimal" do
      assert safe_decimal_field(nil) == Decimal.new("0")
      assert safe_decimal_field(nil, default: "100") == Decimal.new("100")
    end

    test "converts empty string to default decimal" do
      assert safe_decimal_field("") == Decimal.new("0")
      assert safe_decimal_field("", default: "50") == Decimal.new("50")
    end

    test "parses valid decimal strings" do
      assert safe_decimal_field("123.45") == Decimal.new("123.45")
      assert safe_decimal_field("0.001") == Decimal.new("0.001")
      assert safe_decimal_field("999999.999999") == Decimal.new("999999.999999")
    end

    test "handles invalid decimal strings" do
      assert safe_decimal_field("not_a_number") == Decimal.new("0")
      assert safe_decimal_field("abc123") == Decimal.new("0")
      # Decimal.parse actually parses "12.34.56" as "12.34" (stops at second dot)
      assert safe_decimal_field("12.34.56") == Decimal.new("12.34")
    end

    test "converts integers to decimal" do
      assert safe_decimal_field(123) == Decimal.new("123")
      assert safe_decimal_field(0) == Decimal.new("0")
      assert safe_decimal_field(-50) == Decimal.new("-50")
    end

    test "converts floats to decimal" do
      assert safe_decimal_field(123.45) == Decimal.new("123.45")
      assert safe_decimal_field(0.001) == Decimal.new("0.001")
    end

    test "handles basis points conversion for integers" do
      # 10 basis points = 0.001
      assert safe_decimal_field(10, basis_points: true) == Decimal.new("0.001")
      # 100 basis points = 0.01
      assert safe_decimal_field(100, basis_points: true) == Decimal.new("0.01")
      # 1 basis point = 0.0001
      assert safe_decimal_field(1, basis_points: true) == Decimal.new("0.0001")
    end

    test "ignores basis_points flag for non-integers" do
      # String values should not be affected by basis_points flag
      assert safe_decimal_field("10", basis_points: true) == Decimal.new("10")
      assert safe_decimal_field(10.5, basis_points: true) == Decimal.new("10.5")
    end

    test "handles unexpected types" do
      assert safe_decimal_field(%{}) == Decimal.new("0")
      assert safe_decimal_field([]) == Decimal.new("0")
      assert safe_decimal_field(:atom) == Decimal.new("0")
    end
  end

  describe "extract_field/3" do
    test "extracts field from map with first matching key" do
      map = %{"orderId" => 123, "id" => 456}
      assert extract_field(map, ["orderId", "id"]) == 123
      assert extract_field(map, ["id", "orderId"]) == 456
    end

    test "returns nil when no fields match" do
      map = %{"other" => "value"}
      assert extract_field(map, ["orderId", "id"]) == nil
    end

    test "transforms to string" do
      map = %{"orderId" => 123}
      assert extract_field(map, ["orderId"], :string) == "123"
      assert extract_field(map, ["missing"], :string) == ""
    end

    test "transforms to decimal" do
      map = %{"price" => "50.25"}
      assert extract_field(map, ["price"], :decimal) == Decimal.new("50.25")

      map2 = %{"quantity" => 10}
      assert extract_field(map2, ["quantity"], :decimal) == Decimal.new("10")
    end

    test "transforms to integer" do
      map = %{"count" => "5"}
      assert extract_field(map, ["count"], :integer) == 5

      map2 = %{"count" => 5.7}
      assert extract_field(map2, ["count"], :integer) == 6
    end

    test "applies custom transformation function" do
      map = %{"timestamp" => 1000}
      transform = fn value -> value * 2 end
      assert extract_field(map, ["timestamp"], transform) == 2000
    end

    test "handles non-map input gracefully" do
      assert extract_field(nil, ["field"], :string) == nil
      assert extract_field("not a map", ["field"], :string) == nil
    end

    test "finds first non-nil value in field list" do
      map = %{"field1" => nil, "field2" => "value", "field3" => "other"}
      assert extract_field(map, ["field1", "field2", "field3"]) == "value"
    end
  end

  describe "convert_to_decimal/3" do
    test "direct function call matches macro behavior" do
      assert ZenCex.ParserMacros.convert_to_decimal("123.45", "0", false) ==
               Decimal.new("123.45")

      assert ZenCex.ParserMacros.convert_to_decimal(10, "0", true) ==
               Decimal.new("0.001")

      assert ZenCex.ParserMacros.convert_to_decimal(nil, "100", false) ==
               Decimal.new("100")
    end
  end

  describe "extract_and_transform/3" do
    test "direct function call matches macro behavior" do
      map = %{"price" => "50.25", "amount" => 100}

      assert ZenCex.ParserMacros.extract_and_transform(map, ["price"], :decimal) ==
               Decimal.new("50.25")

      assert ZenCex.ParserMacros.extract_and_transform(map, ["amount"], :string) ==
               "100"

      assert ZenCex.ParserMacros.extract_and_transform(map, ["missing"], :identity) ==
               nil
    end
  end

  describe "normalize_keys/1" do
    test "converts camelCase to snake_case atoms" do
      input = %{"orderId" => "123", "clientOrderId" => "abc"}
      expected = %{order_id: "123", client_order_id: "abc"}
      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end

    test "handles nested maps" do
      input = %{"result" => %{"timeSecond" => "123"}}
      expected = %{result: %{time_second: "123"}}
      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end

    test "handles deeply nested maps" do
      input = %{
        "data" => %{
          "userInfo" => %{
            "userId" => "123",
            "accountType" => "SPOT"
          }
        }
      }

      expected = %{
        data: %{
          user_info: %{
            user_id: "123",
            account_type: "SPOT"
          }
        }
      }

      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end

    test "handles lists of maps" do
      input = [%{"symbol" => "BTCUSDT"}, %{"symbol" => "ETHUSDT"}]
      expected = [%{symbol: "BTCUSDT"}, %{symbol: "ETHUSDT"}]
      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end

    test "handles nested lists" do
      input = %{"orders" => [%{"orderId" => "123"}, %{"orderId" => "456"}]}
      expected = %{orders: [%{order_id: "123"}, %{order_id: "456"}]}
      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end

    test "preserves non-map/list values" do
      assert ZenCex.ParserMacros.normalize_keys("string") == "string"
      assert ZenCex.ParserMacros.normalize_keys(123) == 123
      assert ZenCex.ParserMacros.normalize_keys(nil) == nil
      assert ZenCex.ParserMacros.normalize_keys(true) == true
      assert ZenCex.ParserMacros.normalize_keys(12.34) == 12.34
    end

    test "handles empty collections" do
      assert ZenCex.ParserMacros.normalize_keys(%{}) == %{}
      assert ZenCex.ParserMacros.normalize_keys([]) == []
    end

    test "converts existing atom keys to snake_case" do
      input = %{orderId: "123", clientOrderId: "abc"}
      expected = %{order_id: "123", client_order_id: "abc"}
      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end

    test "handles mixed string and atom keys" do
      input = %{"orderId" => "123", clientOrderId: "abc"}
      expected = %{order_id: "123", client_order_id: "abc"}
      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end

    test "handles common exchange field names" do
      input = %{
        "orderId" => "123",
        "clientOrderId" => "abc",
        "serverTime" => 1_234_567_890,
        "retCode" => 0,
        "retMsg" => "OK"
      }

      expected = %{
        order_id: "123",
        client_order_id: "abc",
        server_time: 1_234_567_890,
        ret_code: 0,
        ret_msg: "OK"
      }

      assert ZenCex.ParserMacros.normalize_keys(input) == expected
    end
  end

  describe "decode_json_body/1" do
    test "decodes valid JSON" do
      json = ~s({"key": "value"})
      assert {:ok, %{"key" => "value"}} = ZenCex.ParserMacros.decode_json_body(json)
    end

    test "decodes complex nested JSON" do
      json = ~s({"result": {"data": [{"id": 1}, {"id": 2}]}})

      assert {:ok, %{"result" => %{"data" => [%{"id" => 1}, %{"id" => 2}]}}} =
               ZenCex.ParserMacros.decode_json_body(json)
    end

    test "returns error for invalid JSON" do
      assert {:error, :invalid_json} = ZenCex.ParserMacros.decode_json_body("not json")
    end

    test "handles empty string" do
      assert {:error, :invalid_json} = ZenCex.ParserMacros.decode_json_body("")
    end

    test "handles malformed JSON" do
      assert {:error, :invalid_json} = ZenCex.ParserMacros.decode_json_body("{invalid}")
      assert {:error, :invalid_json} = ZenCex.ParserMacros.decode_json_body(~s({"key": }))
    end

    test "decodes JSON arrays" do
      json = ~s([1, 2, 3])
      assert {:ok, [1, 2, 3]} = ZenCex.ParserMacros.decode_json_body(json)
    end

    test "decodes JSON with numbers and booleans" do
      json = ~s({"count": 123, "price": 45.67, "active": true, "empty": null})

      assert {:ok, %{"count" => 123, "price" => 45.67, "active" => true, "empty" => nil}} =
               ZenCex.ParserMacros.decode_json_body(json)
    end
  end

  describe "normalize_enum_value/1" do
    test "converts strings to lowercase atoms" do
      assert ZenCex.ParserMacros.normalize_enum_value("BUY") == :buy
      assert ZenCex.ParserMacros.normalize_enum_value("SELL") == :sell
      assert ZenCex.ParserMacros.normalize_enum_value("PARTIALLY_FILLED") == :partially_filled
    end

    test "handles already lowercase strings" do
      assert ZenCex.ParserMacros.normalize_enum_value("buy") == :buy
      assert ZenCex.ParserMacros.normalize_enum_value("sell") == :sell
    end

    test "handles mixed case strings" do
      assert ZenCex.ParserMacros.normalize_enum_value("Buy") == :buy
      assert ZenCex.ParserMacros.normalize_enum_value("Sell") == :sell
    end

    test "handles nil gracefully" do
      assert ZenCex.ParserMacros.normalize_enum_value(nil) == nil
    end

    test "preserves existing atoms" do
      assert ZenCex.ParserMacros.normalize_enum_value(:buy) == :buy
      assert ZenCex.ParserMacros.normalize_enum_value(:sell) == :sell
    end

    test "handles common exchange enum values" do
      assert ZenCex.ParserMacros.normalize_enum_value("NEW") == :new
      assert ZenCex.ParserMacros.normalize_enum_value("FILLED") == :filled
      assert ZenCex.ParserMacros.normalize_enum_value("CANCELED") == :canceled
      assert ZenCex.ParserMacros.normalize_enum_value("REJECTED") == :rejected
    end

    test "handles enum values with underscores" do
      assert ZenCex.ParserMacros.normalize_enum_value("LIMIT_MAKER") == :limit_maker
      assert ZenCex.ParserMacros.normalize_enum_value("STOP_LOSS") == :stop_loss

      assert ZenCex.ParserMacros.normalize_enum_value("STOP_LOSS_LIMIT") ==
               :stop_loss_limit
    end
  end
end
