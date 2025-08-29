defmodule ZenCex.Adapters.Bybit.AuthCredentialsIntegrationTest do
  @moduledoc """
  Integration tests for passing auth_credentials in different formats.
  Tests both keyword lists and maps across different Bybit categories.
  """
  use ZenCex.IntegrationCase, exchange: :bybit

  alias ZenCex.Adapters.Bybit.Unified

  describe "Spot trading with auth_credentials" do
    @tag :integration
    test "spot endpoints accept auth_credentials as keyword list" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Test getting wallet balance
      assert {:ok, _balance} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, opts)
    end

    @tag :integration
    test "spot endpoints accept auth_credentials as map" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      # Test getting wallet balance
      assert {:ok, _balance} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, opts)
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
      assert {:error, _reason} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, opts)
    end
  end

  describe "Linear futures with auth_credentials" do
    @tag :integration
    test "linear endpoints accept auth_credentials as keyword list" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Test getting positions - linear_get_position_list requires either symbol or settleCoin
      assert {:ok, _positions} = Unified.get_position_list(%{category: "linear", settleCoin: "USDT"}, opts)
    end

    @tag :integration
    test "linear endpoints accept auth_credentials as map" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      # Test getting positions - linear_get_position_list requires either symbol or settleCoin
      assert {:ok, _positions} = Unified.get_position_list(%{category: "linear", settleCoin: "USDT"}, opts)
    end
  end

  describe "Inverse futures with auth_credentials" do
    @tag :integration
    test "inverse endpoints accept auth_credentials as keyword list" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Test getting positions
      assert {:ok, _positions} = Unified.get_position_list(%{category: "inverse"}, opts)
    end

    @tag :integration
    test "inverse endpoints accept auth_credentials as map" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      # Test getting positions
      assert {:ok, _positions} = Unified.get_position_list(%{category: "inverse"}, opts)
    end
  end

  describe "Cross-category operations" do
    @tag :integration
    test "can use different credentials for different operations" do
      account1_key = System.get_env("BYBIT_TESTNET_API_KEY")
      account1_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert account1_key && account1_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      # In a real scenario, these could be different subaccounts
      account2_key = account1_key
      account2_secret = account1_secret

      # Account 1 - keyword list
      account1_opts = [
        auth_credentials: %{
          api_key: account1_key,
          api_secret: account1_secret
        }
      ]

      # Account 2 - map
      account2_opts = %{
        auth_credentials: %{
          api_key: account2_key,
          api_secret: account2_secret
        }
      }

      # Both should work
      assert {:ok, _} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, account1_opts)
      assert {:ok, _} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, account2_opts)
    end
  end

  describe "Order operations with auth_credentials" do
    @tag :integration
    test "spot_get_open_orders accepts auth_credentials" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      # Test with keyword list
      opts_keyword = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      assert {:ok, _orders} = Unified.get_open_closed_orders(%{category: "spot"}, opts_keyword)

      # Test with map
      opts_map = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      }

      assert {:ok, _orders} = Unified.get_open_closed_orders(%{category: "spot"}, opts_map)
    end

    @tag :integration
    test "linear_get_open_orders accepts auth_credentials" do
      api_key = System.get_env("BYBIT_TESTNET_API_KEY")
      api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

      assert api_key && api_secret, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET must be set"

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret
        }
      ]

      # Linear requires settleCoin parameter
      assert {:ok, _orders} = Unified.get_open_closed_orders(%{category: "linear", settleCoin: "USDT"}, opts)
    end
  end

  # Tests will fail loudly if credentials are not set - no skipping allowed
end
