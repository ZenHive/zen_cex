defmodule ZenCex.Behaviors.AdapterTest do
  use ExUnit.Case, async: true

  defmodule TestAdapter do
    @behaviour ZenCex.Behaviors.Adapter

    @impl true
    def base_url(:prod), do: "https://api.test.com"
    def base_url(:test), do: "https://testnet.test.com"

    @impl true
    def get_positions(_params) do
      {:ok, [%{symbol: "BTCUSDT", size: 1.0}]}
    end

    @impl true
    def get_balances(_params) do
      {:ok, [%{asset: "BTC", free: 0.5, locked: 0.1}]}
    end

    @impl true
    def place_order(_symbol, _side, _type, _params) do
      {:ok, %{order_id: "12345"}}
    end

    @impl true
    def cancel_order(_order_id, _params) do
      {:ok, %{status: "cancelled"}}
    end
  end

  describe "behavior implementation" do
    test "implements required callbacks" do
      assert "https://api.test.com" == TestAdapter.base_url(:prod)
      assert "https://testnet.test.com" == TestAdapter.base_url(:test)
    end

    test "get_positions returns expected format" do
      assert {:ok, positions} = TestAdapter.get_positions(%{})
      assert [%{symbol: "BTCUSDT", size: 1.0}] = positions
    end

    test "get_balances returns expected format" do
      assert {:ok, balances} = TestAdapter.get_balances(%{})
      assert [%{asset: "BTC", free: 0.5, locked: 0.1}] = balances
    end

    test "optional callbacks work when implemented" do
      assert {:ok, %{order_id: "12345"}} = TestAdapter.place_order("BTCUSDT", :buy, :limit, %{})
      assert {:ok, %{status: "cancelled"}} = TestAdapter.cancel_order("12345", %{})
    end
  end

  describe "optional callbacks" do
    defmodule MinimalAdapter do
      @behaviour ZenCex.Behaviors.Adapter

      @impl true
      def base_url(:prod), do: "https://minimal.com"

      @impl true
      def get_positions(_), do: {:ok, []}

      @impl true
      def get_balances(_), do: {:ok, []}
    end

    test "adapter works without optional callbacks" do
      assert "https://minimal.com" == MinimalAdapter.base_url(:prod)
      assert {:ok, []} = MinimalAdapter.get_positions(%{})
      assert {:ok, []} = MinimalAdapter.get_balances(%{})
    end
  end
end
