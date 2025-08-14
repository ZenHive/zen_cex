defmodule ZenCex.Core.RegistryTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.Registry

  describe "get_adapter!/1" do
    test "returns adapter module for known exchanges" do
      assert Registry.get_adapter!(:binance) == ZenCex.Adapters.Binance.Adapter
      assert Registry.get_adapter!(:kraken) == ZenCex.Adapters.Kraken.Adapter
      assert Registry.get_adapter!(:deribit) == ZenCex.Adapters.Deribit.Adapter
    end

    test "raises for unknown exchange" do
      assert_raise RuntimeError, "Unknown exchange: unknown", fn ->
        Registry.get_adapter!(:unknown)
      end
    end
  end

  describe "list_exchanges/0" do
    test "returns all supported exchanges" do
      exchanges = Registry.list_exchanges()
      assert :binance in exchanges
      assert :kraken in exchanges
      assert :deribit in exchanges
      assert length(exchanges) == 3
    end
  end
end
