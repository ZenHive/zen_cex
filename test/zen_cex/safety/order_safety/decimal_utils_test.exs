defmodule ZenCex.Safety.OrderSafety.DecimalUtilsTest do
  use ExUnit.Case, async: true

  alias ZenCex.Safety.OrderSafety.DecimalUtils

  describe "parse_decimal/1" do
    test "parses valid string decimals" do
      assert DecimalUtils.parse_decimal("123.456") == Decimal.new("123.456")
      assert DecimalUtils.parse_decimal("0.00000001") == Decimal.new("0.00000001")
      assert DecimalUtils.parse_decimal("999999999.999999999") == Decimal.new("999999999.999999999")
    end

    test "handles scientific notation in strings" do
      # Decimal library preserves scientific notation
      assert DecimalUtils.parse_decimal("1.5e-8") == Decimal.new("1.5e-8")
      assert DecimalUtils.parse_decimal("2.5E+3") == Decimal.new("2.5E+3")
      assert DecimalUtils.parse_decimal("1e10") == Decimal.new("1e10")

      # But they are mathematically equivalent
      assert Decimal.equal?(DecimalUtils.parse_decimal("1.5e-8"), Decimal.new("0.000000015"))
      assert Decimal.equal?(DecimalUtils.parse_decimal("2.5E+3"), Decimal.new("2500"))
      assert Decimal.equal?(DecimalUtils.parse_decimal("1e10"), Decimal.new("10000000000"))
    end

    test "handles negative numbers" do
      assert DecimalUtils.parse_decimal("-123.456") == Decimal.new("-123.456")
      assert DecimalUtils.parse_decimal("-0.00001") == Decimal.new("-0.00001")
    end

    test "handles integer strings" do
      assert DecimalUtils.parse_decimal("123") == Decimal.new("123")
      assert DecimalUtils.parse_decimal("0") == Decimal.new("0")
    end

    test "handles numbers with trailing/leading spaces" do
      assert DecimalUtils.parse_decimal(" 123.45 ") == Decimal.new("123.45")
      assert DecimalUtils.parse_decimal("\t100\n") == Decimal.new("100")
    end

    test "parses numeric types" do
      assert DecimalUtils.parse_decimal(123) == Decimal.new("123")
      assert DecimalUtils.parse_decimal(123.456) == Decimal.new("123.456")
      assert DecimalUtils.parse_decimal(0) == Decimal.new("0")
      assert DecimalUtils.parse_decimal(-42.5) == Decimal.new("-42.5")
    end

    test "handles Decimal input" do
      decimal = Decimal.new("123.456")
      assert DecimalUtils.parse_decimal(decimal) == decimal
    end

    test "returns zero for invalid strings" do
      assert DecimalUtils.parse_decimal("not_a_number") == Decimal.new("0")
      assert DecimalUtils.parse_decimal("123.456.789") == Decimal.new("0")
      assert DecimalUtils.parse_decimal("") == Decimal.new("0")
      assert DecimalUtils.parse_decimal("abc123") == Decimal.new("0")
    end

    test "returns zero for nil and other types" do
      assert DecimalUtils.parse_decimal(nil) == Decimal.new("0")
      assert DecimalUtils.parse_decimal(:atom) == Decimal.new("0")
      assert DecimalUtils.parse_decimal(%{}) == Decimal.new("0")
      assert DecimalUtils.parse_decimal([]) == Decimal.new("0")
    end

    test "handles infinity and NaN edge cases" do
      assert DecimalUtils.parse_decimal("Infinity") == Decimal.new("0")
      assert DecimalUtils.parse_decimal("NaN") == Decimal.new("0")
      assert DecimalUtils.parse_decimal("-Infinity") == Decimal.new("0")
    end
  end

  describe "safe_parse_decimal/1" do
    test "returns ok tuple for valid strings" do
      assert {:ok, decimal} = DecimalUtils.safe_parse_decimal("123.456")
      assert decimal == Decimal.new("123.456")

      assert {:ok, decimal} = DecimalUtils.safe_parse_decimal("1.5e-8")
      assert decimal == Decimal.new("1.5e-8")
      assert Decimal.equal?(decimal, Decimal.new("0.000000015"))
    end

    test "returns ok tuple for numeric types" do
      assert {:ok, decimal} = DecimalUtils.safe_parse_decimal(123)
      assert decimal == Decimal.new("123")

      assert {:ok, decimal} = DecimalUtils.safe_parse_decimal(123.456)
      assert decimal == Decimal.new("123.456")
    end

    test "returns ok tuple for Decimal input" do
      input = Decimal.new("123.456")
      assert {:ok, ^input} = DecimalUtils.safe_parse_decimal(input)
    end

    test "returns error tuple for invalid strings" do
      assert {:error, {:invalid_decimal, "not_a_number"}} =
               DecimalUtils.safe_parse_decimal("not_a_number")

      assert {:error, {:invalid_decimal, ""}} =
               DecimalUtils.safe_parse_decimal("")
    end

    test "returns error tuple for nil and other types" do
      assert {:error, {:invalid_decimal, nil}} = DecimalUtils.safe_parse_decimal(nil)
      assert {:error, {:invalid_decimal, :atom}} = DecimalUtils.safe_parse_decimal(:atom)
      assert {:error, {:invalid_decimal, %{}}} = DecimalUtils.safe_parse_decimal(%{})
      assert {:error, {:invalid_decimal, []}} = DecimalUtils.safe_parse_decimal([])
    end
  end

  describe "extract_available_balance/2" do
    test "extracts from Binance spot format" do
      balances = %{
        "BTC" => %{free: "1.5", locked: "0.5"},
        "ETH" => %{free: "10.0", locked: "0"}
      }

      assert DecimalUtils.extract_available_balance(balances, "BTC") == Decimal.new("1.5")
      assert DecimalUtils.extract_available_balance(balances, "ETH") == Decimal.new("10.0")
    end

    test "extracts from Bybit unified format" do
      balances = %{
        "BTC" => %{available: "2.5"},
        "USDT" => %{available: "1000.0"}
      }

      assert DecimalUtils.extract_available_balance(balances, "BTC") == Decimal.new("2.5")
      assert DecimalUtils.extract_available_balance(balances, "USDT") == Decimal.new("1000.0")
    end

    test "extracts from alternative balance formats" do
      # Available balance format
      balances1 = %{"BTC" => %{available_balance: "1.234"}}
      assert DecimalUtils.extract_available_balance(balances1, "BTC") == Decimal.new("1.234")

      # Available to withdraw format
      balances2 = %{"ETH" => %{available_to_withdraw: "5.678"}}
      assert DecimalUtils.extract_available_balance(balances2, "ETH") == Decimal.new("5.678")
    end

    test "returns zero for missing asset" do
      balances = %{"BTC" => %{free: "1.5"}}
      assert DecimalUtils.extract_available_balance(balances, "ETH") == Decimal.new("0")
    end

    test "returns zero for invalid balance format" do
      balances = %{
        "BTC" => %{wrong_field: "1.5"},
        "ETH" => "not_a_map",
        "ADA" => nil
      }

      assert DecimalUtils.extract_available_balance(balances, "BTC") == Decimal.new("0")
      assert DecimalUtils.extract_available_balance(balances, "ETH") == Decimal.new("0")
      assert DecimalUtils.extract_available_balance(balances, "ADA") == Decimal.new("0")
    end

    test "returns zero for nil or non-map balances" do
      assert DecimalUtils.extract_available_balance(nil, "BTC") == Decimal.new("0")
      assert DecimalUtils.extract_available_balance([], "BTC") == Decimal.new("0")
      assert DecimalUtils.extract_available_balance("not_a_map", "BTC") == Decimal.new("0")
    end

    test "handles numeric values in balance fields" do
      # Some APIs might return numbers instead of strings
      balances = %{
        "BTC" => %{free: 1.5},
        "ETH" => %{available: 10}
      }

      # Current implementation expects strings, so these should return zero
      # This documents the current behavior
      assert DecimalUtils.extract_available_balance(balances, "BTC") == Decimal.new("0")
      assert DecimalUtils.extract_available_balance(balances, "ETH") == Decimal.new("0")
    end

    test "handles mixed case and special characters in asset names" do
      balances = %{
        "BTC" => %{free: "1.0"},
        "btc" => %{free: "2.0"},
        "BTC-USDT" => %{free: "3.0"}
      }

      assert DecimalUtils.extract_available_balance(balances, "BTC") == Decimal.new("1.0")
      assert DecimalUtils.extract_available_balance(balances, "btc") == Decimal.new("2.0")
      assert DecimalUtils.extract_available_balance(balances, "BTC-USDT") == Decimal.new("3.0")
      assert DecimalUtils.extract_available_balance(balances, "ETH") == Decimal.new("0")
    end
  end
end
