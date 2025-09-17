defmodule ZenCex.Analysis.BasisIntegrationTest do
  use ExUnit.Case, async: false

  alias ZenCex.Analysis.Basis
  alias ZenCex.TestUtilities

  @moduletag :integration

  describe "get_basis_spread/3 with real APIs" do
    @tag :integration
    test "fetches real basis spread from Binance" do
      config = TestUtilities.get_test_config!(:binance)

      # Test with a common symbol
      assert {:ok, result} = Basis.get_basis_spread(:binance, "BTCUSDT", config)

      # Verify structure
      assert Map.has_key?(result, :spot_price)
      assert Map.has_key?(result, :perp_price)
      assert Map.has_key?(result, :spread)
      assert Map.has_key?(result, :spread_pct)
      assert Map.has_key?(result, :annualized_return)
      assert Map.has_key?(result, :market_condition)

      # Verify data types
      assert %Decimal{} = result.spot_price
      assert %Decimal{} = result.perp_price
      assert %Decimal{} = result.spread
      assert %Decimal{} = result.spread_pct
      assert %Decimal{} = result.annualized_return
      assert result.market_condition in [:contango, :backwardation, :neutral]

      # Prices should be positive
      assert Decimal.compare(result.spot_price, Decimal.new(0)) == :gt
      assert Decimal.compare(result.perp_price, Decimal.new(0)) == :gt
    end

    @tag :integration
    test "fetches real basis spread from Bybit" do
      config = TestUtilities.get_test_config!(:bybit)

      # Test with a common symbol
      assert {:ok, result} = Basis.get_basis_spread(:bybit, "BTCUSDT", config)

      # Verify structure
      assert Map.has_key?(result, :spot_price)
      assert Map.has_key?(result, :perp_price)
      assert Map.has_key?(result, :spread)
      assert Map.has_key?(result, :spread_pct)
      assert Map.has_key?(result, :annualized_return)
      assert Map.has_key?(result, :market_condition)

      # Verify data types
      assert %Decimal{} = result.spot_price
      assert %Decimal{} = result.perp_price
      assert %Decimal{} = result.spread
      assert %Decimal{} = result.spread_pct
      assert %Decimal{} = result.annualized_return
      assert result.market_condition in [:contango, :backwardation, :neutral]
    end

    @tag :integration
    test "handles invalid symbol gracefully" do
      config = TestUtilities.get_test_config!(:binance)

      assert {:error, _reason} = Basis.get_basis_spread(:binance, "INVALIDSYMBOL", config)
    end

    @tag :integration
    test "compares multiple symbols across exchanges" do
      binance_config = TestUtilities.get_test_config!(:binance)
      bybit_config = TestUtilities.get_test_config!(:bybit)

      exchanges_with_configs = [
        {:binance, binance_config},
        {:bybit, bybit_config}
      ]

      symbols = ["BTCUSDT", "ETHUSDT"]

      assert {:ok, result} = Basis.compare_basis_spreads(exchanges_with_configs, symbols)

      # Should have results for each symbol
      assert Map.has_key?(result, "BTCUSDT")
      assert Map.has_key?(result, "ETHUSDT")

      # Check BTCUSDT results
      btc_result = result["BTCUSDT"]

      # Should have data from at least one exchange
      assert map_size(btc_result) > 0

      # If we have data from both exchanges, check for arbitrage analysis
      if Map.has_key?(btc_result, :binance) and Map.has_key?(btc_result, :bybit) do
        assert Map.has_key?(btc_result, :arbitrage_opportunity)
        assert is_boolean(btc_result.arbitrage_opportunity)

        if btc_result.arbitrage_opportunity do
          assert Map.has_key?(btc_result, :best_long_spot)
          assert Map.has_key?(btc_result, :best_short_perp)
          assert Map.has_key?(btc_result, :potential_profit_pct)
        end
      end
    end
  end

  describe "term structure analysis" do
    @tag :integration
    test "fetches real term structure from Binance" do
      config = TestUtilities.get_test_config!(:binance)

      # Now that we've implemented futures contract fetching, this should work!
      assert {:ok, term_structure} = Basis.get_term_structure(:binance, "BTC", config)

      # Should have at least one contract (typically 2: current and next quarter)
      assert is_list(term_structure)
      assert length(term_structure) > 0

      # Check the structure of each term point
      Enum.each(term_structure, fn point ->
        assert Map.has_key?(point, :expiry)
        assert Map.has_key?(point, :days_to_expiry)
        assert Map.has_key?(point, :price)
        assert Map.has_key?(point, :basis)
        assert Map.has_key?(point, :basis_pct)
        assert Map.has_key?(point, :annualized_return)

        # Verify data types
        assert is_binary(point.expiry)
        assert is_integer(point.days_to_expiry)
        assert %Decimal{} = point.price
        assert %Decimal{} = point.basis
        assert %Decimal{} = point.basis_pct
        assert %Decimal{} = point.annualized_return

        # Price should be positive
        assert Decimal.compare(point.price, Decimal.new(0)) == :gt
      end)
    end

    @tag :integration
    test "term structure works for Bybit" do
      config = TestUtilities.get_test_config!(:bybit)

      # Bybit actually has delivery futures! Let's verify they work
      assert {:ok, term_structure} = Basis.get_term_structure(:bybit, "BTC", config)

      # Should have at least one contract
      assert is_list(term_structure)
      assert length(term_structure) > 0

      # Check the structure of each term point
      Enum.each(term_structure, fn point ->
        assert Map.has_key?(point, :expiry)
        assert Map.has_key?(point, :days_to_expiry)
        assert Map.has_key?(point, :price)
        assert Map.has_key?(point, :basis)
        assert Map.has_key?(point, :basis_pct)
        assert Map.has_key?(point, :annualized_return)

        # Verify data types
        assert is_binary(point.expiry)
        assert is_integer(point.days_to_expiry)
        assert %Decimal{} = point.price
        assert %Decimal{} = point.basis
        assert %Decimal{} = point.basis_pct
        assert %Decimal{} = point.annualized_return

        # Price should be positive
        assert Decimal.compare(point.price, Decimal.new(0)) == :gt
      end)
    end
  end

  describe "caching behavior with real data" do
    @tag :integration
    test "caches real API responses" do
      config = TestUtilities.get_test_config!(:binance)

      # First call - hits API
      {time1, {:ok, result1}} =
        :timer.tc(fn ->
          Basis.get_basis_spread(:binance, "BTCUSDT", config)
        end)

      # Second call - should be cached
      {time2, {:ok, result2}} =
        :timer.tc(fn ->
          Basis.get_basis_spread(:binance, "BTCUSDT", config)
        end)

      # Cached call should be faster, but timing can vary
      # Just verify cache hit is faster than API call
      assert time2 < time1

      # Results should be identical
      assert result1 == result2

      # Third call to ensure cache is consistent
      {:ok, result3} = Basis.get_basis_spread(:binance, "BTCUSDT", config)
      assert result3 == result1
    end
  end

  describe "cross-exchange arbitrage detection" do
    @tag :integration
    test "identifies real arbitrage opportunities if they exist" do
      binance_config = TestUtilities.get_test_config!(:binance)
      bybit_config = TestUtilities.get_test_config!(:bybit)

      exchanges_with_configs = [
        {:binance, binance_config},
        {:bybit, bybit_config}
      ]

      # Test with multiple symbols to increase chance of finding arbitrage
      symbols = ["BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "ADAUSDT"]

      assert {:ok, result} = Basis.compare_basis_spreads(exchanges_with_configs, symbols)

      # Log any arbitrage opportunities found
      arbitrage_symbols =
        result
        |> Enum.filter(fn {_symbol, data} ->
          Map.get(data, :arbitrage_opportunity, false)
        end)
        |> Enum.map(fn {symbol, data} ->
          %{
            symbol: symbol,
            spread_diff: Map.get(data, :spread_difference),
            best_long: Map.get(data, :best_long_spot),
            best_short: Map.get(data, :best_short_perp)
          }
        end)

      if length(arbitrage_symbols) > 0 do
        IO.puts("Found arbitrage opportunities: #{inspect(arbitrage_symbols)}")
      end

      # Verify structure regardless of arbitrage
      for {_symbol, data} <- result do
        # Should have some exchange data
        assert map_size(data) > 0

        # If both exchanges responded, should have arbitrage analysis
        if Map.has_key?(data, :binance) and Map.has_key?(data, :bybit) do
          assert Map.has_key?(data, :arbitrage_opportunity)
          assert Map.has_key?(data, :spread_difference)
        end
      end
    end
  end

  describe "error handling with real APIs" do
    @tag :integration
    test "handles invalid symbols gracefully" do
      config = TestUtilities.get_test_config!(:binance)

      # Use an invalid symbol that doesn't exist on the exchange
      # This will cause the market data endpoint to return an error
      invalid_symbol = "INVALIDXYZ123"

      # Should return error, not crash
      assert {:error, _reason} = Basis.get_basis_spread(:binance, invalid_symbol, config)
    end

    @tag :integration
    test "handles unsupported exchanges" do
      config = %{api_key: "test", api_secret: "test"}

      assert {:error, {:unsupported_exchange, :kraken}} =
               Basis.get_basis_spread(:kraken, "BTCUSD", config)
    end
  end
end
