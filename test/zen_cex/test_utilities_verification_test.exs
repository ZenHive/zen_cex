defmodule ZenCex.TestUtilitiesVerificationTest do
  @moduledoc """
  Verifies that test utilities are properly exposed for external applications.
  """

  use ExUnit.Case

  alias ZenCex.TestUtilities.EnvHelpers

  describe "public modules are accessible" do
    test "IntegrationCase module exists and is accessible" do
      assert Code.ensure_loaded?(ZenCex.TestUtilities.IntegrationCase)
    end

    test "EnvHelpers module exists and is accessible" do
      assert Code.ensure_loaded?(EnvHelpers)
    end

    test "Generators module exists and is accessible" do
      assert Code.ensure_loaded?(ZenCex.TestUtilities.Generators)
    end

    test "Validators module exists and is accessible" do
      assert Code.ensure_loaded?(ZenCex.TestUtilities.Validators)
    end

    test "main TestUtilities module exists" do
      assert Code.ensure_loaded?(ZenCex.TestUtilities)
    end
  end

  describe "with_env macro works" do
    import EnvHelpers

    test "can temporarily set environment variable" do
      original = System.get_env("TEST_UTILITIES_VERIFICATION")

      with_env [{"TEST_UTILITIES_VERIFICATION", "test_value"}] do
        assert System.get_env("TEST_UTILITIES_VERIFICATION") == "test_value"
      end

      assert System.get_env("TEST_UTILITIES_VERIFICATION") == original
    end

    test "can temporarily delete environment variable" do
      System.put_env("TEST_UTILITIES_VERIFICATION", "original")

      with_env [{"TEST_UTILITIES_VERIFICATION", nil}] do
        assert System.get_env("TEST_UTILITIES_VERIFICATION") == nil
      end

      assert System.get_env("TEST_UTILITIES_VERIFICATION") == "original"

      # Clean up
      System.delete_env("TEST_UTILITIES_VERIFICATION")
    end
  end

  describe "test configuration helpers" do
    test "get_test_config! returns configuration map" do
      # This will use whatever credentials are in the environment
      # or raise if missing
      config = ZenCex.TestUtilities.get_test_config!(:binance)

      assert is_map(config)
      assert config.exchange == :binance
      assert config.testnet == true
      assert is_binary(config.api_key)
      assert is_binary(config.api_secret)
    end

    test "get_invalid_config creates invalid config for testing" do
      config = ZenCex.TestUtilities.get_invalid_config(:binance, :spot)

      assert config.api_key == "invalid_api_key_binance"
      assert config.api_secret == "invalid_api_secret_binance"
      assert config.account_type == :spot
    end

    test "with_account_type adds account type to config" do
      config = %{api_key: "test", api_secret: "test"}
      updated = ZenCex.TestUtilities.with_account_type(config, :futures_usdm)

      assert updated.account_type == :futures_usdm
      assert updated.api_key == "test"
    end
  end
end
