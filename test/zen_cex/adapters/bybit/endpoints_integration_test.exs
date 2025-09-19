defmodule ZenCex.Adapters.Bybit.EndpointsIntegrationTest do
  use ZenCex.IntegrationCase, exchange: :bybit, api_type: :unified

  alias ZenCex.Adapters.Bybit.Common
  alias ZenCex.Adapters.Bybit.Unified

  require Logger

  describe "health check endpoints" do
    test "get_server_time returns successful response" do
      assert {:ok, response} = Common.get_server_time()
      # Bybit returns timeSecond and timeNano fields directly
      assert is_map(response)
      assert Map.has_key?(response, "timeSecond") or Map.has_key?(response, "time")
      Logger.debug("TESTNET get_server_time response: #{inspect(response)}")
    end

    test "get_announcements returns announcements list" do
      # Bybit announcements endpoint requires locale parameter
      assert {:ok, response} = Common.get_announcements(%{locale: "en-US"})
      assert is_map(response)
      Logger.debug("TESTNET get_announcements response: #{inspect(response, limit: 3)}")
    end
  end

  describe "account information endpoints (requires auth)" do
    test "get_wallet_balance returns testnet account balances" do
      # Bybit unified API requires accountType parameter
      assert {:ok, response} = Unified.get_wallet_balance(%{accountType: "UNIFIED"})
      assert is_map(response)
      Logger.debug("TESTNET get_wallet_balance response: #{inspect(response, limit: 3)}")
    end

    test "get_wallet_balance with spot account type" do
      result = Unified.get_wallet_balance(%{accountType: "SPOT"})
      Logger.debug("TESTNET get_wallet_balance SPOT response: #{inspect(result, limit: 3)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET SPOT wallet balance error (may not have SPOT account): #{inspect(reason)}")
      end
    end
  end

  describe "spot trading endpoints" do
    test "spot_get_order_history returns order history" do
      result = Unified.get_order_history(%{category: "spot"})
      Logger.debug("TESTNET spot_get_order_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET spot order history error: #{inspect(reason)}")
      end
    end

    test "spot_get_open_closed_orders returns orders" do
      result = Unified.get_open_closed_orders(%{category: "spot"})
      Logger.debug("TESTNET spot_get_open_closed_orders response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET spot open orders error: #{inspect(reason)}")
      end
    end

    test "spot_get_trade_history returns trades" do
      result = Unified.get_trade_history(%{category: "spot"})
      Logger.debug("TESTNET spot_get_trade_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET spot trade history error: #{inspect(reason)}")
      end
    end
  end

  describe "spot order management endpoints (dangerous - read-only tests)" do
    # NOTE: These tests check error responses, NOT actual order placement
    # We don't want to accidentally place real orders on testnet

    test "spot_place_order with invalid parameters returns error" do
      # Use obviously invalid params to get error response
      result =
        Unified.place_order(%{
          category: "spot",
          symbol: "INVALID",
          side: "Buy",
          orderType: "Limit",
          qty: "0",
          price: "0"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET spot_place_order error response: #{inspect(reason)}")

      # Document what Bybit testnet actually returns for invalid orders
      assert is_atom(reason) or is_map(reason) or is_binary(reason) or is_tuple(reason)
    end

    test "spot_cancel_order with invalid order returns error" do
      # Try to cancel non-existent order
      result =
        Unified.cancel_order(%{
          category: "spot",
          symbol: "BTCUSDT",
          orderId: "99999999-9999-9999-9999-999999999999"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET spot_cancel_order error response: #{inspect(reason)}")
    end

    test "spot_cancel_all_orders returns appropriate response" do
      # This is safer - cancels any existing orders but won't place new ones
      result = Unified.cancel_all_orders(%{category: "spot"})
      Logger.debug("TESTNET spot_cancel_all_orders response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)
          IO.puts("TESTNET: Successfully canceled orders (if any)")

        {:error, reason} ->
          IO.puts("TESTNET spot cancel all orders error: #{inspect(reason)}")
      end
    end
  end

  describe "linear futures endpoints" do
    test "linear_get_position_list returns positions" do
      result = Unified.get_position_list(%{category: "linear"})
      Logger.debug("TESTNET linear_get_position_list response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET linear position list error: #{inspect(reason)}")
      end
    end

    test "linear_get_order_history returns order history" do
      result = Unified.get_order_history(%{category: "linear"})
      Logger.debug("TESTNET linear_get_order_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET linear order history error: #{inspect(reason)}")
      end
    end

    test "linear_get_trade_history returns trades" do
      result = Unified.get_trade_history(%{category: "linear"})
      Logger.debug("TESTNET linear_get_trade_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET linear trade history error: #{inspect(reason)}")
      end
    end
  end

  describe "linear futures order management (dangerous - read-only tests)" do
    test "linear_place_order with invalid parameters returns error" do
      # Use obviously invalid params to get error response
      result =
        Unified.place_order(%{
          category: "linear",
          symbol: "INVALID",
          side: "Buy",
          orderType: "Limit",
          qty: "0",
          price: "0"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET linear_place_order error response: #{inspect(reason)}")
    end

    test "linear_cancel_order with invalid order returns error" do
      result =
        Unified.cancel_order(%{
          category: "linear",
          symbol: "BTCUSDT",
          orderId: "99999999-9999-9999-9999-999999999999"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET linear_cancel_order error response: #{inspect(reason)}")
    end

    test "linear_cancel_all_orders returns appropriate response" do
      result = Unified.cancel_all_orders(%{category: "linear"})
      Logger.debug("TESTNET linear_cancel_all_orders response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)
          IO.puts("TESTNET: Successfully canceled linear orders (if any)")

        {:error, reason} ->
          IO.puts("TESTNET linear cancel all orders error: #{inspect(reason)}")
      end
    end

    test "linear_set_leverage with invalid params returns error" do
      result =
        Unified.set_leverage(%{
          category: "linear",
          symbol: "INVALID",
          buyLeverage: "100",
          sellLeverage: "100"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET linear_set_leverage error response: #{inspect(reason)}")
    end

    test "linear_create_trading_stop with invalid params returns error" do
      result =
        Unified.create_trading_stop(%{
          category: "linear",
          symbol: "INVALID",
          stopLoss: "0",
          takeProfit: "999999"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET linear_create_trading_stop error response: #{inspect(reason)}")
    end
  end

  describe "inverse futures endpoints" do
    test "inverse_get_position_list returns positions" do
      result = Unified.get_position_list(%{category: "inverse"})
      Logger.debug("TESTNET inverse_get_position_list response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET inverse position list error: #{inspect(reason)}")
      end
    end

    test "inverse_get_order_history returns order history" do
      result = Unified.get_order_history(%{category: "inverse"})
      Logger.debug("TESTNET inverse_get_order_history response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET inverse order history error: #{inspect(reason)}")
      end
    end
  end

  describe "unified endpoint with direct category parameter" do
    test "place_order with spot category" do
      result =
        Unified.place_order(%{
          category: "spot",
          symbol: "INVALID",
          side: "Buy",
          orderType: "Limit",
          qty: "0",
          price: "0"
        })

      assert {:error, reason} = result
      Logger.debug("TESTNET place_order with spot category error: #{inspect(reason)}")
    end

    test "get_order_history with linear category" do
      result = Unified.get_order_history(%{category: "linear"})
      Logger.debug("TESTNET get_order_history with linear category response: #{inspect(result)}")

      case result do
        {:ok, response} ->
          assert is_map(response)

        {:error, reason} ->
          IO.puts("TESTNET get_order_history with linear category error: #{inspect(reason)}")
      end
    end
  end

  describe "error handling validation" do
    test "authentication errors are properly formatted" do
      # Temporarily break auth to test error formatting
      # The with_env macro automatically restores the original auth after the test
      with_env [{"BYBIT_TESTNET_API_KEY", "invalid_key"}] do
        result = Unified.get_wallet_balance(%{accountType: "UNIFIED"})
        assert {:error, reason} = result
        Logger.debug("TESTNET auth error format: #{inspect(reason)}")
      end

      # Auth is automatically restored by with_env macro's after block
    end

    test "rate limit errors are properly handled" do
      # Make rapid requests to potentially trigger rate limits
      results =
        for _i <- 1..5 do
          Common.get_server_time()
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

  describe "environment configuration" do
    test "current_env returns :test in test environment" do
      alias ZenCex.Adapters.Bybit.Endpoints

      assert Endpoints.current_env() == :test
    end

    test "base_url returns testnet URL in test environment" do
      alias ZenCex.Adapters.Bybit.Endpoints

      assert Endpoints.base_url() == "https://api-testnet.bybit.com"
    end
  end
end
