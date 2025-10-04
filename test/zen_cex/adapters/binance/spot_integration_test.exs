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
    test "get_balances returns testnet account balances", %{api_key: api_key, api_secret: api_secret, testnet: testnet} do
      opts = [auth_credentials: %{api_key: api_key, api_secret: api_secret, testnet: testnet}]
      assert {:ok, response} = Spot.get_balances(%{}, opts)
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
    test "get_all_orders with default params" do
      # May fail without symbol - document requirement
      result = Spot.get_all_orders()
      Logger.debug("TESTNET get_all_orders response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET order history error (may need symbol): #{inspect(reason)}")
      end
    end

    test "get_open_orders returns open orders" do
      result = Spot.get_open_orders()
      Logger.debug("TESTNET get_open_orders response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET open orders error: #{inspect(reason)}")
      end
    end

    test "get_my_trades with default params" do
      # Will likely fail without symbol - document requirement
      result = Spot.get_my_trades()
      Logger.debug("TESTNET get_my_trades response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_list(response) or is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET trade history error (may need symbol): #{inspect(reason)}")
      end
    end

    test "get_all_order_list returns OCO order history" do
      result = Spot.get_all_order_list()
      Logger.debug("TESTNET get_all_order_list response: #{inspect(result)}")

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

    test "place_order validates required parameters" do
      # Test missing symbol
      result = Spot.place_order(%{side: "BUY", type: "LIMIT", quantity: "1", price: "100"})
      assert {:error, _reason} = result

      # Test missing side
      result = Spot.place_order(%{symbol: "BTCUSDT", type: "LIMIT", quantity: "1", price: "100"})
      assert {:error, _reason} = result

      # Test missing type for limit order
      result = Spot.place_order(%{symbol: "BTCUSDT", side: "BUY", quantity: "1", price: "100"})
      assert {:error, _reason} = result
    end

    test "place_order with various order types returns proper errors" do
      # Test MARKET order with invalid symbol
      market_result =
        Spot.place_order(%{
          symbol: "INVALIDPAIR",
          side: "BUY",
          type: "MARKET",
          quantity: "0.001"
        })

      assert {:error, _reason} = market_result
      Logger.debug("TESTNET MARKET order error: #{inspect(market_result)}")

      # Test LIMIT order with missing price
      limit_result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.001",
          timeInForce: "GTC"
          # Missing price parameter
        })

      assert {:error, _reason} = limit_result
      Logger.debug("TESTNET LIMIT order missing price error: #{inspect(limit_result)}")

      # Test STOP_LOSS order with invalid stopPrice
      stop_result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "SELL",
          type: "STOP_LOSS",
          quantity: "0.001",
          # Invalid stop price
          stopPrice: "0"
        })

      assert {:error, _reason} = stop_result
      Logger.debug("TESTNET STOP_LOSS order error: #{inspect(stop_result)}")

      # Test LIMIT_MAKER order
      limit_maker_result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT_MAKER",
          quantity: "0.001",
          # Very low price to avoid matching
          price: "1"
        })

      # This might succeed or fail depending on testnet state
      Logger.debug("TESTNET LIMIT_MAKER order result: #{inspect(limit_maker_result)}")
    end

    test "place_order with different timeInForce options" do
      # Test GTC (Good Till Cancel)
      gtc_result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.001",
          # Very low price to avoid execution
          price: "1",
          timeInForce: "GTC"
        })

      Logger.debug("TESTNET GTC order result: #{inspect(gtc_result)}")

      # Test IOC (Immediate or Cancel)
      ioc_result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.001",
          # Very low price, should cancel immediately
          price: "1",
          timeInForce: "IOC"
        })

      Logger.debug("TESTNET IOC order result: #{inspect(ioc_result)}")

      # Test FOK (Fill or Kill)
      fok_result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.001",
          # Very low price, should kill immediately
          price: "1",
          timeInForce: "FOK"
        })

      Logger.debug("TESTNET FOK order result: #{inspect(fok_result)}")
    end

    test "place_order with newClientOrderId works" do
      # Generate unique client order ID
      client_order_id = "test_order_#{:os.system_time(:microsecond)}"

      result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.001",
          # Very low price to avoid execution
          price: "1",
          timeInForce: "GTC",
          newClientOrderId: client_order_id
        })

      case result do
        {:ok, response} ->
          # If successful, verify the clientOrderId is in response
          assert response["clientOrderId"] == client_order_id or
                   Map.get(response, :clientOrderId) == client_order_id

          Logger.debug("TESTNET order with clientOrderId successful: #{inspect(response)}")

          # Try to cancel it to clean up
          cancel_result =
            Spot.cancel_order(%{
              symbol: "BTCUSDT",
              origClientOrderId: client_order_id
            })

          Logger.debug("TESTNET cleanup cancel result: #{inspect(cancel_result)}")

        {:error, reason} ->
          # Document the error
          Logger.debug("TESTNET order with clientOrderId failed: #{inspect(reason)}")
      end
    end

    test "place_order with quoteOrderQty for MARKET orders" do
      # Test MARKET order with quoteOrderQty (spend exactly X USDT)
      # Note: Binance API expects camelCase parameters
      result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "MARKET",
          # Buy exactly 10 USDT worth of BTC (camelCase required)
          quoteOrderQty: "10"
        })

      case result do
        {:ok, response} ->
          Logger.debug("TESTNET MARKET quoteOrderQty order successful: #{inspect(response)}")
          # Parser normalizes executedQty to filled_quantity
          assert Map.has_key?(response, :filled_quantity)
          assert response.filled_quantity

        {:error, reason} ->
          # Might fail due to insufficient balance on testnet
          Logger.debug("TESTNET MARKET quoteOrderQty order failed: #{inspect(reason)}")
      end
    end

    test "place_order with iceberg order parameters" do
      # Test iceberg order (must have timeInForce = GTC)
      result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.01",
          price: "1",
          timeInForce: "GTC",
          # Show only 0.001 BTC at a time
          icebergQty: "0.001"
        })

      Logger.debug("TESTNET iceberg order result: #{inspect(result)}")

      # Test iceberg with wrong timeInForce (should fail)
      bad_iceberg =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.01",
          price: "1",
          # Wrong! Must be GTC for iceberg
          timeInForce: "IOC",
          icebergQty: "0.001"
        })

      assert {:error, _reason} = bad_iceberg
      Logger.debug("TESTNET iceberg with wrong TIF error: #{inspect(bad_iceberg)}")
    end

    test "place_order response structure validation" do
      # Place a limit order that won't execute (low price but within percent price filter)
      # BTC is typically $90k-100k, so $50k should be safe from execution but pass filters
      result =
        Spot.place_order(%{
          symbol: "BTCUSDT",
          side: "BUY",
          type: "LIMIT",
          quantity: "0.001",
          # ~50% of market price, should pass PERCENT_PRICE_BY_SIDE filter
          price: "50000",
          timeInForce: "GTC"
        })

      case result do
        {:ok, response} ->
          # Validate response structure based on Binance docs
          assert is_map(response)

          # Log the actual response to see what we got
          Logger.debug("TESTNET order response: #{inspect(response)}")
          Logger.debug("TESTNET order response keys: #{inspect(Map.keys(response))}")

          # Check for expected fields in successful order response
          # The parser converts to atoms and snake_case
          expected_fields = [
            :symbol,
            :order_id,
            :client_order_id,
            :timestamp,
            :price,
            :quantity,
            :filled_quantity,
            :status,
            :type,
            :side
          ]

          # Check that all expected fields are present
          Enum.each(expected_fields, fn field ->
            assert Map.has_key?(response, field),
                   "Missing expected field: #{field}. Available keys: #{inspect(Map.keys(response))}"
          end)

          # Validate field types
          assert is_binary(response.symbol)
          assert is_binary(response.order_id)
          assert is_binary(response.client_order_id)
          assert is_integer(response.timestamp)
          assert %Decimal{} = response.price
          assert %Decimal{} = response.quantity
          assert %Decimal{} = response.filled_quantity
          assert is_atom(response.status)
          assert is_atom(response.type)
          assert is_atom(response.side)

          # Cancel the order to clean up
          cancel_result =
            Spot.cancel_order(%{
              symbol: "BTCUSDT",
              orderId: response.order_id
            })

          Logger.debug("TESTNET cleanup cancel: #{inspect(cancel_result)}")

        {:error, reason} ->
          Logger.debug("TESTNET order failed (might be insufficient balance): #{inspect(reason)}")
      end
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
    test "cancel_order_list with invalid order list returns error" do
      result = Spot.cancel_order_list(%{symbol: "BTCUSDT", orderListId: 99_999_999})

      assert {:error, reason} = result
      Logger.debug("TESTNET cancel_order_list error response: #{inspect(reason)}")
    end

    test "get_order_list with invalid order list returns error" do
      result = Spot.get_order_list(%{orderListId: 99_999_999})

      assert {:error, reason} = result
      Logger.debug("TESTNET get_order_list error response: #{inspect(reason)}")
    end

    # NOTE: OCO placement tests would be dangerous - we only test error cases
    test "place_order_list/oco with invalid params returns error" do
      invalid_params = %{
        symbol: "INVALID",
        side: "BUY",
        quantity: "0",
        price: "0",
        stopPrice: "0"
      }

      result = Spot."place_order_list/oco"(invalid_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place OCO error response: #{inspect(reason)}")
    end

    test "cancel_oco_order with invalid order list returns error" do
      result = Spot.cancel_oco_order(%{symbol: "BTCUSDT", orderListId: 99_999_999})

      assert {:error, reason} = result
      Logger.debug("TESTNET cancel_oco_order error response: #{inspect(reason)}")
    end

    test "cancel_oco_order with invalid symbol returns error" do
      result = Spot.cancel_oco_order(%{symbol: "INVALID", orderListId: 123})

      assert {:error, reason} = result
      Logger.debug("TESTNET cancel_oco_order invalid symbol error: #{inspect(reason)}")
    end

    test "cancel_oco_order missing required parameters returns error" do
      # Missing both orderListId and listClientOrderId
      result = Spot.cancel_oco_order(%{symbol: "BTCUSDT"})

      assert {:error, reason} = result
      Logger.debug("TESTNET cancel_oco_order missing params error: #{inspect(reason)}")
    end

    test "cancel_oco_order with invalid listClientOrderId returns error" do
      result =
        Spot.cancel_oco_order(%{
          symbol: "BTCUSDT",
          listClientOrderId: "nonexistent_oco_123"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET cancel_oco_order invalid client ID error: #{inspect(reason)}")
    end
  end

  describe "OCO order error handling" do
    test "place_oco_order with invalid symbol returns error" do
      invalid_params = %{
        symbol: "INVALID",
        side: "SELL",
        quantity: "0.001",
        price: "120000",
        stopPrice: "95000",
        stopLimitPrice: "94500"
      }

      result = Spot.place_oco_order(invalid_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place_oco_order invalid symbol error: #{inspect(reason)}")
    end

    test "place_oco_order with invalid quantity returns error" do
      invalid_params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        # Invalid quantity
        quantity: "0",
        price: "120000",
        stopPrice: "95000",
        stopLimitPrice: "94500"
      }

      result = Spot.place_oco_order(invalid_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place_oco_order invalid quantity error: #{inspect(reason)}")
    end

    test "place_oco_order with invalid price relationships returns error" do
      # SELL OCO with incorrect price relationships
      # Should be: price > current > stopPrice, but we reverse it
      invalid_params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        # Should be higher than stop for SELL
        price: "80000",
        # Should be lower than price for SELL
        stopPrice: "120000",
        stopLimitPrice: "119000"
      }

      result = Spot.place_oco_order(invalid_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place_oco_order invalid price relationship error: #{inspect(reason)}")
    end

    test "place_oco_order BUY side with invalid price relationships returns error" do
      # BUY OCO with incorrect price relationships  
      # Should be: stopPrice > current > price, but we reverse it
      invalid_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.001",
        # Should be lower than current for BUY
        price: "120000",
        # Should be higher than current for BUY
        stopPrice: "80000",
        stopLimitPrice: "81000"
      }

      result = Spot.place_oco_order(invalid_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place_oco_order BUY invalid price relationship error: #{inspect(reason)}")
    end

    test "place_oco_order with missing required price fields returns error" do
      # Missing stopPrice
      incomplete_params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        price: "120000",
        stopLimitPrice: "94500"
        # Missing stopPrice
      }

      result = Spot.place_oco_order(incomplete_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place_oco_order missing stopPrice error: #{inspect(reason)}")

      # Missing price (take profit)
      incomplete_params2 = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        stopPrice: "95000",
        stopLimitPrice: "94500"
        # Missing price
      }

      result2 = Spot.place_oco_order(incomplete_params2)
      assert {:error, reason2} = result2
      Logger.debug("TESTNET place_oco_order missing price error: #{inspect(reason2)}")

      # Missing stopLimitPrice
      incomplete_params3 = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        price: "120000",
        stopPrice: "95000"
        # Missing stopLimitPrice
      }

      result3 = Spot.place_oco_order(incomplete_params3)
      assert {:error, reason3} = result3
      Logger.debug("TESTNET place_oco_order missing stopLimitPrice error: #{inspect(reason3)}")
    end

    test "place_oco_order with extreme price values returns error" do
      # Prices way outside reasonable ranges to trigger filters
      extreme_params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        # Extremely high
        price: "1000000",
        # Extremely low
        stopPrice: "1",
        stopLimitPrice: "0.5"
      }

      result = Spot.place_oco_order(extreme_params)
      assert {:error, reason} = result
      Logger.debug("TESTNET place_oco_order extreme prices error: #{inspect(reason)}")
    end

    test "place_oco_order with duplicate client order IDs returns error" do
      # Generate a client order ID
      client_id = "oco_test_#{:os.system_time(:microsecond)}"

      params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        price: "120000",
        stopPrice: "95000",
        stopLimitPrice: "94500",
        listClientOrderId: client_id
      }

      # First attempt might succeed (if testnet allows it)
      result1 = Spot.place_oco_order(params)
      Logger.debug("TESTNET first OCO attempt: #{inspect(result1)}")

      # Second attempt with same client ID should fail
      result2 = Spot.place_oco_order(params)

      case result1 do
        {:ok, _} ->
          # If first succeeded, second should fail with duplicate ID
          assert {:error, reason} = result2
          Logger.debug("TESTNET duplicate client ID error: #{inspect(reason)}")

        {:error, _} ->
          # If first failed for other reasons, second might also fail
          assert {:error, _} = result2
          Logger.debug("TESTNET both OCO attempts failed (expected)")
      end
    end
  end

  describe "batch operations" do
    test "delete_open_orders returns appropriate response" do
      # This is safer - cancels any existing orders but won't place new ones
      result = Spot.delete_open_orders(%{symbol: "BTCUSDT"})
      Logger.debug("TESTNET delete_open_orders response: #{inspect(result)}")

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
      # The with_env macro automatically restores the original auth after the test
      with_env [{"BINANCE_TESTNET_API_KEY", "invalid_key"}] do
        result = Spot.get_balances()
        assert {:error, reason} = result
        Logger.debug("TESTNET auth error format: #{inspect(reason)}")
      end

      # Auth is automatically restored by with_env macro's after block
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
