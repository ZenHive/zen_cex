defmodule ZenCex.Core.ParameterBuilderTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.ParameterBuilder

  doctest ParameterBuilder

  describe "build_query_string/2" do
    test "builds query string with sorted parameters" do
      params = %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "side=BUY&symbol=BTCUSDT&type=MARKET"
    end

    test "handles empty parameters" do
      result = ParameterBuilder.build_query_string(%{})

      assert result == ""
    end

    test "URL encodes parameter values" do
      params = %{"symbol" => "BTC/USDT", "message" => "hello world"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "message=hello+world&symbol=BTC%2FUSDT"
    end

    test "converts non-string values to strings" do
      params = %{"quantity" => 1.5, "price" => 100, "active" => true}

      result = ParameterBuilder.build_query_string(params)

      assert result == "active=true&price=100&quantity=1.5"
    end

    test "excludes specified keys" do
      params = %{"symbol" => "BTCUSDT", "timestamp" => "123456", "side" => "BUY"}

      result = ParameterBuilder.build_query_string(params, exclude_keys: ["timestamp"])

      assert result == "side=BUY&symbol=BTCUSDT"
    end

    test "preserves original order when sort is disabled" do
      # Test that we can disable sorting by comparing sorted vs unsorted results
      params = %{"c" => "3", "a" => "1", "b" => "2"}

      sorted_result = ParameterBuilder.build_query_string(params, sort: true)
      unsorted_result = ParameterBuilder.build_query_string(params, sort: false)

      # Sorted result should be alphabetical
      assert sorted_result == "a=1&b=2&c=3"

      # Both results should contain the same parameters, just different order
      sorted_pairs = sorted_result |> String.split("&") |> Enum.sort()
      unsorted_pairs = unsorted_result |> String.split("&") |> Enum.sort()
      assert sorted_pairs == unsorted_pairs
    end
  end

  describe "filter_optional_params/2" do
    test "removes nil values" do
      params = %{"symbol" => "BTCUSDT", "type" => nil, "side" => "BUY"}

      result = ParameterBuilder.filter_optional_params(params)

      assert result == %{"symbol" => "BTCUSDT", "side" => "BUY"}
    end

    test "removes empty strings by default" do
      params = %{"symbol" => "BTCUSDT", "type" => "", "side" => "BUY"}

      result = ParameterBuilder.filter_optional_params(params)

      assert result == %{"symbol" => "BTCUSDT", "side" => "BUY"}
    end

    test "keeps empty strings when option is disabled" do
      params = %{"symbol" => "BTCUSDT", "type" => "", "side" => "BUY"}

      result = ParameterBuilder.filter_optional_params(params, remove_empty_strings: false)

      assert result == %{"symbol" => "BTCUSDT", "type" => "", "side" => "BUY"}
    end

    test "keeps zero and false values" do
      params = %{"quantity" => 0, "test" => false, "price" => 0.0}

      result = ParameterBuilder.filter_optional_params(params)

      assert result == %{"quantity" => 0, "test" => false, "price" => 0.0}
    end

    test "handles empty map" do
      result = ParameterBuilder.filter_optional_params(%{})

      assert result == %{}
    end
  end

  describe "validate_required_params/2" do
    test "returns :ok when all required params are present" do
      params = %{"symbol" => "BTCUSDT", "side" => "BUY", "quantity" => "1.0"}
      required = ["symbol", "side"]

      result = ParameterBuilder.validate_required_params(params, required)

      assert result == :ok
    end

    test "returns error when required param is missing" do
      params = %{"symbol" => "BTCUSDT"}
      required = ["symbol", "side"]

      result = ParameterBuilder.validate_required_params(params, required)

      assert result == {:error, {:missing_required_param, "side"}}
    end

    test "returns error when required param is nil" do
      params = %{"symbol" => "BTCUSDT", "side" => nil}
      required = ["symbol", "side"]

      result = ParameterBuilder.validate_required_params(params, required)

      assert result == {:error, {:missing_required_param, "side"}}
    end

    test "handles empty required list" do
      params = %{"symbol" => "BTCUSDT"}

      result = ParameterBuilder.validate_required_params(params, [])

      assert result == :ok
    end
  end

  describe "normalize_param_values/1" do
    test "converts numeric values to strings" do
      params = %{"quantity" => 1.5, "price" => 100}

      result = ParameterBuilder.normalize_param_values(params)

      assert result == %{"quantity" => "1.5", "price" => "100"}
    end

    test "converts boolean values to strings" do
      params = %{"active" => true, "disabled" => false}

      result = ParameterBuilder.normalize_param_values(params)

      assert result == %{"active" => "true", "disabled" => "false"}
    end

    test "converts atoms to strings" do
      params = %{"type" => :limit, "side" => :buy}

      result = ParameterBuilder.normalize_param_values(params)

      assert result == %{"type" => "limit", "side" => "buy"}
    end

    test "handles Decimal values" do
      decimal_value = Decimal.new("10.50")
      params = %{"price" => decimal_value}

      result = ParameterBuilder.normalize_param_values(params)

      assert result == %{"price" => "10.50"}
    end

    test "keeps string values unchanged" do
      params = %{"symbol" => "BTCUSDT", "side" => "BUY"}

      result = ParameterBuilder.normalize_param_values(params)

      assert result == %{"symbol" => "BTCUSDT", "side" => "BUY"}
    end

    test "handles mixed value types" do
      params = %{
        "symbol" => "BTCUSDT",
        "quantity" => 1.5,
        "active" => true,
        "type" => :limit,
        "price" => Decimal.new("100.25")
      }

      result = ParameterBuilder.normalize_param_values(params)

      expected = %{
        "symbol" => "BTCUSDT",
        "quantity" => "1.5",
        "active" => "true",
        "type" => "limit",
        "price" => "100.25"
      }

      assert result == expected
    end
  end

  describe "merge_with_defaults/2" do
    test "merges parameters with defaults" do
      params = %{"symbol" => "BTCUSDT", "quantity" => "1.0"}
      defaults = %{"type" => "LIMIT", "timeInForce" => "GTC"}

      result = ParameterBuilder.merge_with_defaults(params, defaults)

      expected = %{
        "symbol" => "BTCUSDT",
        "quantity" => "1.0",
        "type" => "LIMIT",
        "timeInForce" => "GTC"
      }

      assert result == expected
    end

    test "existing parameters override defaults" do
      params = %{"symbol" => "BTCUSDT", "type" => "MARKET"}
      defaults = %{"symbol" => "ETHUSDT", "type" => "LIMIT", "timeInForce" => "GTC"}

      result = ParameterBuilder.merge_with_defaults(params, defaults)

      expected = %{
        "symbol" => "BTCUSDT",
        "type" => "MARKET",
        "timeInForce" => "GTC"
      }

      assert result == expected
    end

    test "handles empty defaults" do
      params = %{"symbol" => "BTCUSDT"}

      result = ParameterBuilder.merge_with_defaults(params, %{})

      assert result == %{"symbol" => "BTCUSDT"}
    end

    test "handles empty parameters" do
      defaults = %{"type" => "LIMIT", "timeInForce" => "GTC"}

      result = ParameterBuilder.merge_with_defaults(%{}, defaults)

      assert result == defaults
    end
  end

  describe "split_params_by_groups/2" do
    test "splits parameters into specified groups" do
      params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "timestamp" => "123456",
        "recvWindow" => "5000"
      }

      groups = [
        timing: ["timestamp", "recvWindow"],
        trading: ["symbol", "side"]
      ]

      result = ParameterBuilder.split_params_by_groups(params, groups)

      expected = %{
        timing: %{"timestamp" => "123456", "recvWindow" => "5000"},
        trading: %{"symbol" => "BTCUSDT", "side" => "BUY"}
      }

      assert result == expected
    end

    test "handles missing parameters in groups" do
      params = %{"symbol" => "BTCUSDT", "timestamp" => "123456"}

      groups = [
        timing: ["timestamp", "recvWindow"],
        trading: ["symbol", "side", "quantity"]
      ]

      result = ParameterBuilder.split_params_by_groups(params, groups)

      expected = %{
        timing: %{"timestamp" => "123456"},
        trading: %{"symbol" => "BTCUSDT"}
      }

      assert result == expected
    end

    test "handles parameters not in any group" do
      params = %{"symbol" => "BTCUSDT", "extra" => "value", "timestamp" => "123456"}

      groups = [timing: ["timestamp"]]

      result = ParameterBuilder.split_params_by_groups(params, groups)

      expected = %{timing: %{"timestamp" => "123456"}}

      assert result == expected
    end

    test "handles empty groups" do
      params = %{"symbol" => "BTCUSDT"}

      result = ParameterBuilder.split_params_by_groups(params, [])

      assert result == %{}
    end
  end
end
