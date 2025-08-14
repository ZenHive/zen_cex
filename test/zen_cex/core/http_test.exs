defmodule ZenCex.Core.HTTPTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.HTTP

  describe "base_request/2" do
    test "creates request with correct base URL for known exchange" do
      request = HTTP.base_request(:binance)

      assert %Req.Request{} = request
      assert request.options[:base_url] == "https://api.binance.com"
    end

    test "sets correct timeout for trading operations" do
      request = HTTP.base_request(:binance, :trading)

      assert request.options[:receive_timeout] == 2_000
    end

    test "sets correct timeout for market operations" do
      request = HTTP.base_request(:binance, :market)

      assert request.options[:receive_timeout] == 5_000
    end

    test "sets correct timeout for historical operations" do
      request = HTTP.base_request(:binance, :historical)

      assert request.options[:receive_timeout] == 30_000
    end

    test "defaults to 5 second timeout for unspecified operation" do
      request = HTTP.base_request(:binance, :unknown)

      assert request.options[:receive_timeout] == 5_000
    end

    test "defaults to standard operation type when not specified" do
      request = HTTP.base_request(:binance)

      assert request.options[:receive_timeout] == 5_000
    end

    test "configures Finch connection pool" do
      request = HTTP.base_request(:binance)

      assert request.options[:finch] == ZenCex.Finch
    end

    test "configures retry strategy" do
      request = HTTP.base_request(:binance)

      assert request.options[:retry] == :safe_transient
      assert request.options[:max_retries] == 3
      assert is_function(request.options[:retry_delay], 1)
    end

    test "stores exchange and operation_type in request" do
      request = HTTP.base_request(:binance, :trading)

      assert request.options[:exchange] == :binance
      assert request.options[:operation_type] == :trading
    end

    test "raises for unknown exchange" do
      assert_raise RuntimeError, "Unknown exchange: unknown_exchange", fn ->
        HTTP.base_request(:unknown_exchange)
      end
    end
  end

  describe "exponential_backoff_with_jitter/1" do
    # Testing the private function indirectly through retry_delay
    test "calculates backoff with jitter correctly" do
      request = HTTP.base_request(:binance)
      retry_delay = request.options[:retry_delay]

      # Test first retry
      delay1 = retry_delay.(1)
      # 2^1 * 1000 = 2000
      assert delay1 >= 2_000
      # 2000 + max jitter (500)
      assert delay1 <= 2_500

      # Test second retry
      delay2 = retry_delay.(2)
      # 2^2 * 1000 = 4000
      assert delay2 >= 4_000
      # 4000 + max jitter (500)
      assert delay2 <= 4_500

      # Test third retry
      delay3 = retry_delay.(3)
      # 2^3 * 1000 = 8000
      assert delay3 >= 8_000
      # 8000 + max jitter (500)
      assert delay3 <= 8_500
    end

    test "caps backoff at 60 seconds" do
      request = HTTP.base_request(:binance)
      retry_delay = request.options[:retry_delay]

      # Test with high retry count
      delay = retry_delay.(20)
      assert delay <= 60_000
    end

    test "adds random jitter to prevent thundering herd" do
      request = HTTP.base_request(:binance)
      retry_delay = request.options[:retry_delay]

      # Generate multiple delays for same retry count
      delays = for _ <- 1..10, do: retry_delay.(2)

      # They should not all be the same (due to jitter)
      unique_delays = Enum.uniq(delays)
      assert length(unique_delays) > 1
    end
  end

  describe "integration with Registry" do
    test "fetches adapter from registry" do
      # This test verifies the integration with Registry module
      request = HTTP.base_request(:binance)

      # Should have gotten the base_url from the adapter
      assert request.options[:base_url] == "https://api.binance.com"
    end

    test "raises when registry doesn't have adapter" do
      assert_raise RuntimeError, ~r/Unknown exchange/, fn ->
        HTTP.base_request(:nonexistent)
      end
    end
  end

  describe "request structure" do
    test "creates valid Req.Request struct" do
      request = HTTP.base_request(:binance, :market)

      assert %Req.Request{} = request
      assert Map.has_key?(request, :options)
      assert Map.has_key?(request, :headers)
      assert Map.has_key?(request, :body)
    end

    test "registers custom options for exchange and operation_type" do
      request = HTTP.base_request(:binance, :trading)

      # These custom options should be available in the request
      assert request.options[:exchange] == :binance
      assert request.options[:operation_type] == :trading
    end
  end
end
