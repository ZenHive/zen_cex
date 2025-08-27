defmodule ZenCex.TestHelpers do
  @moduledoc """
  Common helper functions for tests.
  """

  @doc """
  Clears the persistent_term cache for environment detection.

  This is useful in tests when simulating environment changes
  without restarting the application.

  ## When to Use
  - During development when switching between testnet/prod
  - In tests when simulating environment changes
  - Never needed in production (restart required anyway)

  ## Examples

      # Clear cache for a specific module
      TestHelpers.clear_environment_cache(Binance.Endpoints)

      # Clear cache for all exchange modules
      TestHelpers.clear_all_environment_caches()
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

  Currently supports:
  - Binance.Endpoints
  - Bybit.Endpoints (when implemented)
  - Kraken.Endpoints (when implemented)
  - Deribit.Endpoints (when implemented)
  """
  @spec clear_all_environment_caches() :: :ok
  def clear_all_environment_caches do
    # List all exchange endpoint modules that might have caches
    modules = [
      ZenCex.Adapters.Binance.Endpoints
      # Future exchanges will be added here:
      # ZenCex.Adapters.Bybit.Endpoints,
      # ZenCex.Adapters.Kraken.Endpoints,
      # ZenCex.Adapters.Deribit.Endpoints
    ]

    for module <- modules do
      if Code.ensure_loaded?(module) do
        clear_environment_cache(module)
      end
    end

    :ok
  end

  @doc """
  Helper to temporarily set environment variables in tests.

  This function is re-exported from ZenCex.IntegrationCase for convenience.
  """
  defmacro with_env(env_vars, do: block) do
    quote do
      ZenCex.IntegrationCase.with_env(unquote(env_vars), do: unquote(block))
    end
  end
end
