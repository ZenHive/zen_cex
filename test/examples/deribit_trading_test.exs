defmodule ZenCex.Examples.DeribitTradingTest do
  @moduledoc """
  Tests for deribit_trading.ex examples.

  Tests use DeribitTestHelpers to get safe prices (20% away from market)
  that won't fill but stay within Deribit's price rejection limits.

  Most tests are read-only operations. Write operations (order placement)
  are tagged with @tag :write_operation and skipped by default.
  """

  use ZenCex.IntegrationCase, exchange: :deribit

  import ZenCex.DeribitTestHelpers

  alias ZenCex.Examples.DeribitTrading

  @moduletag :example

  setup context do
    client_id = context[:api_key]
    client_secret = context[:api_secret]

    # Connect and authenticate once for all tests
    {:ok, client} =
      DeribitTrading.connect_and_authenticate(
        client_id: client_id,
        client_secret: client_secret
      )

    # Get safe prices for test orders (20% away from market)
    safe_buy_price = get_safe_buy_price(client, "BTC-PERPETUAL")
    safe_sell_price = get_safe_sell_price(client, "BTC-PERPETUAL")

    {:ok,
     client: client,
     safe_buy_price: safe_buy_price,
     safe_sell_price: safe_sell_price,
     instrument: "BTC-PERPETUAL"}
  end

  describe "connection and authentication" do
    test "connect_and_authenticate/1 establishes authenticated WebSocket connection", context do
      # Use credentials from context
      assert {:ok, client} =
               DeribitTrading.connect_and_authenticate(
                 client_id: context[:api_key],
                 client_secret: context[:api_secret]
               )

      assert client.authenticated == true
      assert is_pid(client.client.server_pid)
    end
  end

  describe "order queries (read-only)" do
    test "get_open_orders/2 returns list of all open orders", context do
      # Query all open orders
      assert {:ok, orders} = DeribitTrading.get_open_orders(context[:client])
      assert is_list(orders)
    end

    test "get_open_orders/2 with instrument option filters by instrument", context do
      # Query orders for specific instrument
      assert {:ok, orders} =
               DeribitTrading.get_open_orders(context[:client], instrument: context[:instrument])

      assert is_list(orders)

      # If there are orders, they should all be for the requested instrument
      for order <- orders do
        assert order[:instrument_name] == context[:instrument]
      end
    end

    test "get_open_orders/2 with currency option filters by currency", context do
      # Query orders for BTC currency (all BTC instruments)
      assert {:ok, orders} = DeribitTrading.get_open_orders(context[:client], currency: "BTC")

      assert is_list(orders)
    end
  end

  describe "write operations (skipped by default)" do
    @tag :write_operation
    @tag :skip
    test "buy_limit/4 places limit buy order", context do
      # Use safe price (20% below market) to avoid fill
      price = context[:safe_buy_price]

      case DeribitTrading.buy_limit(context[:client], context[:instrument], 10, price) do
        {:ok, order} ->
          assert is_map(order)
          assert order[:order_state] == :open
          assert order[:direction] == :buy
          assert order[:price] == price
          assert order[:amount] == 10

          # Clean up: cancel the test order
          DeribitTrading.cancel_order(context[:client], order[:order_id])

        # Testnet may not have enough collateral
        {:error, %{"error" => %{"code" => 10_009}}} ->
          :ok

        # Not enough funds
        {:error, %{"error" => %{"code" => 10_004}}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "sell_limit/4 places limit sell order", context do
      # Use safe price (20% above market) to avoid fill
      price = context[:safe_sell_price]

      case DeribitTrading.sell_limit(context[:client], context[:instrument], 10, price) do
        {:ok, order} ->
          assert is_map(order)
          assert order[:order_state] == :open
          assert order[:direction] == :sell
          assert order[:price] == price
          assert order[:amount] == 10

          # Clean up: cancel the test order
          DeribitTrading.cancel_order(context[:client], order[:order_id])

        # Testnet may not have enough collateral
        {:error, %{"error" => %{"code" => 10_009}}} ->
          :ok

        # Not enough funds or position
        {:error, %{"error" => %{"code" => 10_004}}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "buy_market/3 places market buy order", context do
      case DeribitTrading.buy_market(context[:client], context[:instrument], 10) do
        {:ok, order} ->
          assert is_map(order)
          assert order[:direction] == :buy
          assert order[:amount] == 10
          # Market orders should fill immediately
          assert order[:order_state] == :filled

        # Testnet may not have enough collateral
        {:error, %{"error" => %{"code" => 10_009}}} ->
          :ok

        # Not enough funds
        {:error, %{"error" => %{"code" => 10_004}}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "sell_market/3 places market sell order", context do
      case DeribitTrading.sell_market(context[:client], context[:instrument], 10) do
        {:ok, order} ->
          assert is_map(order)
          assert order[:direction] == :sell
          assert order[:amount] == 10
          # Market orders should fill immediately
          assert order[:order_state] == :filled

        # Testnet may not have enough collateral
        {:error, %{"error" => %{"code" => 10_009}}} ->
          :ok

        # Not enough funds or position
        {:error, %{"error" => %{"code" => 10_004}}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    @tag :write_operation
    @tag :skip
    test "cancel_order/2 cancels an order", context do
      # First place an order to cancel
      price = context[:safe_buy_price]

      case DeribitTrading.buy_limit(context[:client], context[:instrument], 10, price) do
        {:ok, order} ->
          # Now cancel it
          assert {:ok, result} = DeribitTrading.cancel_order(context[:client], order[:order_id])
          assert result[:order_state] == :cancelled
          assert result[:order_id] == order[:order_id]

        # If we can't place the order, skip the cancel test
        {:error, _} ->
          :ok
      end
    end

    @tag :write_operation
    @tag :skip
    test "edit_order/3 edits an existing order", context do
      # First place an order to edit
      price = context[:safe_buy_price]

      case DeribitTrading.buy_limit(context[:client], context[:instrument], 10, price) do
        {:ok, order} ->
          # Edit the order (new price and amount)
          new_price = trunc(price * 0.95)
          new_amount = 20

          case DeribitTrading.edit_order(context[:client], order[:order_id], %{
                 price: new_price,
                 amount: new_amount
               }) do
            {:ok, edited} ->
              assert edited[:price] == new_price
              assert edited[:amount] == new_amount

              # Clean up
              DeribitTrading.cancel_order(context[:client], order[:order_id])

            {:error, _} ->
              # Clean up original order
              DeribitTrading.cancel_order(context[:client], order[:order_id])
              :ok
          end

        # If we can't place the order, skip the edit test
        {:error, _} ->
          :ok
      end
    end

    @tag :write_operation
    @tag :skip
    test "cancel_all_orders/2 cancels all orders for instrument", context do
      # Place a few test orders
      price = context[:safe_buy_price]

      orders =
        for _i <- 1..2 do
          case DeribitTrading.buy_limit(context[:client], context[:instrument], 10, price) do
            {:ok, order} -> order
            {:error, _} -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      if length(orders) > 0 do
        # Cancel all orders for this instrument
        assert {:ok, count} =
                 DeribitTrading.cancel_all_orders(context[:client], instrument: context[:instrument])

        assert count >= length(orders)
      else
        # If we couldn't place orders, just verify the API call works
        assert {:ok, _count} =
                 DeribitTrading.cancel_all_orders(context[:client], instrument: context[:instrument])
      end
    end
  end

  describe "error handling" do
    test "buy_limit/4 handles invalid instrument gracefully", context do
      case DeribitTrading.buy_limit(context[:client], "INVALID-INSTRUMENT", 10, 50000) do
        {:ok, _} ->
          flunk("Expected error for invalid instrument")

        {:error, _reason} ->
          :ok
      end
    end

    test "cancel_order/2 handles non-existent order_id gracefully", context do
      # Try to cancel an order that doesn't exist
      case DeribitTrading.cancel_order(context[:client], "invalid_order_id_12345") do
        {:ok, _} ->
          flunk("Expected error for non-existent order")

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "order lifecycle" do
    @tag :write_operation
    @tag :skip
    test "complete order lifecycle: place -> check -> edit -> cancel", context do
      price = context[:safe_buy_price]

      # Step 1: Place order
      case DeribitTrading.buy_limit(context[:client], context[:instrument], 10, price) do
        {:ok, order} ->
          assert order[:order_state] == :open
          order_id = order[:order_id]

          # Step 2: Check it appears in open orders
          {:ok, open_orders} =
            DeribitTrading.get_open_orders(context[:client], instrument: context[:instrument])

          assert Enum.any?(open_orders, fn o -> o[:order_id] == order_id end)

          # Step 3: Edit the order
          new_price = trunc(price * 0.95)

          case DeribitTrading.edit_order(context[:client], order_id, %{price: new_price}) do
            {:ok, edited} ->
              assert edited[:price] == new_price

            {:error, _} ->
              :ok
          end

          # Step 4: Cancel the order
          {:ok, cancelled} = DeribitTrading.cancel_order(context[:client], order_id)
          assert cancelled[:order_state] == :cancelled

        # If we can't place the order, skip the lifecycle test
        {:error, _} ->
          :ok
      end
    end
  end
end
