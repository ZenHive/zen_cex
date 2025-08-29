defmodule ZenCex.Core.AuthTest do
  use ExUnit.Case

  import ZenCex.IntegrationCase, only: [with_env: 2]

  alias ZenCex.Core.Auth

  # Import the with_env macro from IntegrationCase
  describe "get_api_key/2" do
    test "returns api key from request private data first" do
      request =
        Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "private_key", api_secret: "private_secret"})

      assert Auth.get_api_key(request, :binance) == "private_key"
    end

    test "returns nil when no credentials available" do
      request = Req.new()

      with_env [{"BINANCE_API_KEY", nil}, {"BINANCE_TESTNET_API_KEY", nil}, {"BINANCE_TESTNET", nil}] do
        assert Auth.get_api_key(request, :binance) == nil
      end
    end
  end

  describe "get_api_secret/2" do
    test "returns api secret from request private data first" do
      request =
        Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "private_key", api_secret: "private_secret"})

      assert Auth.get_api_secret(request, :binance) == "private_secret"
    end

    test "returns nil when no credentials available" do
      request = Req.new()

      with_env [{"BINANCE_API_SECRET", nil}, {"BINANCE_TESTNET_API_SECRET", nil}, {"BINANCE_TESTNET", nil}] do
        assert Auth.get_api_secret(request, :binance) == nil
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

    test "returns {nil, nil} when either credential is missing" do
      # Missing secret (clear env vars to avoid fallback)
      with_env [{"BINANCE_API_SECRET", nil}, {"BINANCE_TESTNET_API_SECRET", nil}] do
        request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key"})
        assert {nil, nil} = Auth.get_credentials(request, :binance)
      end

      # Missing key (clear env vars to avoid fallback)
      with_env [{"BINANCE_API_KEY", nil}, {"BINANCE_TESTNET_API_KEY", nil}] do
        request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_secret: "secret"})
        assert {nil, nil} = Auth.get_credentials(request, :binance)
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
        assert {nil, nil} = Auth.get_credentials(request, :binance)
      end
    end
  end

  describe "testnet?/1" do
    test "returns true when EXCHANGE_TESTNET is set to truthy value" do
      with_env [{"BINANCE_TESTNET", "true"}] do
        assert Auth.testnet?(:binance) == true
      end

      with_env [{"BINANCE_TESTNET", "1"}] do
        assert Auth.testnet?(:binance) == true
      end

      with_env [{"BINANCE_TESTNET", "yes"}] do
        assert Auth.testnet?(:binance) == true
      end
    end

    test "returns false when EXCHANGE_TESTNET is false or empty" do
      with_env [{"BINANCE_TESTNET", "false"}] do
        assert Auth.testnet?(:binance) == false
      end

      with_env [{"BINANCE_TESTNET", ""}] do
        assert Auth.testnet?(:binance) == false
      end

      with_env [{"BINANCE_TESTNET", nil}] do
        assert Auth.testnet?(:binance) == false
      end
    end

    test "works with different exchange names" do
      with_env [{"KRAKEN_TESTNET", "true"}] do
        assert Auth.testnet?(:kraken) == true
      end

      with_env [{"BYBIT_TESTNET", "true"}] do
        assert Auth.testnet?(:bybit) == true
      end

      with_env [{"KRAKEN_TESTNET", nil}, {"BYBIT_TESTNET", nil}] do
        assert Auth.testnet?(:kraken) == false
        assert Auth.testnet?(:bybit) == false
      end
    end
  end

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

    test "works with environment variable fallback" do
      request = Req.new()

      with_env [
        {"BINANCE_API_KEY", "env_key"},
        {"BINANCE_API_SECRET", "env_secret"}
      ] do
        assert Auth.valid_credentials?(request, :binance) == true
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
    test "handles empty auth_credentials map" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{})

      with_env [{"BINANCE_API_KEY", nil}, {"BINANCE_API_SECRET", nil}] do
        assert Auth.get_api_key(request, :binance) == nil
        assert Auth.get_api_secret(request, :binance) == nil
        assert {nil, nil} = Auth.get_credentials(request, :binance)
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "handles partial credentials with only api_key" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key123"})

      with_env [{"BINANCE_API_SECRET", nil}] do
        assert Auth.get_api_key(request, :binance) == "key123"
        assert Auth.get_api_secret(request, :binance) == nil
        assert {nil, nil} = Auth.get_credentials(request, :binance)
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "handles partial credentials with only api_secret" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_secret: "secret456"})

      with_env [{"BINANCE_API_KEY", nil}] do
        assert Auth.get_api_key(request, :binance) == nil
        assert Auth.get_api_secret(request, :binance) == "secret456"
        assert {nil, nil} = Auth.get_credentials(request, :binance)
        assert Auth.valid_credentials?(request, :binance) == false
      end
    end

    test "handles non-string api_key values" do
      # Integer api_key
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: 12_345, api_secret: "secret"})
      assert Auth.get_api_key(request, :binance) == nil

      # Atom api_key
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: :invalid, api_secret: "secret"})
      assert Auth.get_api_key(request, :binance) == nil

      # List api_key
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: ["invalid"], api_secret: "secret"})
      assert Auth.get_api_key(request, :binance) == nil

      # Map api_key
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: %{invalid: true}, api_secret: "secret"})
      assert Auth.get_api_key(request, :binance) == nil
    end

    test "handles non-string api_secret values" do
      # Integer api_secret
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: 67_890})
      assert Auth.get_api_secret(request, :binance) == nil

      # Atom api_secret
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: :invalid})
      assert Auth.get_api_secret(request, :binance) == nil

      # List api_secret
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: ["invalid"]})
      assert Auth.get_api_secret(request, :binance) == nil

      # Map api_secret
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "key", api_secret: %{invalid: true}})
      assert Auth.get_api_secret(request, :binance) == nil
    end

    test "handles empty string credentials" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: "", api_secret: ""})

      assert Auth.get_api_key(request, :binance) == nil
      assert Auth.get_api_secret(request, :binance) == nil
      assert {nil, nil} = Auth.get_credentials(request, :binance)
      assert Auth.valid_credentials?(request, :binance) == false
    end

    test "handles nil values in credentials map" do
      request = Req.Request.put_private(Req.new(), :auth_credentials, %{api_key: nil, api_secret: nil})

      assert Auth.get_api_key(request, :binance) == nil
      assert Auth.get_api_secret(request, :binance) == nil
      assert {nil, nil} = Auth.get_credentials(request, :binance)
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

  describe "environment variable fallback" do
    test "uses testnet credentials when EXCHANGE_TESTNET is set" do
      request = Req.new()

      with_env [
        {"BINANCE_TESTNET", "true"},
        {"BINANCE_TESTNET_API_KEY", "testnet_key"},
        {"BINANCE_TESTNET_API_SECRET", "testnet_secret"},
        {"BINANCE_API_KEY", "prod_key"},
        {"BINANCE_API_SECRET", "prod_secret"}
      ] do
        assert Auth.get_api_key(request, :binance) == "testnet_key"
        assert Auth.get_api_secret(request, :binance) == "testnet_secret"
      end
    end

    test "falls back to production credentials in testnet mode if testnet creds missing" do
      request = Req.new()

      with_env [
        {"BINANCE_TESTNET", "true"},
        {"BINANCE_TESTNET_API_KEY", nil},
        {"BINANCE_TESTNET_API_SECRET", nil},
        {"BINANCE_API_KEY", "prod_key"},
        {"BINANCE_API_SECRET", "prod_secret"}
      ] do
        assert Auth.get_api_key(request, :binance) == "prod_key"
        assert Auth.get_api_secret(request, :binance) == "prod_secret"
      end
    end

    test "uses production credentials when EXCHANGE_TESTNET is not set" do
      request = Req.new()

      with_env [{"BINANCE_TESTNET", nil}, {"BINANCE_API_KEY", "prod_key"}, {"BINANCE_API_SECRET", "prod_secret"}] do
        assert Auth.get_api_key(request, :binance) == "prod_key"
        assert Auth.get_api_secret(request, :binance) == "prod_secret"
      end
    end
  end
end
