defmodule ZenCex.Analysis.MarketTest do
  use ExUnit.Case, async: false
  use ZenCex.IntegrationCase, exchange: :binance, api_type: :usdm_futures

  alias ZenCex.Analysis.Market
  alias ZenCex.Core.Cache

  setup do
    # Ensure cache is started for testing
    if !Process.whereis(Cache) do
      start_supervised!(Cache)
    end

    # Clear cache before each test to ensure isolation
    Cache.clear()
    :ok
  end

  describe "funding APR calculations" do
    test "calculates annualized funding rates correctly" do
      funding_data = %{
        # 0.01% per 8 hours
        rate: 0.0001,
        interval_hours: 8,
        next_funding_time: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      # Test internal function directly
      result = Market.calculate_apr_from_data(funding_data)
      assert {:ok, apr} = result

      # Verify calculations
      # Hourly: 0.0001 / 8 = 0.0000125 * 100 = 0.00125%
      assert Decimal.equal?(apr.hourly, Decimal.new("0.0013"))

      # Daily: 0.0001 * 3 = 0.0003 * 100 = 0.03%
      assert Decimal.equal?(apr.daily, Decimal.new("0.03"))

      # Annual: 0.0003 * 365 = 0.1095 * 100 = 10.95%
      assert Decimal.equal?(apr.annual, Decimal.new("10.95"))
    end

    test "handles negative funding rates" do
      funding_data = %{
        # Negative funding rate
        rate: -0.0002,
        interval_hours: 8
      }

      result = Market.calculate_apr_from_data(funding_data)
      assert {:ok, apr} = result

      # Negative rates should result in negative APRs
      assert Decimal.compare(apr.hourly, Decimal.new(0)) == :lt
      assert Decimal.compare(apr.daily, Decimal.new(0)) == :lt
      assert Decimal.compare(apr.annual, Decimal.new(0)) == :lt
    end

    test "handles invalid funding data" do
      result1 = Market.calculate_apr_from_data(nil)
      assert {:error, :invalid_funding_data} = result1

      result2 = Market.calculate_apr_from_data("invalid")
      assert {:error, :invalid_funding_data} = result2
    end

    test "calculates different funding intervals correctly" do
      # Test 4-hour funding interval
      funding_data_4h = %{
        rate: 0.0001,
        interval_hours: 4
      }

      result = Market.calculate_apr_from_data(funding_data_4h)
      assert {:ok, apr} = result

      # Daily: 0.0001 * 6 (24/4) = 0.0006 * 100 = 0.06%
      assert Decimal.equal?(apr.daily, Decimal.new("0.06"))

      # Annual: 0.0006 * 365 = 0.219 * 100 = 21.9%
      assert Decimal.equal?(apr.annual, Decimal.new("21.90"))
    end
  end

  describe "cache behavior" do
    test "stores and retrieves data correctly" do
      cache_key = "test_cache_key"
      test_data = %{hourly: 0.01, daily: 0.24, annual: 87.6}

      # Put data in cache
      Cache.put(cache_key, test_data, 60)

      # Retrieve from cache
      assert {:ok, cached_data} = Cache.get(cache_key)
      assert cached_data == test_data
    end

    test "returns error for non-existent keys" do
      assert {:error, _} = Cache.get("non_existent_key")
    end

    test "clears cache correctly" do
      Cache.put("key1", "value1", 60)
      Cache.put("key2", "value2", 60)

      Cache.clear()

      assert {:error, _} = Cache.get("key1")
      assert {:error, _} = Cache.get("key2")
    end

    test "deletes specific keys" do
      Cache.put("key1", "value1", 60)
      Cache.put("key2", "value2", 60)

      Cache.delete("key1")

      assert {:error, _} = Cache.get("key1")
      assert {:ok, "value2"} = Cache.get("key2")
    end

    test "handles expiry correctly" do
      # Put data with 1 second TTL (expires quickly)
      Cache.put("expiring_key", "value", 1)

      # Sleep to ensure time has passed
      Process.sleep(1100)

      # Should return error as it's expired
      assert {:error, _} = Cache.get("expiring_key")
    end
  end

  describe "rate difference analysis" do
    test "identifies arbitrage opportunities" do
      rates = %{
        binance: 0.003,
        bybit: 0.001
      }

      result = Market.analyze_rate_differences(rates)

      assert result.arbitrage_opportunity == true
      assert result.max_exchange == :binance
      assert result.min_exchange == :bybit
      assert Decimal.equal?(result.delta, Decimal.new("0.002"))
      # Annual APR delta: 0.002 * 3 * 365 * 100 = 219%
      assert Decimal.equal?(result.annual_apr_delta, Decimal.new("219.00"))
    end

    test "handles insufficient data" do
      # Only one exchange
      rates = %{binance: 0.001}

      result = Market.analyze_rate_differences(rates)

      assert result.insufficient_data == true
      assert result.arbitrage_opportunity == false
    end

    test "identifies no arbitrage when delta is too small" do
      rates = %{
        binance: 0.0001,
        bybit: 0.00009
      }

      result = Market.analyze_rate_differences(rates)

      assert result.arbitrage_opportunity == false
      assert Decimal.equal?(result.delta, Decimal.new("0.00001"))
    end
  end

  describe "trend analysis" do
    test "detects increasing trends" do
      history = [
        %{rate: 0.0001, time: ~U[2024-01-01 00:00:00Z]},
        %{rate: 0.0001, time: ~U[2024-01-01 08:00:00Z]},
        %{rate: 0.00012, time: ~U[2024-01-01 16:00:00Z]},
        %{rate: 0.00013, time: ~U[2024-01-02 00:00:00Z]},
        %{rate: 0.00015, time: ~U[2024-01-02 08:00:00Z]},
        %{rate: 0.00016, time: ~U[2024-01-02 16:00:00Z]}
      ]

      result = Market.analyze_funding_trend(history)
      assert {:ok, trend} = result

      assert trend.trend == :increasing

      # Check average rate (sum of all rates / 6)
      expected_avg = Decimal.new("0.000127")

      assert Decimal.compare(trend.avg_rate, expected_avg) == :eq ||
               Decimal.compare(Decimal.abs(Decimal.sub(trend.avg_rate, expected_avg)), Decimal.new("0.000001")) == :lt

      assert Decimal.equal?(trend.max_rate, Decimal.new("0.00016"))
      assert Decimal.equal?(trend.min_rate, Decimal.new("0.0001"))
      assert trend.data_points == 6
    end

    test "detects decreasing trends" do
      history = [
        %{rate: 0.0002, time: ~U[2024-01-01 00:00:00Z]},
        %{rate: 0.00018, time: ~U[2024-01-01 08:00:00Z]},
        %{rate: 0.00015, time: ~U[2024-01-01 16:00:00Z]},
        %{rate: 0.00012, time: ~U[2024-01-02 00:00:00Z]}
      ]

      result = Market.analyze_funding_trend(history)
      assert {:ok, trend} = result

      assert trend.trend == :decreasing
    end

    test "detects flat trends" do
      history = [
        %{rate: 0.0001, time: ~U[2024-01-01 00:00:00Z]},
        %{rate: 0.00011, time: ~U[2024-01-01 08:00:00Z]},
        %{rate: 0.0001, time: ~U[2024-01-01 16:00:00Z]},
        %{rate: 0.00011, time: ~U[2024-01-02 00:00:00Z]}
      ]

      result = Market.analyze_funding_trend(history)
      assert {:ok, trend} = result

      assert trend.trend == :flat
    end

    test "handles insufficient data" do
      result1 = Market.analyze_funding_trend([])
      assert {:error, :insufficient_data} = result1

      result2 = Market.analyze_funding_trend(nil)
      assert {:error, :insufficient_data} = result2
    end
  end

  describe "arbitrage opportunity building" do
    test "builds arbitrage opportunity correctly" do
      data = %{
        min_exchange: :bybit,
        max_exchange: :binance,
        delta: Decimal.new("0.002"),
        annual_apr_delta: Decimal.new("219.0"),
        binance: Decimal.new("0.003"),
        bybit: Decimal.new("0.001"),
        deribit: Decimal.new("0.002")
      }

      result = Market.build_arbitrage_opportunity("BTCUSDT", data)

      assert result.symbol == "BTCUSDT"
      assert result.long_exchange == :bybit
      assert result.short_exchange == :binance
      assert Decimal.equal?(result.delta, Decimal.new("0.002"))
      assert Decimal.equal?(result.annual_apr_delta, Decimal.new("219.0"))

      assert result.rates == %{
               binance: Decimal.new("0.003"),
               bybit: Decimal.new("0.001"),
               deribit: Decimal.new("0.002")
             }
    end
  end

  describe "integration tests" do
    @tag :integration
    test "calculates APR from real API data", %{api_key: api_key, api_secret: api_secret} do
      # Build config from IntegrationCase context
      config = %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: true
      }

      # Test with real testnet API
      result = Market.calculate_funding_apr(:binance, "BTCUSDT", config)

      case result do
        {:ok, apr} ->
          assert %Decimal{} = apr.hourly
          assert %Decimal{} = apr.daily
          assert %Decimal{} = apr.annual
          # Verify the APR values are reasonable
          assert Decimal.compare(apr.annual, Decimal.new("-100")) == :gt
          assert Decimal.compare(apr.annual, Decimal.new("1000")) == :lt

        {:error, reason} ->
          # Document the actual error for debugging
          flunk("Failed to fetch funding APR: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "compares rates across multiple exchanges" do
      # Get real testnet configs from environment
      binance_config = %{
        api_key: System.get_env("BINANCE_FUTURES_TEST_API_KEY"),
        api_secret: System.get_env("BINANCE_FUTURES_TEST_API_SECRET"),
        testnet: true
      }

      bybit_config = %{
        api_key: System.get_env("BYBIT_TESTNET_API_KEY"),
        api_secret: System.get_env("BYBIT_TESTNET_API_SECRET"),
        testnet: true
      }

      # Only test exchanges with configured credentials
      exchanges_with_configs = []

      exchanges_with_configs =
        if binance_config.api_key && binance_config.api_secret do
          [{:binance, binance_config} | exchanges_with_configs]
        else
          exchanges_with_configs
        end

      exchanges_with_configs =
        if bybit_config.api_key && bybit_config.api_secret do
          [{:bybit, bybit_config} | exchanges_with_configs]
        else
          exchanges_with_configs
        end

      if length(exchanges_with_configs) > 0 do
        result = Market.compare_funding_rates(exchanges_with_configs, ["BTCUSDT"])

        case result do
          {:ok, comparison} ->
            assert is_map(comparison)
            # Verify structure of comparison data
            assert Map.has_key?(comparison, "BTCUSDT")

          {:error, reason} ->
            # Document the actual error for debugging
            flunk("Failed to compare funding rates: #{inspect(reason)}")
        end
      else
        # Skip test if no credentials are configured
        IO.puts("Skipping test - no exchange credentials configured")
      end
    end
  end
end
