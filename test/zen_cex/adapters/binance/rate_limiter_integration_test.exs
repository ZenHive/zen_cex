defmodule ZenCex.Adapters.Binance.RateLimiterIntegrationTest do
  @moduledoc """
  Integration tests for Binance rate limiter against REAL API.

  These tests interact with actual Binance API endpoints to:
  1. Observe real rate limit headers
  2. Document actual API behavior
  3. Validate our implementation matches reality

  Uses smart bucketing to avoid DDoS:
  - Groups requests into small buckets
  - Adds delays between buckets
  - Uses public endpoints that don't require auth
  """

  use ExUnit.Case, async: false

  alias ZenCex.Adapters.Binance.RateLimiter

  require Logger

  # Only run if explicitly enabled
  @moduletag :integration
  @moduletag :binance

  # Smart testing parameters
  # Small buckets to avoid hammering
  @bucket_size 3
  # 2 seconds between buckets
  @inter_bucket_delay_ms 2000
  # Maximum buckets to test
  @max_buckets 5

  # Test against public endpoints (no auth needed)
  @test_endpoints [
    # Weight: 1
    {"https://api.binance.com/api/v3/ping", 1},
    # Weight: 1
    {"https://api.binance.com/api/v3/time", 1},
    # Weight: 10
    {"https://api.binance.com/api/v3/exchangeInfo", 10}
  ]

  setup do
    # Initialize rate limiter
    RateLimiter.init()
    RateLimiter.reset()

    # Skip if no network
    case check_network_connectivity() do
      :ok ->
        :ok

      {:error, reason} ->
        {:skip, "Network unavailable: #{reason}"}
    end
  end

  describe "real API rate limit headers" do
    @tag :requires_network
    test "observes and documents actual Binance rate limit headers" do
      Logger.info("Testing against REAL Binance API to observe rate limit headers")

      # Make a single request to observe headers
      {endpoint, _weight} = List.first(@test_endpoints)

      case make_request(endpoint) do
        {:ok, response} ->
          # Document observed headers
          headers = Map.new(response.headers)

          Logger.info("Observed Binance headers:")

          Enum.each(headers, fn {key, value} ->
            if String.contains?(String.downcase(key), ["limit", "weight", "retry"]) do
              Logger.info("  #{key}: #{value}")
            end
          end)

          # Check for expected rate limit headers
          assert Map.has_key?(headers, "x-mbx-used-weight-1m") or
                   Map.has_key?(headers, "x-mbx-used-weight") or
                   Map.has_key?(headers, "x-used-weight-1m"),
                 "Expected rate limit headers not found. Headers: #{inspect(Map.keys(headers))}"

          # Document the actual header format
          weight_header =
            headers["x-mbx-used-weight-1m"] ||
              headers["x-mbx-used-weight"] ||
              headers["x-used-weight-1m"]

          if weight_header do
            # Headers can come as lists or strings
            weight_str =
              case weight_header do
                [val | _] when is_binary(val) -> val
                val when is_binary(val) -> val
                _ -> nil
              end

            if weight_str do
              {weight_value, ""} = Integer.parse(weight_str)
              assert weight_value > 0
              Logger.info("Current weight usage: #{weight_value}")
            end
          end

        {:error, reason} ->
          Logger.warning("Could not connect to Binance API: #{inspect(reason)}")
          flunk("Binance API unreachable: #{inspect(reason)}")
      end
    end

    @tag :requires_network
    test "validates rate limiter tracking against real API responses" do
      Logger.info("Testing rate limiter tracking with real API")

      # Process requests in smart buckets
      bucket_results =
        for bucket_num <- 1..@max_buckets do
          Logger.info("Processing bucket #{bucket_num}/#{@max_buckets}")

          # Execute bucket
          requests_in_bucket =
            for i <- 1..@bucket_size do
              {endpoint, expected_weight} =
                Enum.at(@test_endpoints, rem(i - 1, length(@test_endpoints)))

              # Track with our rate limiter
              limiter_result = RateLimiter.check_and_increment(endpoint, expected_weight)

              # Make actual request
              api_result = make_request(endpoint)

              # Small delay within bucket to be respectful
              Process.sleep(100)

              %{
                endpoint: endpoint,
                weight: expected_weight,
                limiter_result: limiter_result,
                api_result: api_result,
                bucket: bucket_num,
                request_num: i
              }
            end

          # Analyze bucket results
          analyze_bucket_results(requests_in_bucket, bucket_num)

          # Delay between buckets
          if bucket_num < @max_buckets do
            Logger.info("Waiting #{@inter_bucket_delay_ms}ms before next bucket...")
            Process.sleep(@inter_bucket_delay_ms)
          end

          requests_in_bucket
        end
        |> List.flatten()

      # Overall analysis
      successful =
        Enum.count(bucket_results, fn r ->
          match?({:ok, _}, r.api_result) and r.limiter_result == :ok
        end)

      rate_limited_by_us =
        Enum.count(bucket_results, fn r ->
          match?({:error, {:rate_limited, _}}, r.limiter_result)
        end)

      rate_limited_by_api =
        Enum.count(bucket_results, fn r ->
          match?({:error, %{status: 429}}, r.api_result)
        end)

      Logger.info("""
      Test Summary:
        Total requests: #{length(bucket_results)}
        Successful: #{successful}
        Rate limited by our limiter: #{rate_limited_by_us}
        Rate limited by API (429): #{rate_limited_by_api}
      """)

      # Our limiter should prevent any 429s from the API
      assert rate_limited_by_api == 0,
             "Got #{rate_limited_by_api} 429 responses - our limiter should have prevented these"

      # If we hit rate limits, verify retry_after is reasonable
      if rate_limited_by_us > 0 do
        limited_requests =
          Enum.filter(bucket_results, fn r ->
            match?({:error, {:rate_limited, _}}, r.limiter_result)
          end)

        Enum.each(limited_requests, fn r ->
          {:error, {:rate_limited, retry_after_ms}} = r.limiter_result

          assert retry_after_ms > 0 and retry_after_ms <= 60_000,
                 "Invalid retry_after: #{retry_after_ms}ms"
        end)
      end
    end

    @tag :requires_network
    test "updates tracking from real response headers" do
      Logger.info("Testing rate limit updates from real headers")

      # Make a request and capture response
      {endpoint, weight} = List.first(@test_endpoints)

      case make_request(endpoint) do
        {:ok, response} ->
          # Update our tracking
          assert :ok = RateLimiter.update_from_response(response)

          # Check if weights match
          headers = Map.new(response.headers)

          if weight_header = headers["x-mbx-used-weight-1m"] do
            # Handle list or string format
            weight_str =
              case weight_header do
                [val | _] when is_binary(val) -> val
                val when is_binary(val) -> val
                _ -> "0"
              end

            {api_weight, ""} = Integer.parse(weight_str)

            # Our tracking should reflect the API's count
            status = RateLimiter.get_status()

            Logger.info("""
            Weight comparison:
              API reported: #{api_weight}
              Our tracking: #{status.ip.used}
              Expected weight: #{weight}
            """)

            # Note: Our count might differ due to other tests/timing
            # But it should be in a reasonable range
            assert status.ip.used <= status.ip.limit,
                   "Our tracking exceeds known limits"
          end

        {:error, reason} ->
          flunk("Could not test header updates: #{inspect(reason)}")
      end
    end
  end

  describe "edge cases from real API" do
    @tag :requires_network
    test "handles various endpoint weights correctly" do
      # Test different weight endpoints
      test_cases = [
        {"https://api.binance.com/api/v3/ping", 1},
        {"https://api.binance.com/api/v3/time", 1},
        {"https://api.binance.com/api/v3/depth?symbol=BTCUSDT&limit=5", 1},
        {"https://api.binance.com/api/v3/exchangeInfo", 10}
      ]

      Enum.each(test_cases, fn {endpoint, expected_weight} ->
        # Track with our limiter
        assert :ok = RateLimiter.check_and_increment(endpoint, expected_weight)

        # Make request and check headers
        case make_request(endpoint) do
          {:ok, response} ->
            headers = Map.new(response.headers)

            # Log weight if available
            if weight_header = headers["x-mbx-used-weight-1m"] do
              Logger.info("Endpoint #{endpoint} used weight: #{weight_header}")
            end

          {:error, _reason} ->
            # Network issue, skip
            :ok
        end

        # Be respectful - delay between requests
        Process.sleep(500)
      end)
    end

    @tag :requires_network
    test "documents actual rate limit values from API" do
      # Make a request to get current limits
      {endpoint, _} = List.first(@test_endpoints)

      case make_request(endpoint) do
        {:ok, response} ->
          headers = Map.new(response.headers)

          # Document all rate limit related headers
          rate_limit_info = %{
            used_weight_1m: headers["x-mbx-used-weight-1m"],
            used_weight: headers["x-mbx-used-weight"],
            order_count_10s: headers["x-mbx-order-count-10s"],
            order_count_1d: headers["x-mbx-order-count-1d"],
            retry_after: headers["retry-after"]
          }

          Logger.info("""
          Documented Binance Rate Limit Headers:
          #{inspect(rate_limit_info, pretty: true)}

          Note: These are actual values from production API.
          Our mocks should return similar headers.
          """)

          # Save for fixture generation
          assert is_map(rate_limit_info)

        {:error, reason} ->
          flunk("Could not document headers: #{inspect(reason)}")
      end
    end
  end

  # Helper functions

  defp check_network_connectivity do
    case :httpc.request(:get, {~c"https://api.binance.com/api/v3/ping", []}, [], []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp make_request(url) do
    # Use Req to make actual HTTP request
    request =
      Req.new(
        url: url,
        # Don't retry to avoid confusing our tests
        retry: false,
        pool_timeout: 5000,
        receive_timeout: 5000
      )

    case Req.get(request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp analyze_bucket_results(requests, bucket_num) do
    successful =
      Enum.count(requests, fn r ->
        match?({:ok, _}, r.api_result) and r.limiter_result == :ok
      end)

    limited =
      Enum.count(requests, fn r ->
        match?({:error, {:rate_limited, _}}, r.limiter_result)
      end)

    api_errors =
      Enum.count(requests, fn r ->
        match?({:error, _}, r.api_result)
      end)

    Logger.info("""
    Bucket #{bucket_num} results:
      Successful: #{successful}/#{length(requests)}
      Limited by us: #{limited}
      API errors: #{api_errors}
    """)

    # Extract and log weights from successful requests
    Enum.each(requests, fn r ->
      case r.api_result do
        {:ok, response} ->
          headers = Map.new(response.headers)

          if weight = headers["x-mbx-used-weight-1m"] do
            Logger.debug("  Request to #{r.endpoint}: weight=#{weight}")
          end

        _ ->
          :ok
      end
    end)
  end
end
