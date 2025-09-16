defmodule ZenCex.TestUtilities do
  @moduledoc """
  Comprehensive test utilities for ZenCex and consuming applications.

  Provides utilities for:
  - Test configuration management
  - Response structure validation
  - Test data generation
  - Environment management
  - Integration test cases

  These helpers can be used both in tests and during development.

  ## Available Modules

  - `ZenCex.TestUtilities.IntegrationCase` - Test case template for integration tests
  - `ZenCex.TestUtilities.EnvHelpers` - Macros for safe environment variable manipulation
  - `ZenCex.TestUtilities.Generators` - Property-based testing generators
  - `ZenCex.TestUtilities.Validators` - Response validation helpers

  ## Usage in External Applications

  Add ZenCex to your test dependencies:

      def deps do
        [
          {:zen_cex, "~> 0.1.0", only: [:dev, :test]}
        ]
      end

  Then use the test utilities in your tests:

      # Use the integration test case
      defmodule MyApp.ExchangeTest do
        use ZenCex.TestUtilities.IntegrationCase, exchange: :binance, api_type: :spot

        test "fetch balances" do
          {:ok, balances} = ZenCex.Adapters.Binance.Spot.get_balances()
          assert is_list(balances)
        end
      end

      # Or use helpers directly
      defmodule MyApp.ConfigTest do
        use ExUnit.Case
        import ZenCex.TestUtilities.EnvHelpers

        test "handles missing API key" do
          with_env [{"BINANCE_TESTNET_API_KEY", nil}] do
            assert {:error, :missing_credentials} = MyModule.authenticate()
          end
        end
      end
  """

  alias ZenCex.TestUtilities.Generators
  alias ZenCex.TestUtilities.Validators

  @type exchange :: :binance | :bybit | :deribit | :okx
  @type account_type ::
          :spot
          | :futures_usdm
          | :futures_coinm
          | :margin
          | :margin_isolated
          | :portfolio
          | :portfolio_coinm
  @type decimal_string :: String.t()

  @supported_exchanges [:binance, :bybit, :deribit, :okx]
  @account_types [:spot, :futures_usdm, :futures_coinm, :margin, :margin_isolated, :portfolio, :portfolio_coinm]

  # ============================================================================
  # Configuration Management
  # ============================================================================

  @doc """
  Gets test configuration for the specified exchange.
  Fails loudly if credentials are missing.

  ## Examples

      config = ZenCex.TestUtilities.get_test_config!(:binance)
      {:ok, balances} = ZenCex.Adapters.Binance.Spot.get_balances(config)
  """
  @spec get_test_config!(exchange()) :: map()
  def get_test_config!(exchange) when exchange in @supported_exchanges do
    case maybe_get_test_config(exchange) do
      {:ok, config} ->
        config

      {:error, reason} ->
        raise """
        Missing #{exchange} testnet credentials!
        #{reason}

        Set the following environment variables to run integration tests:
        #{env_var_instructions(exchange)}
        """
    end
  end

  @doc """
  Attempts to get test configuration for the specified exchange.
  Returns {:ok, config} or {:error, reason}.
  """
  @spec maybe_get_test_config(exchange()) :: {:ok, map()} | {:error, String.t()}
  def maybe_get_test_config(exchange) when exchange in @supported_exchanges do
    get_exchange_config(exchange)
  end

  defp get_exchange_config(:binance) do
    api_key = System.get_env("BINANCE_TESTNET_API_KEY")
    api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

    if api_key && api_secret do
      {:ok,
       %{
         api_key: api_key,
         api_secret: api_secret,
         testnet: true,
         exchange: :binance
       }}
    else
      {:error, "BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET not set"}
    end
  end

  defp get_exchange_config(:bybit) do
    api_key = System.get_env("BYBIT_TESTNET_API_KEY")
    api_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

    if api_key && api_secret do
      {:ok,
       %{
         api_key: api_key,
         api_secret: api_secret,
         testnet: true,
         exchange: :bybit
       }}
    else
      {:error, "BYBIT_TESTNET_API_KEY and BYBIT_TESTNET_API_SECRET not set"}
    end
  end

  defp get_exchange_config(:deribit) do
    api_key = System.get_env("DERIBIT_TESTNET_API_KEY")
    api_secret = System.get_env("DERIBIT_TESTNET_API_SECRET")

    if api_key && api_secret do
      {:ok,
       %{
         api_key: api_key,
         api_secret: api_secret,
         testnet: true,
         exchange: :deribit
       }}
    else
      {:error, "DERIBIT_TESTNET_API_KEY and DERIBIT_TESTNET_API_SECRET not set"}
    end
  end

  defp get_exchange_config(:okx) do
    api_key = System.get_env("OKX_TESTNET_API_KEY")
    api_secret = System.get_env("OKX_TESTNET_API_SECRET")
    passphrase = System.get_env("OKX_TESTNET_PASSPHRASE")

    if api_key && api_secret && passphrase do
      {:ok,
       %{
         api_key: api_key,
         api_secret: api_secret,
         passphrase: passphrase,
         testnet: true,
         exchange: :okx
       }}
    else
      {:error, "OKX_TESTNET_API_KEY, OKX_TESTNET_API_SECRET, and OKX_TESTNET_PASSPHRASE not set"}
    end
  end

  @doc """
  Gets test configuration for Binance futures (uses different env vars).
  Fails loudly if credentials are missing.
  """
  @spec get_binance_futures_test_config!() :: map()
  def get_binance_futures_test_config! do
    api_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY")
    api_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET")

    if api_key && api_secret do
      %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: true,
        exchange: :binance
      }
    else
      raise """
      Missing Binance futures testnet credentials!
      Set BINANCE_FUTURES_TEST_API_KEY and BINANCE_FUTURES_TEST_API_SECRET environment variables to run integration tests.

      Get testnet API keys from: https://testnet.binancefuture.com/
      """
    end
  end

  @doc """
  Creates an invalid configuration for error testing.
  """
  @spec get_invalid_config(exchange(), account_type()) :: map()
  def get_invalid_config(exchange, account_type \\ :spot) do
    %{
      api_key: "invalid_api_key_#{exchange}",
      api_secret: "invalid_api_secret_#{exchange}",
      testnet: true,
      exchange: exchange,
      account_type: account_type
    }
  end

  @doc """
  Adds account type to existing configuration.
  """
  @spec with_account_type(map(), account_type()) :: map()
  def with_account_type(config, account_type) when account_type in @account_types do
    Map.put(config, :account_type, account_type)
  end

  @doc """
  Checks if API tests should run for the given exchange.
  """
  @spec should_run_api_tests?(exchange()) :: boolean()
  def should_run_api_tests?(exchange) when exchange in @supported_exchanges do
    case maybe_get_test_config(exchange) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Checks if API tests should run (for any configured exchange).
  """
  @spec should_run_api_tests?() :: boolean()
  def should_run_api_tests? do
    # Check if we're in CI environment
    ci = System.get_env("CI") == "true"

    # Check if any exchange has credentials
    has_any = Enum.any?(@supported_exchanges, &should_run_api_tests?/1)

    !ci && has_any
  end

  # ============================================================================
  # Assertion Helpers
  # ============================================================================

  @doc """
  Asserts that the result is {:ok, _} and returns the value.
  """
  def assert_ok({:ok, value}), do: value

  def assert_ok(other) do
    raise "Expected {:ok, value}, got: #{inspect(other)}"
  end

  @doc """
  Asserts that the result is {:error, _} and returns the error.
  """
  def assert_error({:error, reason}), do: reason

  def assert_error(other) do
    raise "Expected {:error, reason}, got: #{inspect(other)}"
  end

  # ============================================================================
  # Response Validators (Delegated)
  # ============================================================================

  defdelegate assert_valid_balance_structure(data, exchange), to: Validators
  defdelegate assert_valid_position_structure(data, exchange), to: Validators
  defdelegate assert_valid_order_structure(data, exchange), to: Validators
  defdelegate assert_valid_kline_structure(data, exchange), to: Validators
  defdelegate assert_valid_ticker_structure(data, exchange), to: Validators
  defdelegate assert_valid_order_book_structure(data, exchange), to: Validators
  defdelegate assert_valid_funding_rate_structure(data, exchange), to: Validators

  # ============================================================================
  # Test Data Generators (Delegated)
  # ============================================================================

  defdelegate generate_test_balance(exchange, asset, amount), to: Generators
  defdelegate generate_test_balance(exchange, asset, amount, locked), to: Generators
  defdelegate generate_test_position(exchange, symbol, side, size), to: Generators
  defdelegate generate_test_position(exchange, symbol, side, size, entry_price, mark_price), to: Generators
  defdelegate generate_test_order(exchange, symbol, side, order_type, quantity, price), to: Generators
  defdelegate generate_test_kline(exchange, timestamp, o, h, l, c, volume), to: Generators
  defdelegate generate_test_ticker(exchange, symbol, last_price), to: Generators
  defdelegate generate_test_funding_rate(exchange, symbol, rate), to: Generators

  # ============================================================================
  # Environment Management
  # ============================================================================

  @doc """
  Clears the persistent_term cache for environment detection.

  This is useful in tests when simulating environment changes
  without restarting the application.
  """
  @spec clear_environment_cache(module()) :: :ok
  def clear_environment_cache(module) do
    key = {:zen_cex, module, :current_env}

    try do
      :persistent_term.erase(key)
    catch
      :error, :badarg ->
        # Key didn't exist, which is fine
        :ok
    end

    :ok
  end

  @doc """
  Clears environment caches for all known exchange endpoint modules.
  """
  @spec clear_all_environment_caches() :: :ok
  def clear_all_environment_caches do
    modules = [
      ZenCex.Adapters.Binance.Endpoints,
      ZenCex.Adapters.Bybit.Endpoints
      # Future: Deribit.Endpoints, OKX.Endpoints
    ]

    for module <- modules do
      if Code.ensure_loaded?(module) do
        clear_environment_cache(module)
      end
    end

    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp env_var_instructions(:binance) do
    """
    BINANCE_TESTNET_API_KEY=your_key
    BINANCE_TESTNET_API_SECRET=your_secret

    Get testnet API keys from: https://testnet.binance.vision/

    For futures:
    BINANCE_FUTURES_TEST_API_KEY=your_key
    BINANCE_FUTURES_TEST_API_SECRET=your_secret

    Get futures testnet API keys from: https://testnet.binancefuture.com/
    """
  end

  defp env_var_instructions(:bybit) do
    """
    BYBIT_TESTNET_API_KEY=your_key
    BYBIT_TESTNET_API_SECRET=your_secret

    Get testnet API keys from: https://testnet.bybit.com/
    """
  end

  defp env_var_instructions(:deribit) do
    """
    DERIBIT_TESTNET_API_KEY=your_key
    DERIBIT_TESTNET_API_SECRET=your_secret

    Get testnet API keys from: https://test.deribit.com/
    """
  end

  defp env_var_instructions(:okx) do
    """
    OKX_TESTNET_API_KEY=your_key
    OKX_TESTNET_API_SECRET=your_secret
    OKX_TESTNET_PASSPHRASE=your_passphrase

    Get testnet API keys from: https://www.okx.com/
    """
  end
end
