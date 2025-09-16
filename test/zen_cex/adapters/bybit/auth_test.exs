defmodule ZenCex.Adapters.Bybit.AuthTest do
  use ExUnit.Case

  import ZenCex.TestUtilities.EnvHelpers

  alias ZenCex.Adapters.Bybit.Auth

  describe "apply_auth/1" do
    test "returns request unchanged when no credentials available" do
      # Clear any existing credentials
      with_env [
        {"BYBIT_API_KEY", nil},
        {"BYBIT_API_SECRET", nil},
        {"BYBIT_TESTNET_API_KEY", nil},
        {"BYBIT_TESTNET_API_SECRET", nil}
      ] do
        request = Req.new(url: "/v5/account/wallet-balance")
        result = Auth.apply_auth(request)
        assert result == request
      end
    end

    test "adds authentication headers when credentials are provided" do
      request =
        [url: "/v5/account/wallet-balance"]
        |> Req.new()
        |> Req.Request.put_private(:auth_credentials, %{
          api_key: "test_key",
          api_secret: "test_secret"
        })

      result = Auth.apply_auth(request)

      # Check that all required headers are present
      assert ["test_key"] == Req.Request.get_header(result, "x-bapi-api-key")
      assert [_timestamp] = Req.Request.get_header(result, "x-bapi-timestamp")
      assert [_recv_window] = Req.Request.get_header(result, "x-bapi-recv-window")
      assert [_signature] = Req.Request.get_header(result, "x-bapi-sign")
    end
  end

  describe "sign_request/3" do
    test "adds all required Bybit authentication headers" do
      request =
        [url: "/v5/account/wallet-balance", params: %{"accountType" => "UNIFIED"}]
        |> Req.new()
        |> Req.Request.put_private(:auth_credentials, %{
          api_key: "test_key",
          api_secret: "test_secret"
        })

      signed = Auth.apply_auth(request)

      # Verify all headers are present
      assert ["test_key"] == Req.Request.get_header(signed, "x-bapi-api-key")
      assert [timestamp] = Req.Request.get_header(signed, "x-bapi-timestamp")
      assert [recv_window] = Req.Request.get_header(signed, "x-bapi-recv-window")
      assert [signature] = Req.Request.get_header(signed, "x-bapi-sign")

      # Verify headers are not empty
      assert timestamp != ""
      assert recv_window != ""
      assert signature != ""
      # HMAC-SHA256 produces 64 hex chars
      assert String.length(signature) == 64
    end

    test "preserves existing query parameters" do
      request =
        [url: "/v5/order/realtime", params: %{"category" => "spot", "symbol" => "BTCUSDT"}]
        |> Req.new()
        |> Req.Request.put_private(:auth_credentials, %{
          api_key: "test_key",
          api_secret: "test_secret"
        })

      signed = Auth.apply_auth(request)

      # Verify parameters are preserved in options
      assert signed.options[:params]["category"] == "spot"
      assert signed.options[:params]["symbol"] == "BTCUSDT"
    end

    test "handles POST requests with JSON body" do
      request =
        [
          url: "/v5/order/create",
          method: :post,
          json: %{
            "category" => "spot",
            "symbol" => "BTCUSDT",
            "side" => "Buy",
            "orderType" => "Limit",
            "qty" => "0.001",
            "price" => "30000"
          }
        ]
        |> Req.new()
        |> Req.Request.put_private(:auth_credentials, %{
          api_key: "test_key",
          api_secret: "test_secret"
        })

      signed = Auth.apply_auth(request)

      # Verify authentication headers are added
      assert ["test_key"] == Req.Request.get_header(signed, "x-bapi-api-key")
      assert [_signature] = Req.Request.get_header(signed, "x-bapi-sign")

      # Verify JSON body is preserved
      assert signed.options[:json]["category"] == "spot"
      assert signed.options[:json]["symbol"] == "BTCUSDT"
    end
  end

  describe "base_url/0" do
    test "returns production URL when not in testnet mode" do
      # Use with_env to safely test without testnet var
      with_env [{"BYBIT_TESTNET", nil}] do
        assert Auth.base_url() == "https://api.bybit.com"
      end
    end

    test "returns testnet URL when BYBIT_TESTNET is set" do
      with_env [{"BYBIT_TESTNET", "true"}] do
        assert Auth.base_url() == "https://api-testnet.bybit.com"
      end
    end
  end

  describe "generate_signature/5" do
    test "generates consistent signatures for known inputs" do
      params = %{"category" => "spot", "symbol" => "BTCUSDT"}
      timestamp = "1234567890"
      recv_window = "5000"

      signature = Auth.generate_signature(params, "test_key", "test_secret", timestamp, recv_window)

      # Should produce a 64-character hex string
      assert String.length(signature) == 64
      assert signature =~ ~r/^[a-f0-9]{64}$/

      # Should be deterministic
      signature2 = Auth.generate_signature(params, "test_key", "test_secret", timestamp, recv_window)
      assert signature == signature2
    end

    test "uses default recv_window when not specified" do
      params = %{"category" => "spot"}
      timestamp = "1234567890"

      signature1 = Auth.generate_signature(params, "key", "secret", timestamp)
      signature2 = Auth.generate_signature(params, "key", "secret", timestamp, "5000")

      # Should produce the same signature since default is 5000
      assert signature1 == signature2
    end
  end
end
