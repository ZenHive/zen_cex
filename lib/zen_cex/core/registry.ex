defmodule ZenCex.Core.Registry do
  @moduledoc """
  Compile-time endpoints registry with runtime validation for exchange endpoints.

  This module provides a central registry for mapping exchange names to their
  corresponding endpoint modules. It uses compile-time configuration with
  runtime validation to avoid circular dependency issues.

  ## Supported Exchanges

  Currently supported exchanges:
  - `:binance` - Binance exchange endpoints

  ## Examples

      iex> ZenCex.Core.Registry.get_endpoints!(:binance)
      ZenCex.Adapters.Binance.Endpoints

      iex> ZenCex.Core.Registry.list_exchanges()
      [:binance]

      iex> ZenCex.Core.Registry.get_endpoints!(:unknown)
      ** (RuntimeError) Unknown exchange: unknown
  """

  @endpoints %{
    binance: ZenCex.Adapters.Binance.Endpoints
    # kraken: ZenCex.Adapters.Kraken.Endpoints,  # TODO: Implement Kraken endpoints
    # deribit: ZenCex.Adapters.Deribit.Endpoints  # TODO: Implement Deribit endpoints
  }

  # Validate at runtime on first access instead of compile time
  # This avoids circular dependency issues during compilation
  @spec ensure_endpoints_loaded!(module(), atom()) :: :ok
  defp ensure_endpoints_loaded!(module, name) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> :ok
      {:error, reason} -> raise "Endpoints #{module} for #{name} failed to load: #{reason}"
    end
  end

  @doc """
  Gets the endpoints module for the specified exchange.

  Validates that the endpoints module can be loaded at runtime to avoid
  circular dependency issues during compilation.

  ## Parameters
  - `exchange` - Exchange atom (e.g., `:binance`, `:kraken`, `:deribit`)

  ## Returns
  The endpoints module for the exchange.

  ## Raises
  - `RuntimeError` if the exchange is unknown or endpoints fail to load

  ## Examples

      iex> ZenCex.Core.Registry.get_endpoints!(:binance)
      ZenCex.Adapters.Binance.Endpoints

      iex> ZenCex.Core.Registry.get_endpoints!(:invalid)
      ** (RuntimeError) Unknown exchange: invalid
  """
  @spec get_endpoints!(atom()) :: module()
  def get_endpoints!(exchange) do
    case @endpoints[exchange] do
      nil ->
        raise "Unknown exchange: #{exchange}"

      module ->
        ensure_endpoints_loaded!(module, exchange)
        module
    end
  end

  @doc """
  DEPRECATED: Use get_endpoints!/1 instead.

  This function is kept for backward compatibility during the transition.
  """
  @spec get_adapter!(atom()) :: module()
  def get_adapter!(exchange) do
    get_endpoints!(exchange)
  end

  @doc """
  Lists all supported exchange atoms.

  ## Returns
  List of exchange atoms that have registered endpoints.

  ## Examples

      iex> ZenCex.Core.Registry.list_exchanges()
      [:binance]
  """
  @spec list_exchanges() :: [atom()]
  def list_exchanges, do: Map.keys(@endpoints)
end
