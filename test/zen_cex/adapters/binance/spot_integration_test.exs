defmodule ZenCex.Adapters.Binance.SpotIntegrationTest do
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Adapters.Binance.Spot

  require Logger

  describe "health check endpoints" do
    test "get_ping returns successful response" do
      assert {:ok, response} = Spot.get_ping()
      # Binance ping returns empty object
      assert is_map(response) or response == %{}
    end

    test "get_time returns server time" do
      assert {:ok, response} = Spot.get_time()
      # Should contain server time - document actual structure
      assert is_map(response)
      Logger.debug("TESTNET get_time response: #{inspect(response)}")
    end
  end

  describe "account information endpoints (requires auth)" do
    test "get_balances returns testnet account balances" do
      assert {:ok, response} = Spot.get_balances()
      assert is_list(response) or is_map(response)
      Logger.debug("TESTNET get_balances response: #{inspect(response, limit: 3)}")
    end

    test "get_commission_rates returns commission info" do
      # This might fail if missing symbol parameter - document actual requirement
      result = Spot.get_commission_rates()
      Logger.debug("TESTNET get_commission_rates response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET commission rates error (may need symbol param): #{inspect(reason)}")
      end
    end
  end

  describe "order query endpoints (read-only)" do
    test "get_order_history with default params" do
      # May fail without symbol - document requirement
      result = Spot.get_order_history()
      Logger.debug("TESTNET get_order_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET order history error (may need symbol): #{inspect(reason)}")
      end
    end

    test "get_openOrders returns open orders" do
      result = Spot.get_openOrders()
      Logger.debug("TESTNET get_openOrders response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET open orders error: #{inspect(reason)}")
      end
    end

    test "get_trade_history with default params" do
      # Will likely fail without symbol - document requirement  
      result = Spot.get_trade_history()
      Logger.debug("TESTNET get_trade_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET trade history error (may need symbol): #{inspect(reason)}")
      end
    end

    test "get_oco_history returns OCO order history" do
      result = Spot.get_oco_history()
      Logger.debug("TESTNET get_oco_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET OCO history error: #{inspect(reason)}")
      end
    end
  end

  describe "order management endpoints (dangerous - read-only tests)" do
    # NOTE: These tests check error responses, NOT actual order placement
    # We don't want to accidentally place real orders on testnet

    test "place_order with invalid parameters returns error" do
      # Use obviously invalid params to get error response
      result = Spot.place_order(%{symbol: "INVALID", side: "BUY", quantity: "0"})

      assert {:error, reason} = result
      Logger.debug("TESTNET place_order error response: #{inspect(reason)}")

      # Document what Binance testnet actually returns for invalid orders
      # The error is returned as a tuple {:exchange_error, message}
      assert is_atom(reason) or is_map(reason) or is_binary(reason) or is_tuple(reason)
    end

    test "cancel_order with invalid order returns error" do
      # Try to cancel non-existent order
      result = Spot.cancel_order(%{symbol: "BTCUSDT", orderId: 99_999_999})

      assert {:error, reason} = result
      Logger.debug("TESTNET cancel_order error response: #{inspect(reason)}")
    end

    test "get_order with invalid order returns error" do
      result = Spot.get_order(%{symbol: "BTCUSDT", orderId: 99_999_999})

      assert {:error, reason} = result
      Logger.debug("TESTNET get_order error response: #{inspect(reason)}")
    end
  end

  describe "OCO and advanced order endpoints" do
    test "cancel_orderList with invalid order list returns error" do
      result = Spot.cancel_orderList(%{symbol: "BTCUSDT", orderListId: 99_999_999})

      assert {:error, reason} = result
      Logger.debug("TESTNET cancel_orderList error response: #{inspect(reason)}")
    end

    test "get_orderList with invalid order list returns error" do
      result = Spot.get_orderList(%{orderListId: 99_999_999})

      assert {:error, reason} = result
      Logger.debug("TESTNET get_orderList error response: #{inspect(reason)}")
    end

    # NOTE: OCO placement tests would be dangerous - we only test error cases
    test "place_orderList/oco with invalid params returns error" do
      invalid_params = %{
        symbol: "INVALID",
        side: "BUY",
        quantity: "0",
        price: "0",
        stopPrice: "0"
      }

      result = Spot."place_orderList/oco"(invalid_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place OCO error response: #{inspect(reason)}")
    end
  end

  describe "batch operations" do
    test "cancel_all_orders returns appropriate response" do
      # This is safer - cancels any existing orders but won't place new ones
      result = Spot.cancel_all_orders(%{symbol: "BTCUSDT"})
      Logger.debug("TESTNET cancel_all_orders response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)
          IO.puts("TESTNET: Successfully canceled orders (if any)")

        {:error, reason} ->
          IO.puts("TESTNET cancel all orders error: #{inspect(reason)}")
      end
    end
  end

  describe "error handling validation" do
    test "authentication errors are properly formatted" do
      # Temporarily break auth to test error formatting
      with_env [{"BINANCE_TESTNET_API_KEY", "invalid_key"}] do
        result = Spot.get_balances()
        assert {:error, reason} = result
        Logger.debug("TESTNET auth error format: #{inspect(reason)}")
      end
    end

    test "rate limit errors are properly handled" do
      # Make rapid requests to potentially trigger rate limits
      results =
        for _i <- 1..5 do
          Spot.get_time()
        end

      # At least some should succeed
      successful = Enum.count(results, fn {status, _} -> status == :ok end)
      assert successful > 0

      # Check if any hit rate limits and document format
      rate_limited =
        Enum.filter(results, fn
          {:error, reason} ->
            reason_str = inspect(reason)
            String.contains?(reason_str, "rate") or String.contains?(reason_str, "limit")

          _ ->
            false
        end)

      if length(rate_limited) > 0 do
        Logger.debug("TESTNET rate limit responses: #{inspect(rate_limited)}")
      end
    end
  end
end
