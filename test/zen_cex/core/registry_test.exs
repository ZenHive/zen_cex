defmodule ZenCex.Core.RegistryTest do
  use ExUnit.Case, async: true

  alias ZenCex.Core.Registry

  describe "get_endpoints!/1" do
    test "returns endpoints module for known exchanges" do
      assert Registry.get_endpoints!(:binance) == ZenCex.Adapters.Binance.Endpoints
    end

    test "raises for unknown exchange" do
      assert_raise RuntimeError, "Unknown exchange: unknown", fn ->
        Registry.get_endpoints!(:unknown)
      end
    end

    test "raises for not yet implemented exchanges" do
      assert_raise RuntimeError, "Unknown exchange: kraken", fn ->
        Registry.get_endpoints!(:kraken)
      end

      assert_raise RuntimeError, "Unknown exchange: deribit", fn ->
        Registry.get_endpoints!(:deribit)
      end
    end
  end

  describe "list_exchanges/0" do
    test "returns all supported exchanges" do
      exchanges = Registry.list_exchanges()
      assert :binance in exchanges
      assert length(exchanges) == 2
    end
  end
end
