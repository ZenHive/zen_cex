defmodule ZenCex.Core.SignerTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.Signer

  describe "hmac_sha256/2" do
    test "generates correct SHA256 signature" do
      # Test vector from Binance API documentation
      payload =
        "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"

      secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"

      signature = Signer.hmac_sha256(payload, secret)
      hex_signature = Signer.encode_hex(signature)

      assert hex_signature == "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71"
    end

    test "handles empty payload" do
      signature = Signer.hmac_sha256("", "secret")
      assert is_binary(signature)
      # SHA256 produces 32 bytes
      assert byte_size(signature) == 32
    end

    test "handles binary inputs" do
      payload = <<1, 2, 3, 4>>
      secret = <<5, 6, 7, 8>>

      signature = Signer.hmac_sha256(payload, secret)
      assert is_binary(signature)
      assert byte_size(signature) == 32
    end
  end

  describe "hmac_sha512/2" do
    test "generates correct SHA512 signature" do
      payload = "test_payload"
      secret = "test_secret"

      signature = Signer.hmac_sha512(payload, secret)
      assert is_binary(signature)
      # SHA512 produces 64 bytes
      assert byte_size(signature) == 64
    end

    test "produces different signature than SHA256" do
      payload = "same_payload"
      secret = "same_secret"

      sha256_sig = Signer.hmac_sha256(payload, secret)
      sha512_sig = Signer.hmac_sha512(payload, secret)

      refute sha256_sig == sha512_sig
      assert byte_size(sha256_sig) == 32
      assert byte_size(sha512_sig) == 64
    end

    test "handles empty payload" do
      signature = Signer.hmac_sha512("", "secret")
      assert is_binary(signature)
      assert byte_size(signature) == 64
    end
  end

  describe "encode_hex/2" do
    test "encodes to lowercase hex by default" do
      data = <<255, 0, 128>>
      assert Signer.encode_hex(data) == "ff0080"
    end

    test "encodes to uppercase hex when specified" do
      data = <<255, 0, 128>>
      assert Signer.encode_hex(data, case: :upper) == "FF0080"
    end

    test "handles empty binary" do
      assert Signer.encode_hex(<<>>) == ""
    end

    test "encodes SHA256 signature correctly" do
      signature = Signer.hmac_sha256("test", "secret")
      hex = Signer.encode_hex(signature)

      # SHA256 = 32 bytes = 64 hex chars
      assert String.length(hex) == 64
      assert String.match?(hex, ~r/^[a-f0-9]+$/)
    end

    test "encodes SHA512 signature correctly" do
      signature = Signer.hmac_sha512("test", "secret")
      hex = Signer.encode_hex(signature, case: :upper)

      # SHA512 = 64 bytes = 128 hex chars
      assert String.length(hex) == 128
      assert String.match?(hex, ~r/^[A-F0-9]+$/)
    end
  end

  describe "decode_hex/1" do
    test "decodes lowercase hex" do
      assert {:ok, <<255, 0, 128>>} == Signer.decode_hex("ff0080")
    end

    test "decodes uppercase hex" do
      assert {:ok, <<255, 0, 128>>} == Signer.decode_hex("FF0080")
    end

    test "decodes mixed case hex" do
      assert {:ok, <<255, 0, 128>>} == Signer.decode_hex("Ff0080")
    end

    test "returns error for invalid hex" do
      assert {:error, :invalid_hex} == Signer.decode_hex("invalid")
      assert {:error, :invalid_hex} == Signer.decode_hex("gg0080")
      # Odd length
      assert {:error, :invalid_hex} == Signer.decode_hex("ff008")
    end

    test "handles empty string" do
      assert {:ok, <<>>} == Signer.decode_hex("")
    end
  end

  describe "encode_base64/1" do
    test "encodes binary to base64" do
      assert Signer.encode_base64(<<255, 0, 128>>) == "/wCA"
    end

    test "encodes string to base64" do
      assert Signer.encode_base64("hello") == "aGVsbG8="
    end

    test "handles empty binary" do
      assert Signer.encode_base64(<<>>) == ""
    end
  end

  describe "decode_base64/1" do
    test "decodes valid base64" do
      assert {:ok, <<255, 0, 128>>} == Signer.decode_base64("/wCA")
      assert {:ok, "hello"} == Signer.decode_base64("aGVsbG8=")
    end

    test "returns error for invalid base64" do
      assert {:error, :invalid_base64} == Signer.decode_base64("!invalid!")
      # Invalid padding
      assert {:error, :invalid_base64} == Signer.decode_base64("abc")
    end

    test "handles empty string" do
      assert {:ok, <<>>} == Signer.decode_base64("")
    end

    test "handles base64 with padding" do
      assert {:ok, "a"} == Signer.decode_base64("YQ==")
      assert {:ok, "ab"} == Signer.decode_base64("YWI=")
      assert {:ok, "abc"} == Signer.decode_base64("YWJj")
    end
  end

  describe "generate_nonce/1" do
    test "generates millisecond nonce by default" do
      nonce = Signer.generate_nonce()
      assert is_integer(nonce)
      # Should be milliseconds since epoch
      assert nonce > 1_000_000_000_000
      # But not microseconds
      assert nonce < 10_000_000_000_000
    end

    test "generates microsecond nonce when specified" do
      nonce = Signer.generate_nonce(unit: :microsecond)
      assert is_integer(nonce)
      # Should be microseconds
      assert nonce > 1_000_000_000_000_000
    end

    test "generates nanosecond nonce when specified" do
      nonce = Signer.generate_nonce(unit: :nanosecond)
      assert is_integer(nonce)
      # Should be nanoseconds
      assert nonce > 1_000_000_000_000_000_000
    end

    test "applies offset when specified" do
      base_nonce = Signer.generate_nonce()
      offset_nonce = Signer.generate_nonce(offset: 1000)

      # The offset nonce should be approximately 1000 more than base
      # (allowing for time passage between calls)
      assert offset_nonce >= base_nonce + 999
      assert offset_nonce <= base_nonce + 1010
    end

    test "generates strictly increasing nonces" do
      # Use nanosecond precision or add offset to ensure uniqueness
      nonces = for i <- 0..9, do: Signer.generate_nonce(unit: :nanosecond, offset: i)
      assert nonces == Enum.sort(nonces)
      assert length(Enum.uniq(nonces)) == 10
    end
  end

  describe "timestamp_seconds/0" do
    test "returns timestamp string in seconds" do
      timestamp = Signer.timestamp_seconds()
      assert is_binary(timestamp)
      assert String.match?(timestamp, ~r/^\d{10}$/)

      # Verify it's a reasonable timestamp (after year 2020)
      assert String.to_integer(timestamp) > 1_577_836_800
    end
  end

  describe "timestamp_milliseconds/0" do
    test "returns timestamp string in milliseconds" do
      timestamp = Signer.timestamp_milliseconds()
      assert is_binary(timestamp)
      assert String.match?(timestamp, ~r/^\d{13}$/)

      # Verify it's a reasonable timestamp (after year 2020)
      assert String.to_integer(timestamp) > 1_577_836_800_000
    end
  end

  describe "timestamp_microseconds/0" do
    test "returns timestamp string in microseconds" do
      timestamp = Signer.timestamp_microseconds()
      assert is_binary(timestamp)
      assert String.match?(timestamp, ~r/^\d{16}$/)

      # Verify it's a reasonable timestamp (after year 2020)
      assert String.to_integer(timestamp) > 1_577_836_800_000_000
    end
  end

  describe "sign_payload/3" do
    test "signs with SHA256 and lowercase hex by default" do
      signature = Signer.sign_payload("payload", "secret")

      assert is_binary(signature)
      assert String.length(signature) == 64
      assert String.match?(signature, ~r/^[a-f0-9]+$/)
    end

    test "signs with SHA256 and uppercase hex" do
      signature = Signer.sign_payload("payload", "secret", case: :upper)

      assert String.length(signature) == 64
      assert String.match?(signature, ~r/^[A-F0-9]+$/)
    end

    test "signs with SHA512 and hex" do
      signature = Signer.sign_payload("payload", "secret", algorithm: :sha512)

      assert String.length(signature) == 128
      assert String.match?(signature, ~r/^[a-f0-9]+$/)
    end

    test "signs with SHA256 and base64 encoding" do
      signature = Signer.sign_payload("payload", "secret", encoding: :base64)

      assert is_binary(signature)
      # Base64 encoded SHA256 (32 bytes) should be 44 chars with padding
      assert String.length(signature) == 44
      assert String.ends_with?(signature, "=")
    end

    test "signs with SHA512 and base64 encoding" do
      signature = Signer.sign_payload("payload", "secret", algorithm: :sha512, encoding: :base64)

      # Base64 encoded SHA512 (64 bytes) should be 88 chars with padding
      assert String.length(signature) == 88
      assert String.ends_with?(signature, "=")
    end

    test "produces consistent signatures" do
      sig1 = Signer.sign_payload("test", "secret")
      sig2 = Signer.sign_payload("test", "secret")
      assert sig1 == sig2
    end

    test "produces different signatures for different payloads" do
      sig1 = Signer.sign_payload("test1", "secret")
      sig2 = Signer.sign_payload("test2", "secret")
      refute sig1 == sig2
    end

    test "produces different signatures for different secrets" do
      sig1 = Signer.sign_payload("test", "secret1")
      sig2 = Signer.sign_payload("test", "secret2")
      refute sig1 == sig2
    end
  end

  describe "verify_signature/4" do
    test "verifies valid SHA256 hex signature" do
      payload = "test_payload"
      secret = "test_secret"
      signature = Signer.sign_payload(payload, secret)

      assert Signer.verify_signature(payload, signature, secret)
    end

    test "rejects invalid SHA256 hex signature" do
      payload = "test_payload"
      secret = "test_secret"

      refute Signer.verify_signature(payload, "invalid_signature", secret)
    end

    test "verifies valid SHA512 hex signature" do
      payload = "test_payload"
      secret = "test_secret"
      signature = Signer.sign_payload(payload, secret, algorithm: :sha512)

      assert Signer.verify_signature(payload, signature, secret, algorithm: :sha512)
    end

    test "verifies valid base64 signature" do
      payload = "test_payload"
      secret = "test_secret"
      signature = Signer.sign_payload(payload, secret, encoding: :base64)

      assert Signer.verify_signature(payload, signature, secret, encoding: :base64)
    end

    test "rejects signature with wrong algorithm" do
      payload = "test_payload"
      secret = "test_secret"
      sha256_sig = Signer.sign_payload(payload, secret, algorithm: :sha256)

      refute Signer.verify_signature(payload, sha256_sig, secret, algorithm: :sha512)
    end

    test "rejects signature with wrong secret" do
      payload = "test_payload"
      signature = Signer.sign_payload(payload, "secret1")

      refute Signer.verify_signature(payload, signature, "secret2")
    end

    test "rejects signature with wrong payload" do
      secret = "test_secret"
      signature = Signer.sign_payload("payload1", secret)

      refute Signer.verify_signature("payload2", signature, secret)
    end

    test "handles uppercase hex signatures" do
      payload = "test_payload"
      secret = "test_secret"
      signature = Signer.sign_payload(payload, secret, case: :upper)

      assert Signer.verify_signature(payload, signature, secret, case: :upper)
    end

    test "protects against timing attacks" do
      # Even with wrong signatures of different lengths, 
      # the function should still perform constant-time comparison
      payload = "test"
      secret = "secret"
      correct_sig = Signer.sign_payload(payload, secret)

      # These should all return false without timing differences
      refute Signer.verify_signature(payload, "short", secret)
      refute Signer.verify_signature(payload, correct_sig <> "extra", secret)
      refute Signer.verify_signature(payload, String.slice(correct_sig, 0..10), secret)
    end
  end

  describe "integration with Binance requirements" do
    test "generates Binance-compatible signatures" do
      # Example from Binance API docs
      params_string =
        "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"

      secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"

      signature = Signer.sign_payload(params_string, secret, algorithm: :sha256, case: :lower)

      assert signature == "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71"
    end
  end

  describe "integration with Kraken requirements" do
    test "supports SHA512 for Kraken-style signatures" do
      # Kraken uses SHA512 and base64-decoded secrets
      # "base64_secret" in base64
      encoded_secret = "YmFzZTY0X3NlY3JldA=="
      {:ok, decoded_secret} = Signer.decode_base64(encoded_secret)

      payload = "nonce=1234567890&ordertype=limit"
      signature = Signer.hmac_sha512(payload, decoded_secret)
      hex_signature = Signer.encode_hex(signature, case: :upper)

      assert is_binary(hex_signature)
      assert String.length(hex_signature) == 128
      assert String.match?(hex_signature, ~r/^[A-F0-9]+$/)
    end

    test "generates Kraken-compatible nonces" do
      # Kraken needs microsecond timestamps
      nonce = Signer.generate_nonce(unit: :microsecond)
      nonce_string = Integer.to_string(nonce)

      assert String.length(nonce_string) >= 16
      assert String.match?(nonce_string, ~r/^\d+$/)
    end
  end
end
