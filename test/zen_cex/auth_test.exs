defmodule ZenCex.AuthTest do
  use ExUnit.Case, async: true
  alias ZenCex.Auth

  describe "hmac_sha256/3 - Binance signature generation" do
    test "generates correct HMAC-SHA256 signature for Binance" do
      secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"

      message =
        "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"

      expected = "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71"
      assert Auth.hmac_sha256(secret, message, :hex) == expected
    end

    test "generates correct HMAC-SHA256 in base64 format" do
      secret = "test_secret"
      message = "test_message"

      # Generate signature in base64
      signature = Auth.hmac_sha256(secret, message, :base64)

      # Verify it's valid base64
      assert {:ok, _decoded} = Base.decode64(signature)

      # Verify consistency
      hex_signature = Auth.hmac_sha256(secret, message, :hex)
      {:ok, decoded} = Base.decode64(signature)
      assert Base.encode16(decoded, case: :lower) == hex_signature
    end

    test "generates consistent signatures for same input" do
      secret = "my_secret_key"
      message = "timestamp=1234567890&symbol=BTCUSD"

      sig1 = Auth.hmac_sha256(secret, message, :hex)
      sig2 = Auth.hmac_sha256(secret, message, :hex)

      assert sig1 == sig2
    end

    test "generates different signatures for different messages" do
      secret = "my_secret_key"

      sig1 = Auth.hmac_sha256(secret, "message1", :hex)
      sig2 = Auth.hmac_sha256(secret, "message2", :hex)

      refute sig1 == sig2
    end

    test "handles empty message" do
      secret = "my_secret_key"
      signature = Auth.hmac_sha256(secret, "", :hex)

      assert is_binary(signature)
      # SHA256 produces 32 bytes = 64 hex chars
      assert String.length(signature) == 64
    end
  end

  describe "kraken_nonce/0 - Kraken nonce generation" do
    test "generates monotonically increasing nonces" do
      nonces = for _ <- 1..100, do: Auth.kraken_nonce()

      # All nonces should be unique
      assert length(Enum.uniq(nonces)) == 100

      # Should be strictly increasing
      assert nonces == Enum.sort(nonces)
    end

    test "generates nonces in microsecond format" do
      nonce = Auth.kraken_nonce()

      # Should be a string of digits
      assert Regex.match?(~r/^\d+$/, nonce)

      # Should be around 22-23 digits (16-17 for microseconds + 6 for counter)
      assert String.length(nonce) >= 22
      assert String.length(nonce) <= 23
    end

    test "handles rapid successive calls with counter" do
      # Generate many nonces in quick succession
      nonces = for _ <- 1..1000, do: Auth.kraken_nonce()

      # All should be unique even when called rapidly
      assert length(Enum.uniq(nonces)) == 1000

      # Parse and verify counter increments
      parsed = Enum.map(nonces, &String.to_integer/1)

      # Check differences are at least 1 (counter increment)
      diffs =
        parsed
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)

      assert Enum.all?(diffs, &(&1 >= 1))
    end

    test "nonces from different processes don't collide" do
      # Spawn multiple processes generating nonces
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            for _ <- 1..100, do: Auth.kraken_nonce()
          end)
        end

      all_nonces =
        tasks
        |> Enum.flat_map(&Task.await/1)

      # All nonces should be unique across processes
      assert length(Enum.uniq(all_nonces)) == length(all_nonces)
    end
  end

  describe "deribit_oauth/3 - Deribit OAuth token management" do
    test "generates OAuth token request with proper structure" do
      client_id = "test_client_id"
      client_secret = "test_client_secret"

      {:ok, request} = Auth.deribit_oauth(client_id, client_secret, :request)

      assert request.grant_type == "client_credentials"
      assert request.client_id == client_id
      assert request.client_secret == client_secret
    end

    test "calculates token expiry with 120 second buffer" do
      # Token expires in 3600 seconds
      expires_in = 3600

      expiry_time = Auth.deribit_oauth("", "", {:calculate_expiry, expires_in})
      now = System.system_time(:second)

      # Should expire 120 seconds before actual expiry
      expected_expiry = now + expires_in - 120

      # Allow 1 second tolerance for test execution time
      assert abs(expiry_time - expected_expiry) <= 1
    end

    test "determines when token needs refresh" do
      # Token that expires in 5 minutes
      future_expiry = System.system_time(:second) + 300
      assert Auth.deribit_oauth("", "", {:needs_refresh?, future_expiry}) == false

      # Token that expired 1 minute ago
      past_expiry = System.system_time(:second) - 60
      assert Auth.deribit_oauth("", "", {:needs_refresh?, past_expiry}) == true

      # Token that expires in exactly 120 seconds (buffer threshold)
      boundary_expiry = System.system_time(:second) + 120
      assert Auth.deribit_oauth("", "", {:needs_refresh?, boundary_expiry}) == true
    end

    test "formats OAuth header correctly" do
      token = "test_access_token_12345"

      header = Auth.deribit_oauth("", "", {:format_header, token})

      assert header == {"Authorization", "Bearer test_access_token_12345"}
    end
  end

  describe "add_binance_timestamp/2" do
    test "adds default timestamp and recvWindow" do
      params = %{symbol: "BTCUSDT", side: "BUY"}
      updated = Auth.add_binance_timestamp(params)

      assert Map.has_key?(updated, "timestamp")
      assert Map.has_key?(updated, "recvWindow")
      assert updated["recvWindow"] == "5000"

      # Verify timestamp is recent
      timestamp = String.to_integer(updated["timestamp"])
      now = System.system_time(:millisecond)
      assert abs(now - timestamp) < 100
    end

    test "accepts custom recv_window" do
      params = %{}
      updated = Auth.add_binance_timestamp(params, recv_window: 10000)

      assert updated["recvWindow"] == "10000"
    end

    test "accepts custom timestamp" do
      custom_time = 1_234_567_890_000
      params = %{}
      updated = Auth.add_binance_timestamp(params, timestamp: custom_time)

      assert updated["timestamp"] == "1234567890000"
    end
  end

  describe "validate_timestamp/2 - Timestamp validation" do
    test "accepts timestamp within valid window" do
      now = System.system_time(:millisecond)

      # Timestamp from 1 second ago
      assert Auth.validate_timestamp(now - 1000, 5000) == :ok

      # Current timestamp
      assert Auth.validate_timestamp(now, 5000) == :ok

      # Timestamp 1 second in future (clock skew tolerance)
      assert Auth.validate_timestamp(now + 1000, 5000) == :ok
    end

    test "rejects timestamp outside window" do
      now = System.system_time(:millisecond)
      # 5 seconds
      window = 5000

      # Too old (6 seconds ago)
      assert {:error, :timestamp_expired} = Auth.validate_timestamp(now - 6000, window)

      # Too far in future (6 seconds ahead)  
      assert {:error, :timestamp_too_far} = Auth.validate_timestamp(now + 6000, window)
    end

    test "handles different window sizes" do
      now = System.system_time(:millisecond)

      # 1 second window
      assert Auth.validate_timestamp(now - 500, 1000) == :ok
      assert {:error, :timestamp_expired} = Auth.validate_timestamp(now - 1500, 1000)

      # 60 second window
      assert Auth.validate_timestamp(now - 30000, 60000) == :ok
      assert {:error, :timestamp_expired} = Auth.validate_timestamp(now - 65000, 60000)
    end

    test "provides helpful error messages" do
      now = System.system_time(:millisecond)

      assert {:error, :timestamp_expired} = Auth.validate_timestamp(now - 10000, 5000)
      assert {:error, :timestamp_too_far} = Auth.validate_timestamp(now + 10000, 5000)
    end
  end

  describe "get_api_keys/1 - API key retrieval from environment" do
    test "retrieves API keys for exchanges when available" do
      # Test with whatever keys are actually in the environment
      # Don't modify environment variables

      # Test Binance
      case Auth.get_api_keys(:binance) do
        {:ok, keys} ->
          assert keys.api_key
          assert keys.secret_key

        {:error, reason} when is_binary(reason) ->
          assert String.contains?(reason, "Missing environment variable:")
          assert String.contains?(reason, "BINANCE")
      end

      # Test Kraken
      case Auth.get_api_keys(:kraken) do
        {:ok, keys} ->
          assert keys.api_key
          assert keys.secret_key

        {:error, reason} when is_binary(reason) ->
          assert String.contains?(reason, "Missing environment variable:")
          assert String.contains?(reason, "KRAKEN")
      end

      # Test Deribit
      case Auth.get_api_keys(:deribit) do
        {:ok, keys} ->
          assert keys.client_id
          assert keys.client_secret

        {:error, reason} when is_binary(reason) ->
          assert String.contains?(reason, "Missing environment variable:")
          assert String.contains?(reason, "DERIBIT")
      end
    end

    test "returns error for unknown exchange" do
      assert {:error, :unknown_exchange} = Auth.get_api_keys(:unknown_exchange)
    end

    test "error messages are descriptive" do
      # Test that error messages are descriptive strings
      # We can't guarantee which keys are missing without messing with env
      case Auth.get_api_keys(:binance) do
        {:error, "Missing environment variable: " <> var_name} ->
          # Check that the error message includes the variable name
          assert var_name in ["BINANCE_API_KEY", "BINANCE_API_SECRET"]

        {:ok, _} ->
          # Keys are present, that's fine too
          assert true
      end
    end
  end

  describe "sign_request/3 - Exchange-specific request signing" do
    test "signs requests when keys are available" do
      request = %{
        method: :get,
        url: "https://api.binance.com/api/v3/account",
        params: %{
          "timestamp" => "1499827319559",
          "recvWindow" => "5000"
        },
        headers: []
      }

      # Test Binance signing if keys available
      case Auth.sign_request(:binance, request, []) do
        {:ok, signed} ->
          # Should add signature to params
          assert signed.params["signature"]
          assert signed.params["timestamp"] == "1499827319559"
          # Should add API key header
          assert Enum.any?(signed.headers, fn {k, _} -> k == "X-MBX-APIKEY" end)

        {:error, reason} when is_binary(reason) ->
          # Keys not available, that's ok for unit tests
          assert String.contains?(reason, "Missing environment variable:")
          assert String.contains?(reason, "BINANCE")
      end

      # Test Kraken signing if keys available
      kraken_request = %{
        method: :post,
        url: "https://api.kraken.com/0/private/Balance",
        body: %{},
        headers: []
      }

      case Auth.sign_request(:kraken, kraken_request, []) do
        {:ok, signed} ->
          # Should add nonce to body
          assert signed.body["nonce"]
          # Should add API-Key and API-Sign headers
          assert Enum.any?(signed.headers, fn {k, _} -> k == "API-Key" end)
          assert Enum.any?(signed.headers, fn {k, _} -> k == "API-Sign" end)

        {:error, reason} when is_binary(reason) ->
          # Keys not available, that's ok for unit tests
          assert String.contains?(reason, "Missing environment variable:")
          assert String.contains?(reason, "KRAKEN")
      end
    end

    test "returns appropriate errors for missing keys" do
      request = %{
        method: :get,
        url: "https://api.example.com/test",
        params: %{},
        headers: [],
        body: %{}
      }

      # Test each exchange
      for exchange <- [:binance, :kraken, :deribit] do
        case Auth.sign_request(exchange, request, []) do
          {:ok, _signed} ->
            # Keys are present, signing worked
            assert true

          {:error, reason} when is_binary(reason) ->
            # Missing keys return appropriate errors
            assert String.contains?(reason, "Missing environment variable:")

          {:error, :unknown_exchange} ->
            # Unknown exchange error is also acceptable
            assert true
        end
      end
    end
  end
end
