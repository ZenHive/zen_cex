defmodule ZenCex.Adapters.Binance.ParameterBuilderTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.ParameterBuilder

  doctest ParameterBuilder

  describe "build_query_string/1" do
    test "builds query string with standard parameters only" do
      params = %{"symbol" => "BTCUSDT", "side" => "BUY", "type" => "MARKET"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "side=BUY&symbol=BTCUSDT&type=MARKET"
    end

    test "builds query string with timing parameters in Binance order" do
      params = %{"symbol" => "BTCUSDT", "timestamp" => "1234567890", "recvWindow" => "5000"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "symbol=BTCUSDT&timestamp=1234567890&recvWindow=5000"
    end

    test "builds query string with mixed parameters maintaining Binance order" do
      params = %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "timestamp" => "1234567890",
        "recvWindow" => "5000",
        "type" => "MARKET"
      }

      result = ParameterBuilder.build_query_string(params)

      # Standard params (alphabetically sorted) + timing params in specific order
      assert result == "side=BUY&symbol=BTCUSDT&type=MARKET&timestamp=1234567890&recvWindow=5000"
    end

    test "handles only timing parameters" do
      params = %{"timestamp" => "1234567890", "recvWindow" => "5000"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "timestamp=1234567890&recvWindow=5000"
    end

    test "handles only timestamp parameter" do
      params = %{"timestamp" => "1234567890"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "timestamp=1234567890"
    end

    test "handles only recvWindow parameter" do
      params = %{"recvWindow" => "5000"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "recvWindow=5000"
    end

    test "handles empty parameters" do
      result = ParameterBuilder.build_query_string(%{})

      assert result == ""
    end

    test "URL encodes parameter values" do
      params = %{"symbol" => "BTC/USDT", "timestamp" => "1234567890"}

      result = ParameterBuilder.build_query_string(params)

      assert result == "symbol=BTC%2FUSDT&timestamp=1234567890"
    end
  end

  describe "build_ordered_query_string/3" do
    test "builds final query string with signature" do
      existing_params = %{"symbol" => "BTCUSDT", "side" => "BUY"}
      all_params = %{"symbol" => "BTCUSDT", "side" => "BUY", "timestamp" => "123", "recvWindow" => "5000"}
      signature = "abc123def456"

      result = ParameterBuilder.build_ordered_query_string(existing_params, all_params, signature)

      expected = "side=BUY&symbol=BTCUSDT&timestamp=123&recvWindow=5000&signature=abc123def456"
      assert result == expected
    end

    test "handles only timing parameters with signature" do
      existing_params = %{}
      all_params = %{"timestamp" => "123", "recvWindow" => "5000"}
      signature = "abc123"

      result = ParameterBuilder.build_ordered_query_string(existing_params, all_params, signature)

      assert result == "timestamp=123&recvWindow=5000&signature=abc123"
    end

    test "handles only standard parameters with timing and signature" do
      existing_params = %{"symbol" => "BTCUSDT"}
      all_params = %{"symbol" => "BTCUSDT", "timestamp" => "123", "recvWindow" => "5000"}
      signature = "abc123"

      result = ParameterBuilder.build_ordered_query_string(existing_params, all_params, signature)

      assert result == "symbol=BTCUSDT&timestamp=123&recvWindow=5000&signature=abc123"
    end

    test "signature is always last parameter" do
      existing_params = %{"z_last" => "value", "a_first" => "value"}

      all_params = %{
        "z_last" => "value",
        "a_first" => "value",
        "timestamp" => "123",
        "recvWindow" => "5000"
      }

      signature = "signature_value"

      result = ParameterBuilder.build_ordered_query_string(existing_params, all_params, signature)

      # Should end with signature regardless of other parameter names
      assert String.ends_with?(result, "&signature=signature_value")
      assert result == "a_first=value&z_last=value&timestamp=123&recvWindow=5000&signature=signature_value"
    end
  end

  describe "ensure_timing_params/2" do
    test "adds timestamp and recvWindow when missing" do
      params = %{"symbol" => "BTCUSDT"}

      result = ParameterBuilder.ensure_timing_params(params, :spot)

      assert Map.has_key?(result, "timestamp")
      assert Map.has_key?(result, "recvWindow")
      # Default value
      assert result["recvWindow"] == "5000"
      assert result["symbol"] == "BTCUSDT"
    end

    test "preserves existing timestamp and recvWindow" do
      params = %{"symbol" => "BTCUSDT", "timestamp" => "1111111111", "recvWindow" => "3000"}

      result = ParameterBuilder.ensure_timing_params(params, :spot)

      assert result["timestamp"] == "1111111111"
      assert result["recvWindow"] == "3000"
      assert result["symbol"] == "BTCUSDT"
    end

    test "validates and clamps recvWindow to maximum" do
      # Above 60000 limit
      params = %{"symbol" => "BTCUSDT", "recvWindow" => "70000"}

      result = ParameterBuilder.ensure_timing_params(params, :spot)

      # Clamped to max
      assert result["recvWindow"] == "60000"
    end

    test "fixes invalid recvWindow format" do
      params = %{"symbol" => "BTCUSDT", "recvWindow" => "invalid"}

      result = ParameterBuilder.ensure_timing_params(params, :spot)

      # Reset to default
      assert result["recvWindow"] == "5000"
    end

    test "filters out nil parameters" do
      params = %{"symbol" => "BTCUSDT", "side" => nil, "type" => "MARKET"}

      result = ParameterBuilder.ensure_timing_params(params, :spot)

      assert Map.has_key?(result, "symbol")
      assert Map.has_key?(result, "type")
      refute Map.has_key?(result, "side")
      assert Map.has_key?(result, "timestamp")
      assert Map.has_key?(result, "recvWindow")
    end

    test "handles different api types" do
      params = %{"symbol" => "BTCUSDT"}

      # Should work with different API types
      spot_result = ParameterBuilder.ensure_timing_params(params, :spot)
      futures_result = ParameterBuilder.ensure_timing_params(params, :usdm_futures)

      # Both should have timing params added
      assert Map.has_key?(spot_result, "timestamp")
      assert Map.has_key?(futures_result, "timestamp")
    end

    test "handles zero recvWindow (valid but unusual)" do
      params = %{"symbol" => "BTCUSDT", "recvWindow" => "0"}

      result = ParameterBuilder.ensure_timing_params(params, :spot)

      # Zero is technically invalid for Binance (must be > 0), so should be reset to default
      assert result["recvWindow"] == "5000"
    end

    test "handles negative recvWindow" do
      params = %{"symbol" => "BTCUSDT", "recvWindow" => "-1000"}

      result = ParameterBuilder.ensure_timing_params(params, :spot)

      # Negative values are invalid, should be reset to default
      assert result["recvWindow"] == "5000"
    end
  end
end
