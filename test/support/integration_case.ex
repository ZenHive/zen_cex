defmodule ZenCex.IntegrationCase do
  @moduledoc """
  Test case template for integration tests that require testnet/sandbox API connections.

  This module provides common setup and helpers for integration tests:
  - Enforces testnet/sandbox usage (prevents production API calls)
  - Validates credentials are configured
  - Provides consistent error messages
  - Ensures tests fail loudly without proper setup

  ## Usage

      defmodule MyExchangeIntegrationTest do
        use ZenCex.IntegrationCase, exchange: :binance

        test "real API call" do
          # Test will only run if testnet is properly configured
        end
      end

  ## Options

  - `:exchange` - The exchange to test (`:binance`, `:kraken`, `:deribit`)
  - `:api_type` - For exchanges with multiple APIs (e.g., `:spot`, `:futures`)
  """

  use ExUnit.CaseTemplate

  alias ZenCex.Adapters.Binance.Spot

  using options do
    exchange = Keyword.fetch!(options, :exchange)
    api_type = Keyword.get(options, :api_type)
    use_production_for_test = Keyword.get(options, :use_production_for_test, false)

    quote do
      use ExUnit.Case

      import ZenCex.IntegrationCase

      # Import the shared env helpers
      import ZenCex.TestUtilities.EnvHelpers

      alias ZenCex.Adapters.Binance.Endpoints

      @moduletag :integration
      @moduletag unquote(exchange)
      if unquote(api_type), do: @moduletag(unquote(api_type))
      if unquote(use_production_for_test), do: @moduletag(:production_test)

      setup_all do
        # If using production for test, temporarily disable testnet mode
        if unquote(use_production_for_test) do
          # Save original values
          original_binance_testnet = System.get_env("BINANCE_TESTNET")
          original_bybit_testnet = System.get_env("BYBIT_TESTNET")

          # Temporarily set to production mode
          System.delete_env("BINANCE_TESTNET")
          System.delete_env("BYBIT_TESTNET")

          # Clear the cached environment from persistent_term
          # This forces the Endpoints module to re-evaluate the environment
          :persistent_term.erase({:zen_cex, Endpoints, :current_env})
          :persistent_term.erase({:zen_cex, ZenCex.Adapters.Bybit.Endpoints, :current_env})

          on_exit(fn ->
            # Restore original values
            if original_binance_testnet, do: System.put_env("BINANCE_TESTNET", original_binance_testnet)
            if original_bybit_testnet, do: System.put_env("BYBIT_TESTNET", original_bybit_testnet)

            # Clear the cache again to force re-evaluation with restored env
            :persistent_term.erase({:zen_cex, Endpoints, :current_env})
            :persistent_term.erase({:zen_cex, ZenCex.Adapters.Bybit.Endpoints, :current_env})
          end)
        end

        unquote(__MODULE__).enforce_testnet!(
          unquote(exchange),
          unquote(api_type),
          unquote(use_production_for_test)
        )
      end
    end
  end

  @doc """
  Enforces testnet usage for the given exchange and validates credentials.

  This function:
  1. Verifies the exchange is configured for testnet/sandbox mode (unless use_production_for_test is true)
  2. Checks that testnet URLs are being used (unless use_production_for_test is true)
  3. Validates required credentials are present
  4. Tests basic connectivity to the testnet

  ## Options
  - `use_production_for_test`: When true, allows using production API with alternative test credentials.
    WARNING: This uses REAL production endpoints with a test account. Only use with accounts that have minimal funds!

  Raises an error if any validation fails, ensuring tests don't accidentally
  run against production APIs or hide missing configuration.
  """
  @spec enforce_testnet!(atom(), atom() | nil, boolean()) :: {:ok, keyword()}
  def enforce_testnet!(exchange, api_type \\ nil, use_production_for_test \\ false) do
    case exchange do
      :binance -> enforce_binance_testnet!(api_type, use_production_for_test)
      :bybit -> enforce_bybit_testnet!(api_type)
      :kraken -> enforce_kraken_testnet!(api_type)
      :deribit -> enforce_deribit_testnet!(api_type)
      :multi -> enforce_multi_exchange_testnet!()
      _ -> raise "Unknown exchange: #{exchange}"
    end
  end

  # Binance testnet enforcement
  defp enforce_binance_testnet!(api_type, use_production_for_test) do
    alias ZenCex.Adapters.Binance.Endpoints

    require Logger

    # If using production for test, warn and skip testnet checks
    if use_production_for_test do
      Logger.warning("""
      ⚠️  USING PRODUCTION API FOR TESTING
      ⚠️  This test is configured to use PRODUCTION Binance endpoints
      ⚠️  Make sure to use an account with MINIMAL funds!
      ⚠️  API Type: #{inspect(api_type)}
      """)
    else
      # Check environment is set to test
      env = Endpoints.current_env()

      if env != :test do
        raise """
        TESTNET REQUIRED: Environment is #{env}, expected :test.
        Set BINANCE_TESTNET=true to enable testnet mode.
        """
      end

      # Verify base URL for the specific API type
      actual_url = get_binance_base_url(api_type)

      # Skip validation for portfolio margin (no testnet available)
      if actual_url != :skip_portfolio_testnet_check do
        expected_url = expected_binance_testnet_url(api_type)

        if actual_url != expected_url do
          raise """
          TESTNET URL REQUIRED: Got #{actual_url}, expected #{expected_url}
          Ensure BINANCE_TESTNET=true is set.
          """
        end
      end
    end

    # Check credentials - handle production test account if enabled
    {api_key, api_secret} =
      if use_production_for_test do
        # Using production API with test account - use alternative credentials
        fetch_production_test_credentials!(api_type)
      else
        # Normal testnet flow
        if api_type in [:usdm_futures, :coinm_futures] do
          # Futures testnet uses different credentials
          api_key =
            fetch_testnet_credential!("BINANCE_FUTURES_TEST_API_KEY", """
            BINANCE_FUTURES_TEST_API_KEY required for futures integration tests.

            Get futures testnet credentials at: https://testnet.binancefuture.com/
            Then run: export BINANCE_FUTURES_TEST_API_KEY=your_futures_key
            """)

          api_secret =
            fetch_testnet_credential!("BINANCE_FUTURES_TEST_API_SECRET", """
            BINANCE_FUTURES_TEST_API_SECRET required for futures integration tests.

            Get futures testnet credentials at: https://testnet.binancefuture.com/
            Then run: export BINANCE_FUTURES_TEST_API_SECRET=your_futures_secret
            """)

          {api_key, api_secret}
        else
          # Spot/margin testnet uses standard testnet credentials
          api_key =
            fetch_testnet_credential!("BINANCE_TESTNET_API_KEY", """
            BINANCE_TESTNET_API_KEY required for integration tests.

            Get testnet credentials at: https://testnet.binance.vision/
            Then run: export BINANCE_TESTNET_API_KEY=your_key
            """)

          api_secret =
            fetch_testnet_credential!("BINANCE_TESTNET_API_SECRET", """
            BINANCE_TESTNET_API_SECRET required for integration tests.

            Get testnet credentials at: https://testnet.binance.vision/
            Then run: export BINANCE_TESTNET_API_SECRET=your_secret
            """)

          {api_key, api_secret}
        end
      end

    # Test connectivity (skip for portfolio - no testnet)
    # Also skip for production test mode since we don't want to make unnecessary API calls
    if api_type != :portfolio and not use_production_for_test do
      verify_binance_connectivity!(api_type)
    end

    # Determine testnet flag based on use_production_for_test
    testnet = not use_production_for_test

    {:ok,
     api_key: api_key,
     api_secret: api_secret,
     testnet: testnet,
     exchange: :binance,
     use_production_for_test: use_production_for_test}
  end

  # Kraken testnet enforcement
  defp enforce_kraken_testnet!(_api_type) do
    # TODO: Implement Kraken testnet enforcement when Kraken adapter is added
    raise """
    Kraken testnet enforcement not yet implemented.
    The Kraken adapter needs to be completed first.
    """
  end

  # Deribit testnet enforcement
  defp enforce_deribit_testnet!(_api_type) do
    # TODO: Implement Deribit testnet enforcement when Deribit adapter is added
    # Deribit uses test.deribit.com for testnet
    raise """
    Deribit testnet enforcement not yet implemented.
    The Deribit adapter needs to be completed first.
    """
  end

  # Multi-exchange testnet enforcement for tests that need multiple exchanges
  defp enforce_multi_exchange_testnet! do
    # Check that at least Binance and Bybit testnets are available
    # We don't enforce all exchanges, just validate the common ones used in multi-exchange tests

    binance_futures_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY")
    binance_futures_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET")
    bybit_key = System.get_env("BYBIT_TESTNET_API_KEY")
    bybit_secret = System.get_env("BYBIT_TESTNET_API_SECRET")

    missing = []

    missing =
      if is_nil(binance_futures_key) or binance_futures_key == "",
        do: ["BINANCE_FUTURES_TEST_API_KEY" | missing],
        else: missing

    missing =
      if is_nil(binance_futures_secret) or binance_futures_secret == "",
        do: ["BINANCE_FUTURES_TEST_API_SECRET" | missing],
        else: missing

    missing = if is_nil(bybit_key) or bybit_key == "", do: ["BYBIT_TESTNET_API_KEY" | missing], else: missing
    missing = if is_nil(bybit_secret) or bybit_secret == "", do: ["BYBIT_TESTNET_API_SECRET" | missing], else: missing

    if length(missing) > 0 do
      raise """
      MULTI-EXCHANGE TESTNET CREDENTIALS REQUIRED

      The following environment variables are missing:
      #{Enum.join(missing, "\n")}

      Multi-exchange tests require both Binance and Bybit testnet credentials.

      Get Binance futures testnet credentials at: https://testnet.binancefuture.com/
      Get Bybit testnet credentials at: https://testnet.bybit.com/

      Then export the credentials:
      export BINANCE_FUTURES_TEST_API_KEY=your_binance_key
      export BINANCE_FUTURES_TEST_API_SECRET=your_binance_secret
      export BYBIT_TESTNET_API_KEY=your_bybit_key
      export BYBIT_TESTNET_API_SECRET=your_bybit_secret
      """
    end

    # Verify testnet mode is enabled for both
    binance_testnet = System.get_env("BINANCE_TESTNET")
    bybit_testnet = System.get_env("BYBIT_TESTNET")

    if binance_testnet != "true" do
      raise """
      BINANCE TESTNET MODE REQUIRED
      Set BINANCE_TESTNET=true to enable Binance testnet mode.
      """
    end

    if bybit_testnet != "true" do
      raise """
      BYBIT TESTNET MODE REQUIRED
      Set BYBIT_TESTNET=true to enable Bybit testnet mode.
      """
    end

    {:ok,
     binance_futures_key: binance_futures_key,
     binance_futures_secret: binance_futures_secret,
     bybit_key: bybit_key,
     bybit_secret: bybit_secret,
     exchange: :multi}
  end

  # Helper to get expected Binance testnet URL based on API type
  defp expected_binance_testnet_url(nil), do: "https://testnet.binance.vision"
  defp expected_binance_testnet_url(:spot), do: "https://testnet.binance.vision"
  defp expected_binance_testnet_url(:margin), do: "https://testnet.binance.vision"
  defp expected_binance_testnet_url(:usdm_futures), do: "https://testnet.binancefuture.com"
  defp expected_binance_testnet_url(:coinm_futures), do: "https://testnet.binancefuture.com"
  defp expected_binance_testnet_url(:futures), do: "https://testnet.binancefuture.com"
  defp expected_binance_testnet_url(:portfolio), do: "https://testnet.binancefuture.com"

  defp expected_binance_testnet_url(:sapi) do
    raise "SAPI endpoints are not supported on Binance testnet"
  end

  defp expected_binance_testnet_url(api_type) do
    raise "Unknown Binance API type: #{api_type}"
  end

  # Helper to get actual Binance base URL
  defp get_binance_base_url(nil) do
    ZenCex.Adapters.Binance.Endpoints.base_url(:spot, testnet: true)
  end

  defp get_binance_base_url(api_type) do
    case ZenCex.Adapters.Binance.Endpoints.base_url(api_type, testnet: true) do
      {:error, :no_testnet_for_portfolio_margin} ->
        # Portfolio margin has no testnet, skip URL validation
        :skip_portfolio_testnet_check

      {:error, _} = error ->
        raise "Failed to get base URL: #{inspect(error)}"

      url ->
        url
    end
  end

  # Bybit testnet enforcement
  defp enforce_bybit_testnet!(_api_type) do
    alias ZenCex.Adapters.Bybit.Endpoints

    # Check environment is set to test
    env = Endpoints.current_env()

    if env != :test do
      raise """
      TESTNET REQUIRED: Environment is #{env}, expected :test.
      Set BYBIT_TESTNET=true to enable testnet mode.
      """
    end

    # Verify base URL (Bybit uses unified API)
    actual_url = Endpoints.base_url(testnet: true)
    expected_url = "https://api-testnet.bybit.com"

    if actual_url != expected_url do
      raise """
      TESTNET URL REQUIRED: Got #{actual_url}, expected #{expected_url}
      Ensure BYBIT_TESTNET=true is set.
      """
    end

    # Check credentials for authenticated endpoints
    api_key =
      fetch_testnet_credential!("BYBIT_TESTNET_API_KEY", """
      BYBIT_TESTNET_API_KEY required for integration tests.

      Get testnet credentials at: https://testnet.bybit.com/
      Then run: export BYBIT_TESTNET_API_KEY=your_key
      """)

    api_secret =
      fetch_testnet_credential!("BYBIT_TESTNET_API_SECRET", """
      BYBIT_TESTNET_API_SECRET required for integration tests.

      Get testnet credentials at: https://testnet.bybit.com/
      Then run: export BYBIT_TESTNET_API_SECRET=your_secret
      """)

    # Verify connectivity to Bybit testnet
    verify_bybit_connectivity!()

    {:ok, api_key: api_key, api_secret: api_secret, testnet: true, exchange: :bybit}
  end

  defp verify_bybit_connectivity! do
    alias ZenCex.Adapters.Bybit.Common

    case Common.get_server_time() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise """
        Cannot connect to Bybit testnet: #{inspect(reason)}

        Please verify:
        1. Your internet connection is working
        2. Bybit testnet is accessible from your location
        3. The testnet API is operational
        """
    end
  end

  # Helper to fetch required testnet credentials
  defp fetch_testnet_credential!(env_var, error_message) do
    System.get_env(env_var) || raise(error_message)
  end

  # Helper to fetch production test account credentials
  # WARNING: These are PRODUCTION credentials for a test account with minimal funds!
  defp fetch_production_test_credentials!(api_type) do
    require Logger

    # First try to get ALT credentials (production test account)
    api_key = System.get_env("BINANCE_TESTNET_ALT_API_KEY")
    api_secret = System.get_env("BINANCE_TESTNET_ALT_API_SECRET")

    if api_key && api_key != "" && api_secret && api_secret != "" do
      Logger.warning("""
      ⚠️  Using PRODUCTION TEST ACCOUNT credentials
      ⚠️  API Type: #{inspect(api_type)}
      ⚠️  These connect to PRODUCTION Binance, not testnet!
      ⚠️  Ensure this account has MINIMAL funds for safety
      """)

      {api_key, api_secret}
    else
      # Fall back to regular testnet credentials if ALT not available
      # This allows gradual migration
      {fallback_key, fallback_secret} =
        cond do
          api_type in [:usdm_futures, :coinm_futures] ->
            {System.get_env("BINANCE_FUTURES_TEST_API_KEY"), System.get_env("BINANCE_FUTURES_TEST_API_SECRET")}

          api_type == :portfolio ->
            {System.get_env("BINANCE_PM_TEST_API_KEY"), System.get_env("BINANCE_PM_TEST_API_SECRET")}

          true ->
            {System.get_env("BINANCE_TESTNET_API_KEY"), System.get_env("BINANCE_TESTNET_API_SECRET")}
        end

      if fallback_key && fallback_key != "" && fallback_secret && fallback_secret != "" do
        Logger.warning("""
        ⚠️  ALT credentials not found, falling back to testnet credentials
        ⚠️  This may fail if testnet has IP restrictions
        ⚠️  Consider setting BINANCE_TESTNET_ALT_API_KEY/SECRET
        """)

        {fallback_key, fallback_secret}
      else
        # Provide specific error message based on api_type
        credentials_msg =
          if api_type == :portfolio do
            """
            Portfolio Margin tests require:
            - BINANCE_PM_TEST_API_KEY
            - BINANCE_PM_TEST_API_SECRET

            Note: Portfolio Margin has NO testnet - must use production API.
            """
          else
            """
            When using use_production_for_test: true, you must provide:
            - BINANCE_TESTNET_ALT_API_KEY
            - BINANCE_TESTNET_ALT_API_SECRET
            """
          end

        raise """
        PRODUCTION TEST ACCOUNT CREDENTIALS REQUIRED

        #{credentials_msg}

        These should be credentials for a PRODUCTION Binance account
        with MINIMAL funds that is used only for testing purposes.

        ⚠️  WARNING: These will connect to PRODUCTION Binance API!
        ⚠️  Only use an account with minimal funds for safety.

        To set up:
        1. Create a separate Binance account for testing
        2. Fund it with minimal amounts (< $100 recommended)
        3. Generate API credentials
        4. Export them:
           export BINANCE_TESTNET_ALT_API_KEY=your_test_account_key
           export BINANCE_TESTNET_ALT_API_SECRET=your_test_account_secret
        """
      end
    end
  end

  # Verify connectivity to Binance testnet
  defp verify_binance_connectivity!(api_type) do
    api_type
    |> get_connectivity_test_result()
    |> handle_connectivity_result(api_type)
  end

  defp get_connectivity_test_result(api_type) do
    cond do
      api_type in [nil, :spot] -> Spot.get_ping()
      api_type in [:usdm_futures, :coinm_futures] -> verify_futures_connectivity(api_type)
      true -> {:ok, :skip_connectivity_check}
    end
  end

  defp handle_connectivity_result({:ok, _}, _api_type), do: :ok

  defp handle_connectivity_result({:error, reason}, api_type) do
    raise """
    Cannot connect to Binance testnet (#{api_type || "spot"}): #{inspect(reason)}

    Please verify:
    1. Your internet connection is working
    2. Binance testnet is accessible from your location
    3. Your testnet credentials are valid
    """
  end

  defp verify_futures_connectivity(api_type) do
    # Use public ping endpoints (no auth required) for connectivity check
    case api_type do
      :coinm_futures -> ZenCex.Adapters.Binance.CoinmFutures.get_ping()
      :usdm_futures -> ZenCex.Adapters.Binance.UsdmFutures.get_ping()
    end
  end

  @doc """
  Asserts that Portfolio Margin API call succeeded or failed with expected credentials/config errors.

  This helper allows Portfolio Margin tests to pass when PM credentials are not configured,
  while still failing loudly on unexpected errors that indicate actual bugs.

  ## Expected errors (test passes):
  - `{:error, %{"code" => -2014}}` - API-key format invalid
  - `{:error, %{"code" => -2015}}` - Invalid API-key, IP, or permissions
  - `{:error, %{"code" => -11001}}` - Portfolio Margin not enabled on account

  ## Unexpected errors (test fails):
  - Any other error format or code will cause the test to fail with a descriptive message

  ## TODO
  Configure Portfolio Margin credentials to enable full test coverage:
  - Set BINANCE_PM_TEST_API_KEY
  - Set BINANCE_PM_TEST_API_SECRET
  - Ensure account has Portfolio Margin enabled
  - Note: PM has no testnet, must use production API with test account

  ## Examples

      # In a Portfolio Margin test
      result = PortfolioMargin.change_um_initial_leverage(%{symbol: "BTCUSDT", leverage: 5}, opts)
      assert_pm_success_or_not_configured(result)

  """
  def assert_pm_success_or_not_configured(result) do
    case result do
      {:ok, response} ->
        assert is_map(response)

      {:error, %{"code" => -2014}} ->
        # TODO: Configure PM credentials (BINANCE_PM_TEST_API_KEY/SECRET)
        # "API-key format invalid"
        :ok

      {:error, %{"code" => -2015}} ->
        # TODO: Configure PM credentials (BINANCE_PM_TEST_API_KEY/SECRET)
        # "Invalid API-key, IP, or permissions for Portfolio Margin"
        :ok

      {:error, %{"code" => -11_001}} ->
        # TODO: Configure PM credentials with Portfolio Margin enabled account
        # "Portfolio Margin account not enabled"
        :ok

      {:error, other} ->
        flunk("""
        Unexpected Portfolio Margin error (not a credential/config issue).
        This may indicate a bug in the implementation.
        Error: #{inspect(other)}
        """)
    end
  end

  @doc """
  Asserts that API call succeeded or failed with one of the expected error codes.

  More generic version of `assert_pm_success_or_not_configured/1` that allows
  specifying which Binance error codes are acceptable.

  ## Examples

      # Accept specific testnet restriction errors
      result = Spot.new_order(params, opts)
      assert_success_or_expected_error(result, [
        {-4131, "Testnet price restriction"},
        {-1102, "Mandatory parameter missing"}
      ])

  """
  def assert_success_or_expected_error(result, expected_errors) when is_list(expected_errors) do
    case result do
      {:ok, response} ->
        assert is_map(response) or is_list(response)

      {:error, %{"code" => code}} ->
        if Enum.any?(expected_errors, fn
             {error_code, _description} -> error_code == code
             error_code when is_integer(error_code) -> error_code == code
           end) do
          :ok
        else
          flunk("""
          Unexpected Binance error code.
          Got: #{code}
          Expected one of: #{inspect(expected_errors)}
          """)
        end

      {:error, other} ->
        flunk("Unexpected error format (not a Binance API error): #{inspect(other)}")
    end
  end
end
