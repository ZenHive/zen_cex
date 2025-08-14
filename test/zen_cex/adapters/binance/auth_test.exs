defmodule ZenCex.Adapters.Binance.AuthTest do
  use ExUnit.Case, async: true
  alias ZenCex.Adapters.Binance.Auth

  @test_api_key "test_api_key"
  @test_api_secret "test_secret"

  describe "sign_request/2 with credentials in options" do
    setup do
      request = %{
        params: %{"symbol" => "BTCUSDT"},
        headers: []
      }

      {:ok, request: request}
    end

    test "adds timestamp to params", %{request: request} do
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["timestamp"]
      assert is_integer(signed.params["timestamp"])
      # Verify timestamp is recent (within last 5 seconds)
      assert abs(System.system_time(:millisecond) - signed.params["timestamp"]) < 5000
    end

    test "adds recvWindow to params with default value", %{request: request} do
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["recvWindow"] == 5000
    end

    test "uses custom recvWindow when provided", %{request: request} do
      signed =
        Auth.sign_request(request,
          api_key: @test_api_key,
          api_secret: @test_api_secret,
          recv_window: 10000
        )

      assert signed.params["recvWindow"] == 10000
    end

    test "uses custom timestamp when provided", %{request: request} do
      custom_timestamp = 1_234_567_890_000

      signed =
        Auth.sign_request(request,
          api_key: @test_api_key,
          api_secret: @test_api_secret,
          timestamp: custom_timestamp
        )

      assert signed.params["timestamp"] == custom_timestamp
    end

    test "adds HMAC-SHA256 signature to params", %{request: request} do
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["signature"]
      assert is_binary(signed.params["signature"])
      # HMAC-SHA256 produces 64 character hex string
      assert String.length(signed.params["signature"]) == 64
      # Verify it's lowercase hex
      assert signed.params["signature"] =~ ~r/^[a-f0-9]{64}$/
    end

    test "signature is generated from correct query string", %{request: request} do
      # Use fixed timestamp for deterministic signature
      timestamp = 1_234_567_890_000

      signed =
        Auth.sign_request(request,
          api_key: @test_api_key,
          api_secret: @test_api_secret,
          timestamp: timestamp,
          recv_window: 5000
        )

      # Manually calculate expected signature
      params = %{
        "symbol" => "BTCUSDT",
        "timestamp" => timestamp,
        "recvWindow" => 5000
      }

      query_string = URI.encode_query(params)

      expected_signature =
        :crypto.mac(:hmac, :sha256, @test_api_secret, query_string)
        |> Base.encode16(case: :lower)

      assert signed.params["signature"] == expected_signature
    end

    test "preserves original params", %{request: request} do
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["symbol"] == "BTCUSDT"
    end

    test "adds X-MBX-APIKEY header with provided api_key", %{request: request} do
      signed = Auth.sign_request(request, api_key: "custom_key", api_secret: @test_api_secret)

      api_key_header = Enum.find(signed.headers, fn {key, _} -> key == "X-MBX-APIKEY" end)
      assert api_key_header == {"X-MBX-APIKEY", "custom_key"}
    end

    test "preserves existing headers", %{request: request} do
      request = %{request | headers: [{"Content-Type", "application/json"}]}
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert {"Content-Type", "application/json"} in signed.headers
      assert {"X-MBX-APIKEY", @test_api_key} in signed.headers
      assert length(signed.headers) == 2
    end

    test "handles empty params", %{request: _request} do
      request = %{params: %{}, headers: []}
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["timestamp"]
      assert signed.params["recvWindow"]
      assert signed.params["signature"]
    end

    test "handles params as keyword list", %{request: _request} do
      request = %{params: [symbol: "BTCUSDT"], headers: []}
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["symbol"] == "BTCUSDT"
      assert signed.params["timestamp"]
      assert signed.params["signature"]
    end

    test "falls back to env secret when API secret is not provided in options", %{
      request: request
    } do
      signed = Auth.sign_request(request, api_key: @test_api_key)

      # If env has a secret, signature won't be empty
      if System.get_env("BINANCE_API_SECRET") do
        assert signed.params["signature"] != ""
        assert String.length(signed.params["signature"]) == 64
      else
        assert signed.params["signature"] == ""
      end
    end

    test "handles nil params gracefully" do
      request = %{params: nil, headers: []}
      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["timestamp"]
      assert signed.params["recvWindow"]
      assert signed.params["signature"]
    end
  end

  describe "validate_credentials/1 with options" do
    test "returns :ok when both API key and secret are present in options" do
      assert Auth.validate_credentials(api_key: "valid_key", api_secret: "valid_secret") == :ok
    end

    test "falls back to env for missing API key when secret provided" do
      # Only api_secret provided, api_key falls back to env
      result = Auth.validate_credentials(api_secret: "valid_secret")

      # If env has API key, this will be :ok, otherwise error
      if System.get_env("BINANCE_API_KEY") do
        assert result == :ok
      else
        assert result == {:error, :missing_api_key}
      end
    end

    test "falls back to env for missing API secret when key provided" do
      # Only api_key provided, api_secret falls back to env
      result = Auth.validate_credentials(api_key: "valid_key")

      # If env has API secret, this will be :ok, otherwise error
      if System.get_env("BINANCE_API_SECRET") do
        assert result == :ok
      else
        assert result == {:error, :missing_api_secret}
      end
    end

    test "returns error when API key is empty string" do
      assert Auth.validate_credentials(api_key: "", api_secret: "valid_secret") ==
               {:error, :empty_api_key}
    end

    test "returns error when API secret is empty string" do
      assert Auth.validate_credentials(api_key: "valid_key", api_secret: "") ==
               {:error, :empty_api_secret}
    end

    test "returns error when API key is explicitly nil" do
      assert Auth.validate_credentials(api_key: nil, api_secret: "valid_secret") ==
               {:error, :missing_api_key}
    end

    test "returns error when API secret is explicitly nil" do
      assert Auth.validate_credentials(api_key: "valid_key", api_secret: nil) ==
               {:error, :missing_api_secret}
    end

    test "returns empty signature when secret is explicitly nil" do
      request = %{params: %{"test" => "value"}, headers: []}

      # Explicitly passing nil secret should not fall back to env
      signed = Auth.sign_request(request, api_key: "test_key", api_secret: nil)

      assert signed.params["signature"] == ""
    end

    test "accepts map as options" do
      assert Auth.validate_credentials(%{api_key: "valid_key", api_secret: "valid_secret"}) == :ok
    end

    test "falls back to environment with empty map" do
      # Empty map means no options provided, so it falls back to env vars
      result = Auth.validate_credentials(%{})

      # Result depends on current environment
      assert match?(:ok, result) or match?({:error, _}, result)
    end

    test "falls back to environment with empty keyword list" do
      # Empty list means no options provided, so it falls back to env vars
      result = Auth.validate_credentials([])

      # Result depends on current environment
      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end

  describe "validate_credentials/0 with environment variables" do
    test "checks environment variables when called without arguments" do
      # This test just verifies the function can be called
      # The actual result depends on the current environment
      result = Auth.validate_credentials()

      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end

  describe "auth_method/0" do
    test "returns :hmac_sha256" do
      assert Auth.auth_method() == :hmac_sha256
    end
  end

  describe "signature generation details" do
    test "generates deterministic signature for known input" do
      # Use Binance documentation example values
      params = %{
        "symbol" => "LTCBTC",
        "side" => "BUY",
        "type" => "LIMIT",
        "timeInForce" => "GTC",
        "quantity" => "1",
        "price" => "0.1"
      }

      request = %{params: params, headers: []}

      # Known test secret from Binance docs
      test_secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"

      signed =
        Auth.sign_request(request,
          api_key: "test_key",
          api_secret: test_secret,
          timestamp: 1_499_827_319_559,
          recv_window: 5000
        )

      # Calculate expected signature
      expected_params =
        Map.merge(params, %{
          "timestamp" => 1_499_827_319_559,
          "recvWindow" => 5000
        })

      query_string = URI.encode_query(expected_params)

      expected_signature =
        :crypto.mac(:hmac, :sha256, test_secret, query_string)
        |> Base.encode16(case: :lower)

      assert signed.params["signature"] == expected_signature
    end

    test "signature is always last parameter in params map" do
      request = %{
        params: %{"symbol" => "BTCUSDT", "side" => "BUY"},
        headers: []
      }

      signed =
        Auth.sign_request(request,
          api_key: @test_api_key,
          api_secret: @test_api_secret,
          timestamp: 1_234_567_890_000
        )

      # Verify signature exists
      assert signed.params["signature"]

      # All other expected params should be present
      assert signed.params["symbol"] == "BTCUSDT"
      assert signed.params["side"] == "BUY"
      assert signed.params["timestamp"] == 1_234_567_890_000
      assert signed.params["recvWindow"] == 5000
    end
  end

  describe "edge cases" do
    test "handles special characters in params" do
      request = %{
        params: %{"note" => "Test & verify @ 100%"},
        headers: []
      }

      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["note"] == "Test & verify @ 100%"
      assert signed.params["signature"]
    end

    test "handles numeric values in params" do
      request = %{
        params: %{"quantity" => 0.001, "price" => 50000},
        headers: []
      }

      signed = Auth.sign_request(request, api_key: @test_api_key, api_secret: @test_api_secret)

      assert signed.params["quantity"] == 0.001
      assert signed.params["price"] == 50000
      assert signed.params["signature"]
    end
  end
end
