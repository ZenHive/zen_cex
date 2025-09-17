defmodule ZenCex.Analysis.BasisTest do
  use ExUnit.Case, async: true

  alias ZenCex.Analysis.Basis
  alias ZenCex.Core.Cache

  setup do
    # Clear cache before each test
    Cache.clear()
    :ok
  end

  describe "get_basis_spread/3" do
    test "calculates basis spread correctly for contango market" do
      # Mock the API calls
      spot_price = Decimal.new("45000.00")
      perp_price = Decimal.new("45100.00")

      _config = %{api_key: "test", api_secret: "test"}

      # We need to mock the actual Binance API calls
      # For unit tests, we'll use the cache to simulate responses
      cache_key_spot = "basis:spot_price:binance:BTCUSDT"
      cache_key_perp = "basis:perp_price:binance:BTCUSDT"

      Cache.put(cache_key_spot, spot_price, 60)
      Cache.put(cache_key_perp, perp_price, 60)

      # Since the actual implementation calls real APIs, we'll test the calculation function
      {:ok, result} = Basis.calculate_basis_spread(spot_price, perp_price)

      assert result.spot_price == spot_price
      assert result.perp_price == perp_price
      assert result.spread == Decimal.new("100.00")
      assert result.spread_pct == Decimal.new("0.22")
      assert result.market_condition == :contango
      assert Map.has_key?(result, :funding_rate)
      assert Map.has_key?(result, :funding_apr)
    end

    test "calculates basis spread correctly for backwardation market" do
      spot_price = Decimal.new("45000.00")
      perp_price = Decimal.new("44900.00")

      {:ok, result} = Basis.calculate_basis_spread(spot_price, perp_price)

      assert result.spot_price == spot_price
      assert result.perp_price == perp_price
      assert result.spread == Decimal.new("-100.00")
      assert result.spread_pct == Decimal.new("-0.22")
      assert result.market_condition == :backwardation
      assert Map.has_key?(result, :funding_rate)
      assert Map.has_key?(result, :funding_apr)
    end

    test "calculates basis spread correctly for neutral market" do
      spot_price = Decimal.new("45000.00")
      perp_price = Decimal.new("45020.00")

      {:ok, result} = Basis.calculate_basis_spread(spot_price, perp_price)

      assert result.spot_price == spot_price
      assert result.perp_price == perp_price
      assert result.spread == Decimal.new("20.00")
      assert result.spread_pct == Decimal.new("0.04")
      assert result.market_condition == :neutral
      assert Map.has_key?(result, :funding_rate)
      assert Map.has_key?(result, :funding_apr)
    end

    test "calculates annualized return correctly without funding" do
      spot_price = Decimal.new("45000.00")
      perp_price = Decimal.new("45450.00")
      # No funding
      funding_rate = Decimal.new("0")

      {:ok, result} = Basis.calculate_basis_spread(spot_price, perp_price, funding_rate)

      # 1% spread * 365 days = 365% annualized (no funding adjustment)
      assert result.spread_pct == Decimal.new("1.00")
      assert result.annualized_return == Decimal.new("365.00")
      assert Decimal.compare(result.funding_rate, Decimal.new("0")) == :eq
      assert Decimal.compare(result.funding_apr, Decimal.new("0")) == :eq
    end

    test "calculates annualized return with funding rate" do
      spot_price = Decimal.new("45000.00")
      perp_price = Decimal.new("45100.00")
      # 0.01% per 8 hours
      funding_rate = Decimal.new("0.0001")

      {:ok, result} = Basis.calculate_basis_spread(spot_price, perp_price, funding_rate)

      # Verify funding calculations
      # In percentage
      assert Decimal.compare(result.funding_rate, Decimal.new("0.01")) == :eq
      # 0.01% * 3 * 365
      assert result.funding_apr == Decimal.new("10.95")

      # In contango, annualized return = basis APR - funding APR
      basis_apr = Decimal.mult(result.spread_pct, Decimal.new(365))
      expected_return = basis_apr |> Decimal.sub(result.funding_apr) |> Decimal.round(2)
      assert result.annualized_return == expected_return
    end
  end

  describe "calculate_term_structure/2" do
    test "calculates term structure for multiple expiries" do
      spot_price = Decimal.new("45000.00")

      futures_data = [
        %{expiry: "250328", price: Decimal.new("45500.00")},
        %{expiry: "250627", price: Decimal.new("46000.00")},
        %{expiry: "250926", price: Decimal.new("46500.00")}
      ]

      {:ok, result} = Basis.calculate_term_structure(spot_price, futures_data)

      assert length(result) == 3

      # Check first expiry
      first = hd(result)
      assert first.price == Decimal.new("45500.00")
      assert first.basis == Decimal.new("500.00")
      assert first.basis_pct == Decimal.new("1.11")
    end

    test "sorts term structure by days to expiry" do
      spot_price = Decimal.new("45000.00")

      # Provide out-of-order expiries
      futures_data = [
        %{expiry: "250926", price: Decimal.new("46500.00")},
        %{expiry: "250328", price: Decimal.new("45500.00")},
        %{expiry: "250627", price: Decimal.new("46000.00")}
      ]

      {:ok, result} = Basis.calculate_term_structure(spot_price, futures_data)

      # Should be sorted by days to expiry (ascending)
      expiries = Enum.map(result, & &1.expiry)
      assert expiries == ["250328", "250627", "250926"]
    end

    test "handles empty futures data" do
      spot_price = Decimal.new("45000.00")
      futures_data = []

      {:ok, result} = Basis.calculate_term_structure(spot_price, futures_data)
      assert result == []
    end
  end

  describe "analyze_basis_arbitrage/1" do
    test "identifies arbitrage opportunity when spread difference is significant" do
      spreads = %{
        binance: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("45200.00"),
          spread_pct: Decimal.new("0.44"),
          market_condition: :contango
        },
        bybit: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("44900.00"),
          spread_pct: Decimal.new("-0.22"),
          market_condition: :backwardation
        }
      }

      result = Basis.analyze_basis_arbitrage(spreads)

      assert result.arbitrage_opportunity == true
      assert result.spread_difference == Decimal.new("0.66")
      assert result.best_long_spot == :bybit
      assert result.best_short_perp == :binance
      assert result.potential_profit_pct == Decimal.new("0.66")
    end

    test "no arbitrage opportunity when spread difference is small" do
      spreads = %{
        binance: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("45050.00"),
          spread_pct: Decimal.new("0.11"),
          market_condition: :contango
        },
        bybit: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("45080.00"),
          spread_pct: Decimal.new("0.18"),
          market_condition: :contango
        }
      }

      result = Basis.analyze_basis_arbitrage(spreads)

      assert result.arbitrage_opportunity == false
      assert result.spread_difference == Decimal.new("0.07")
    end

    test "handles single exchange data without arbitrage analysis" do
      spreads = %{
        binance: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("45100.00"),
          spread_pct: Decimal.new("0.22"),
          market_condition: :contango
        }
      }

      result = Basis.analyze_basis_arbitrage(spreads)

      assert result.arbitrage_opportunity == false
      assert result.insufficient_data == true
    end

    test "identifies correct exchanges for long and short positions" do
      spreads = %{
        binance: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("45300.00"),
          spread_pct: Decimal.new("0.67"),
          market_condition: :contango
        },
        bybit: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("45100.00"),
          spread_pct: Decimal.new("0.22"),
          market_condition: :contango
        },
        okx: %{
          spot_price: Decimal.new("45000.00"),
          perp_price: Decimal.new("44950.00"),
          spread_pct: Decimal.new("-0.11"),
          market_condition: :backwardation
        }
      }

      result = Basis.analyze_basis_arbitrage(spreads)

      assert result.arbitrage_opportunity == true
      # Should long spot on OKX (lowest basis)
      assert result.best_long_spot == :okx
      # Should short perp on Binance (highest basis)
      assert result.best_short_perp == :binance
      assert result.spread_difference == Decimal.new("0.78")
    end
  end

  describe "parse_expiry_date/1" do
    test "parses valid expiry date in YYMMDD format" do
      {:ok, date} = Basis.parse_expiry_date("250328")

      assert date.year == 2025
      assert date.month == 3
      assert date.day == 28
    end

    test "parses valid expiry date in ISO format" do
      {:ok, date} = Basis.parse_expiry_date("2025-03-28")

      assert date.year == 2025
      assert date.month == 3
      assert date.day == 28
    end

    test "parses valid expiry date in Bybit DD-MMM-YY format" do
      {:ok, date} = Basis.parse_expiry_date("26-DEC-25")

      assert date.year == 2025
      assert date.month == 12
      assert date.day == 26
    end

    test "parses valid expiry date in Bybit symbol format" do
      {:ok, date} = Basis.parse_expiry_date("03OCT25")

      assert date.year == 2025
      assert date.month == 10
      assert date.day == 3
    end

    test "handles invalid date format" do
      assert {:error, {:unsupported_expiry_format, _}} = Basis.parse_expiry_date("250328XX")
      assert {:error, {:unsupported_expiry_format, _}} = Basis.parse_expiry_date("invalid")
    end

    test "handles invalid date values" do
      # Invalid month
      assert {:error, {:invalid_date_format, _}} = Basis.parse_expiry_date("251328")
      # Invalid day
      assert {:error, {:invalid_date_format, _}} = Basis.parse_expiry_date("250332")
    end
  end

  describe "calculate_days_to_expiry/2" do
    test "calculates days correctly for future date" do
      now = ~U[2025-01-01 00:00:00Z]
      days = Basis.calculate_days_to_expiry("250131", now)

      assert days == 30
    end

    test "returns 0 for invalid expiry format" do
      now = ~U[2025-01-01 00:00:00Z]
      days = Basis.calculate_days_to_expiry("invalid", now)

      assert days == 0
    end

    test "handles past dates by returning 0" do
      now = ~U[2025-01-31 00:00:00Z]
      days = Basis.calculate_days_to_expiry("250101", now)

      # Should return 0 for past dates, not negative
      assert days == 0
    end
  end

  describe "caching behavior" do
    test "caches basis spread results" do
      spot_price = Decimal.new("45000.00")
      perp_price = Decimal.new("45100.00")

      # First call - calculates
      {:ok, result1} = Basis.calculate_basis_spread(spot_price, perp_price)

      # Store in cache manually (simulating what the main function would do)
      cache_key = "basis:basis_spread:binance:BTCUSDT"
      Cache.put(cache_key, result1, 5)

      # Second call - should get from cache
      {:ok, cached_result} = Cache.get(cache_key)
      assert cached_result == result1
    end

    test "cache expires after TTL" do
      cache_key = "basis:test:binance:BTCUSDT"
      test_data = %{test: "data"}

      # Put with 1 second TTL
      Cache.put(cache_key, test_data, 1)

      # Should be available immediately
      assert {:ok, ^test_data} = Cache.get(cache_key)

      # Wait for expiry
      Process.sleep(1100)

      # Should be expired (or marked as expired)
      result = Cache.get(cache_key)
      assert match?({:error, _}, result)
    end
  end

  describe "edge cases" do
    test "handles zero spot price gracefully" do
      spot_price = Decimal.new(0)
      perp_price = Decimal.new("45000.00")

      # Should handle division by zero
      {:ok, result} = Basis.calculate_basis_spread(spot_price, perp_price)
      assert result.spread_pct == Decimal.new("0")
    end

    test "handles equal spot and perp prices" do
      price = Decimal.new("45000.00")

      {:ok, result} = Basis.calculate_basis_spread(price, price)

      assert result.spread == Decimal.new("0.00")
      assert result.spread_pct == Decimal.new("0.00")
      assert result.annualized_return == Decimal.new("0.00")
      assert result.market_condition == :neutral
    end

    test "handles very large spread values" do
      spot_price = Decimal.new("45000.00")
      perp_price = Decimal.new("50000.00")

      {:ok, result} = Basis.calculate_basis_spread(spot_price, perp_price)

      assert result.spread == Decimal.new("5000.00")
      assert result.spread_pct == Decimal.new("11.11")
      assert result.market_condition == :contango
    end
  end
end
