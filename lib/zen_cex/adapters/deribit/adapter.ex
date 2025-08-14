defmodule ZenCex.Adapters.Deribit.Adapter do
  @moduledoc """
  Deribit exchange adapter placeholder.
  Will be fully implemented in Day 2.
  """

  # Placeholder module to satisfy Core.Registry compile-time validation
  # Full implementation coming in Day 2

  def base_url(:prod), do: "https://www.deribit.com"
  def base_url(:test), do: "https://test.deribit.com"
end
