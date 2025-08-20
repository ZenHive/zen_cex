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
end
