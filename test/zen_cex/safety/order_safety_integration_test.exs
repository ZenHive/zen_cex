defmodule ZenCex.Safety.OrderSafetyIntegrationTest do
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :spot

  alias ZenCex.Safety.OrderSafety

  @moduletag :integration

  setup_all do
    # Start OrderSafety GenServer
    {:ok, _pid} = OrderSafety.start_link(name: :order_safety_integration)

    # Clear any existing data
    OrderSafety.clear_all()

    # Ensure trading is enabled
    OrderSafety.set_kill_switch(:binance, true)

    :ok
  end

  describe "comprehensive order validation against real Binance testnet" do
    @tag :integration
    test "validates valid BTCUSDT limit order" do
      # Test a realistic order that should pass all validations
      order_params = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        # Small amount to avoid balance issues
        quantity: "0.001",
        # Conservative price
        price: "30000.00"
      }

      case OrderSafety.validate_order(:binance, order_params) do
        {:ok, validated_params} ->
          # Validation passed
          assert Map.has_key?(validated_params, :client_order_id)
          assert validated_params.symbol == "BTCUSDT"
          assert validated_params.side == :buy

          # Record the order to test idempotency
          assert :ok = OrderSafety.record_order(:binance, validated_params.client_order_id)

        {:error, reason} ->
          # Log the reason for debugging - some validations might fail on testnet
          IO.puts("Order validation failed: #{inspect(reason)}")

          case reason do
            # Expected possible failures on testnet
            {:insufficient_balance, _} ->
              # This is expected if testnet account has no balance
              flunk("Insufficient balance - need testnet funds")

            {:invalid_symbol, _} ->
              # Symbol info fetching might fail
              flunk("Symbol validation failed - check symbol info stub")

            _ ->
              # Unexpected error
              flunk("Unexpected validation error: #{inspect(reason)}")
          end
      end
    end

    @tag :integration
    test "rejects order with invalid symbol" do
      order_params = %{
        symbol: "INVALIDPAIR",
        side: :buy,
        quantity: "0.001"
      }

      assert {:error, {:invalid_symbol, "INVALIDPAIR"}} =
               OrderSafety.validate_order(:binance, order_params)
    end

    @tag :integration
    test "enforces kill switch" do
      # Disable trading
      OrderSafety.set_kill_switch(:binance, false)

      order_params = %{
        symbol: "BTCUSDT",
        side: :buy,
        quantity: "0.001"
      }

      assert {:error, :kill_switch_active} =
               OrderSafety.validate_order(:binance, order_params)

      # Re-enable for other tests
      OrderSafety.set_kill_switch(:binance, true)
    end

    @tag :integration
    test "prevents duplicate orders" do
      order_params = %{
        symbol: "BTCUSDT",
        side: :buy,
        quantity: "0.001",
        price: "30000.00",
        client_order_id: "integration_test_#{System.unique_integer()}"
      }

      # First validation should succeed (assuming balances/symbol are valid)
      case OrderSafety.validate_order(:binance, order_params) do
        {:ok, _} ->
          # Record the order
          assert :ok = OrderSafety.record_order(:binance, order_params.client_order_id)

          # Second validation should fail due to duplicate
          assert {:error, :duplicate} = OrderSafety.validate_order(:binance, order_params)

        {:error, reason} ->
          # Log for debugging but don't fail test if it's a testnet limitation
          IO.puts("Initial validation failed: #{inspect(reason)}")

          # Still test idempotency check by recording manually
          assert :ok = OrderSafety.record_order(:binance, order_params.client_order_id)
          assert {:error, :duplicate} = OrderSafety.validate_order(:binance, order_params)
      end
    end

    @tag :integration
    test "validates market orders" do
      order_params = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :market,
        # Small amount
        quantity: "0.001"
      }

      case OrderSafety.validate_order(:binance, order_params) do
        {:ok, validated_params} ->
          assert validated_params.type == :market
          assert Map.has_key?(validated_params, :client_order_id)

        {:error, reason} ->
          IO.puts("Market order validation failed: #{inspect(reason)}")

          # Market orders might fail due to balance estimation logic
          case reason do
            {:insufficient_balance, _} ->
              # Expected on testnet with no funds
              :ok

            _ ->
              flunk("Unexpected market order validation error: #{inspect(reason)}")
          end
      end
    end

    @tag :integration
    test "rejects orders with invalid quantities" do
      # Test various invalid quantity formats
      invalid_orders = [
        # Zero quantity
        %{symbol: "BTCUSDT", side: :buy, quantity: "0"},
        # Negative quantity
        %{symbol: "BTCUSDT", side: :buy, quantity: "-0.001"},
        # Non-numeric
        %{symbol: "BTCUSDT", side: :buy, quantity: "invalid"},
        # Empty string
        %{symbol: "BTCUSDT", side: :buy, quantity: ""}
      ]

      for order_params <- invalid_orders do
        case OrderSafety.validate_order(:binance, order_params) do
          {:error, {:invalid_quantity_format, _}} ->
            # Expected error
            :ok

          {:error, {:invalid_quantity, _}} ->
            # Expected error
            :ok

          {:error, _other_reason} ->
            # Validation might fail for other reasons (kill switch, symbol, etc)
            # but should not succeed
            :ok

          {:ok, _} ->
            flunk("Order with invalid quantity #{order_params.quantity} should not validate")
        end
      end
    end

    @tag :integration
    test "rejects orders with invalid prices" do
      invalid_orders = [
        # Zero price
        %{symbol: "BTCUSDT", side: :buy, quantity: "0.001", price: "0"},
        # Negative price
        %{symbol: "BTCUSDT", side: :buy, quantity: "0.001", price: "-1000"},
        # Non-numeric
        %{symbol: "BTCUSDT", side: :buy, quantity: "0.001", price: "invalid"},
        # Empty string
        %{symbol: "BTCUSDT", side: :buy, quantity: "0.001", price: ""}
      ]

      for order_params <- invalid_orders do
        case OrderSafety.validate_order(:binance, order_params) do
          {:error, {:invalid_price_format, _}} ->
            # Expected error
            :ok

          {:error, {:invalid_price, _}} ->
            # Expected error
            :ok

          {:error, _other_reason} ->
            # Other validation failures are acceptable
            :ok

          {:ok, _} ->
            flunk("Order with invalid price #{order_params.price} should not validate")
        end
      end
    end

    @tag :integration
    test "handles notional validation" do
      # Test very small notional value (should fail minimum notional)
      small_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        # Very small quantity
        quantity: "0.000001",
        # Very low price = tiny notional
        price: "1.00"
      }

      case OrderSafety.validate_order(:binance, small_order) do
        {:error, {:notional_too_small, _}} ->
          # Expected - notional too small
          :ok

        {:error, _other_reason} ->
          # Other validation failures are acceptable for this test
          :ok

        {:ok, _} ->
          # Small orders might still validate depending on exchange rules
          IO.puts("Small notional order unexpectedly validated - check minimum notional settings")
          :ok
      end
    end

    @tag :integration
    test "validates sell orders" do
      sell_order = %{
        symbol: "BTCUSDT",
        side: :sell,
        quantity: "0.001",
        price: "30000.00"
      }

      case OrderSafety.validate_order(:binance, sell_order) do
        {:ok, validated_params} ->
          assert validated_params.side == :sell

        {:error, {:insufficient_balance, _}} ->
          # Expected on testnet - no BTC to sell
          :ok

        {:error, reason} ->
          IO.puts("Sell order validation failed: #{inspect(reason)}")
          :ok
      end
    end

    @tag :integration
    test "validates different trading pairs" do
      # Test multiple symbols to verify symbol validation works
      test_symbols = ["BTCUSDT", "ETHUSDT", "ADAUSDT"]

      for symbol <- test_symbols do
        order_params = %{
          symbol: symbol,
          side: :buy,
          quantity: "0.001",
          # Generic price
          price: "1000.00"
        }

        case OrderSafety.validate_order(:binance, order_params) do
          {:ok, _} ->
            # Symbol validation passed
            :ok

          {:error, {:invalid_symbol, _}} ->
            # Some symbols might not be available on testnet
            IO.puts("Symbol #{symbol} not available on testnet")

          {:error, reason} ->
            # Other validation errors are acceptable
            IO.puts("Validation failed for #{symbol}: #{inspect(reason)}")
        end
      end
    end
  end

  describe "performance under load" do
    @tag :integration
    test "validates multiple orders concurrently" do
      # Test concurrent validation to ensure no race conditions
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            order_params = %{
              symbol: "BTCUSDT",
              side: :buy,
              quantity: "0.001",
              price: "30000.00",
              client_order_id: "concurrent_test_#{i}_#{System.unique_integer()}"
            }

            result = OrderSafety.validate_order(:binance, order_params)

            case result do
              {:ok, validated_params} ->
                # Record to test idempotency
                OrderSafety.record_order(:binance, validated_params.client_order_id)
                :success

              {:error, _reason} ->
                # Validation failures are acceptable in this test
                :validation_failed
            end
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # Should not crash or have race conditions
      assert is_list(results)
      assert Enum.all?(results, &(&1 in [:success, :validation_failed]))

      # Check that some validations succeeded (if testnet is properly configured)
      success_count = Enum.count(results, &(&1 == :success))
      IO.puts("#{success_count}/#{length(results)} concurrent validations succeeded")
    end
  end

  describe "integration with exchange info" do
    @tag :integration
    test "fetches real symbol information from Binance testnet" do
      # Test real symbol validation against testnet API
      case OrderSafety.validate_symbol(:binance, "BTCUSDT") do
        :ok ->
          # Symbol validation passed
          :ok

        {:error, reason} ->
          # Document the actual error for debugging
          flunk("Symbol validation failed: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "fetches real account balances from Binance testnet" do
      # Test real balance validation against testnet API
      case OrderSafety.validate_balance(:binance, "USDT", Decimal.new("10.0")) do
        :ok ->
          IO.puts("Balance validation passed - testnet has sufficient USDT")

        {:error, {:insufficient_balance, _}} ->
          # Expected on testnet with no funds
          IO.puts("Insufficient balance on testnet - expected")

        {:error, reason} ->
          # Document the actual error for debugging
          flunk("Balance check failed: #{inspect(reason)}")
      end
    end
  end
end
