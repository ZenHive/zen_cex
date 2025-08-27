defmodule ZenCex.Adapters.BaseParameterBuilderTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.BaseParameterBuilder

  # Create a test module that uses BaseParameterBuilder
  defmodule TestParameterBuilder do
    @moduledoc false
    use BaseParameterBuilder, default_recv_window: 3000
  end

  # Create another with default recv_window
  defmodule DefaultParameterBuilder do
    @moduledoc false
    use BaseParameterBuilder
  end

  describe "filter_and_normalize/1" do
    test "filters out nil and empty string values" do
      params = %{
        "valid" => "value",
        "nil_param" => nil,
        "empty_string" => "",
        "zero" => 0,
        "false" => false
      }

      result = TestParameterBuilder.filter_and_normalize(params)

      # Should keep valid, zero, and false but remove nil and empty
      assert Map.has_key?(result, "valid")
      assert Map.has_key?(result, "zero")
      assert Map.has_key?(result, "false")
      refute Map.has_key?(result, "nil_param")
      refute Map.has_key?(result, "empty_string")
    end

    test "normalizes parameter values to strings" do
      params = %{
        "string" => "already_string",
        "number" => 123,
        "float" => 45.67,
        "atom" => :symbol,
        "boolean" => true
      }

      result = TestParameterBuilder.filter_and_normalize(params)

      assert result["string"] == "already_string"
      assert result["number"] == "123"
      assert result["float"] == "45.67"
      assert result["atom"] == "symbol"
      assert result["boolean"] == "true"
    end
  end

  describe "build_query_string/1" do
    test "builds query string from parameters" do
      params = %{
        "symbol" => "BTCUSDT",
        "limit" => "100",
        "timestamp" => "1234567890"
      }

      query = TestParameterBuilder.build_query_string(params)

      # Query string should contain all params (order may vary)
      assert query =~ "symbol=BTCUSDT"
      assert query =~ "limit=100"
      assert query =~ "timestamp=1234567890"
      assert query =~ "&"
    end

    test "handles empty parameters" do
      assert TestParameterBuilder.build_query_string(%{}) == ""
    end
  end

  describe "add_timestamp_if_missing/2" do
    test "adds timestamp when not present" do
      params = %{"symbol" => "BTCUSDT"}

      result = TestParameterBuilder.add_timestamp_if_missing(params, :test_exchange)

      assert Map.has_key?(result, "timestamp")
      assert is_binary(result["timestamp"])

      # Should be a valid timestamp
      {timestamp, ""} = Integer.parse(result["timestamp"])
      assert timestamp > 0
    end

    test "preserves existing timestamp" do
      params = %{"symbol" => "BTCUSDT", "timestamp" => "9999999999"}

      result = TestParameterBuilder.add_timestamp_if_missing(params, :test_exchange)

      assert result["timestamp"] == "9999999999"
    end

    test "handles ClockSync not initialized" do
      # When ClockSync hasn't synchronized for this exchange,
      # it should fall back to system time
      params = %{"symbol" => "BTCUSDT"}

      result = TestParameterBuilder.add_timestamp_if_missing(params, :unknown_exchange)

      assert Map.has_key?(result, "timestamp")
      assert is_binary(result["timestamp"])

      # Should be close to current system time
      {timestamp, ""} = Integer.parse(result["timestamp"])
      system_time = System.system_time(:millisecond)
      # Within 1 second
      assert abs(timestamp - system_time) < 1000
    end
  end

  describe "get_default_recv_window/0" do
    test "returns configured default recv_window" do
      assert TestParameterBuilder.get_default_recv_window() == 3000
    end

    test "returns default 5000 when not specified" do
      assert DefaultParameterBuilder.get_default_recv_window() == 5000
    end
  end

  describe "private helper functions" do
    test "ensure_string_value converts various types to strings" do
      # These are private functions, but we can test them through
      # the public filter_and_normalize function
      params = %{
        "already_string" => "test",
        "integer" => 42,
        "float" => 3.14,
        "atom" => :test_atom,
        "boolean" => false
      }

      result = TestParameterBuilder.filter_and_normalize(params)

      assert result["already_string"] == "test"
      assert result["integer"] == "42"
      assert result["float"] == "3.14"
      assert result["atom"] == "test_atom"
      assert result["boolean"] == "false"
    end
  end
end
