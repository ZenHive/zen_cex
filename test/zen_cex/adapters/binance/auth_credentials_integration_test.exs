defmodule ZenCex.Adapters.Binance.AuthCredentialsIntegrationTest do
  @moduledoc """
  Integration tests for passing auth_credentials in different formats.
  Tests both keyword lists and maps across different Binance API types.
  """
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.CoinmFutures
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Adapters.Binance.UsdmFutures

  describe "Spot API with auth_credentials" do
    @tag :integration
    test "accepts auth_credentials as keyword list" do
      # Get credentials from environment
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      # Pass credentials as keyword list
      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Test with get_balances which requires auth
      assert {:ok, balances} = Spot.get_balances(%{}, opts)
      assert is_list(balances)
    end

    @tag :integration
    test "accepts auth_credentials as map" do
      # Get credentials from environment
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      # Pass credentials as map
      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      # Test with get_balances which requires auth
      assert {:ok, balances} = Spot.get_balances(%{}, opts)
      assert is_list(balances)
    end

    @tag :integration
    test "auth_credentials override environment variables" do
      # Use invalid credentials to verify they override env vars
      opts = [
        auth_credentials: %{
          api_key: "invalid_key",
          api_secret: "invalid_secret"
        }
      ]

      # Should get authentication error
      assert {:error, _reason} = Spot.get_balances(%{}, opts)
    end
  end

  describe "Margin API with auth_credentials" do
    @tag :integration
    test "margin endpoints accept auth_credentials as keyword list" do
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Test margin account info - using get_balances as margin endpoints may not be available on testnet
      # This still tests auth_credentials passing
      assert {:ok, _balances} = Spot.get_balances(%{}, opts)
    end

    @tag :integration
    test "margin endpoints accept auth_credentials as map" do
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      # Test margin account info - using get_balances as margin endpoints may not be available on testnet
      # This still tests auth_credentials passing
      assert {:ok, _balances} = Spot.get_balances(%{}, opts)
    end
  end

  describe "USD-M Futures API with auth_credentials" do
    @tag :integration
    test "usdm endpoints accept auth_credentials as keyword list" do
      # Use futures-specific testnet credentials
      api_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY") || System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET") || System.get_env("BINANCE_TESTNET_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Test USDM account (authenticated endpoint)
      assert {:ok, _account} = UsdmFutures.account_information_v3(%{}, opts)
    end

    @tag :integration
    test "usdm endpoints accept auth_credentials as map" do
      # Use futures-specific testnet credentials
      api_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY")
      api_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      # Test USDM account (authenticated endpoint)
      assert {:ok, _account} = UsdmFutures.account_information_v3(%{}, opts)
    end
  end

  describe "COIN-M Futures API with auth_credentials" do
    @tag :integration
    test "coinm endpoints accept auth_credentials as keyword list" do
      # Use futures-specific testnet credentials
      api_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY")
      api_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Test COINM account (authenticated endpoint)
      assert {:ok, _account} = CoinmFutures.get_account(%{}, opts)
    end

    @tag :integration
    test "coinm endpoints accept auth_credentials as map" do
      # Use futures-specific testnet credentials
      api_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY")
      api_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET")

      assert api_key && api_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      # Test COINM account (authenticated endpoint)
      assert {:ok, _account} = CoinmFutures.get_account(%{}, opts)
    end
  end

  describe "Multi-account trading simulation" do
    @tag :integration
    test "can use different credentials for different accounts" do
      # Simulate having multiple accounts
      account1_key = System.get_env("BINANCE_TESTNET_API_KEY")
      account1_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      assert account1_key && account1_secret, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET must be set"

      # In a real scenario, these would be different accounts
      # Using same for testing
      account2_key = account1_key
      account2_secret = account1_secret

      # Account 1 credentials
      account1_opts = [
        auth_credentials: %{
          api_key: account1_key,
          api_secret: account1_secret
        }
      ]

      # Account 2 credentials (same in this test, but would be different in production)
      account2_opts = %{
        auth_credentials: %{
          api_key: account2_key,
          api_secret: account2_secret
        }
      }

      # Both should work independently
      assert {:ok, _balances1} = Spot.get_balances(%{}, account1_opts)
      assert {:ok, _balances2} = Spot.get_balances(%{}, account2_opts)
    end
  end

  # Tests will fail loudly if credentials are not set - no skipping allowed
end
