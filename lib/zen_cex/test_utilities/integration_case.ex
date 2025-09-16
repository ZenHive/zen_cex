defmodule ZenCex.TestUtilities.IntegrationCase do
  @moduledoc """
  Test case template for integration tests that require testnet/sandbox API connections.

  This is the public version of the integration test case for use by external applications
  that depend on ZenCex. It provides the same functionality as the internal test case
  but is exposed as part of the library's public API.

  ## Usage in External Applications

  Add ZenCex test utilities to your test dependencies in `mix.exs`:

      def deps do
        [
          {:zen_cex, "~> 0.1.0", only: [:dev, :test]}
        ]
      end

  Then use the integration case in your tests:

      defmodule MyApp.BinanceIntegrationTest do
        use ZenCex.TestUtilities.IntegrationCase, exchange: :binance, api_type: :spot

        test "fetches balances from Binance testnet" do
          {:ok, balances} = ZenCex.Adapters.Binance.Spot.get_balances()
          assert is_list(balances)
        end
      end

  ## Features

  - Enforces testnet/sandbox usage (prevents production API calls)
  - Validates credentials are configured
  - Provides consistent error messages
  - Ensures tests fail loudly without proper setup
  - Provides `with_env` macro for environment variable manipulation

  ## Options

  - `:exchange` - The exchange to test (`:binance`, `:bybit`, `:kraken`, `:deribit`)
  - `:api_type` - For exchanges with multiple APIs (e.g., `:spot`, `:futures`, `:usdm_futures`)

  ## Environment Variables

  Each exchange requires specific testnet credentials:

  ### Binance
  - `BINANCE_TESTNET_API_KEY` - Spot/Margin testnet API key
  - `BINANCE_TESTNET_API_SECRET` - Spot/Margin testnet API secret
  - `BINANCE_FUTURES_TEST_API_KEY` - Futures testnet API key
  - `BINANCE_FUTURES_TEST_API_SECRET` - Futures testnet API secret
  - `BINANCE_TESTNET=true` - Enable testnet mode

  ### Bybit
  - `BYBIT_TESTNET_API_KEY` - Testnet API key
  - `BYBIT_TESTNET_API_SECRET` - Testnet API secret
  - `BYBIT_TESTNET=true` - Enable testnet mode
  """

  use ExUnit.CaseTemplate

  alias ZenCex.Adapters.Binance.Spot

  using options do
    exchange = Keyword.fetch!(options, :exchange)
    api_type = Keyword.get(options, :api_type)

    quote do
      use ExUnit.Case

      import ZenCex.TestUtilities.EnvHelpers

      # Import the public version of the integration case
      import ZenCex.TestUtilities.IntegrationCase

      # Import the env helpers for with_env macro
      @moduletag :integration
      @moduletag unquote(exchange)
      if unquote(api_type), do: @moduletag(unquote(api_type))

      setup_all do
        unquote(__MODULE__).enforce_testnet!(unquote(exchange), unquote(api_type))
      end
    end
  end

  @doc """
  Enforces testnet usage for the given exchange and validates credentials.

  This function:
  1. Verifies the exchange is configured for testnet/sandbox mode
  2. Checks that testnet URLs are being used
  3. Validates required credentials are present
  4. Tests basic connectivity to the testnet

  Raises an error if any validation fails, ensuring tests don't accidentally
  run against production APIs or hide missing configuration.

  ## Examples

      # In your test setup
      setup_all do
        ZenCex.TestUtilities.IntegrationCase.enforce_testnet!(:binance, :spot)
      end

      # Or use the macro
      use ZenCex.TestUtilities.IntegrationCase, exchange: :binance, api_type: :spot
  """
  @spec enforce_testnet!(atom(), atom() | nil) :: {:ok, keyword()}
  def enforce_testnet!(exchange, api_type \\ nil) do
    case exchange do
      :binance -> enforce_binance_testnet!(api_type)
      :bybit -> enforce_bybit_testnet!(api_type)
      :kraken -> enforce_kraken_testnet!(api_type)
      :deribit -> enforce_deribit_testnet!(api_type)
      _ -> raise "Unknown exchange: #{exchange}"
    end
  end

  # Binance testnet enforcement
  defp enforce_binance_testnet!(api_type) do
    alias ZenCex.Adapters.Binance.Endpoints

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

    # Check credentials - use futures testnet for futures operations
    {api_key, api_secret} =
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

    # Test connectivity (skip for portfolio - no testnet)
    if api_type != :portfolio do
      verify_binance_connectivity!(api_type)
    end

    {:ok, api_key: api_key, api_secret: api_secret, exchange: :binance}
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
    ZenCex.Adapters.Binance.Endpoints.base_url()
  end

  defp get_binance_base_url(api_type) do
    case ZenCex.Adapters.Binance.Endpoints.base_url(:test, api_type) do
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
    actual_url = Endpoints.base_url()
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

    {:ok, api_key: api_key, api_secret: api_secret, exchange: :bybit}
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

  # Verify connectivity to Binance testnet
  defp verify_binance_connectivity!(api_type) do
    api_type
    |> get_connectivity_test_result()
    |> handle_connectivity_result(api_type)
  end

  defp get_connectivity_test_result(api_type) do
    cond do
      api_type in [nil, :spot] -> Spot.get_ping()
      api_type in [:futures, :usdm_futures, :coinm_futures] -> verify_futures_connectivity()
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

  defp verify_futures_connectivity do
    # USD-M Futures connectivity check - try to get positions
    # Use futures-specific credentials if available, fall back to spot testnet
    futures_key = System.get_env("BINANCE_FUTURES_TEST_API_KEY")
    futures_secret = System.get_env("BINANCE_FUTURES_TEST_API_SECRET")

    opts =
      if futures_key && futures_secret do
        %{auth_credentials: %{api_key: futures_key, api_secret: futures_secret}}
      else
        %{}
      end

    # This may fail if futures isn't activated, which is OK for connectivity test
    case ZenCex.Adapters.Binance.UsdmFutures.get_positions(%{}, opts) do
      {:ok, _} -> {:ok, :connected}
      {:error, {:binance_error, _code, _msg}} -> {:ok, :connected}
      {:error, {:exchange_error, msg}} when is_binary(msg) -> {:ok, :connected}
      {:error, reason} -> {:error, reason}
    end
  end
end
