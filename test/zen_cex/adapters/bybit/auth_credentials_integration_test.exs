defmodule ZenCex.Adapters.Bybit.AuthCredentialsIntegrationTest do
  @moduledoc """
  Integration tests for passing auth_credentials in different formats.
  Tests both keyword lists and maps across different Bybit categories.
  """
  use ZenCex.IntegrationCase, exchange: :bybit

  alias ZenCex.Adapters.Bybit.Unified

  describe "Spot trading with auth_credentials" do
    @tag :integration
    test "spot endpoints accept auth_credentials as keyword list", %{
      api_key: api_key,
      api_secret: api_secret,
      testnet: testnet
    } do
      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      ]

      # Test getting wallet balance
      assert {:ok, _balance} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, opts)
    end

    @tag :integration
    test "spot endpoints accept auth_credentials as map", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
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
    test "linear endpoints accept auth_credentials as keyword list", %{
      api_key: api_key,
      api_secret: api_secret,
      testnet: testnet
    } do
      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      ]

      # Test getting positions - linear_get_position_list requires either symbol or settleCoin
      assert {:ok, _positions} = Unified.get_position_list(%{category: "linear", settleCoin: "USDT"}, opts)
    end

    @tag :integration
    test "linear endpoints accept auth_credentials as map", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      }

      # Test getting positions - linear_get_position_list requires either symbol or settleCoin
      assert {:ok, _positions} = Unified.get_position_list(%{category: "linear", settleCoin: "USDT"}, opts)
    end
  end

  describe "Inverse futures with auth_credentials" do
    @tag :integration
    test "inverse endpoints accept auth_credentials as keyword list", %{
      api_key: api_key,
      api_secret: api_secret,
      testnet: testnet
    } do
      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      ]

      # Test getting positions
      assert {:ok, _positions} = Unified.get_position_list(%{category: "inverse"}, opts)
    end

    @tag :integration
    test "inverse endpoints accept auth_credentials as map", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      }

      # Test getting positions
      assert {:ok, _positions} = Unified.get_position_list(%{category: "inverse"}, opts)
    end
  end

  describe "Cross-category operations" do
    @tag :integration
    test "can use different credentials for different operations", %{
      api_key: api_key,
      api_secret: api_secret,
      testnet: testnet
    } do
      # In a real scenario, these could be different subaccounts
      # For testing, we use the same credentials in different formats

      # Account 1 - keyword list
      account1_opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      ]

      # Account 2 - map
      account2_opts = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      }

      # Both should work
      assert {:ok, _} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, account1_opts)
      assert {:ok, _} = Unified.get_wallet_balance(%{accountType: "UNIFIED"}, account2_opts)
    end
  end

  describe "Order operations with auth_credentials" do
    @tag :integration
    test "spot_get_open_orders accepts auth_credentials", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      # Test with keyword list
      opts_keyword = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      ]

      assert {:ok, _orders} = Unified.get_open_closed_orders(%{category: "spot"}, opts_keyword)

      # Test with map
      opts_map = %{
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      }

      assert {:ok, _orders} = Unified.get_open_closed_orders(%{category: "spot"}, opts_map)
    end

    @tag :integration
    test "linear_get_open_orders accepts auth_credentials", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: testnet
        }
      ]

      # Linear requires settleCoin parameter
      assert {:ok, _orders} = Unified.get_open_closed_orders(%{category: "linear", settleCoin: "USDT"}, opts)
    end
  end

  # Tests will fail loudly if credentials are not set - no skipping allowed
end
