defmodule ZenCex.Analysis.MarketIntegrationTest do
  @moduledoc """
  Integration tests for market analysis with real testnet APIs.
  These tests require valid testnet API credentials to run.
  """

  use ZenCex.IntegrationCase, exchange: :multi

  alias ZenCex.Analysis.Market
  alias ZenCex.Core.Cache

  @moduletag :zen_cex

  setup do
    # Ensure cache is started for testing
    if !Process.whereis(Cache) do
      start_supervised!(Cache)
    end

    # Clear cache before each test
    Cache.clear()
    :ok
  end

  describe "Binance funding rate integration" do
    @tag :binance
    test "fetches real-time funding rate from Binance USDM futures", %{
      binance_futures_key: api_key,
      binance_futures_secret: api_secret
    } do
      config = %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: true,
        account_type: :futures_usdm
      }

      # Use a popular symbol that should have funding data
      symbol = "BTCUSDT"

      result = Market.calculate_funding_apr(:binance, symbol, config)

      assert {:ok, apr} = result
      assert is_map(apr)
      assert Map.has_key?(apr, :hourly)
      assert Map.has_key?(apr, :daily)
      assert Map.has_key?(apr, :annual)
      # APR calculation returns simple fields without raw_rate

      # Funding rates should be reasonable (testnet can have extreme values)
      # In production, this would be between -100% and 100%, but testnet can be higher
      assert Decimal.compare(apr.annual, Decimal.new("-1000")) != :lt
      assert Decimal.compare(apr.annual, Decimal.new("1000")) != :gt
    end

    @tag :binance
    test "fetches funding rate history from Binance", %{binance_futures_key: api_key, binance_futures_secret: api_secret} do
      config = %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: true,
        account_type: :futures_usdm
      }

      symbol = "BTCUSDT"

      # Get 24 hours of funding data
      result = Market.get_funding_trend(:binance, symbol, config, hours: 24)

      assert {:ok, trend} = result
      assert is_map(trend)
      assert Map.has_key?(trend, :history)
      assert is_list(trend.history)

      # Should have at least some data points
      assert length(trend.history) > 0

      # Check each data point structure
      Enum.each(trend.history, fn point ->
        assert Map.has_key?(point, :rate)
        assert Map.has_key?(point, :interval_hours)
        assert Map.has_key?(point, :time)
        assert %Decimal{} = point.rate
      end)

      # Check trend analysis
      assert Map.has_key?(trend, :avg_rate)
      assert Map.has_key?(trend, :min_rate)
      assert Map.has_key?(trend, :max_rate)
      assert Map.has_key?(trend, :volatility)
    end
  end

  describe "Bybit funding rate integration" do
    @tag :bybit
    test "fetches real-time funding rate from Bybit linear futures", %{bybit_key: api_key, bybit_secret: api_secret} do
      config = %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: true,
        account_type: :linear
      }

      # Use a popular symbol that should have funding data
      symbol = "BTCUSDT"

      result = Market.calculate_funding_apr(:bybit, symbol, config)

      assert {:ok, apr} = result
      assert is_map(apr)
      assert Map.has_key?(apr, :hourly)
      assert Map.has_key?(apr, :daily)
      assert Map.has_key?(apr, :annual)
      # APR calculation returns simple fields without raw_rate

      # Funding rates should be reasonable (testnet can have extreme values)
      # In production, this would be between -100% and 100%, but testnet can be higher
      assert Decimal.compare(apr.annual, Decimal.new("-1000")) != :lt
      assert Decimal.compare(apr.annual, Decimal.new("1000")) != :gt
    end

    @tag :bybit
    test "fetches funding rate history from Bybit", %{bybit_key: api_key, bybit_secret: api_secret} do
      config = %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: true,
        account_type: :linear
      }

      symbol = "BTCUSDT"

      # Get 24 hours of funding data
      result = Market.get_funding_trend(:bybit, symbol, config, hours: 24)

      assert {:ok, trend} = result
      assert is_map(trend)
      assert Map.has_key?(trend, :history)
      assert is_list(trend.history)

      # Should have at least some data points (3 per day for 8-hour intervals)
      assert length(trend.history) > 0

      # Check each data point structure
      Enum.each(trend.history, fn point ->
        assert Map.has_key?(point, :rate)
        assert Map.has_key?(point, :interval_hours)
        assert Map.has_key?(point, :time)
        assert %Decimal{} = point.rate
      end)

      # Check trend analysis
      assert Map.has_key?(trend, :avg_rate)
      assert Map.has_key?(trend, :min_rate)
      assert Map.has_key?(trend, :max_rate)
      assert Map.has_key?(trend, :volatility)
    end
  end

  describe "Cross-exchange funding comparison" do
    @tag :binance
    @tag :bybit
    test "compares funding rates across Binance and Bybit", %{
      binance_futures_key: binance_api_key,
      binance_futures_secret: binance_api_secret,
      bybit_key: bybit_api_key,
      bybit_secret: bybit_api_secret
    } do
      exchanges_with_configs = [
        {:binance,
         %{
           api_key: binance_api_key,
           api_secret: binance_api_secret,
           testnet: true,
           account_type: :futures_usdm
         }},
        {:bybit,
         %{
           api_key: bybit_api_key,
           api_secret: bybit_api_secret,
           testnet: true,
           account_type: :linear
         }}
      ]

      symbols = ["BTCUSDT", "ETHUSDT"]

      result = Market.compare_funding_rates(exchanges_with_configs, symbols)

      assert {:ok, comparison} = result
      assert is_map(comparison)

      # Check each symbol
      Enum.each(symbols, fn symbol ->
        assert Map.has_key?(comparison, symbol)
        symbol_data = Map.get(comparison, symbol)

        # Check the actual fields returned by analyze_rate_differences
        assert Map.has_key?(symbol_data, :arbitrage_opportunity)
        # The function returns the rates directly as keys (e.g., binance: 0.001, bybit: 0.002)

        # Check that we have data from exchanges (rates are top-level keys)
        assert Map.has_key?(symbol_data, :binance) or Map.has_key?(symbol_data, :bybit)
      end)
    end

    @tag :binance
    @tag :bybit
    test "identifies arbitrage opportunities", %{
      binance_futures_key: binance_api_key,
      binance_futures_secret: binance_api_secret,
      bybit_key: bybit_api_key,
      bybit_secret: bybit_api_secret
    } do
      exchanges_with_configs = [
        {:binance,
         %{
           api_key: binance_api_key,
           api_secret: binance_api_secret,
           testnet: true,
           account_type: :futures_usdm
         }},
        {:bybit,
         %{
           api_key: bybit_api_key,
           api_secret: bybit_api_secret,
           testnet: true,
           account_type: :linear
         }}
      ]

      symbols = ["BTCUSDT"]

      result = Market.find_arbitrage_opportunities(exchanges_with_configs, symbols)

      assert {:ok, opportunities} = result
      assert is_list(opportunities)

      # Each opportunity should have proper structure (if any exist)
      Enum.each(opportunities, fn opp ->
        assert Map.has_key?(opp, :symbol)
        assert Map.has_key?(opp, :long_exchange)
        assert Map.has_key?(opp, :short_exchange)
        assert Map.has_key?(opp, :delta)
        assert Map.has_key?(opp, :annual_apr_delta)
        assert %Decimal{} = opp.delta
      end)
    end
  end
end
