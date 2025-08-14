defmodule ZenCex.Adapters.Binance.AuthIntegrationTest do
  use ExUnit.Case, async: false
  alias ZenCex.Adapters.Binance.Auth

  @moduletag :integration
  @moduletag timeout: 10_000

  describe "real API authentication" do
    setup do
      # Check if credentials are available in environment
      api_key = System.get_env("BINANCE_API_KEY")
      api_secret = System.get_env("BINANCE_API_SECRET")

      if api_key && api_secret do
        {:ok, api_key: api_key, api_secret: api_secret, valid_credentials: true}
      else
        {:ok, valid_credentials: false}
      end
    end

    @tag :skip_unless_credentials
    test "signs request correctly for real API", %{valid_credentials: valid} = context do
      if valid do
        # Create a request for account info (requires auth)
        request = %{
          params: %{},
          headers: []
        }

        # Sign the request with credentials from context
        signed =
          Auth.sign_request(request,
            api_key: context[:api_key],
            api_secret: context[:api_secret]
          )

        # Verify signature components
        assert signed.params["timestamp"]
        assert signed.params["recvWindow"] == 5000
        assert signed.params["signature"]
        assert String.length(signed.params["signature"]) == 64

        # Verify header
        assert {"X-MBX-APIKEY", key} =
                 Enum.find(signed.headers, fn {k, _v} -> k == "X-MBX-APIKEY" end)

        assert key == context[:api_key]
      else
        IO.puts("Skipping integration test - no Binance credentials configured")
      end
    end

    @tag :skip_unless_credentials
    test "timestamp is within server tolerance", %{valid_credentials: valid} = context do
      if valid do
        # Get current timestamp
        request = %{params: %{}, headers: []}

        signed =
          Auth.sign_request(request,
            api_key: context[:api_key],
            api_secret: context[:api_secret]
          )

        # Timestamp should be very recent
        now = System.system_time(:millisecond)
        timestamp_diff = abs(now - signed.params["timestamp"])

        # Should be within 1 second (well under recvWindow)
        assert timestamp_diff < 1000,
               "Timestamp difference too large: #{timestamp_diff}ms"
      else
        :ok
      end
    end

    @tag :skip_unless_credentials
    test "handles complex params correctly", %{valid_credentials: valid} = context do
      if valid do
        # Complex order params
        request = %{
          params: %{
            "symbol" => "BTCUSDT",
            "side" => "BUY",
            "type" => "LIMIT",
            "timeInForce" => "GTC",
            "quantity" => "0.001",
            "price" => "30000"
          },
          headers: []
        }

        signed =
          Auth.sign_request(request,
            api_key: context[:api_key],
            api_secret: context[:api_secret]
          )

        # All original params should be preserved
        assert signed.params["symbol"] == "BTCUSDT"
        assert signed.params["side"] == "BUY"
        assert signed.params["type"] == "LIMIT"
        assert signed.params["timeInForce"] == "GTC"
        assert signed.params["quantity"] == "0.001"
        assert signed.params["price"] == "30000"

        # Auth params should be added
        assert signed.params["timestamp"]
        assert signed.params["recvWindow"]
        assert signed.params["signature"]
      else
        :ok
      end
    end
  end

  describe "validate_credentials/1 with real credentials" do
    test "validates actual environment credentials through options" do
      api_key = System.get_env("BINANCE_API_KEY")
      api_secret = System.get_env("BINANCE_API_SECRET")

      if api_key && api_secret do
        # Test with real credentials passed as options
        assert Auth.validate_credentials(api_key: api_key, api_secret: api_secret) == :ok
      else
        # Test with missing credentials
        assert {:error, :missing_api_key} = Auth.validate_credentials([])
      end
    end

    test "validate_credentials/0 checks environment directly" do
      result = Auth.validate_credentials()

      # Check based on what's actually configured
      if System.get_env("BINANCE_API_KEY") && System.get_env("BINANCE_API_SECRET") do
        assert result == :ok
      else
        assert {:error, _reason} = result
      end
    end
  end

  describe "signature verification with known values" do
    test "generates correct signature using Binance documentation example" do
      # This is from Binance documentation example
      # Using their test secret for verification
      test_secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"

      params = %{
        "symbol" => "LTCBTC",
        "side" => "BUY",
        "type" => "LIMIT",
        "timeInForce" => "GTC",
        "quantity" => "1",
        "price" => "0.1"
      }

      request = %{params: params, headers: []}

      # Use fixed timestamp from Binance example
      signed =
        Auth.sign_request(request,
          api_key: "test_key",
          api_secret: test_secret,
          timestamp: 1_499_827_319_559,
          recv_window: 5000
        )

      # Build query string like Binance does
      expected_params = %{
        "symbol" => "LTCBTC",
        "side" => "BUY",
        "type" => "LIMIT",
        "timeInForce" => "GTC",
        "quantity" => "1",
        "price" => "0.1",
        "timestamp" => 1_499_827_319_559,
        "recvWindow" => 5000
      }

      query_string = URI.encode_query(expected_params)

      expected_signature =
        :crypto.mac(
          :hmac,
          :sha256,
          test_secret,
          query_string
        )
        |> Base.encode16(case: :lower)

      assert signed.params["signature"] == expected_signature
    end
  end

  describe "fallback to environment variables" do
    test "sign_request falls back to env vars when options not provided" do
      # Only run this test if env vars are configured
      if System.get_env("BINANCE_API_KEY") && System.get_env("BINANCE_API_SECRET") do
        request = %{params: %{"test" => "value"}, headers: []}

        # Call without credentials options
        signed = Auth.sign_request(request)

        # Should have API key from env
        assert {"X-MBX-APIKEY", key} =
                 Enum.find(signed.headers, fn {k, _} -> k == "X-MBX-APIKEY" end)

        assert key == System.get_env("BINANCE_API_KEY")

        # Should have signature (not empty)
        assert signed.params["signature"] != ""
      else
        :ok
      end
    end

    test "options take precedence over environment variables" do
      request = %{params: %{"test" => "value"}, headers: []}

      # Use specific test credentials via options
      test_key = "option_test_key"
      test_secret = "option_test_secret"

      signed =
        Auth.sign_request(request,
          api_key: test_key,
          api_secret: test_secret,
          timestamp: 1_234_567_890_000
        )

      # Should use the option key, not env var (if any)
      assert {"X-MBX-APIKEY", ^test_key} =
               Enum.find(signed.headers, fn {k, _} -> k == "X-MBX-APIKEY" end)

      # Verify signature was generated with option secret
      params = %{
        "test" => "value",
        "timestamp" => 1_234_567_890_000,
        "recvWindow" => 5000
      }

      query_string = URI.encode_query(params)

      expected_signature =
        :crypto.mac(:hmac, :sha256, test_secret, query_string)
        |> Base.encode16(case: :lower)

      assert signed.params["signature"] == expected_signature
    end
  end
end
