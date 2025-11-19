# Example usage of ZenCex TestUtilities in external applications
# This file demonstrates how external apps can use the test utilities

defmodule MyApp.ExchangeIntegrationTest do
  @moduledoc """
  Example integration test using ZenCex.TestUtilities
  """

  use ZenCex.TestUtilities.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.Spot

  test "fetches account balances from Binance testnet" do
    # The IntegrationCase ensures we're using testnet
    {:ok, balances} = Spot.get_balances()

    assert is_list(balances)

    # Validate the response structure
    ZenCex.TestUtilities.assert_valid_balance_structure(balances, :binance)
  end

  test "handles invalid credentials gracefully" do
    # Use with_env macro to temporarily change credentials
    with_env [{"BINANCE_TESTNET_API_KEY", "invalid"}] do
      result = Spot.get_balances()
      assert {:error, _} = result
    end
  end
end

defmodule MyApp.ConfigurationTest do
  @moduledoc """
  Example of using test configuration helpers
  """

  use ExUnit.Case

  import ZenCex.TestUtilities.EnvHelpers

  test "creates test configuration for Binance" do
    config = ZenCex.TestUtilities.get_test_config!(:binance)

    assert config.exchange == :binance
    assert config.testnet == true
    assert config.api_key
    assert config.api_secret
  end

  test "creates invalid config for error testing" do
    config = ZenCex.TestUtilities.get_invalid_config(:binance, :spot)

    assert config.api_key == "invalid_api_key_binance"
    assert config.api_secret == "invalid_api_secret_binance"
  end

  test "adds account type to configuration" do
    config = ZenCex.TestUtilities.get_test_config!(:binance)
    config = ZenCex.TestUtilities.with_account_type(config, :futures_usdm)

    assert config.account_type == :futures_usdm
  end
end

defmodule MyApp.ValidationTest do
  @moduledoc """
  Example of using response validators
  """

  use ExUnit.Case

  test "validates balance structure" do
    # Generate test data
    balance = ZenCex.TestUtilities.generate_test_balance(:binance, "BTC", "10.5", "0.5")

    # Validate it matches expected structure
    ZenCex.TestUtilities.assert_valid_balance_structure([balance], :binance)
  end

  test "validates order structure" do
    order =
      ZenCex.TestUtilities.generate_test_order(
        :binance,
        "BTCUSDT",
        :buy,
        :limit,
        "0.001",
        "50000"
      )

    ZenCex.TestUtilities.assert_valid_order_structure(order, :binance)
  end
end

defmodule MyApp.EnvironmentTest do
  @moduledoc """
  Example of environment management utilities
  """

  use ExUnit.Case

  import ZenCex.TestUtilities.EnvHelpers

  test "temporarily modifies environment variables" do
    original_value = System.get_env("MY_TEST_VAR")

    with_env [{"MY_TEST_VAR", "temporary_value"}] do
      assert System.get_env("MY_TEST_VAR") == "temporary_value"
    end

    # Automatically restored
    assert System.get_env("MY_TEST_VAR") == original_value
  end

  test "clears environment cache when needed" do
    # Useful when simulating environment changes in tests
    ZenCex.TestUtilities.clear_all_environment_caches()

    # Now environment detection will re-read from System.get_env
  end
end
