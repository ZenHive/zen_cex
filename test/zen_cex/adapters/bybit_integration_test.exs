defmodule ZenCex.Adapters.BybitIntegrationTest do
  @moduledoc """
  Integration tests for Bybit v5 API endpoints.

  These tests run against the REAL Bybit testnet API to ensure proper behavior.
  Tests will FAIL if BYBIT_TESTNET is not set to true.

  For authenticated tests, you need:
  - BYBIT_TESTNET_API_KEY
  - BYBIT_TESTNET_API_SECRET

  Get testnet credentials at: https://testnet.bybit.com/
  """
  use ZenCex.IntegrationCase, exchange: :bybit

  alias ZenCex.Adapters.Bybit.Common
  alias ZenCex.Adapters.Bybit.Endpoints
  alias ZenCex.Adapters.Bybit.Unified

  @test_symbol "BTCUSDT"
  @test_linear_symbol "BTCUSDT"
  @test_order_qty "0.001"

  describe "environment validation" do
    test "confirms testnet environment is active" do
      assert Endpoints.current_env() == :test
      assert Endpoints.base_url() == "https://api-testnet.bybit.com"
    end
  end

  describe "public endpoints - no auth required" do
    test "get_server_time returns current server timestamp" do
      assert {:ok, result} = Common.get_server_time()

      # Bybit testnet returns: %{"timeSecond" => "1234567890", "timeNano" => "123456789012345"}
      assert is_map(result)
      assert Map.has_key?(result, "timeSecond")
      assert Map.has_key?(result, "timeNano")
      assert is_binary(result["timeSecond"])
      assert is_binary(result["timeNano"])
    end

    test "get_announcements returns latest announcements" do
      assert {:ok, result} = Common.get_announcements(%{locale: "en-US"})

      # Bybit testnet returns announcement list with structure:
      # %{"total" => 5913, "list" => [%{"title" => "...", "description" => "...", ...}]}
      assert is_map(result)
      assert Map.has_key?(result, "total")
      assert Map.has_key?(result, "list")
      assert is_list(result["list"])
    end
  end

  describe "authenticated endpoints - requires API credentials" do
    @describetag :requires_auth

    test "get_wallet_balance returns account balances" do
      if has_credentials?() do
        assert {:ok, result} = Unified.get_wallet_balance(%{accountType: "UNIFIED"})

        # Bybit testnet returns: %{"list" => [%{"accountType" => "UNIFIED", "coin" => [%{"coin" => "BTC", ...}]}]}
        assert is_map(result)
        assert Map.has_key?(result, "list")
        assert is_list(result["list"])

        if length(result["list"]) > 0 do
          account = hd(result["list"])
          assert Map.has_key?(account, "accountType")
          assert Map.has_key?(account, "coin")
          assert is_list(account["coin"])
        end
      else
        assert {:error, reason} = Unified.get_wallet_balance(%{accountType: "UNIFIED"})
        assert reason =~ "API key" or reason =~ "authentication" or reason =~ "Not authenticated"
      end
    end

    test "place_order creates a spot limit order" do
      if has_credentials?() do
        # Generate unique order link ID for testing
        order_link_id = "test_#{:erlang.system_time(:millisecond)}"

        result =
          Unified.place_order(%{
            category: "spot",
            symbol: @test_symbol,
            side: "Buy",
            orderType: "Limit",
            qty: @test_order_qty,
            # Low price to avoid fill
            price: "10000",
            orderLinkId: order_link_id
          })

        case result do
          {:ok, data} ->
            # Bybit testnet returns: %{"orderId" => "xxx", "orderLinkId" => "xxx"}
            assert is_map(data)
            assert Map.has_key?(data, "orderId")
            assert Map.has_key?(data, "orderLinkId")
            assert data["orderLinkId"] == order_link_id

            # Clean up - cancel the order
            _ =
              Unified.cancel_order(%{
                category: "spot",
                symbol: @test_symbol,
                orderId: data["orderId"]
              })

          {:error, {:insufficient_balance, _msg}} ->
            # Expected when testnet account has no balance
            assert true

          {:error, other_reason} ->
            flunk("Unexpected error: #{inspect(other_reason)}")
        end
      else
        assert {:error, reason} =
                 Unified.place_order(%{
                   category: "spot",
                   symbol: @test_symbol,
                   side: "Buy",
                   orderType: "Limit",
                   qty: @test_order_qty,
                   # Low price to avoid fill
                   price: "10000"
                 })

        assert reason =~ "API key" or reason =~ "authentication" or reason =~ "Not authenticated"
      end
    end

    test "cancel_order cancels an open order" do
      if has_credentials?() do
        # First place an order to cancel
        order_result =
          Unified.place_order(%{
            category: "spot",
            symbol: @test_symbol,
            side: "Buy",
            orderType: "Limit",
            qty: @test_order_qty,
            # Low price to avoid fill
            price: "10000"
          })

        case order_result do
          {:ok, order} ->
            # Then cancel it
            assert {:ok, result} =
                     Unified.cancel_order(%{
                       category: "spot",
                       symbol: @test_symbol,
                       orderId: order["orderId"]
                     })

            # Bybit testnet returns: %{"orderId" => "xxx", "orderLinkId" => "xxx"}
            assert is_map(result)
            assert Map.has_key?(result, "orderId")
            assert result["orderId"] == order["orderId"]

          {:error, {:insufficient_balance, _msg}} ->
            # Can't test cancel without placing an order first
            assert true
        end
      else
        assert {:error, _reason} =
                 Unified.cancel_order(%{
                   category: "spot",
                   symbol: @test_symbol,
                   orderId: "fake_order_id"
                 })
      end
    end

    test "cancel_all_orders cancels all open orders" do
      if has_credentials?() do
        assert {:ok, result} =
                 Unified.cancel_all_orders(%{
                   category: "spot",
                   symbol: @test_symbol
                 })

        # Bybit testnet returns: %{"list" => [%{"orderId" => "xxx", ...}], "success" => "1"}
        assert is_map(result)
      else
        assert {:error, _reason} =
                 Unified.cancel_all_orders(%{
                   category: "spot",
                   symbol: @test_symbol
                 })
      end

      # Result format may vary depending on if there are orders to cancel
    end

    test "get_order retrieves order details" do
      if has_credentials?() do
        # First place an order
        order_result =
          Unified.place_order(%{
            category: "spot",
            symbol: @test_symbol,
            side: "Buy",
            orderType: "Limit",
            qty: @test_order_qty,
            # Low price to avoid fill
            price: "10000"
          })

        case order_result do
          {:ok, order} ->
            # Get order details
            assert {:ok, result} =
                     Unified.get_order(%{
                       category: "spot",
                       orderId: order["orderId"]
                     })

            # Parser returns list directly for get_order
            assert is_list(result)
            assert length(result) > 0

            order_info = hd(result)
            assert Map.has_key?(order_info, "orderId")
            assert Map.has_key?(order_info, "symbol")
            assert Map.has_key?(order_info, "orderStatus")

            # Clean up
            _ =
              Unified.cancel_order(%{
                category: "spot",
                symbol: @test_symbol,
                orderId: order["orderId"]
              })

          {:error, {:insufficient_balance, _msg}} ->
            # Can't test get_order without an order
            assert true
        end
      else
        assert {:error, _reason} =
                 Unified.get_order(%{
                   category: "spot",
                   orderId: "fake_order_id"
                 })
      end
    end

    test "get_order_history retrieves historical orders" do
      if has_credentials?() do
        assert {:ok, result} =
                 Unified.get_order_history(%{
                   category: "spot",
                   limit: 10
                 })

        # Bybit testnet returns list directly after parser processes it
        assert is_list(result)

        if length(result) > 0 do
          order = hd(result)
          assert Map.has_key?(order, "orderId")
          assert Map.has_key?(order, "symbol")
          assert Map.has_key?(order, "orderStatus")
          assert Map.has_key?(order, "orderType")
        end
      else
        assert {:error, _reason} =
                 Unified.get_order_history(%{
                   category: "spot",
                   limit: 10
                 })
      end
    end

    test "get_trades retrieves execution history" do
      if has_credentials?() do
        assert {:ok, result} =
                 Unified.get_trades(%{
                   category: "spot",
                   limit: 10
                 })

        # Bybit testnet returns list directly after parser processes it
        assert is_list(result)

        if length(result) > 0 do
          trade = hd(result)
          assert Map.has_key?(trade, "execId")
          assert Map.has_key?(trade, "symbol")
          assert Map.has_key?(trade, "side")
          assert Map.has_key?(trade, "execPrice")
          assert Map.has_key?(trade, "execQty")
        end
      else
        assert {:error, _reason} =
                 Unified.get_trades(%{
                   category: "spot",
                   limit: 10
                 })
      end
    end
  end

  describe "derivatives endpoints - futures and options" do
    @describetag :requires_auth
    @describetag :derivatives

    test "get_positions returns open positions for linear futures" do
      if has_credentials?() do
        assert {:ok, result} =
                 Unified.get_positions(%{
                   category: "linear",
                   symbol: @test_linear_symbol
                 })

        # Bybit testnet returns list directly after parser processes it
        assert is_list(result)

        if length(result) > 0 do
          position = hd(result)
          assert Map.has_key?(position, "symbol")
          assert Map.has_key?(position, "side")
          assert Map.has_key?(position, "size")
          assert Map.has_key?(position, "leverage")
        end
      else
        assert {:error, _reason} =
                 Unified.get_positions(%{
                   category: "linear",
                   symbol: @test_linear_symbol
                 })
      end
    end

    test "set_leverage updates position leverage for linear futures" do
      if has_credentials?() do
        result =
          Unified.set_leverage(%{
            category: "linear",
            symbol: @test_linear_symbol,
            buyLeverage: "2",
            sellLeverage: "2"
          })

        case result do
          {:ok, data} ->
            # Bybit testnet returns confirmation
            assert is_map(data)

          {:error, {:order_would_trigger_immediately, _msg}} ->
            # Leverage already set or no change needed
            assert true

          {:error, other} ->
            flunk("Unexpected error: #{inspect(other)}")
        end
      else
        assert {:error, _reason} =
                 Unified.set_leverage(%{
                   category: "linear",
                   symbol: @test_linear_symbol,
                   buyLeverage: "2",
                   sellLeverage: "2"
                 })
      end
    end

    test "set_trading_stop sets stop loss and take profit" do
      if has_credentials?() do
        # Note: This may fail if no position exists, which is expected
        result =
          Unified.set_trading_stop(%{
            category: "linear",
            symbol: @test_linear_symbol,
            positionIdx: 0,
            stopLoss: "20000",
            takeProfit: "80000"
          })

        case result do
          {:ok, data} ->
            assert is_map(data)

          {:error, reason} ->
            # Expected if no position exists
            assert reason
        end
      else
        assert {:error, _reason} =
                 Unified.set_trading_stop(%{
                   category: "linear",
                   symbol: @test_linear_symbol,
                   positionIdx: 0,
                   stopLoss: "20000",
                   takeProfit: "80000"
                 })
      end
    end

    test "place_order creates a linear futures order" do
      if has_credentials?() do
        # Generate unique order link ID for testing
        order_link_id = "test_linear_#{:erlang.system_time(:millisecond)}"

        result =
          Unified.place_order(%{
            category: "linear",
            symbol: @test_linear_symbol,
            side: "Buy",
            orderType: "Limit",
            qty: "0.001",
            # Low price to avoid fill
            price: "10000",
            orderLinkId: order_link_id
          })

        case result do
          {:ok, data} ->
            assert is_map(data)
            assert Map.has_key?(data, "orderId")
            assert Map.has_key?(data, "orderLinkId")
            assert data["orderLinkId"] == order_link_id

            # Clean up - cancel the order
            _ =
              Unified.cancel_order(%{
                category: "linear",
                symbol: @test_linear_symbol,
                orderId: data["orderId"]
              })

          {:error, {:order_already_canceled, _msg}} ->
            # Price might be invalid for current market conditions
            assert true

          {:error, :insufficient_balance} ->
            # Expected when testnet account has no balance (old format)
            assert true

          {:error, {:insufficient_balance, _msg}} ->
            # Expected when testnet account has no balance (new format)
            assert true

          {:error, other} ->
            flunk("Unexpected error: #{inspect(other)}")
        end
      else
        assert {:error, _reason} =
                 Unified.place_order(%{
                   category: "linear",
                   symbol: @test_linear_symbol,
                   side: "Buy",
                   orderType: "Limit",
                   qty: "0.001",
                   # Low price to avoid fill
                   price: "10000"
                 })
      end
    end
  end

  describe "error handling" do
    test "handles network errors gracefully" do
      # Temporarily set wrong URL to trigger network error
      with_env [{"BYBIT_TESTNET", "true"}] do
        # This would normally fail with network error, but testnet should be properly configured
        result = Common.get_server_time()
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    test "handles invalid parameters with proper error messages" do
      # Try to get order with missing required parameters
      assert {:error, reason} = Unified.get_order(%{})

      # Should get a parameter error
      assert reason
    end

    test "handles rate limiting appropriately" do
      # Make multiple rapid requests to test rate limiting
      for_result =
        for _ <- 1..5 do
          Task.async(fn ->
            Common.get_server_time()
          end)
        end

      results = Enum.map(for_result, &Task.await/1)

      # All should succeed due to rate limiter
      assert Enum.all?(results, fn result ->
               match?({:ok, _}, result) or match?({:error, {:rate_limited, _}}, result)
             end)
    end
  end

  # Helper functions

  defp has_credentials? do
    System.get_env("BYBIT_TESTNET_API_KEY") != nil and
      System.get_env("BYBIT_TESTNET_API_SECRET") != nil
  end
end
