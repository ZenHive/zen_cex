defmodule ZenCex.Adapters.Binance.Adapter do
  @moduledoc """
  Binance exchange adapter placeholder.
  Will be fully implemented in Task 1.4.
  """

  # Placeholder module to satisfy Core.Registry compile-time validation
  # Full implementation coming in next task

  def base_url(:prod), do: "https://api.binance.com"
  def base_url(:test), do: "https://testnet.binance.vision"
end
