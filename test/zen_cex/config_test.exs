defmodule ZenCex.ConfigTest do
  use ExUnit.Case, async: false

  import ZenCex.TestUtilities.EnvHelpers

  alias ZenCex.Adapters.Binance.Endpoints
  alias ZenCex.Config

  describe "testnet?/1" do
    test "returns false when environment variable is not set" do
      with_env [
        {"BINANCE_TESTNET", nil},
        {"KRAKEN_TESTNET", nil},
        {"DERIBIT_TESTNET", nil}
      ] do
        refute Config.testnet?(:binance)
        refute Config.testnet?(:kraken)
        refute Config.testnet?(:deribit)
      end
    end

    test "returns true when environment variable is 'true'" do
      with_env [
        {"BINANCE_TESTNET", "true"},
        {"KRAKEN_TESTNET", "true"},
        {"DERIBIT_TESTNET", "true"}
      ] do
        assert Config.testnet?(:binance)
        assert Config.testnet?(:kraken)
        assert Config.testnet?(:deribit)
      end
    end

    test "returns false for other values" do
      with_env [
        {"BINANCE_TESTNET", "false"},
        {"KRAKEN_TESTNET", "1"},
        {"DERIBIT_TESTNET", "yes"}
      ] do
        refute Config.testnet?(:binance)
        refute Config.testnet?(:kraken)
        refute Config.testnet?(:deribit)
      end
    end
  end

  describe "environment/1" do
    test "returns :prod when testnet is not enabled" do
      with_env [{"BINANCE_TESTNET", nil}] do
        assert Config.environment(:binance) == :prod
      end
    end

    test "returns :test when testnet is enabled" do
      with_env [{"BINANCE_TESTNET", "true"}] do
        assert Config.environment(:binance) == :test
      end
    end
  end

  describe "base_url/1" do
    test "returns production URLs when testnet is disabled" do
      with_env [
        {"BINANCE_TESTNET", nil},
        {"DERIBIT_TESTNET", nil}
      ] do
        assert Config.base_url(:binance) == "https://api.binance.com"
        assert Config.base_url(:kraken) == "https://api.kraken.com"
        assert Config.base_url(:deribit) == "https://www.deribit.com"
      end
    end

    test "returns testnet URLs when testnet is enabled" do
      with_env [
        {"BINANCE_TESTNET", "true"},
        {"DERIBIT_TESTNET", "true"}
      ] do
        assert Config.base_url(:binance) == "https://testnet.binance.vision"
        assert Config.base_url(:deribit) == "https://test.deribit.com"

        # Kraken uses same URL for both
        assert Config.base_url(:kraken) == "https://api.kraken.com"
      end
    end
  end

  describe "credentials/1" do
    test "returns production credentials when testnet is disabled" do
      # NOTE: This test must use production vars to test production mode
      # but we're in a test environment, so this is safe
      with_env [
        {"BINANCE_TESTNET", nil},
        {"BINANCE_API_KEY", "prod_key"},
        {"BINANCE_API_SECRET", "prod_secret"},
        {"BINANCE_TESTNET_API_KEY", nil},
        {"BINANCE_TESTNET_API_SECRET", nil}
      ] do
        creds = Config.credentials(:binance)
        assert creds.api_key == "prod_key"
        assert creds.api_secret == "prod_secret"
      end
    end

    test "returns testnet credentials when testnet is enabled" do
      with_env [
        {"BINANCE_TESTNET", "true"},
        {"BINANCE_API_KEY", nil},
        {"BINANCE_API_SECRET", nil},
        {"BINANCE_TESTNET_API_KEY", "test_key"},
        {"BINANCE_TESTNET_API_SECRET", "test_secret"}
      ] do
        creds = Config.credentials(:binance)
        assert creds.api_key == "test_key"
        assert creds.api_secret == "test_secret"
      end
    end

    test "returns nil when credentials are not set" do
      with_env [
        {"BINANCE_TESTNET", nil},
        {"BINANCE_API_KEY", nil},
        {"BINANCE_API_SECRET", nil},
        {"BINANCE_TESTNET_API_KEY", nil},
        {"BINANCE_TESTNET_API_SECRET", nil}
      ] do
        creds = Config.credentials(:binance)
        assert creds.api_key == nil
        assert creds.api_secret == nil
      end
    end
  end

  describe "validate_credentials/1" do
    test "returns error when api_key is missing" do
      # Use testnet vars since we're in test mode
      with_env [
        {"BINANCE_TESTNET", "true"},
        {"BINANCE_TESTNET_API_KEY", nil},
        {"BINANCE_TESTNET_API_SECRET", "secret"}
      ] do
        assert Config.validate_credentials(:binance) == {:error, :missing_api_key}
      end
    end

    test "returns error when api_secret is missing" do
      # Use testnet vars since we're in test mode
      with_env [
        {"BINANCE_TESTNET", "true"},
        {"BINANCE_TESTNET_API_KEY", "key"},
        {"BINANCE_TESTNET_API_SECRET", nil}
      ] do
        assert Config.validate_credentials(:binance) == {:error, :missing_api_secret}
      end
    end

    test "returns :ok when both credentials are present" do
      # Use testnet vars since we're in test mode
      with_env [
        {"BINANCE_TESTNET", "true"},
        {"BINANCE_TESTNET_API_KEY", "key"},
        {"BINANCE_TESTNET_API_SECRET", "secret"}
      ] do
        assert Config.validate_credentials(:binance) == :ok
      end
    end
  end

  describe "clear_cache/0" do
    test "clears cached environment values" do
      # This should not raise even if nothing is cached
      assert Config.clear_cache() == :ok

      # Cache something first
      :persistent_term.put({Endpoints, :current_env}, :test)

      # Clear it
      assert Config.clear_cache() == :ok

      # Verify it's gone
      assert :persistent_term.get({Endpoints, :current_env}, :not_found) == :not_found
    end
  end
end
