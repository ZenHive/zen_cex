defmodule ZenCex.HTTPRateLimitIntegrationTest do
  use ExUnit.Case, async: false

  alias ZenCex.{HTTP, RateLimit, ReqHelpers}

  setup do
    # Ensure RateLimit is started (it may already be started by the app)
    case Process.whereis(ZenCex.RateLimit) do
      nil ->
        {:ok, _pid} = start_supervised(RateLimit)
        :ok

      _pid ->
        # Already running, just clear any existing state
        :ok
    end
  end

  describe "HTTP and RateLimit integration" do
    test "check_rate_limit/1 integrates with RateLimit module" do
      # Create a request with exchange info
      request = HTTP.base_request(:binance, :market_data)

      # First request should pass
      assert {:ok, _request} = HTTP.check_rate_limit(request)

      # Simulate hitting the rate limit
      # Binance has 1200/min limit, so let's increment by 1200
      for _ <- 1..1199 do
        RateLimit.check_and_increment(:binance, "/api/v3/ticker", 1)
      end

      # Next request should be rate limited
      assert {:error, {:rate_limit_exceeded, :binance}} = HTTP.check_rate_limit(request)
    end

    test "check_rate_limit/1 uses weight from request private" do
      # Clear any previous rate limit data by waiting for a new window
      Process.sleep(1100)

      # Create a request with custom weight
      # Use futures for higher limit
      request =
        HTTP.base_request(:binance_futures, :market_data)
        |> ReqHelpers.put_private(:rate_limit_weight, 100)

      # Increment close to limit (futures has 2400/min limit)
      for _ <- 1..2350 do
        RateLimit.check_and_increment(:binance_futures, "/fapi/v1/ticker", 1)
      end

      # Request with weight 100 should be blocked (2350 + 100 > 2400)
      assert {:error, {:rate_limit_exceeded, :binance_futures}} = HTTP.check_rate_limit(request)
    end

    test "different exchanges have different limits" do
      binance_request = HTTP.base_request(:binance, :market_data)
      kraken_request = HTTP.base_request(:kraken, :market_data)

      # Fill up Kraken's limit (15/sec)
      for _ <- 1..15 do
        RateLimit.check_and_increment(:kraken, "/0/public/Ticker", 1)
      end

      # Kraken should be rate limited
      assert {:error, {:rate_limit_exceeded, :kraken}} = HTTP.check_rate_limit(kraken_request)

      # Binance should still work (different limit)
      assert {:ok, _request} = HTTP.check_rate_limit(binance_request)
    end

    test "extract_weight/1 works with real Req.Response structs" do
      # Create a mock Req.Response with rate limit headers
      response = %Req.Response{
        status: 200,
        headers: %{
          "x-mbx-used-weight-1m" => ["150"],
          "x-mbx-order-count-1m" => ["10"]
        },
        body: "{}",
        private: %{}
      }

      {:ok, {_request, updated}} = HTTP.extract_weight({nil, response})

      # Verify it's still a Req.Response struct
      assert %Req.Response{} = updated

      # Verify private data was extracted
      assert updated.private[:rate_limit_weight] == 150
      assert updated.private[:order_count] == 10
    end
  end
end
