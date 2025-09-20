defmodule ZenCex.Safety.OrderSafety.ValidationTest do
  @moduledoc """
  Tests for OrderSafety.Validation module.
  """

  use ExUnit.Case, async: true

  alias ZenCex.Safety.OrderSafety.Cache
  alias ZenCex.Safety.OrderSafety.Validation

  describe "validate_order/2" do
    test "validates all required fields are present" do
      incomplete_order = %{symbol: "BTCUSDT", side: :buy}
      result = Validation.validate_order(incomplete_order, :binance)
      assert {:error, {:missing_required_fields, missing}} = result
      assert :type in missing
      assert :quantity in missing
    end

    test "accepts valid order with all required fields" do
      valid_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.001",
        price: "50000"
      }

      # Prime cache with symbol info to avoid API call
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10.00"))
      # Prime price cache to avoid API call and ensure price deviation check passes
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

      result = Validation.validate_order(valid_order, :binance)
      assert result == :ok
    end
  end

  describe "validate_balance_requirements/2" do
    test "validates buy order balance requirements" do
      buy_order = %{
        side: :buy,
        symbol: "BTCUSDT",
        quantity: "1.0",
        price: "50000"
      }

      balance_info = %{
        balances: %{
          "USDT" => %{free: "60000.00"}
        }
      }

      result = Validation.validate_balance_requirements(buy_order, balance_info)
      assert result == :ok
    end

    test "rejects buy order with insufficient balance" do
      buy_order = %{
        side: :buy,
        symbol: "BTCUSDT",
        quantity: "1.0",
        price: "50000"
      }

      balance_info = %{
        balances: %{
          "USDT" => %{free: "40000.00"}
        }
      }

      result = Validation.validate_balance_requirements(buy_order, balance_info)
      assert {:error, {:insufficient_balance, msg}} = result
      assert msg =~ "Required: 50000"
      assert msg =~ "Available: 40000"
    end

    test "validates sell order balance requirements" do
      sell_order = %{
        side: :sell,
        symbol: "BTCUSDT",
        quantity: "0.5"
      }

      balance_info = %{
        balances: %{
          "BTC" => %{free: "1.0"}
        }
      }

      result = Validation.validate_balance_requirements(sell_order, balance_info)
      assert result == :ok
    end

    test "rejects sell order with insufficient balance" do
      sell_order = %{
        side: :sell,
        symbol: "BTCUSDT",
        quantity: "2.0"
      }

      balance_info = %{
        balances: %{
          "BTC" => %{free: "1.0"}
        }
      }

      result = Validation.validate_balance_requirements(sell_order, balance_info)
      assert {:error, {:insufficient_balance, msg}} = result
      assert msg =~ "Required: 2.0"
      assert msg =~ "Available: 1.0"
    end

    test "handles missing required parameters" do
      invalid_order = %{symbol: "BTCUSDT"}
      balance_info = %{balances: %{}}

      result = Validation.validate_balance_requirements(invalid_order, balance_info)
      assert {:error, {:missing_required_params, params}} = result
      assert :side in params
    end

    test "handles invalid side" do
      invalid_order = %{
        side: :invalid_side,
        symbol: "BTCUSDT",
        quantity: "1.0"
      }

      balance_info = %{balances: %{}}

      result = Validation.validate_balance_requirements(invalid_order, balance_info)
      assert {:error, {:invalid_side, :invalid_side}} = result
    end
  end

  describe "calculate_required_quote_amount/1" do
    test "calculates quote amount for limit order" do
      order = %{
        type: :limit,
        price: "50000",
        quantity: "0.5"
      }

      {:ok, amount} = Validation.calculate_required_quote_amount(order)
      assert Decimal.equal?(amount, Decimal.new("25000"))
    end

    test "returns error for market order without price fetch capability" do
      order = %{
        type: :market,
        quantity: "0.5",
        # Use a symbol that won't exist
        symbol: "INVALIDTESTPAIR",
        exchange: :binance
      }

      # Clear price cache to force fetch attempt
      Cache.invalidate_price(:binance, "INVALIDTESTPAIR")

      result = Validation.calculate_required_quote_amount(order)
      # This will fail trying to fetch price for non-existent symbol
      assert {:error, _} = result
    end

    test "returns error for order without price or quantity" do
      order = %{type: :limit, quantity: "1.0"}
      result = Validation.calculate_required_quote_amount(order)
      assert {:error, {:missing_price_or_quantity, _}} = result
    end
  end

  describe "calculate_order_notional/1" do
    test "calculates notional for limit order" do
      order = %{
        price: "50000",
        quantity: "0.5"
      }

      {:ok, notional} = Validation.calculate_order_notional(order)
      assert Decimal.equal?(notional, Decimal.new("25000"))
    end

    test "handles market order with cached price" do
      order = %{
        type: :market,
        quantity: "0.5",
        symbol: "BTCUSDT",
        exchange: :binance
      }

      # Prime the price cache
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

      {:ok, notional} = Validation.calculate_order_notional(order)
      assert Decimal.equal?(notional, Decimal.new("25000"))
    end

    test "returns error when price unavailable for market order" do
      order = %{
        type: :market,
        quantity: "0.5",
        # Use a symbol that won't exist
        symbol: "INVALIDTESTPAIR",
        exchange: :binance
      }

      # Clear price cache
      Cache.invalidate_price(:binance, "INVALIDTESTPAIR")

      result = Validation.calculate_order_notional(order)
      # This will fail trying to fetch price for non-existent symbol
      assert {:error, _} = result
    end

    test "returns error for incomplete order params" do
      order = %{quantity: "1.0"}
      result = Validation.calculate_order_notional(order)
      assert {:error, {:missing_price_or_quantity, _}} = result
    end
  end

  describe "quantity validation" do
    test "validates quantity format correctly" do
      valid_cases = [
        {"1.0", :ok},
        {"0.001", :ok},
        {"100", :ok},
        {"0.1", :ok}
      ]

      for {quantity, expected} <- valid_cases do
        order = %{
          symbol: "BTCUSDT",
          side: :buy,
          type: :limit,
          quantity: quantity,
          price: "50000"
        }

        # Prime cache to avoid API calls
        Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})
        Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10.00"))
        # Add price to cache
        Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

        result = Validation.validate_order(order, :binance)
        assert result == expected, "Expected #{expected} for quantity #{quantity}, got #{inspect(result)}"
      end
    end

    test "rejects invalid quantity formats" do
      invalid_quantities = ["-1.0", "0", "0.0"]

      for quantity <- invalid_quantities do
        order = %{
          symbol: "BTCUSDT",
          side: :buy,
          type: :limit,
          quantity: quantity,
          price: "50000"
        }

        # Prime cache
        Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})

        result = Validation.validate_order(order, :binance)
        assert {:error, _} = result, "Should reject quantity: #{quantity}"
      end
    end
  end

  describe "symbol validation" do
    test "validates trading symbols" do
      # Prime cache with trading symbol
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10.00"))
      # Also prime the price cache to avoid API call
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

      order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.001",
        price: "50000"
      }

      result = Validation.validate_order(order, :binance)
      assert result == :ok
    end

    test "rejects non-trading symbols" do
      # Prime cache with halted symbol
      Cache.put_symbol_info({:binance, "HALTUSDT"}, %{status: "HALT", filters: []})

      order = %{
        symbol: "HALTUSDT",
        side: :buy,
        type: :limit,
        quantity: "1.0",
        price: "100"
      }

      result = Validation.validate_order(order, :binance)
      assert {:error, {:symbol_not_trading, msg}} = result
      assert msg =~ "HALT"
    end
  end

  describe "price validation" do
    test "validates reasonable price levels" do
      # Prime cache with current price
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10.00"))

      # Price within 20% deviation (10% above current)
      order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.001",
        # 10% above current
        price: "55000"
      }

      result = Validation.validate_order(order, :binance)
      assert result == :ok
    end

    test "rejects excessive price deviation" do
      # Prime cache with current price
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})

      # Price with >20% deviation
      order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.001",
        # 50% above current
        price: "75000"
      }

      result = Validation.validate_order(order, :binance)
      assert {:error, {:price_deviation_too_large, msg}} = result
      assert msg =~ "exceeds maximum 20%"
    end

    test "skips price validation for market orders" do
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10.00"))
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

      order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :market,
        quantity: "0.001"
      }

      result = Validation.validate_order(order, :binance)
      assert result == :ok
    end
  end

  describe "notional validation" do
    test "accepts orders meeting minimum notional" do
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING", filters: []})
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10.00"))
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

      order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.001",
        # Notional = 50
        price: "50000"
      }

      result = Validation.validate_order(order, :binance)
      assert result == :ok
    end

    test "rejects orders below minimum notional" do
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{
        status: "TRADING",
        filters: [%{"filterType" => "NOTIONAL", "minNotional" => "10.00"}]
      })

      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

      order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.0001",
        # Notional = 5
        price: "50000"
      }

      result = Validation.validate_order(order, :binance)
      assert {:error, {:notional_too_small, msg}} = result
      assert msg =~ "below minimum"
    end
  end

  describe "lot size validation" do
    test "validates against Binance LOT_SIZE filter" do
      symbol_info = %{
        status: "TRADING",
        filters: [
          %{
            "filterType" => "LOT_SIZE",
            "minQty" => "0.001",
            "maxQty" => "100",
            "stepSize" => "0.001"
          }
        ]
      }

      Cache.put_symbol_info({:binance, "BTCUSDT"}, symbol_info)
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10.00"))
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))

      # Valid quantity
      valid_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.002",
        price: "50000"
      }

      assert Validation.validate_order(valid_order, :binance) == :ok

      # Quantity too small
      small_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.0001",
        price: "50000"
      }

      assert {:error, {:quantity_too_small, _}} = Validation.validate_order(small_order, :binance)

      # Quantity too large
      large_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "200",
        price: "50000"
      }

      assert {:error, {:quantity_too_large, _}} = Validation.validate_order(large_order, :binance)

      # Invalid step size
      invalid_step_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        # Not a multiple of 0.001
        quantity: "0.0015",
        price: "50000"
      }

      assert {:error, {:invalid_step_size, _}} = Validation.validate_order(invalid_step_order, :binance)
    end

    test "validates against Bybit lot size filter" do
      symbol_info = %{
        status: "TRADING",
        lot_size_filter: %{
          "minOrderQty" => "0.01",
          "maxOrderQty" => "1000",
          "qtyStep" => "0.01"
        }
      }

      Cache.put_symbol_info({:bybit, "BTCUSDT"}, symbol_info)
      Cache.put_min_notional({:bybit, "BTCUSDT"}, Decimal.new("1.00"))
      Cache.put_price({:bybit, "BTCUSDT"}, Decimal.new("50000"))

      # Valid quantity
      valid_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.05",
        price: "50000"
      }

      assert Validation.validate_order(valid_order, :bybit) == :ok

      # Quantity too small
      small_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.005",
        price: "50000"
      }

      assert {:error, {:quantity_too_small, _}} = Validation.validate_order(small_order, :bybit)
    end
  end

  describe "asset extraction" do
    test "correctly extracts quote assets" do
      test_cases = [
        {"BTCUSDT", "USDT"},
        {"ETHUSDT", "USDT"},
        {"BTCUSDC", "USDC"},
        {"ETHBTC", "BTC"},
        {"BNBETH", "ETH"},
        {"SOLBNB", "BNB"},
        # Default fallback
        {"UNKNOWN", "USDT"}
      ]

      for {symbol, expected_quote} <- test_cases do
        order = %{
          side: :buy,
          symbol: symbol,
          quantity: "1",
          price: "100"
        }

        balance_info = %{
          balances: %{
            expected_quote => %{free: "1000"}
          }
        }

        result = Validation.validate_balance_requirements(order, balance_info)
        assert result == :ok, "Failed for symbol #{symbol}, expected quote #{expected_quote}"
      end
    end

    test "correctly extracts base assets" do
      test_cases = [
        {"BTCUSDT", "BTC"},
        {"ETHUSDT", "ETH"},
        {"SOLBTC", "SOL"},
        {"BNBETH", "BNB"}
      ]

      for {symbol, expected_base} <- test_cases do
        order = %{
          side: :sell,
          symbol: symbol,
          quantity: "1"
        }

        balance_info = %{
          balances: %{
            expected_base => %{free: "10"}
          }
        }

        result = Validation.validate_balance_requirements(order, balance_info)
        assert result == :ok, "Failed for symbol #{symbol}, expected base #{expected_base}"
      end
    end
  end
end
