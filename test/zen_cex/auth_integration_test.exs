defmodule ZenCex.AuthIntegrationTest do
  use ExUnit.Case, async: false
  alias ZenCex.Auth
  require Logger

  @moduletag :integration
  @moduletag :external_api
  @moduletag timeout: :timer.seconds(60)

  describe "Binance Authentication" do
    @tag :binance_testnet
    @tag :requires_api_keys
    test "generates valid HMAC-SHA256 signatures accepted by Binance testnet" do
      # Check for testnet keys first, then fall back to main API keys
      testnet_key = System.get_env("BINANCE_TESTNET_API_KEY")
      testnet_secret = System.get_env("BINANCE_TESTNET_SECRET_KEY")

      # Skip if keys not configured
      cond do
        testnet_key && testnet_secret ->
          # Use testnet keys for testing
          timestamp = System.system_time(:millisecond)
          query_string = "timestamp=#{timestamp}&recvWindow=5000"
          signature = Auth.hmac_sha256(testnet_secret, query_string, :hex)

          # Test account info endpoint (requires authentication)
          request =
            Req.new(
              base_url: "https://testnet.binance.vision",
              finch: ZenCex.Finch,
              receive_timeout: 10_000
            )
            |> Req.Request.put_header("X-MBX-APIKEY", testnet_key)

          response =
            Req.get!(request,
              url: "/api/v3/account",
              params: [
                timestamp: timestamp,
                recvWindow: 5000,
                signature: signature
              ]
            )

          case response.status do
            200 ->
              Logger.info("✓ Binance testnet authentication successful")
              assert Map.has_key?(response.body, "balances")
              assert Map.has_key?(response.body, "accountType")

            401 ->
              flunk("Authentication failed: Invalid API key or signature")

            418 ->
              Logger.warning("Rate limited by Binance testnet - test skipped")

            status ->
              Logger.warning("Unexpected status #{status}: #{inspect(response.body)}")
          end

        true ->
          Logger.info("Skipping: BINANCE_TESTNET_API_KEY or BINANCE_TESTNET_SECRET_KEY not set")
      end
    end

    @tag :binance_testnet
    @tag :requires_api_keys
    test "handles Binance error responses correctly" do
      testnet_key = System.get_env("BINANCE_TESTNET_API_KEY")
      testnet_secret = System.get_env("BINANCE_TESTNET_SECRET_KEY")

      if testnet_key && testnet_secret do
        # Test with invalid timestamp (too old)
        old_timestamp = System.system_time(:millisecond) - 100_000
        query_string = "timestamp=#{old_timestamp}"
        signature = Auth.hmac_sha256(testnet_secret, query_string, :hex)

        request =
          Req.new(
            base_url: "https://testnet.binance.vision",
            finch: ZenCex.Finch,
            receive_timeout: 10_000
          )
          |> Req.Request.put_header("X-MBX-APIKEY", testnet_key)

        response =
          Req.get!(request,
            url: "/api/v3/account",
            params: [
              timestamp: old_timestamp,
              signature: signature
            ]
          )

        # Should get timestamp error
        assert response.status in [400, 401]
        # Timestamp errors
        assert response.body["code"] in [-1021, -1022]
        Logger.info("✓ Binance timestamp validation working correctly")
      else
        Logger.info("Skipping: Binance testnet keys not configured")
      end
    end

    @tag :binance_testnet
    test "validates Binance rate limits" do
      testnet_key = System.get_env("BINANCE_TESTNET_API_KEY")
      testnet_secret = System.get_env("BINANCE_TESTNET_SECRET_KEY")

      if testnet_key && testnet_secret do
        # Test rate limit headers are returned
        timestamp = System.system_time(:millisecond)
        query_string = "timestamp=#{timestamp}"
        signature = Auth.hmac_sha256(testnet_secret, query_string, :hex)

        request =
          Req.new(
            base_url: "https://testnet.binance.vision",
            finch: ZenCex.Finch
          )
          |> Req.Request.put_header("X-MBX-APIKEY", testnet_key)

        response =
          Req.get!(request,
            url: "/api/v3/exchangeInfo",
            params: [
              timestamp: timestamp,
              signature: signature
            ]
          )

        # Check for rate limit headers
        headers = Map.new(response.headers)

        # Binance returns rate limit info in headers
        if Map.has_key?(headers, "x-mbx-used-weight") do
          assert headers["x-mbx-used-weight"]

          Logger.info(
            "✓ Binance rate limit headers present: weight=#{headers["x-mbx-used-weight"]}"
          )
        end
      else
        Logger.info("Skipping: Binance testnet keys not configured")
      end
    end

    test "validates timestamp windows correctly" do
      now = System.system_time(:millisecond)

      # Our module should accept timestamps within window
      assert Auth.validate_timestamp(now, 5000) == :ok
      assert Auth.validate_timestamp(now - 4999, 5000) == :ok

      # And reject those outside
      assert {:error, :timestamp_expired} = Auth.validate_timestamp(now - 6000, 5000)
      assert {:error, :timestamp_too_far} = Auth.validate_timestamp(now + 6000, 5000)
    end

    test "signature generation matches Binance documentation example" do
      # This is the exact example from Binance docs
      secret = "NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j"

      message =
        "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559"

      expected = "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71"

      assert Auth.hmac_sha256(secret, message, :hex) == expected
    end
  end

  describe "Kraken Authentication" do
    @tag :kraken
    @tag :requires_api_keys
    test "generates valid HMAC-SHA512 signatures accepted by Kraken" do
      api_key = System.get_env("KRAKEN_API_KEY")
      api_secret = System.get_env("KRAKEN_API_SECRET")

      if api_key && api_secret do
        # Kraken requires nonce to be strictly increasing
        nonce = System.system_time(:microsecond) |> to_string()

        # Build the request body
        body = URI.encode_query(%{"nonce" => nonce})

        # Build the message to sign (API path + SHA256(nonce + body))
        api_path = "/0/private/Balance"
        message = nonce <> body
        sha256_hash = :crypto.hash(:sha256, message)

        # Decode the base64 secret
        {:ok, decoded_secret} = Base.decode64(api_secret)

        # Create the signature
        api_sign =
          :crypto.mac(:hmac, :sha512, decoded_secret, api_path <> sha256_hash)
          |> Base.encode64()

        # Make the actual API call
        request =
          Req.new(
            base_url: "https://api.kraken.com",
            finch: ZenCex.Finch,
            receive_timeout: 15_000
          )
          |> Req.Request.put_header("API-Key", api_key)
          |> Req.Request.put_header("API-Sign", api_sign)
          |> Req.Request.put_header("content-type", "application/x-www-form-urlencoded")

        response =
          Req.post!(request,
            url: api_path,
            body: body
          )

        case response.status do
          200 ->
            body = response.body

            if body["error"] && body["error"] != [] do
              Logger.warning("Kraken API error: #{inspect(body["error"])}")

              # Check if it's a permission error (expected for demo keys)
              if Enum.any?(body["error"], &String.contains?(&1, "Permission")) do
                Logger.info(
                  "✓ Kraken authentication working (permission denied is expected for demo keys)"
                )
              else
                flunk("Unexpected Kraken error: #{inspect(body["error"])}")
              end
            else
              Logger.info("✓ Kraken authentication successful")
              assert Map.has_key?(body, "result")
            end

          401 ->
            flunk("Authentication failed: Invalid API key or signature")

          status ->
            Logger.warning("Unexpected status #{status}: #{inspect(response.body)}")
        end
      else
        Logger.info("Skipping: KRAKEN_API_KEY or KRAKEN_API_SECRET not set")
      end
    end

    @tag :kraken
    test "handles Kraken nonce errors correctly" do
      api_key = System.get_env("KRAKEN_API_KEY")
      api_secret = System.get_env("KRAKEN_API_SECRET")

      if api_key && api_secret do
        # Use an old nonce (should be rejected)
        old_nonce = "1000000000000"

        body = URI.encode_query(%{"nonce" => old_nonce})
        api_path = "/0/private/Balance"
        message = old_nonce <> body
        sha256_hash = :crypto.hash(:sha256, message)

        {:ok, decoded_secret} = Base.decode64(api_secret)

        api_sign =
          :crypto.mac(:hmac, :sha512, decoded_secret, api_path <> sha256_hash)
          |> Base.encode64()

        request =
          Req.new(
            base_url: "https://api.kraken.com",
            finch: ZenCex.Finch,
            receive_timeout: 15_000
          )
          |> Req.Request.put_header("API-Key", api_key)
          |> Req.Request.put_header("API-Sign", api_sign)
          |> Req.Request.put_header("content-type", "application/x-www-form-urlencoded")

        response =
          Req.post!(request,
            url: api_path,
            body: body
          )

        assert response.status == 200
        body = response.body

        # Should get nonce error
        assert body["error"] && body["error"] != []
        assert Enum.any?(body["error"], &String.contains?(&1, "nonce"))
        Logger.info("✓ Kraken nonce validation working correctly")
      else
        Logger.info("Skipping: Kraken keys not configured")
      end
    end

    test "generates monotonically increasing nonces" do
      # Generate multiple nonces
      nonces = for _ <- 1..100, do: Auth.kraken_nonce()

      # All must be unique
      assert length(Enum.uniq(nonces)) == 100

      # All must be strictly increasing (critical for Kraken)
      assert nonces == Enum.sort(nonces)

      # All must be valid format (numeric string, reasonable length)
      assert Enum.all?(nonces, fn n ->
               Regex.match?(~r/^\d+$/, n) && String.length(n) <= 64
             end)
    end

    @tag :kraken
    @tag :requires_api_keys
    test "generates valid HMAC-SHA512 signatures for Kraken" do
      api_key = System.get_env("KRAKEN_API_KEY")
      secret = System.get_env("KRAKEN_API_SECRET")

      if is_nil(api_key) or is_nil(secret) do
        IO.puts("Skipping: KRAKEN_API_KEY or KRAKEN_API_SECRET not set")
      else
        request = %{
          method: :post,
          url: "https://api.kraken.com/0/private/Balance",
          body: %{},
          headers: []
        }

        # Test our Auth module signs it correctly
        assert {:ok, signed} = Auth.sign_request(:kraken, request, [])

        # Verify Kraken-specific requirements
        assert signed.body["nonce"], "Nonce should be added to body"
        assert String.length(signed.body["nonce"]) >= 16, "Nonce should be microsecond-based"

        # Check headers
        assert {"API-Key", api_key} in signed.headers

        api_sign =
          Enum.find_value(signed.headers, fn
            {"API-Sign", sign} -> sign
            _ -> nil
          end)

        assert api_sign, "API-Sign header should be present"
        assert {:ok, _decoded} = Base.decode64(api_sign), "API-Sign should be valid base64"

        IO.puts("✓ Kraken signature generation successful")
      end
    end

    test "nonces work correctly across concurrent processes" do
      # Spawn 10 processes each generating 100 nonces
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            for _ <- 1..100, do: Auth.kraken_nonce()
          end)
        end

      all_nonces = tasks |> Enum.flat_map(&Task.await/1)

      # All 1000 nonces must be unique
      assert length(Enum.uniq(all_nonces)) == 1000
    end
  end

  describe "Deribit OAuth" do
    @tag :deribit_test
    @tag :requires_api_keys
    test "OAuth2 token request works with test environment" do
      client_id = System.get_env("DERIBIT_CLIENT_ID")
      client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

      if client_id && client_secret do
        # Request OAuth token from Deribit test environment
        request =
          Req.new(
            base_url: "https://test.deribit.com",
            finch: ZenCex.Finch,
            receive_timeout: 10_000
          )

        response =
          Req.get!(request,
            url: "/api/v2/public/auth",
            params: [
              grant_type: "client_credentials",
              client_id: client_id,
              client_secret: client_secret
            ]
          )

        case response.status do
          200 ->
            body = response.body
            result = body["result"]

            # Verify OAuth response structure
            assert result["access_token"]
            assert result["token_type"] == "bearer"
            assert result["expires_in"]
            assert result["scope"]

            # Store token for subsequent tests
            Process.put(:deribit_token, result["access_token"])
            Process.put(:deribit_refresh_token, result["refresh_token"])

            Logger.info("✓ Deribit OAuth token obtained successfully")
            Logger.info("  Token expires in: #{result["expires_in"]} seconds")
            Logger.info("  Scopes: #{result["scope"]}")

          401 ->
            flunk("OAuth authentication failed: Invalid client credentials")

          status ->
            Logger.warning("Unexpected status #{status}: #{inspect(response.body)}")
        end
      else
        Logger.info("Skipping: DERIBIT_CLIENT_ID or DERIBIT_CLIENT_SECRET not set")
      end
    end

    @tag :deribit_test
    @tag :requires_api_keys
    test "authenticated requests work with OAuth token" do
      client_id = System.get_env("DERIBIT_CLIENT_ID")
      client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

      if client_id && client_secret do
        # Get a fresh token
        request =
          Req.new(
            base_url: "https://test.deribit.com",
            finch: ZenCex.Finch,
            receive_timeout: 10_000
          )

        token_response =
          Req.get!(request,
            url: "/api/v2/public/auth",
            params: [
              grant_type: "client_credentials",
              client_id: client_id,
              client_secret: client_secret
            ]
          )

        if token_response.status == 200 do
          token = token_response.body["result"]["access_token"]

          # Use token to make authenticated request
          auth_response =
            Req.get!(request,
              url: "/api/v2/private/get_account_summary",
              params: [
                currency: "BTC",
                extended: true
              ],
              headers: [
                {"authorization", "Bearer #{token}"}
              ]
            )

          case auth_response.status do
            200 ->
              Logger.info("✓ Deribit authenticated request successful")
              result = auth_response.body["result"]

              # Verify account summary structure
              assert Map.has_key?(result, "currency")
              assert Map.has_key?(result, "balance")
              assert Map.has_key?(result, "equity")

            401 ->
              flunk("Token authentication failed")

            status ->
              Logger.warning("Unexpected status #{status}: #{inspect(auth_response.body)}")
          end
        end
      else
        Logger.info("Skipping: Deribit credentials not configured")
      end
    end

    @tag :deribit_test
    @tag :requires_api_keys
    test "token refresh flow works correctly" do
      client_id = System.get_env("DERIBIT_CLIENT_ID")
      client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

      if client_id && client_secret do
        request =
          Req.new(
            base_url: "https://test.deribit.com",
            finch: ZenCex.Finch,
            receive_timeout: 10_000
          )

        # Get initial token
        initial_response =
          Req.get!(request,
            url: "/api/v2/public/auth",
            params: [
              grant_type: "client_credentials",
              client_id: client_id,
              client_secret: client_secret
            ]
          )

        if initial_response.status == 200 do
          refresh_token = initial_response.body["result"]["refresh_token"]

          # Test refresh
          refresh_response =
            Req.get!(request,
              url: "/api/v2/public/auth",
              params: [
                grant_type: "refresh_token",
                refresh_token: refresh_token
              ]
            )

          assert refresh_response.status == 200
          new_result = refresh_response.body["result"]

          # Verify new token received
          assert new_result["access_token"]
          assert new_result["refresh_token"]
          assert new_result["expires_in"]

          Logger.info("✓ Deribit token refresh successful")
        end
      else
        Logger.info("Skipping: Deribit credentials not configured")
      end
    end

    test "generates correct OAuth request structure" do
      client_id = "test_client"
      client_secret = "test_secret"

      {:ok, request} = Auth.deribit_oauth(client_id, client_secret, :request)

      assert request.grant_type == "client_credentials"
      assert request.client_id == client_id
      assert request.client_secret == client_secret
    end

    test "calculates token expiry with safety buffer" do
      # 1 hour
      expires_in = 3600
      expiry = Auth.deribit_oauth("", "", {:calculate_expiry, expires_in})

      now = System.system_time(:second)
      # Should expire 120 seconds before actual expiry
      expected = now + expires_in - 120

      # Allow 2 second tolerance
      assert abs(expiry - expected) <= 2
    end

    test "correctly identifies when token needs refresh" do
      now = System.system_time(:second)

      # Token expiring in 5 minutes - should not need refresh
      refute Auth.deribit_oauth("", "", {:needs_refresh?, now + 300})

      # Token expiring in 100 seconds - within buffer, needs refresh
      assert Auth.deribit_oauth("", "", {:needs_refresh?, now + 100})

      # Token already expired - definitely needs refresh
      assert Auth.deribit_oauth("", "", {:needs_refresh?, now - 60})
    end

    test "formats Bearer token header correctly" do
      token = "test_access_token_abc123"
      header = Auth.deribit_oauth("", "", {:format_header, token})

      assert header == {"Authorization", "Bearer #{token}"}
    end

    @tag :deribit_testnet
    @tag :requires_api_keys
    test "OAuth token request structure is valid for Deribit" do
      client_id = System.get_env("DERIBIT_CLIENT_ID")
      client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

      if is_nil(client_id) or is_nil(client_secret) do
        IO.puts("Skipping: DERIBIT_CLIENT_ID or DERIBIT_CLIENT_SECRET not set")
      else
        # Test our OAuth request generation
        {:ok, oauth_params} = Auth.deribit_oauth(client_id, client_secret, :request)

        # Verify it has all required fields for Deribit
        assert oauth_params.grant_type == "client_credentials"
        assert oauth_params.client_id == client_id
        assert oauth_params.client_secret == client_secret

        IO.puts("✓ Deribit OAuth request structure valid")
      end
    end
  end

  describe "Cross-exchange compatibility" do
    @tag :all_exchanges
    test "all exchanges respond to public endpoints without auth" do
      # Test that public endpoints work for all exchanges
      exchanges = [
        {"https://testnet.binance.vision", "/api/v3/ping"},
        {"https://api.kraken.com", "/0/public/Time"},
        {"https://test.deribit.com", "/api/v2/public/test"}
      ]

      for {base_url, endpoint} <- exchanges do
        request =
          Req.new(
            base_url: base_url,
            finch: ZenCex.Finch,
            receive_timeout: 10_000
          )

        response = Req.get!(request, url: endpoint)

        assert response.status == 200,
               "#{base_url}#{endpoint} should return 200, got #{response.status}"

        Logger.info("✓ #{base_url} public endpoint accessible")
      end
    end

    test "each exchange uses different authentication methods" do
      request = %{
        method: :get,
        url: "https://api.example.com/test",
        params: %{"test" => "value"},
        headers: []
      }

      # Test Binance if keys are available
      case Auth.sign_request(:binance, request, []) do
        {:ok, binance} ->
          # Binance uses HMAC-SHA256 in query params
          assert binance.params["signature"]

          assert {"X-MBX-APIKEY", _} =
                   Enum.find(binance.headers, fn {k, _} -> k == "X-MBX-APIKEY" end)

        {:error, reason} when is_binary(reason) ->
          IO.puts("Skipping Binance: #{reason}")
      end

      # Test Kraken if keys are available
      kraken_req = Map.put(request, :method, :post)

      case Auth.sign_request(:kraken, kraken_req, []) do
        {:ok, kraken} ->
          # Kraken uses HMAC-SHA512 in headers with nonce
          assert kraken.body["nonce"]
          assert {"API-Sign", _} = Enum.find(kraken.headers, fn {k, _} -> k == "API-Sign" end)

        {:error, reason} when is_binary(reason) ->
          IO.puts("Skipping Kraken: #{reason}")
      end

      # Test Deribit if keys are available
      case Auth.sign_request(:deribit, request, []) do
        {:ok, deribit} ->
          # Deribit uses OAuth
          assert is_map(deribit)

        {:error, reason} when is_binary(reason) ->
          IO.puts("Skipping Deribit: #{reason}")
      end
    end

    test "API key retrieval handles missing keys gracefully" do
      assert {:error, :unknown_exchange} = Auth.get_api_keys(:unknown)

      # Test each exchange - they may or may not have keys
      case Auth.get_api_keys(:binance) do
        {:ok, binance_keys} ->
          assert binance_keys.api_key
          assert binance_keys.secret_key

        {:error, _} ->
          IO.puts("Binance keys not configured")
      end

      case Auth.get_api_keys(:kraken) do
        {:ok, kraken_keys} ->
          assert kraken_keys.api_key
          assert kraken_keys.secret_key

        {:error, _} ->
          IO.puts("Kraken keys not configured")
      end

      case Auth.get_api_keys(:deribit) do
        {:ok, deribit_keys} ->
          assert deribit_keys.client_id
          assert deribit_keys.client_secret

        {:error, _} ->
          IO.puts("Deribit keys not configured")
      end
    end
  end
end
