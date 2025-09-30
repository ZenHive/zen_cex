defmodule ZenCex.Adapters.BaseParserTest do
  use ExUnit.Case, async: true

  # Create a test module that uses BaseParser
  defmodule TestParser do
    @moduledoc false
    use ZenCex.Adapters.BaseParser
  end

  describe "parse_server_time/1" do
    test "parses serverTime field" do
      assert {:ok, %{server_time: 1_234_567_890}} =
               TestParser.parse_server_time(%{"serverTime" => 1_234_567_890})
    end

    test "parses time field" do
      assert {:ok, %{server_time: 9_876_543_210}} =
               TestParser.parse_server_time(%{"time" => 9_876_543_210})
    end

    test "parses timestamp field" do
      assert {:ok, %{server_time: 1_111_111_111}} =
               TestParser.parse_server_time(%{"timestamp" => 1_111_111_111})
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} = TestParser.parse_server_time(%{})
      assert {:error, :invalid_format} = TestParser.parse_server_time(%{"other" => 123})
    end

    test "returns error for non-integer time values" do
      assert {:error, :invalid_format} = TestParser.parse_server_time(%{"serverTime" => "123"})
      assert {:error, :invalid_format} = TestParser.parse_server_time(%{"time" => nil})
    end
  end

  describe "parse_generic/1" do
    test "handles maps" do
      assert {:ok, %{key: "value"}} = TestParser.parse_generic(%{key: "value"})
    end

    test "handles lists" do
      assert {:ok, [1, 2, 3]} = TestParser.parse_generic([1, 2, 3])
    end

    test "handles other types" do
      assert {:ok, "string"} = TestParser.parse_generic("string")
      assert {:ok, 123} = TestParser.parse_generic(123)
      assert {:ok, nil} = TestParser.parse_generic(nil)
    end
  end

  # NOTE: standardize_error/1 was removed as part of pure error pass-through philosophy
  # All errors are now passed through unchanged as raw exchange responses
  # See lib/zen_cex/adapters/base_parser.ex moduledoc for rationale

  describe "parse_balances/1" do
    test "parses Binance-style balance format" do
      balances = [
        %{"asset" => "BTC", "free" => "1.5", "locked" => "0.5"},
        %{"asset" => "ETH", "free" => "10", "locked" => "0"}
      ]

      assert {:ok, parsed} = TestParser.parse_balances(balances)
      assert length(parsed) == 2

      [btc, eth] = parsed
      assert btc.asset == "BTC"
      assert Decimal.equal?(btc.free, Decimal.new("1.5"))
      assert Decimal.equal?(btc.locked, Decimal.new("0.5"))
      assert Decimal.equal?(btc.total, Decimal.new("2.0"))

      assert eth.asset == "ETH"
      assert Decimal.equal?(eth.free, Decimal.new("10"))
      assert Decimal.equal?(eth.locked, Decimal.new("0"))
      assert Decimal.equal?(eth.total, Decimal.new("10"))
    end

    test "parses alternative balance field names" do
      balances = [
        %{"coin" => "BTC", "available" => "1.0", "frozen" => "0.5"},
        %{"currency" => "USD", "availableBalance" => 1000, "lockedBalance" => 100}
      ]

      assert {:ok, parsed} = TestParser.parse_balances(balances)
      assert length(parsed) == 2

      [btc, usd] = parsed
      assert btc.asset == "BTC"
      assert Decimal.equal?(btc.free, Decimal.new("1.0"))
      assert Decimal.equal?(btc.locked, Decimal.new("0.5"))

      assert usd.asset == "USD"
      assert Decimal.equal?(usd.free, Decimal.new(1000))
      assert Decimal.equal?(usd.locked, Decimal.new(100))
    end

    test "uses provided total when available" do
      balances = [
        %{"asset" => "BTC", "free" => "1.0", "locked" => "0.5", "total" => "1.5"},
        %{"asset" => "ETH", "free" => "10", "locked" => "0", "balance" => "10"}
      ]

      assert {:ok, parsed} = TestParser.parse_balances(balances)

      [btc, eth] = parsed
      assert Decimal.equal?(btc.total, Decimal.new("1.5"))
      assert Decimal.equal?(eth.total, Decimal.new("10"))
    end

    test "handles missing values with defaults" do
      balances = [
        # No amounts provided
        %{"asset" => "BTC"},
        # Only free provided
        %{"coin" => "ETH", "free" => "5"}
      ]

      assert {:ok, parsed} = TestParser.parse_balances(balances)

      [btc, eth] = parsed
      assert btc.asset == "BTC"
      assert Decimal.equal?(btc.free, Decimal.new("0"))
      assert Decimal.equal?(btc.locked, Decimal.new("0"))
      assert Decimal.equal?(btc.total, Decimal.new("0"))

      assert eth.asset == "ETH"
      assert Decimal.equal?(eth.free, Decimal.new("5"))
      assert Decimal.equal?(eth.locked, Decimal.new("0"))
      assert Decimal.equal?(eth.total, Decimal.new("5"))
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_balance_format} = TestParser.parse_balances("not a list")
      assert {:error, :invalid_balance_format} = TestParser.parse_balances(%{})
      assert {:error, :invalid_balance_format} = TestParser.parse_balances(nil)
    end
  end
end
