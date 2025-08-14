defmodule ZenCex.Core.Registry do
  @moduledoc """
  Compile-time adapter registry with validation.
  """

  @adapters %{
    binance: ZenCex.Adapters.Binance.Adapter,
    kraken: ZenCex.Adapters.Kraken.Adapter,
    deribit: ZenCex.Adapters.Deribit.Adapter
  }

  # Validate at compile time
  for {name, module} <- @adapters do
    unless Code.ensure_loaded?(module) do
      raise "Adapter #{module} for #{name} not found"
    end
  end

  def get_adapter!(exchange) do
    @adapters[exchange] || raise "Unknown exchange: #{exchange}"
  end

  def list_exchanges, do: Map.keys(@adapters)
end
