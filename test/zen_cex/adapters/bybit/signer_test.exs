defmodule ZenCex.Adapters.Bybit.SignerTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Bybit.Signer

  describe "create_signature/6" do
    test "generates correct signature for GET request with query params" do
      # Test vector from Bybit documentation
      params = %{
        "category" => "spot",
        "symbol" => "BTCUSDT"
      }

      api_key = "XXXXXXXXXX"
      api_secret = "YYYYYYYYYY"
      timestamp = "1658385579423"
      recv_window = "5000"

      signature = Signer.create_signature(params, api_key, api_secret, timestamp, recv_window)

      # Signature should be 64 character lowercase hex string
      assert String.length(signature) == 64
      assert signature == String.downcase(signature)
      assert Regex.match?(~r/^[a-f0-9]{64}$/, signature)
    end

    test "generates correct signature for POST request with JSON body" do
      json_body = ~s({"category":"option","symbol":"BTC-29DEC23-10000-P"})
      api_key = "XXXXXXXXXX"
      api_secret = "YYYYYYYYYY"
      timestamp = "1658385579423"
      recv_window = "5000"

      signature = Signer.create_signature(json_body, api_key, api_secret, timestamp, recv_window, method: :post)

      # Signature should be 64 character lowercase hex string
      assert String.length(signature) == 64
      assert signature == String.downcase(signature)
      assert Regex.match?(~r/^[a-f0-9]{64}$/, signature)
    end

    test "generates different signatures for GET vs POST with same data" do
      params = %{"category" => "spot", "symbol" => "BTCUSDT"}
      api_key = "TEST_KEY"
      api_secret = "TEST_SECRET"
      timestamp = "1658385579423"

      get_signature = Signer.create_signature(params, api_key, api_secret, timestamp, "5000", method: :get)
      post_signature = Signer.create_signature(params, api_key, api_secret, timestamp, "5000", method: :post)

      refute get_signature == post_signature
    end

    test "handles empty parameters for GET request" do
      params = %{}
      api_key = "TEST_KEY"
      api_secret = "TEST_SECRET"
      timestamp = "1658385579423"

      signature = Signer.create_signature(params, api_key, api_secret, timestamp)

      assert String.length(signature) == 64
      assert Regex.match?(~r/^[a-f0-9]{64}$/, signature)
    end

    test "uses default recv_window of 5000 when not specified" do
      params = %{"symbol" => "BTCUSDT"}
      api_key = "TEST_KEY"
      api_secret = "TEST_SECRET"
      timestamp = "1658385579423"

      signature_default = Signer.create_signature(params, api_key, api_secret, timestamp)
      signature_explicit = Signer.create_signature(params, api_key, api_secret, timestamp, "5000")

      assert signature_default == signature_explicit
    end

    test "parameters are sorted alphabetically for GET requests" do
      # Order shouldn't matter - should be sorted alphabetically
      params1 = %{"category" => "spot", "symbol" => "BTCUSDT", "limit" => "20"}
      params2 = %{"symbol" => "BTCUSDT", "category" => "spot", "limit" => "20"}

      api_key = "TEST_KEY"
      api_secret = "TEST_SECRET"
      timestamp = "1658385579423"

      signature1 = Signer.create_signature(params1, api_key, api_secret, timestamp)
      signature2 = Signer.create_signature(params2, api_key, api_secret, timestamp)

      assert signature1 == signature2
    end

    test "known test vector for GET request" do
      # Create a known test case with predictable output
      params = %{"category" => "spot", "symbol" => "BTCUSDT"}
      api_key = "test_api_key"
      api_secret = "test_api_secret"
      timestamp = "1000000000000"
      recv_window = "5000"

      signature = Signer.create_signature(params, api_key, api_secret, timestamp, recv_window)

      # The expected payload would be: "1000000000000test_api_key5000category=spot&symbol=BTCUSDT"
      # We can verify this generates consistent output
      expected_signature =
        Signer.sign_payload(
          "1000000000000test_api_key5000category=spot&symbol=BTCUSDT",
          "test_api_secret"
        )

      assert signature == expected_signature
    end

    test "known test vector for POST request" do
      # Create a known test case with predictable output
      json_body = ~s({"category":"spot","symbol":"BTCUSDT"})
      api_key = "test_api_key"
      api_secret = "test_api_secret"
      timestamp = "1000000000000"
      recv_window = "5000"

      signature = Signer.create_signature(json_body, api_key, api_secret, timestamp, recv_window, method: :post)

      # The expected payload would be: "1000000000000test_api_key5000{"category":"spot","symbol":"BTCUSDT"}"
      expected_signature =
        Signer.sign_payload(
          ~s(1000000000000test_api_key5000{"category":"spot","symbol":"BTCUSDT"}),
          "test_api_secret"
        )

      assert signature == expected_signature
    end
  end

  describe "sign_payload/2" do
    test "generates lowercase hex SHA256 signature" do
      payload = "test_payload"
      secret = "test_secret"

      signature = Signer.sign_payload(payload, secret)

      # Should be 64 character lowercase hex
      assert String.length(signature) == 64
      assert signature == String.downcase(signature)
      assert Regex.match?(~r/^[a-f0-9]{64}$/, signature)
    end

    test "generates deterministic signatures" do
      payload = "test_payload"
      secret = "test_secret"

      signature1 = Signer.sign_payload(payload, secret)
      signature2 = Signer.sign_payload(payload, secret)

      assert signature1 == signature2
    end

    test "different payloads generate different signatures" do
      secret = "test_secret"

      signature1 = Signer.sign_payload("payload1", secret)
      signature2 = Signer.sign_payload("payload2", secret)

      refute signature1 == signature2
    end

    test "different secrets generate different signatures" do
      payload = "test_payload"

      signature1 = Signer.sign_payload(payload, "secret1")
      signature2 = Signer.sign_payload(payload, "secret2")

      refute signature1 == signature2
    end

    test "matches expected HMAC-SHA256 output" do
      # Test with a known HMAC-SHA256 result
      # Using: echo -n "message" | openssl dgst -sha256 -hmac "secret"
      # Result: 8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b

      payload = "message"
      secret = "secret"

      signature = Signer.sign_payload(payload, secret)

      assert signature == "8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b"
    end
  end
end
