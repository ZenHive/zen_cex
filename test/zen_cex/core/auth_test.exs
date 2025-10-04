defmodule ZenCex.Core.AuthTest do
  use ExUnit.Case

  import ZenCex.TestUtilities.EnvHelpers

  alias ZenCex.Core.Auth

  describe "get_api_key/2" do
    test "returns api key from request private data first" do
      request =
        Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "private_key", api_secret: "private_secret"})

      assert Auth.get_api_key(request, :binance) == "private_key"
    end

    test "raises ArgumentError when no credentials available" do
      request = Req.new()

      with_env [{"BINANCE_API_KEY", nil}, {"BINANCE_TESTNET_API_KEY", nil}, {"BINANCE_TESTNET", nil}] do
        assert_raise ArgumentError, ~r/Missing auth_credentials for binance/, fn ->
          Auth.get_api_key(request, :binance)
        end
      end
    end
  end

  describe "get_api_secret/2" do
    test "returns api secret from request private data first" do
      request =
        Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "private_key", api_secret: "private_secret"})

      assert Auth.get_api_secret(request, :binance) == "private_secret"
    end

    test "raises ArgumentError when no credentials available" do
      request = Req.new()

      with_env [{"BINANCE_API_SECRET", nil}, {"BINANCE_TESTNET_API_SECRET", nil}, {"BINANCE_TESTNET", nil}] do
        assert_raise ArgumentError, ~r/Missing auth_credentials for binance/, fn ->
          Auth.get_api_secret(request, :binance)
        end
      end
    end
  end

  describe "get_credentials/2" do
    test "returns both credentials when available" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: "secret"})

      assert {key, secret} = Auth.get_credentials(request, :binance)
      assert key == "key"
      assert secret == "secret"
    end

    test "returns {:error, message} when either credential is missing" do
      # Missing secret (clear env vars to avoid fallback)
      with_env [{"BINANCE_API_SECRET", nil}, {"BINANCE_TESTNET_API_SECRET", nil}] do
        request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key"})
        assert {:error, message} = Auth.get_credentials(request, :binance)
        assert message =~ "api_secret"
      end

      # Missing key (clear env vars to avoid fallback)
      with_env [{"BINANCE_API_KEY", nil}, {"BINANCE_TESTNET_API_KEY", nil}] do
        request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_secret: "secret"})
        assert {:error, message} = Auth.get_credentials(request, :binance)
        assert message =~ "api_key"
      end

      # Both missing
      request = Req.new()

      with_env [
        {"BINANCE_API_KEY", nil},
        {"BINANCE_API_SECRET", nil},
        {"BINANCE_TESTNET_API_KEY", nil},
        {"BINANCE_TESTNET_API_SECRET", nil},
        {"BINANCE_TESTNET", nil}
      ] do
        assert {:error, message} = Auth.get_credentials(request, :binance)
        assert message =~ "Missing auth_credentials"
      end
    end
  end

  # testnet?/1 removed - testnet flag is now passed explicitly via auth_credentials
  # Library code never reads ENV variables directly

  describe "valid_credentials?/2" do
    test "returns true when both credentials are present" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: "secret"})

      assert Auth.valid_credentials?(request, :binance) == true
    end

    test "returns false when api key is missing" do
      with_env [{"BINANCE_API_KEY", nil}, {"BINANCE_TESTNET_API_KEY", nil}] do
        request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_secret: "secret"})
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "returns false when api secret is missing" do
      with_env [{"BINANCE_API_SECRET", nil}, {"BINANCE_TESTNET_API_SECRET", nil}] do
        request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key"})
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "returns false when both credentials are missing" do
      request = Req.new()

      with_env [
        {"BINANCE_API_KEY", nil},
        {"BINANCE_API_SECRET", nil},
        {"BINANCE_TESTNET_API_KEY", nil},
        {"BINANCE_TESTNET_API_SECRET", nil}
      ] do
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end
  end

  describe "log_credential_status/3" do
    test "logs credential presence without exposing values" do
      # This just ensures the function doesn't crash
      assert :ok = Auth.log_credential_status(:binance, "key", "secret")
      assert :ok = Auth.log_credential_status(:binance, nil, "secret")
      assert :ok = Auth.log_credential_status(:binance, "key", nil)
      assert :ok = Auth.log_credential_status(:binance, nil, nil)
    end
  end

  describe "edge cases with invalid credentials" do
    test "raises ArgumentError for empty auth_credentials map" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{})

      with_env [{"BINANCE_API_KEY", nil}, {"BINANCE_API_SECRET", nil}] do
        assert_raise ArgumentError, ~r/Missing auth_credentials\.api_key/, fn ->
          Auth.get_api_key(request, :binance)
        end

        assert_raise ArgumentError, ~r/Missing auth_credentials\.api_secret/, fn ->
          Auth.get_api_secret(request, :binance)
        end

        assert {:error, _} = Auth.get_credentials(request, :binance)
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "raises ArgumentError for partial credentials with only api_key" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key123"})

      with_env [{"BINANCE_API_SECRET", nil}] do
        assert Auth.get_api_key(request, :binance) == "key123"

        assert_raise ArgumentError, ~r/Missing auth_credentials\.api_secret/, fn ->
          Auth.get_api_secret(request, :binance)
        end

        assert {:error, _} = Auth.get_credentials(request, :binance)
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "raises ArgumentError for partial credentials with only api_secret" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_secret: "secret456"})

      with_env [{"BINANCE_API_KEY", nil}] do
        assert_raise ArgumentError, ~r/Missing auth_credentials\.api_key/, fn ->
          Auth.get_api_key(request, :binance)
        end

        assert Auth.get_api_secret(request, :binance) == "secret456"
        assert {:error, _} = Auth.get_credentials(request, :binance)
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "raises ArgumentError for non-string api_key values" do
      # Integer api_key
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: 12_345, api_secret: "secret"})

      assert_raise ArgumentError, ~r/api_key must be a string/, fn ->
        Auth.get_api_key(request, :binance)
      end

      # Atom api_key
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: :invalid, api_secret: "secret"})

      assert_raise ArgumentError, ~r/api_key must be a string/, fn ->
        Auth.get_api_key(request, :binance)
      end
    end

    test "raises ArgumentError for non-string api_secret values" do
      # Integer api_secret
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: 67_890})

      assert_raise ArgumentError, ~r/api_secret must be a string/, fn ->
        Auth.get_api_secret(request, :binance)
      end

      # Atom api_secret
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: :invalid})

      assert_raise ArgumentError, ~r/api_secret must be a string/, fn ->
        Auth.get_api_secret(request, :binance)
      end
    end

    test "raises ArgumentError for empty string credentials" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "", api_secret: ""})

      assert_raise ArgumentError, ~r/api_key cannot be empty/, fn ->
        Auth.get_api_key(request, :binance)
      end

      assert_raise ArgumentError, ~r/api_secret cannot be empty/, fn ->
        Auth.get_api_secret(request, :binance)
      end

      assert {:error, _} = Auth.get_credentials(request, :binance)
      assert Auth.valid_credentials?(request, :binance) == false
    end

    test "raises ArgumentError for nil values in credentials map" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: nil, api_secret: nil})

      assert_raise ArgumentError, ~r/api_key must be a string/, fn ->
        Auth.get_api_key(request, :binance)
      end

      assert_raise ArgumentError, ~r/api_secret must be a string/, fn ->
        Auth.get_api_secret(request, :binance)
      end

      assert {:error, _} = Auth.get_credentials(request, :binance)
      assert Auth.valid_credentials?(request, :binance) == false
    end
  end

  describe "validate_credentials/1" do
    test "validates correct credentials" do
      assert :ok = Auth.validate_credentials(%{api_key: "key123", api_secret: "secret456"})
    end

    test "rejects missing api_key" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_secret: "secret456"})
    end

    test "rejects missing api_secret" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: "key123"})
    end

    test "rejects empty api_key" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: "", api_secret: "secret456"})
    end

    test "rejects empty api_secret" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: "key123", api_secret: ""})
    end

    test "rejects non-binary api_key" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: 123, api_secret: "secret456"})
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: :atom, api_secret: "secret456"})
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: nil, api_secret: "secret456"})
    end

    test "rejects non-binary api_secret" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: "key123", api_secret: 456})
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: "key123", api_secret: :atom})
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{api_key: "key123", api_secret: nil})
    end

    test "rejects empty map" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(%{})
    end

    test "rejects non-map input" do
      assert {:error, :invalid_credentials} = Auth.validate_credentials(nil)
      assert {:error, :invalid_credentials} = Auth.validate_credentials("invalid")
      assert {:error, :invalid_credentials} = Auth.validate_credentials(api_key: "key", api_secret: "secret")
    end
  end
end
