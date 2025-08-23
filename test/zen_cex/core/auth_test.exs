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
