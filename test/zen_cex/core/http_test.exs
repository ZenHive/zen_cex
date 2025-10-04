defmodule ZenCex.Core.HTTPTest do
  use ZenCex.IntegrationCase, exchange: :binance

  alias ZenCex.Core.HTTP

  describe "base_request/2 with real testnet API" do
    test "creates request with proper configuration for Binance testnet" do
      # Create a real request to Binance testnet
      request = HTTP.base_request(:binance, :market)

      # Verify configuration
      assert request.options[:finch] == ZenCex.Finch
      assert request.options[:exchange] == :binance
      assert request.options[:operation_type] == :market
      assert request.options[:receive_timeout] == 5_000
      assert request.options[:max_retries] == 3
      assert request.options[:retry] == :safe_transient
      assert request.options[:skip_auth] == false
      assert request.options[:skip_rate_limit] == false

      # Verify base URL is production (testnet enforcement via IntegrationCase/auth_credentials)
      assert request.options[:base_url] == "https://api.binance.com"
    end

    test "makes real request to Binance testnet ping endpoint" do
      # Create and execute a real request
      request =
        :binance
        |> HTTP.base_request(:health)
        |> Req.merge(
          url: "/api/v3/ping",
          # Public endpoint
          skip_auth: true
        )

      # Make real API call to testnet
      assert {:ok, response} = Req.request(request)
      assert response.status == 200
      # Ping returns empty object
      assert response.body == %{}
    end

    test "makes real request to get server time from testnet" do
      request =
        :binance
        |> HTTP.base_request(:market)
        |> Req.merge(
          url: "/api/v3/time",
          # Public endpoint
          skip_auth: true
        )

      # Make real API call to testnet
      assert {:ok, response} = Req.request(request)
      assert response.status == 200
      assert is_integer(response.body["serverTime"])

      # Verify server time is reasonable (within last hour and next hour)
      server_time = response.body["serverTime"]
      now = System.system_time(:millisecond)
      # Within 1 hour
      assert abs(server_time - now) < 3_600_000
    end
  end

  describe "health_check_request/1 with real testnet API" do
    test "creates request with auth and rate limiting disabled" do
      request = HTTP.health_check_request(:binance)

      assert request.options[:operation_type] == :health
      assert request.options[:receive_timeout] == 5_000
      assert request.options[:skip_auth] == true
      assert request.options[:skip_rate_limit] == true
    end

    test "successfully pings Binance testnet without auth" do
      request =
        :binance
        |> HTTP.health_check_request()
        |> Req.merge(url: "/api/v3/ping")

      # Should work without credentials
      assert {:ok, response} = Req.request(request)
      assert response.status == 200
    end
  end

  describe "rate limiting with real testnet API" do
    test "monitors real rate limit headers from Binance testnet" do
      alias ZenCex.Adapters.Binance.RateLimiter

      # Reset rate limiter
      RateLimiter.reset(nil)

      # Make a request that should update rate limits
      request =
        :binance
        |> HTTP.base_request(:market)
        |> Req.merge(
          url: "/api/v3/ticker/price",
          params: [symbol: "BTCUSDT"],
          skip_auth: true
        )

      assert {:ok, response} = Req.request(request)
      assert response.status == 200

      # Check that rate limit headers were present and processed
      headers_map = Map.new(response.headers)
      assert headers_map["x-mbx-used-weight-1m"]

      # Verify rate limiter tracked the usage
      status = RateLimiter.get_status("/api/v3/ticker/price")
      assert status.limit > 0
      assert status.used >= 0
    end
  end

  describe "error handling with real testnet API" do
    test "handles 404 from invalid endpoint" do
      request =
        :binance
        |> HTTP.base_request(:market)
        |> Req.merge(
          url: "/api/v3/invalid_endpoint_that_does_not_exist",
          skip_auth: true
        )

      assert {:ok, response} = Req.request(request)
      assert response.status == 404
    end

    test "handles invalid symbol error from real API" do
      request =
        :binance
        |> HTTP.base_request(:market)
        |> Req.merge(
          url: "/api/v3/ticker/price",
          params: [symbol: "INVALIDPAIR"],
          skip_auth: true
        )

      assert {:ok, response} = Req.request(request)
      assert response.status == 400
      assert response.body["code"] == -1121
      assert response.body["msg"] =~ "Invalid symbol"
    end
  end

  describe "authenticated endpoints" do
    test "requires credentials for authenticated endpoints", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      # If we have credentials, test authenticated endpoint
      request =
        :binance
        |> HTTP.base_request(:account)
        |> Req.merge(
          url: "/api/v3/account",
          auth_credentials: %{
            api_key: api_key,
            api_secret: api_secret,
            testnet: testnet
          }
        )

      # This would make a real authenticated call to testnet
      # The actual auth signing happens in the Binance.Auth module
      assert {:ok, response} = Req.request(request)

      # Should either succeed (200) or fail with auth error (401/403)
      # but not with other errors
      assert response.status in [200, 401, 403]
    end
  end

  describe "telemetry events with real API" do
    test "emits telemetry for successful testnet requests" do
      # Attach telemetry handler
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-handler-#{inspect(ref)}",
        [:zen_cex, :request, :complete],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Make real request
      request =
        :binance
        |> HTTP.base_request(:market)
        |> Req.merge(
          url: "/api/v3/ping",
          skip_auth: true
        )

      assert {:ok, _response} = Req.request(request)

      # Should receive telemetry
      assert_receive {:telemetry, [:zen_cex, :request, :complete], measurements, metadata}, 1000

      assert measurements[:duration] > 0
      assert metadata[:exchange] == :binance
      assert metadata[:status] == 200

      :telemetry.detach("test-handler-#{inspect(ref)}")
    end
  end
end
