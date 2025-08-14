defmodule ZenCex.Adapters.Kraken.Adapter do
  @moduledoc """
  Kraken exchange adapter placeholder.
  Will be fully implemented in Day 2.
  """

  # Placeholder module to satisfy Core.Registry compile-time validation
  # Full implementation coming in Day 2

  def base_url(:prod), do: "https://api.kraken.com"
  # Kraken doesn't have a separate test API
  def base_url(:test), do: "https://api.kraken.com"
end
