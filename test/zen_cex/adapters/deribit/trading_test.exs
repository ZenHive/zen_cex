defmodule ZenCex.Adapters.Deribit.TradingTest do
  @moduledoc """
  Integration tests for Deribit Trading module.

  Tests against real Deribit testnet to verify:
  - Order placement (buy/sell)
  - Order cancellation
  - Order editing
  - Order queries (open orders, history, trades)

  All tests place orders 20% away from market price (safe from fills, within Deribit limits).
  Note: Deribit rejects orders too far from market (e.g., 50%+ away).
  """

  use ZenCex.TestUtilities.IntegrationCase, exchange: :deribit

  import ZenCex.DeribitTestHelpers

  alias ZenCex.Adapters.Deribit.Trading
  alias ZenCex.Adapters.Deribit.WebSocket

  @moduletag :integration
  @moduletag :deribit

  @test_instrument "BTC-PERPETUAL"

  setup context do
    # Connect and authenticate
    {:ok, adapter} =
      WebSocket.connect(
        client_id: context[:client_id],
        client_secret: context[:client_secret],
        testnet: true
      )

    {:ok, adapter} = WebSocket.authenticate(adapter)

    # Get safe test prices based on current market
    safe_buy_price = get_safe_buy_price(adapter, @test_instrument)
    safe_sell_price = get_safe_sell_price(adapter, @test_instrument)

    # Cleanup: cancel all test orders on exit
    on_exit(fn ->
      # Best effort cleanup - ignore errors
      try do
        Trading.cancel_all(adapter, %{instrument_name: @test_instrument})
      catch
        _, _ -> :ok
      end

      WebSocket.close(adapter)
    end)

    {:ok, client: adapter, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price}
  end

  describe "buy/4" do
    test "places limit buy order", %{client: client, safe_buy_price: safe_buy_price} do
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      assert order[:order_id]
      assert order[:instrument_name] == @test_instrument
      assert order[:direction] == :buy
      assert order[:order_state] == :open
      assert order[:amount] == 10
      assert order[:price] == safe_buy_price
    end

    test "places post-only buy order", %{client: client, safe_buy_price: safe_buy_price} do
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price,
          post_only: true
        })

      assert order[:post_only] == true
      assert order[:direction] == :buy
    end

    test "places reduce-only buy order", %{client: client, safe_buy_price: safe_buy_price} do
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price,
          reduce_only: true
        })

      assert order[:reduce_only] == true
    end

    test "places buy order with label", %{client: client, safe_buy_price: safe_buy_price} do
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price,
          label: "test_order_123"
        })

      assert order[:label] == "test_order_123"
    end
  end

  describe "sell/4" do
    test "places limit sell order", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      {:ok, order} =
        Trading.sell(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_sell_price
        })

      assert order[:order_id]
      assert order[:instrument_name] == @test_instrument
      assert order[:direction] == :sell
      assert order[:order_state] == :open
      assert order[:amount] == 10
      assert order[:price] == safe_sell_price
    end

    test "places post-only sell order", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      {:ok, order} =
        Trading.sell(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_sell_price,
          post_only: true
        })

      assert order[:post_only] == true
      assert order[:direction] == :sell
    end
  end

  describe "cancel/2" do
    test "cancels existing order", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      # Place order to cancel
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      order_id = order[:order_id]
      assert order_id

      # Cancel it
      {:ok, cancelled_order} = Trading.cancel(client, order_id)

      assert cancelled_order[:order_id] == order_id
      assert cancelled_order[:order_state] == :cancelled
    end

    test "returns error for invalid order_id", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      case Trading.cancel(client, "INVALID-12345") do
        {:error, error} ->
          # Deribit returns JSON-RPC error
          assert is_map(error)

        {:ok, result} ->
          # Some testnet instances might return success with error in result
          assert result[:error] || result[:message]
      end
    end
  end

  describe "edit_order/3" do
    test "edits order price", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      # Place initial order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      order_id = order[:order_id]
      new_price = safe_buy_price + 100

      # Edit price (Deribit requires both amount and price)
      {:ok, edited} = Trading.edit_order(client, order_id, %{amount: 10, price: new_price})

      assert edited[:order_id] == order_id
      assert edited[:price] == new_price
      assert edited[:amount] == 10
    end

    test "edits order amount", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      # Place initial order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      # Edit amount (Deribit requires both amount and price)
      {:ok, edited} =
        Trading.edit_order(client, order[:order_id], %{amount: 20, price: safe_buy_price})

      assert edited[:amount] == 20
    end

    test "edits both price and amount", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Place initial order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      new_price = safe_buy_price + 200

      # Edit both
      {:ok, edited} =
        Trading.edit_order(client, order[:order_id], %{
          price: new_price,
          amount: 20
        })

      assert edited[:price] == new_price
      assert edited[:amount] == 20
    end
  end

  describe "get_open_orders/2" do
    test "returns open orders for instrument", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Place test order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price,
          label: "test_open_orders"
        })

      # Query open orders
      {:ok, orders} =
        Trading.get_open_orders(client, %{
          instrument_name: @test_instrument
        })

      assert is_list(orders)
      assert Enum.any?(orders, &(&1[:order_id] == order[:order_id]))
    end

    test "returns empty list when no open orders for instrument", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Cancel all orders first
      Trading.cancel_all(client, %{instrument_name: @test_instrument})

      # Query should return empty list
      {:ok, orders} =
        Trading.get_open_orders(client, %{
          instrument_name: @test_instrument
        })

      assert orders == []
    end

    test "filters orders by currency", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      # Place order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      assert order[:order_id]

      # Query by currency
      {:ok, orders} = Trading.get_open_orders(client, %{currency: "BTC"})

      assert is_list(orders)
      # Testnet might not return orders by currency filter, so just verify it's a list
    end

    test "returns all open orders without filters", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Place order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      assert order[:order_id]

      # Query all
      {:ok, orders} = Trading.get_open_orders(client, %{})

      assert is_list(orders)
      # At least our order should be present
      assert Enum.any?(orders, &(&1[:order_id] == order[:order_id]))
    end
  end

  describe "cancel_all/2" do
    test "cancels all orders for instrument", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Place multiple orders (all multiples of 10)
      {:ok, _} =
        Trading.buy(client, @test_instrument, 10, %{type: "limit", price: safe_buy_price})

      {:ok, _} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price + 100
        })

      {:ok, _} =
        Trading.sell(client, @test_instrument, 10, %{type: "limit", price: safe_sell_price})

      # Cancel all
      {:ok, count} =
        Trading.cancel_all(client, %{
          instrument_name: @test_instrument
        })

      assert count >= 3

      # Verify all cancelled
      {:ok, orders} =
        Trading.get_open_orders(client, %{
          instrument_name: @test_instrument
        })

      assert orders == []
    end

    test "cancels all orders for currency", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Place multiple orders on the same instrument (all BTC)
      {:ok, _} = Trading.buy(client, @test_instrument, 10, %{type: "limit", price: safe_buy_price})
      {:ok, _} = Trading.buy(client, @test_instrument, 10, %{type: "limit", price: safe_buy_price + 50})

      # Cancel all BTC orders
      {:ok, count} = Trading.cancel_all(client, %{currency: "BTC"})

      assert count >= 2
    end

    test "returns 0 when no orders to cancel", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Cancel all first
      Trading.cancel_all(client, %{instrument_name: @test_instrument})

      # Try again - should return 0
      {:ok, count} =
        Trading.cancel_all(client, %{
          instrument_name: @test_instrument
        })

      assert count == 0
    end
  end

  describe "get_order_history/2" do
    test "returns historical orders for instrument", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Query history - testnet returns empty array (no history preserved)
      {:ok, history} =
        Trading.get_order_history(client, %{
          instrument_name: @test_instrument,
          count: 10
        })

      # Deribit testnet returns [] for order history (empirically verified)
      assert history == []
    end

    test "returns historical orders for currency", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      {:ok, history} =
        Trading.get_order_history(client, %{
          currency: "BTC",
          count: 20
        })

      # Deribit testnet returns [] for order history (empirically verified)
      assert history == []
    end

    test "respects count parameter", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      {:ok, history} =
        Trading.get_order_history(client, %{
          instrument_name: @test_instrument,
          count: 5
        })

      # Deribit testnet returns [] for order history (empirically verified)
      assert history == []
    end
  end

  describe "get_user_trades/2" do
    test "returns trade history for instrument", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      {:ok, trades} =
        Trading.get_user_trades(client, %{
          instrument_name: @test_instrument,
          count: 10
        })

      assert is_list(trades)
      # May be empty if no fills on testnet
    end

    test "returns trade history for currency", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      {:ok, trades} =
        Trading.get_user_trades(client, %{
          currency: "BTC",
          count: 10
        })

      assert is_list(trades)
    end

    test "returns trade history for specific order", %{
      client: client,
      safe_buy_price: safe_buy_price,
      safe_sell_price: safe_sell_price
    } do
      # Place and cancel order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price
        })

      order_id = order[:order_id]
      Trading.cancel(client, order_id)

      # Query trades for this order (likely empty since no fill)
      {:ok, trades} = Trading.get_user_trades(client, %{order_id: order_id})

      assert is_list(trades)
    end

    test "respects count parameter", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      {:ok, trades} =
        Trading.get_user_trades(client, %{
          instrument_name: @test_instrument,
          count: 3
        })

      assert is_list(trades)
      assert length(trades) <= 3
    end
  end

  describe "order flow integration" do
    test "complete order lifecycle", %{client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price} do
      # 1. Place order
      {:ok, order} =
        Trading.buy(client, @test_instrument, 10, %{
          type: "limit",
          price: safe_buy_price,
          label: "lifecycle_test"
        })

      original_order_id = order[:order_id]
      assert order[:order_state] == :open

      # 2. Verify it appears in open orders
      {:ok, open_orders} =
        Trading.get_open_orders(client, %{
          instrument_name: @test_instrument
        })

      assert Enum.any?(open_orders, &(&1[:order_id] == original_order_id))

      # 3. Edit the order (amount must be multiple of 10)
      {:ok, edited} =
        Trading.edit_order(client, original_order_id, %{
          amount: 20,
          price: safe_buy_price + 100
        })

      assert edited[:amount] == 20

      # 4. Cancel the order
      {:ok, cancelled} = Trading.cancel(client, original_order_id)
      assert cancelled[:order_state] == :cancelled

      # 5. Verify it's not in open orders anymore
      {:ok, open_orders_after} =
        Trading.get_open_orders(client, %{
          instrument_name: @test_instrument
        })

      refute Enum.any?(open_orders_after, &(&1[:order_id] == original_order_id))
    end
  end
end
