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

    quote do
      use ExUnit.Case

      import ZenCex.IntegrationCase

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

    # Check credentials
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

    # Bybit testnet doesn't require API keys for public endpoints
    # For authenticated tests, would check:
    # api_key = fetch_testnet_credential!("BYBIT_TESTNET_API_KEY",
    #   "BYBIT_TESTNET_API_KEY required for authenticated tests")
    # api_secret = fetch_testnet_credential!("BYBIT_TESTNET_API_SECRET",
    #   "BYBIT_TESTNET_API_SECRET required for authenticated tests")

    # Verify connectivity to Bybit testnet
    verify_bybit_connectivity!()

    {:ok, []}
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
    # This may fail if futures isn't activated, which is OK for connectivity test
    case ZenCex.Adapters.Binance.UsdmFutures.get_positions() do
      {:ok, _} -> {:ok, :connected}
      {:error, {:exchange_error, msg}} when is_binary(msg) -> {:ok, :connected}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Helper to temporarily modify environment variables in tests.

  Useful for testing authentication errors or environment detection.

  ## Example

      with_env [{"BINANCE_TESTNET_API_KEY", "invalid"}] do
        assert {:error, _} = MyModule.authenticate()
      end
  """
  defmacro with_env(env_changes, do: block) do
    quote do
      original_env =
        Enum.map(unquote(env_changes), fn {key, _value} ->
          {key, System.get_env(key)}
        end)

      try do
        Enum.each(unquote(env_changes), fn
          {key, nil} -> System.delete_env(key)
          {key, value} -> System.put_env(key, value)
        end)

        unquote(block)
      after
        Enum.each(original_env, fn
          {key, nil} -> System.delete_env(key)
          {key, value} -> System.put_env(key, value)
        end)
      end
    end
  end
end
