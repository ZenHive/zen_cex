defmodule ZenCex.Core.Registry do
  @moduledoc """
  Compile-time adapter registry with runtime validation for exchange adapters.

  This module provides a central registry for mapping exchange names to their
  corresponding adapter modules. It uses compile-time configuration with
  runtime validation to avoid circular dependency issues.

  ## Supported Exchanges

  Currently supported exchanges:
  - `:kraken` - Kraken exchange adapter
  - `:deribit` - Deribit exchange adapter

  ## Examples

      iex> ZenCex.Core.Registry.get_adapter!(:kraken)
      ZenCex.Adapters.Kraken.Adapter

      iex> ZenCex.Core.Registry.list_exchanges()
      [:kraken, :deribit]

      iex> ZenCex.Core.Registry.get_adapter!(:unknown)
      ** (RuntimeError) Unknown exchange: unknown
  """

  @adapters %{
    # binance: ZenCex.Adapters.Binance.Adapter,  # TODO: Implement Binance adapter
    kraken: ZenCex.Adapters.Kraken.Adapter,
    deribit: ZenCex.Adapters.Deribit.Adapter
  }

  # Validate at runtime on first access instead of compile time
  # This avoids circular dependency issues during compilation
  @spec ensure_adapter_loaded!(module(), atom()) :: :ok
  defp ensure_adapter_loaded!(module, name) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> :ok
      {:error, reason} -> raise "Adapter #{module} for #{name} failed to load: #{reason}"
    end
  end

  @doc """
  Gets the adapter module for the specified exchange.

  Validates that the adapter module can be loaded at runtime to avoid
  circular dependency issues during compilation.

  ## Parameters
  - `exchange` - Exchange atom (e.g., `:kraken`, `:deribit`)

  ## Returns
  The adapter module for the exchange.

  ## Raises
  - `RuntimeError` if the exchange is unknown or adapter fails to load

  ## Examples

      iex> ZenCex.Core.Registry.get_adapter!(:kraken)
      ZenCex.Adapters.Kraken.Adapter

      iex> ZenCex.Core.Registry.get_adapter!(:invalid)
      ** (RuntimeError) Unknown exchange: invalid
  """
  @spec get_adapter!(atom()) :: module()
  def get_adapter!(exchange) do
    case @adapters[exchange] do
      nil ->
        raise "Unknown exchange: #{exchange}"

      module ->
        ensure_adapter_loaded!(module, exchange)
        module
    end
  end

  @doc """
  Lists all supported exchange atoms.

  ## Returns
  List of exchange atoms that have registered adapters.

  ## Examples

      iex> ZenCex.Core.Registry.list_exchanges()
      [:kraken, :deribit]
  """
  @spec list_exchanges() :: [atom()]
  def list_exchanges, do: Map.keys(@adapters)
end
