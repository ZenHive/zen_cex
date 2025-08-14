defmodule ZenCex.HTTPTest do
  use ExUnit.Case, async: true

  alias ZenCex.HTTP

  describe "exchange_url/1" do
    test "returns correct URL for Binance spot" do
      assert HTTP.exchange_url(:binance) == "https://api.binance.com"
    end

    test "returns correct URL for Binance futures" do
      assert HTTP.exchange_url(:binance_futures) == "https://fapi.binance.com"
    end

    test "returns correct URL for Kraken" do
      assert HTTP.exchange_url(:kraken) == "https://api.kraken.com"
    end

    test "returns correct URL for Deribit production" do
      assert HTTP.exchange_url(:deribit) == "https://www.deribit.com"
    end

    test "returns correct URL for Deribit test" do
      assert HTTP.exchange_url(:deribit_test) == "https://test.deribit.com"
    end

    test "raises for unknown exchange" do
      assert_raise ArgumentError, ~r/Unknown exchange/, fn ->
        HTTP.exchange_url(:unknown)
      end
    end
  end

  describe "operation_timeout/1" do
    test "returns 2000ms for trading operations" do
      assert HTTP.operation_timeout(:trading) == 2_000
    end

    test "returns 5000ms for market data operations" do
      assert HTTP.operation_timeout(:market_data) == 5_000
    end

    test "returns 30000ms for historical data operations" do
      assert HTTP.operation_timeout(:historical) == 30_000
    end

    test "returns default 5000ms for unknown operations" do
      assert HTTP.operation_timeout(:unknown) == 5_000
    end
  end

  describe "base_request/2" do
    test "creates request with correct base URL for exchange" do
      request = HTTP.base_request(:binance)
      assert request.options[:base_url] == "https://api.binance.com"
    end

    test "uses ZenCex.Finch as HTTP client" do
      request = HTTP.base_request(:binance)
      assert request.options[:finch] == ZenCex.Finch
    end

    test "sets operation-specific timeout" do
      request = HTTP.base_request(:binance, :trading)
      assert request.options[:receive_timeout] == 2_000

      request = HTTP.base_request(:binance, :historical)
      assert request.options[:receive_timeout] == 30_000
    end

    test "enables compression" do
      request = HTTP.base_request(:binance)
      assert request.options[:compressed] == true
    end

    test "configures retry for safe transient errors" do
      request = HTTP.base_request(:binance)
      assert request.options[:retry] == :safe_transient
      assert request.options[:max_retries] == 3
    end

    test "includes required middleware steps" do
      request = HTTP.base_request(:binance)

      # Check request steps are prepended (request_steps is a keyword list)
      request_step_keys = Keyword.keys(request.request_steps)
      assert :inject_timestamp in request_step_keys
      assert :check_rate_limit in request_step_keys
      assert :add_request_id in request_step_keys

      # Check response steps are appended (response_steps is a keyword list)
      response_step_keys = Keyword.keys(request.response_steps)
      assert :extract_weight in response_step_keys
    end

    test "stores exchange in options for middleware" do
      request = HTTP.base_request(:kraken)
      assert request.options[:exchange] == :kraken
    end
  end

  describe "exponential_backoff/1" do
    test "returns exponentially increasing delays with jitter" do
      # Test first few attempts
      delay1 = HTTP.exponential_backoff(0)
      delay2 = HTTP.exponential_backoff(1)
      delay3 = HTTP.exponential_backoff(2)

      # Base delays: 1000ms, 2000ms, 4000ms
      # Plus jitter: 0-500ms
      assert delay1 >= 1000 and delay1 <= 1500
      assert delay2 >= 2000 and delay2 <= 2500
      assert delay3 >= 4000 and delay3 <= 4500
    end

    test "caps delay at 60 seconds" do
      # Large attempt number should still cap at 60s + jitter
      delay = HTTP.exponential_backoff(20)
      assert delay <= 60_000
    end

    test "includes random jitter" do
      # Multiple calls with same attempt should give different results
      delays = for _ <- 1..10, do: HTTP.exponential_backoff(1)
      unique_delays = Enum.uniq(delays)

      # Should have multiple unique values due to jitter
      assert length(unique_delays) > 1
    end
  end

  describe "inject_timestamp/1" do
    test "adds X-Timestamp header with current timestamp" do
      request = Req.new() |> Map.put(:options, %{})
      {:ok, updated} = HTTP.inject_timestamp(request)

      timestamp_header = Req.Request.get_header(updated, "x-timestamp")
      assert [timestamp] = timestamp_header

      # Verify it's a valid millisecond timestamp
      parsed = String.to_integer(timestamp)
      now = System.system_time(:millisecond)
      # Within 1 second
      assert abs(parsed - now) < 1000
    end

    test "stores timestamp in private metadata" do
      request = Req.new() |> Map.put(:options, %{})
      {:ok, updated} = HTTP.inject_timestamp(request)

      timestamp = Req.Request.get_private(updated, :timestamp)
      assert is_integer(timestamp)
    end
  end

  describe "check_rate_limit/1" do
    test "allows request when under rate limit" do
      request = Req.new() |> Map.put(:options, %{exchange: :binance})

      # Mock rate limit check (would use ETS in real implementation)
      {:ok, _updated} = HTTP.check_rate_limit(request)
    end

    test "returns error when rate limit exceeded" do
      request = Req.new() |> Map.put(:options, %{exchange: :binance})

      # Simulate rate limit exceeded scenario
      # In real implementation, this would check ETS counters
      # For now, we'll test the error structure
      # Over Binance limit
      result = HTTP.check_rate_limit_with_count(request, 1201)
      assert {:error, {:rate_limit_exceeded, :binance}} = result
    end
  end

  describe "add_request_id/1" do
    test "adds unique request ID header" do
      request = Req.new() |> Map.put(:options, %{exchange: :binance})
      {:ok, updated} = HTTP.add_request_id(request)

      [request_id] = Req.Request.get_header(updated, "x-request-id")
      assert String.starts_with?(request_id, "binance-")
      assert String.contains?(request_id, "-")
    end

    test "stores request ID in private metadata" do
      request = Req.new() |> Map.put(:options, %{exchange: :kraken})
      {:ok, updated} = HTTP.add_request_id(request)

      request_id = Req.Request.get_private(updated, :request_id)
      assert String.starts_with?(request_id, "kraken-")
    end

    test "generates unique IDs for consecutive calls" do
      request = Req.new() |> Map.put(:options, %{exchange: :binance})

      {:ok, req1} = HTTP.add_request_id(request)
      {:ok, req2} = HTTP.add_request_id(request)

      id1 = Req.Request.get_private(req1, :request_id)
      id2 = Req.Request.get_private(req2, :request_id)

      assert id1 != id2
    end
  end

  describe "extract_weight/1" do
    test "extracts Binance rate limit weight from headers" do
      response = %{
        headers: %{
          "x-mbx-used-weight-1m" => ["75"],
          "x-mbx-order-count-1m" => ["5"]
        }
      }

      {:ok, {_request, updated}} = HTTP.extract_weight({nil, response})

      assert updated.private[:rate_limit_weight] == 75
      assert updated.private[:order_count] == 5
    end

    test "extracts Kraken rate limit info from headers" do
      response = %{
        headers: %{
          "x-ratelimit-remaining" => ["10"],
          "x-ratelimit-limit" => ["15"]
        }
      }

      {:ok, {_request, updated}} = HTTP.extract_weight({nil, response})

      assert updated.private[:rate_limit_remaining] == 10
      assert updated.private[:rate_limit_limit] == 15
    end

    test "handles missing rate limit headers gracefully" do
      response = %{headers: %{}}

      {:ok, {_request, updated}} = HTTP.extract_weight({nil, response})

      # Should not crash, just have no rate limit data
      assert updated.private[:rate_limit_weight] == nil
    end
  end

  describe "parse_response/2" do
    test "parses successful JSON response" do
      response = %{status: 200, body: ~s({"result": "success", "data": [1, 2, 3]})}

      assert {:ok, %{"result" => "success", "data" => [1, 2, 3]}} =
               HTTP.parse_response(response, :json)
    end

    test "returns error for non-200 status" do
      response = %{status: 429, body: ~s({"error": "Rate limit exceeded"})}

      assert {:error, {:http_error, 429, %{"error" => "Rate limit exceeded"}}} =
               HTTP.parse_response(response, :json)
    end

    test "handles malformed JSON" do
      response = %{status: 200, body: "not json"}

      assert {:error, {:parse_error, _}} = HTTP.parse_response(response, :json)
    end

    test "returns raw body for non-JSON format" do
      response = %{status: 200, body: "raw text response"}

      assert {:ok, "raw text response"} = HTTP.parse_response(response, :raw)
    end

    test "handles pre-decoded JSON from Req" do
      # When Req auto-decodes JSON, body is already a map
      response = %{status: 200, body: %{"result" => "success", "data" => [1, 2, 3]}}

      assert {:ok, %{"result" => "success", "data" => [1, 2, 3]}} =
               HTTP.parse_response(response, :json)
    end

    test "handles pre-decoded JSON arrays from Req" do
      # When Req auto-decodes JSON arrays
      response = %{status: 200, body: [1, 2, 3]}

      assert {:ok, [1, 2, 3]} = HTTP.parse_response(response, :json)
    end

    test "handles error responses with pre-decoded JSON" do
      response = %{status: 400, body: %{"error" => "Invalid request"}}

      assert {:error, {:http_error, 400, %{"error" => "Invalid request"}}} =
               HTTP.parse_response(response, :json)
    end
  end

  describe "build_query_string/1" do
    test "builds query string from params map" do
      params = %{symbol: "BTCUSDT", limit: 100, interval: "1h"}

      query = HTTP.build_query_string(params)

      # Order might vary, so check individual parts
      assert String.contains?(query, "symbol=BTCUSDT")
      assert String.contains?(query, "limit=100")
      assert String.contains?(query, "interval=1h")
      assert String.contains?(query, "&")
    end

    test "handles empty params" do
      assert HTTP.build_query_string(%{}) == ""
    end

    test "URL encodes special characters" do
      params = %{query: "test value", symbol: "BTC/USD"}

      query = HTTP.build_query_string(params)

      assert String.contains?(query, "test%20value") or String.contains?(query, "test+value")
      assert String.contains?(query, "BTC%2FUSD")
    end
  end
end
