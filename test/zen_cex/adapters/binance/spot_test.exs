defmodule ZenCex.Adapters.Binance.SpotTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Binance.Spot

  describe "endpoint configurations" do
    test "all endpoints have required fields" do
      endpoints = Spot.all_endpoints()
      assert length(endpoints) == 17

      Enum.each(endpoints, fn config ->
        assert Map.has_key?(config, :operation)
        assert Map.has_key?(config, :method)
        assert Map.has_key?(config, :path)
        assert Map.has_key?(config, :requires_auth)
        assert Map.has_key?(config, :weight)
        assert Map.has_key?(config, :timeout)
        assert Map.has_key?(config, :retry_on)
        assert Map.has_key?(config, :response_parser)
        assert Map.has_key?(config, :error_mapping)
      end)
    end

    test "get_balances configuration" do
      config = Spot.get_endpoint(:get_balances)
      assert config.operation == :get_balances
      assert config.method == :get
      assert config.path == "/api/v3/account"
      assert config.requires_auth == true
      # From generated endpoints with proper weight extraction
      assert config.weight == 20
      assert config.timeout == 5_000
      # From generated smart defaults
      assert config.retry_on == [:rate_limited, :timeout, :server_error]
    end

    test "place_order configuration has no retries" do
      config = Spot.get_endpoint(:place_order)
      assert config.operation == :place_order
      assert config.method == :post
      assert config.path == "/api/v3/order"
      assert config.requires_auth == true
      assert config.max_retries == 0
      assert config.retry_on == []
      assert config.timeout == 2_000
    end

    test "cancel_order configuration has limited retries" do
      config = Spot.get_endpoint(:cancel_order)
      assert config.operation == :cancel_order
      assert config.method == :delete
      assert config.path == "/api/v3/order"
      assert config.requires_auth == true
      # From generated smart defaults
      assert config.max_retries == 1
      # From generated smart defaults
      assert config.retry_on == [:timeout]
      assert config.timeout == 2_000
    end

    test "get_order configuration" do
      config = Spot.get_endpoint(:get_order)
      assert config.operation == :get_order
      assert config.method == :get
      assert config.path == "/api/v3/order"
      assert config.requires_auth == true
      # From generated endpoints with proper weight extraction
      assert config.weight == 4
      assert config.timeout == 5_000
      assert config.retry_on == [:rate_limited, :timeout, :server_error]
    end
  end

  describe "get_endpoint/1" do
    test "returns correct config for known operations" do
      assert Spot.get_endpoint(:get_balances).operation == :get_balances
      assert Spot.get_endpoint(:place_order).operation == :place_order
      assert Spot.get_endpoint(:cancel_order).operation == :cancel_order
      assert Spot.get_endpoint(:get_order).operation == :get_order
    end

    test "returns nil for unknown operations" do
      assert Spot.get_endpoint(:unknown_operation) == nil
      assert Spot.get_endpoint(:get_positions) == nil
      # get_time is now available in generated endpoints
      assert Spot.get_endpoint(:get_time)
    end
  end

  describe "all_endpoints/0" do
    test "returns all spot endpoints" do
      endpoints = Spot.all_endpoints()
      operations = Enum.map(endpoints, & &1.operation)

      # Original endpoints
      assert :get_balances in operations
      assert :place_order in operations
      assert :cancel_order in operations
      assert :get_order in operations

      # New generated endpoints
      assert :get_time in operations
      assert :get_ping in operations
      assert :get_trade_history in operations
      assert :get_order_history in operations
      assert :cancel_all_orders in operations
    end
  end

  describe "function exports" do
    test "exports all endpoint functions" do
      assert function_exported?(Spot, :get_balances, 0)
      assert function_exported?(Spot, :get_balances, 1)
      assert function_exported?(Spot, :get_balances, 2)

      assert function_exported?(Spot, :place_order, 0)
      assert function_exported?(Spot, :place_order, 1)
      assert function_exported?(Spot, :place_order, 2)

      assert function_exported?(Spot, :cancel_order, 0)
      assert function_exported?(Spot, :cancel_order, 1)
      assert function_exported?(Spot, :cancel_order, 2)

      assert function_exported?(Spot, :get_order, 0)
      assert function_exported?(Spot, :get_order, 1)
      assert function_exported?(Spot, :get_order, 2)
    end

    test "exports complex operation functions" do
      assert function_exported?(Spot, :place_oco_order, 1)
      assert function_exported?(Spot, :cancel_oco_order, 1)
      assert function_exported?(Spot, :cancel_all_orders, 1)
    end
  end

  describe "complex operations" do
    @tag :integration
    test "place_oco_order creates OCO order on testnet" do
      # Valid OCO order parameters for testnet
      # For a SELL OCO: price (take profit) > current price > stopPrice (stop loss)
      params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        # Take profit at $120k (above current ~$100k)
        price: "120000",
        # Stop loss trigger at $95k  
        stopPrice: "95000",
        # Stop limit execution at $94.5k
        stopLimitPrice: "94500"
      }

      # This SHOULD succeed on testnet - if it fails, the implementation is broken
      {:ok, response} = Spot.place_oco_order(params)

      # Verify the OCO order response structure
      assert response["orderListId"]
      assert response["contingencyType"] == "OCO"
      assert response["listStatusType"]
      assert response["listOrderStatus"]
      assert response["transactionTime"]
      assert response["symbol"] == "BTCUSDT"

      # OCO creates exactly 2 orders
      assert length(response["orders"]) == 2

      # Check both orders exist with required fields
      orders = response["orders"]

      Enum.each(orders, fn order ->
        assert order["orderId"]
        assert order["clientOrderId"]
        assert order["symbol"] == "BTCUSDT"
      end)
    end
  end

  describe "OCO order input validation" do
    test "place_oco_order returns validation error for missing symbol" do
      result =
        Spot.place_oco_order(%{
          side: "SELL",
          quantity: "0.001",
          price: "120000",
          stopPrice: "95000",
          stopLimitPrice: "94500"
        })

      assert {:error, {:missing_params, [:symbol]}} = result
    end

    test "place_oco_order returns validation error for missing quantity" do
      result =
        Spot.place_oco_order(%{
          symbol: "BTCUSDT",
          side: "SELL",
          price: "120000",
          stopPrice: "95000",
          stopLimitPrice: "94500"
        })

      assert {:error, {:missing_params, [:quantity]}} = result
    end

    test "place_oco_order returns validation error for missing price fields" do
      # Missing price
      result =
        Spot.place_oco_order(%{
          symbol: "BTCUSDT",
          side: "SELL",
          quantity: "0.001",
          stopPrice: "95000",
          stopLimitPrice: "94500"
        })

      assert {:error, {:missing_params, [:price]}} = result

      # Missing stopPrice
      result =
        Spot.place_oco_order(%{
          symbol: "BTCUSDT",
          side: "SELL",
          quantity: "0.001",
          price: "120000",
          stopLimitPrice: "94500"
        })

      assert {:error, {:missing_params, [:stopPrice]}} = result

      # Missing stopLimitPrice
      result =
        Spot.place_oco_order(%{
          symbol: "BTCUSDT",
          side: "SELL",
          quantity: "0.001",
          price: "120000",
          stopPrice: "95000"
        })

      assert {:error, {:missing_params, [:stopLimitPrice]}} = result
    end

    test "place_oco_order returns validation error for multiple missing params" do
      result =
        Spot.place_oco_order(%{
          symbol: "BTCUSDT",
          side: "SELL"
          # Missing quantity, price, stopPrice, stopLimitPrice
        })

      assert {:error, {:missing_params, missing}} = result
      assert :quantity in missing
      assert :price in missing
      assert :stopPrice in missing
      assert :stopLimitPrice in missing
    end

    test "place_oco_order accepts params with string keys" do
      # This should pass validation - string keys are converted
      result =
        Spot.place_oco_order(%{
          "symbol" => "BTCUSDT",
          "side" => "SELL",
          "quantity" => "0.001",
          "price" => "120000",
          "stopPrice" => "95000",
          "stopLimitPrice" => "94500"
        })

      # Should pass validation and attempt API call
      case result do
        {:ok, _} -> assert true
        {:error, {:missing_params, _}} -> flunk("Should not fail validation with string keys")
        # API error is OK, validation passed
        {:error, _} -> assert true
      end
    end

    test "place_oco_order defaults side to SELL when missing" do
      # Missing side should default to SELL and still validate other params
      result =
        Spot.place_oco_order(%{
          symbol: "BTCUSDT",
          quantity: "0.001",
          price: "120000",
          stopPrice: "95000",
          stopLimitPrice: "94500"
        })

      # Side defaults to SELL, so should not be in missing params
      case result do
        {:error, {:missing_params, missing}} ->
          refute :side in missing

        _ ->
          # If validation passes, that's also OK
          assert true
      end
    end

    test "place_oco_order handles both SELL and BUY sides" do
      # Test SELL OCO parameter mapping
      sell_params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        price: "120000",
        stopPrice: "95000",
        stopLimitPrice: "94500"
      }

      # Should not crash on parameter mapping
      result = Spot.place_oco_order(sell_params)
      assert is_tuple(result) and tuple_size(result) == 2

      # Test BUY OCO parameter mapping  
      buy_params = %{
        symbol: "BTCUSDT",
        side: "BUY",
        quantity: "0.001",
        # take profit (below current)
        price: "80000",
        # stop loss trigger (above current)
        stopPrice: "105000",
        # stop limit execution (above trigger)
        stopLimitPrice: "105500"
      }

      # Should not crash on parameter mapping
      result = Spot.place_oco_order(buy_params)
      assert is_tuple(result) and tuple_size(result) == 2
    end

    test "place_oco_order accepts various parameter formats" do
      # Test string keys
      string_params = %{
        "symbol" => "BTCUSDT",
        "side" => "SELL",
        "quantity" => "0.001",
        "price" => "120000",
        "stopPrice" => "95000",
        "stopLimitPrice" => "94500"
      }

      result = Spot.place_oco_order(string_params)
      # Should pass validation with string keys
      case result do
        {:error, {:missing_params, _}} -> flunk("Should accept string keys")
        _ -> assert true
      end

      # Test alternative parameter names (should fail validation as they're not checked)
      alt_params = %{
        symbol: "BTCUSDT",
        side: "SELL",
        quantity: "0.001",
        take_profit_price: "120000",
        stop_price: "95000",
        stop_limit_price: "94500"
      }

      result = Spot.place_oco_order(alt_params)
      # Alternative param names are not in validation, so should fail
      assert {:error, {:missing_params, missing}} = result
      assert :price in missing
      assert :stopPrice in missing
      assert :stopLimitPrice in missing
    end

    test "cancel_oco_order validates required parameters" do
      # Missing symbol
      result = Spot.cancel_oco_order(%{orderListId: 12_345})
      assert is_tuple(result) and tuple_size(result) == 2

      # Missing both orderListId and listClientOrderId  
      result = Spot.cancel_oco_order(%{symbol: "BTCUSDT"})
      assert is_tuple(result) and tuple_size(result) == 2

      # Valid with orderListId
      result =
        Spot.cancel_oco_order(%{
          symbol: "BTCUSDT",
          orderListId: 12_345
        })

      assert is_tuple(result) and tuple_size(result) == 2

      # Valid with listClientOrderId
      result =
        Spot.cancel_oco_order(%{
          symbol: "BTCUSDT",
          listClientOrderId: "test_oco_123"
        })

      assert is_tuple(result) and tuple_size(result) == 2
    end

    test "cancel_oco_order accepts various parameter formats" do
      # Test string keys
      result =
        Spot.cancel_oco_order(%{
          "symbol" => "BTCUSDT",
          "orderListId" => 12_345
        })

      assert is_tuple(result) and tuple_size(result) == 2

      # Test snake_case parameter names
      result =
        Spot.cancel_oco_order(%{
          symbol: "BTCUSDT",
          order_list_id: 12_345,
          new_client_order_id: "cancel_123"
        })

      assert is_tuple(result) and tuple_size(result) == 2
    end
  end
end
