defmodule ZenCex.Adapters.Binance.SpotCancelAllTest do
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.Spot

  describe "cancel_all_orders/1 (auto-generated from :delete_openOrders)" do
    @tag :integration
    test "cancels all open orders for a symbol (testnet)", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret, testnet: testnet}]

      # Note: This test expects no open orders on testnet for BTCUSDT
      # In a real test scenario, you would first place orders, then cancel them
      result = Spot.cancel_all_orders(%{symbol: "BTCUSDT"}, opts)

      case result do
        {:ok, canceled_orders} ->
          # If successful, it should return an array (might be empty if no orders)
          assert is_list(canceled_orders)

          # If there were orders, verify the structure
          if length(canceled_orders) > 0 do
            first_order = hd(canceled_orders)
            assert Map.has_key?(first_order, "symbol")

            # The response can be either regular orders or OCO orders
            # Regular orders have "orderId", OCO orders have "orderListId"
            assert Map.has_key?(first_order, "orderId") or Map.has_key?(first_order, "orderListId")

            # OCO orders have different structure
            if Map.has_key?(first_order, "orderListId") do
              # OCO order structure
              assert Map.has_key?(first_order, "listOrderStatus")
              assert Map.has_key?(first_order, "contingencyType")
            else
              # Regular order structure
              assert Map.has_key?(first_order, "status")
            end
          end

        {:error, {:binance_error, -2011, _}} ->
          # Error -2011 means "Unknown order sent" which is expected if no open orders
          # This is a valid response when there are no open orders to cancel
          :ok

        {:error, %{"code" => -2011, "msg" => _}} ->
          # Raw error format also accepted - means no orders to cancel
          :ok

        {:error, reason} ->
          flunk("Unexpected error in cancel_all_orders test: #{inspect(reason)}")
      end
    end
  end
end
