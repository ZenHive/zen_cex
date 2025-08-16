defmodule ZenCex.Core.Registry do
  @moduledoc """
  Compile-time adapter registry with validation.
  """

  @adapters %{
    # binance: ZenCex.Adapters.Binance.Adapter,  # TODO: Implement Binance adapter
    kraken: ZenCex.Adapters.Kraken.Adapter,
    deribit: ZenCex.Adapters.Deribit.Adapter
  }

  # Validate at runtime on first access instead of compile time
  # This avoids circular dependency issues during compilation
  defp ensure_adapter_loaded!(module, name) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> :ok
      {:error, reason} -> raise "Adapter #{module} for #{name} failed to load: #{reason}"
    end
  end

  def get_adapter!(exchange) do
    case @adapters[exchange] do
      nil ->
        raise "Unknown exchange: #{exchange}"

      module ->
        ensure_adapter_loaded!(module, exchange)
        module
    end
  end

  def list_exchanges, do: Map.keys(@adapters)
end
