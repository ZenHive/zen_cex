defmodule ZenCex.Cache.MarketTest do
  use ExUnit.Case, async: false

  alias ZenCex.Cache.Market
  alias ZenCex.Core.Cache

  # Market tests need async: false because Market module uses fixed key patterns
  # that cannot be namespaced without changing the module's API

  setup do
    # Clear cache before each test to avoid interference
    Cache.clear()
    :ok
  end

  describe "ticker caching" do
    test "get_ticker/2 returns {:error, :not_found} when ticker not cached" do
      assert {:error, :not_found} = Market.get_ticker(:binance, "BTCUSDT")
    end

    test "put_ticker/3 and get_ticker/2 work together" do
      exchange = :binance
      symbol = "BTCUSDT"
      ticker_data = %{price: "45000.00", volume: "1200.50", change_24h: "2.5"}

      Market.put_ticker(exchange, symbol, ticker_data)
      assert {:ok, ^ticker_data} = Market.get_ticker(exchange, symbol)
    end

    test "put_ticker/4 accepts custom TTL" do
      exchange = :binance
      symbol = "ETHUSDT"
      ticker_data = %{price: "3000.00"}

      # Very short TTL for testing
      Market.put_ticker(exchange, symbol, ticker_data, 1)
      assert {:ok, ^ticker_data} = Market.get_ticker(exchange, symbol)

      # Wait for expiration
      Process.sleep(1100)
      assert {:error, :expired} = Market.get_ticker(exchange, symbol)
    end

    test "ticker_key/2 generates expected key format" do
      assert "market:ticker:binance:BTCUSDT" = Market.ticker_key(:binance, "BTCUSDT")
      assert "market:ticker:bybit:ETHUSDT" = Market.ticker_key(:bybit, "ETHUSDT")
    end

    test "validates exchange is atom and symbol is binary" do
      assert_raise FunctionClauseError, fn ->
        Market.put_ticker("binance", "BTCUSDT", %{})
      end

      assert_raise FunctionClauseError, fn ->
        Market.put_ticker(:binance, :BTCUSDT, %{})
      end

      assert_raise FunctionClauseError, fn ->
        Market.get_ticker("binance", "BTCUSDT")
      end
    end
  end

  describe "funding rate caching" do
    test "get_funding_rate/2 returns {:error, :not_found} when not cached" do
      assert {:error, :not_found} = Market.get_funding_rate(:bybit, "BTCUSDT")
    end

    test "put_funding_rate/3 and get_funding_rate/2 work together" do
      exchange = :bybit
      symbol = "ETHUSDT"
      funding_data = %{rate: 0.0001, interval_hours: 8, timestamp: 1_234_567_890}

      Market.put_funding_rate(exchange, symbol, funding_data)
      assert {:ok, ^funding_data} = Market.get_funding_rate(exchange, symbol)
    end

    test "put_funding_rate/4 accepts custom TTL" do
      exchange = :bybit
      symbol = "BTCUSDT"
      funding_data = %{rate: -0.0005, interval_hours: 8}

      # Very short TTL for testing
      Market.put_funding_rate(exchange, symbol, funding_data, 1)
      assert {:ok, ^funding_data} = Market.get_funding_rate(exchange, symbol)

      # Wait for expiration
      Process.sleep(1100)
      assert {:error, :expired} = Market.get_funding_rate(exchange, symbol)
    end

    test "funding_rate_key/2 generates expected key format" do
      assert "market:funding:bybit:BTCUSDT" = Market.funding_rate_key(:bybit, "BTCUSDT")
      assert "market:funding:binance:ETHUSDT" = Market.funding_rate_key(:binance, "ETHUSDT")
    end
  end

  describe "24hr stats caching" do
    test "get_24hr_stats/2 returns {:error, :not_found} when not cached" do
      assert {:error, :not_found} = Market.get_24hr_stats(:binance, "BTCUSDT")
    end

    test "put_24hr_stats/3 and get_24hr_stats/2 work together" do
      exchange = :binance
      symbol = "BTCUSDT"
      stats_data = %{volume: "5420.12", change_percent: "2.45", high: "46000", low: "44000"}

      Market.put_24hr_stats(exchange, symbol, stats_data)
      assert {:ok, ^stats_data} = Market.get_24hr_stats(exchange, symbol)
    end

    test "put_24hr_stats/4 accepts custom TTL" do
      exchange = :binance
      symbol = "ETHUSDT"
      stats_data = %{volume: "12000.00"}

      # Very short TTL for testing
      Market.put_24hr_stats(exchange, symbol, stats_data, 1)
      assert {:ok, ^stats_data} = Market.get_24hr_stats(exchange, symbol)

      # Wait for expiration
      Process.sleep(1100)
      assert {:error, :expired} = Market.get_24hr_stats(exchange, symbol)
    end

    test "stats_24hr_key/2 generates expected key format" do
      assert "market:stats24h:binance:BTCUSDT" = Market.stats_24hr_key(:binance, "BTCUSDT")
      assert "market:stats24h:bybit:ETHUSDT" = Market.stats_24hr_key(:bybit, "ETHUSDT")
    end
  end

  describe "order book caching" do
    test "get_orderbook/2 returns {:error, :not_found} when not cached" do
      assert {:error, :not_found} = Market.get_orderbook(:binance, "BTCUSDT")
    end

    test "put_orderbook/3 and get_orderbook/2 work together" do
      exchange = :binance
      symbol = "BTCUSDT"

      orderbook_data = %{
        bids: [["45000.00", "1.2"], ["44999.50", "0.5"]],
        asks: [["45000.50", "0.8"], ["45001.00", "1.0"]]
      }

      Market.put_orderbook(exchange, symbol, orderbook_data)
      assert {:ok, ^orderbook_data} = Market.get_orderbook(exchange, symbol)
    end

    test "put_orderbook/4 accepts custom TTL" do
      exchange = :binance
      symbol = "ETHUSDT"
      orderbook_data = %{bids: [], asks: []}

      # Very short TTL for testing
      Market.put_orderbook(exchange, symbol, orderbook_data, 1)
      assert {:ok, ^orderbook_data} = Market.get_orderbook(exchange, symbol)

      # Wait for expiration
      Process.sleep(1100)
      assert {:error, :expired} = Market.get_orderbook(exchange, symbol)
    end

    test "orderbook_key/2 generates expected key format" do
      assert "market:orderbook:binance:BTCUSDT" = Market.orderbook_key(:binance, "BTCUSDT")
      assert "market:orderbook:bybit:ETHUSDT" = Market.orderbook_key(:bybit, "ETHUSDT")
    end
  end

  describe "generic market data caching" do
    test "get_market_data/3 returns {:error, :not_found} when not cached" do
      assert {:error, :not_found} = Market.get_market_data(:binance, "BTCUSDT", "klines_1h")
    end

    test "put_market_data/5 and get_market_data/3 work together" do
      exchange = :binance
      symbol = "BTCUSDT"
      data_type = "klines_1h"

      kline_data = [
        [1_234_567_890, "45000", "45100", "44900", "45050", "123.45"],
        [1_234_567_950, "45050", "45200", "45000", "45150", "98.76"]
      ]

      Market.put_market_data(exchange, symbol, data_type, kline_data, 300)
      assert {:ok, ^kline_data} = Market.get_market_data(exchange, symbol, data_type)
    end

    test "market_data_key/3 generates expected key format" do
      assert "market:klines_1h:binance:BTCUSDT" =
               Market.market_data_key(:binance, "BTCUSDT", "klines_1h")

      assert "market:trades:bybit:ETHUSDT" =
               Market.market_data_key(:bybit, "ETHUSDT", "trades")
    end

    test "validates data_type is binary" do
      assert_raise FunctionClauseError, fn ->
        Market.put_market_data(:binance, "BTCUSDT", :klines, [], 60)
      end

      assert_raise FunctionClauseError, fn ->
        Market.get_market_data(:binance, "BTCUSDT", :klines)
      end
    end
  end

  describe "bulk operations" do
    test "clear_exchange/1 clears all data for specific exchange" do
      # Put some data for different exchanges
      Market.put_ticker(:binance, "BTCUSDT", %{price: "45000"})
      Market.put_ticker(:bybit, "ETHUSDT", %{price: "3000"})
      Market.put_funding_rate(:binance, "BTCUSDT", %{rate: 0.0001})
      Market.put_24hr_stats(:bybit, "BTCUSDT", %{volume: "1000"})

      # Verify data exists
      assert {:ok, _} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_ticker(:bybit, "ETHUSDT")
      assert {:ok, _} = Market.get_funding_rate(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_24hr_stats(:bybit, "BTCUSDT")

      # Clear removes data for the specified exchange only
      {:ok, count} = Market.clear_exchange(:binance)
      # At least ticker and funding rate for binance
      assert count >= 2

      # Binance data should be gone
      assert {:error, :not_found} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:error, :not_found} = Market.get_funding_rate(:binance, "BTCUSDT")

      # Bybit data should still exist
      assert {:ok, _} = Market.get_ticker(:bybit, "ETHUSDT")
      assert {:ok, _} = Market.get_24hr_stats(:bybit, "BTCUSDT")
    end

    test "clear_symbol/1 clears all data for specific symbol" do
      # Put some data for different symbols
      Market.put_ticker(:binance, "BTCUSDT", %{price: "45000"})
      Market.put_ticker(:binance, "ETHUSDT", %{price: "3000"})
      Market.put_funding_rate(:bybit, "BTCUSDT", %{rate: 0.0001})
      Market.put_orderbook(:binance, "ETHUSDT", %{bids: [], asks: []})

      # Verify data exists
      assert {:ok, _} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_ticker(:binance, "ETHUSDT")
      assert {:ok, _} = Market.get_funding_rate(:bybit, "BTCUSDT")
      assert {:ok, _} = Market.get_orderbook(:binance, "ETHUSDT")

      # Clear removes data for the specified symbol only
      {:ok, count} = Market.clear_symbol("BTCUSDT")
      # At least ticker and funding rate for BTCUSDT
      assert count >= 2

      # BTCUSDT data should be gone
      assert {:error, :not_found} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:error, :not_found} = Market.get_funding_rate(:bybit, "BTCUSDT")

      # ETHUSDT data should still exist
      assert {:ok, _} = Market.get_ticker(:binance, "ETHUSDT")
      assert {:ok, _} = Market.get_orderbook(:binance, "ETHUSDT")
    end

    test "clear_data_type/1 clears all data of specific type" do
      # Put data of different types
      Market.put_ticker(:binance, "BTCUSDT", %{price: "45000"})
      Market.put_ticker(:bybit, "ETHUSDT", %{price: "3000"})
      Market.put_funding_rate(:binance, "BTCUSDT", %{rate: 0.0001})
      Market.put_24hr_stats(:bybit, "BTCUSDT", %{volume: "1000"})

      # Verify data exists
      assert {:ok, _} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_ticker(:bybit, "ETHUSDT")
      assert {:ok, _} = Market.get_funding_rate(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_24hr_stats(:bybit, "BTCUSDT")

      # Clear all ticker data
      {:ok, count} = Market.clear_data_type("ticker")
      # At least two ticker entries
      assert count >= 2

      # Ticker data should be gone
      assert {:error, :not_found} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:error, :not_found} = Market.get_ticker(:bybit, "ETHUSDT")

      # Other data types should still exist
      assert {:ok, _} = Market.get_funding_rate(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_24hr_stats(:bybit, "BTCUSDT")
    end

    test "clear_all/0 clears all market data" do
      # Put various data
      Market.put_ticker(:binance, "BTCUSDT", %{price: "45000"})
      Market.put_funding_rate(:bybit, "ETHUSDT", %{rate: 0.0001})
      Market.put_24hr_stats(:binance, "BTCUSDT", %{volume: "1000"})
      Market.put_orderbook(:bybit, "ETHUSDT", %{bids: [], asks: []})

      # Verify data exists
      assert {:ok, _} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_funding_rate(:bybit, "ETHUSDT")
      assert {:ok, _} = Market.get_24hr_stats(:binance, "BTCUSDT")
      assert {:ok, _} = Market.get_orderbook(:bybit, "ETHUSDT")

      # Clear all market data
      {:ok, count} = Market.clear_all()
      # At least four entries
      assert count >= 4

      # All data should be gone
      assert {:error, :not_found} = Market.get_ticker(:binance, "BTCUSDT")
      assert {:error, :not_found} = Market.get_funding_rate(:bybit, "ETHUSDT")
      assert {:error, :not_found} = Market.get_24hr_stats(:binance, "BTCUSDT")
      assert {:error, :not_found} = Market.get_orderbook(:bybit, "ETHUSDT")
    end
  end

  describe "data type handling" do
    test "handles different data types correctly" do
      test_cases = [
        {"string", "simple_string"},
        {"map", %{key: "value", nested: %{deep: true}}},
        {"list", [1, 2, 3, %{a: :b}]},
        {"atom", :test_atom},
        {"tuple", {:ok, "result", 123}},
        {"binary", <<1, 2, 3, 4, 5>>},
        {"number", 42.123}
      ]

      Enum.each(test_cases, fn {type, value} ->
        symbol = "TEST#{String.upcase(type)}"
        Market.put_ticker(:test_exchange, symbol, value)

        assert {:ok, ^value} = Market.get_ticker(:test_exchange, symbol),
               "Failed for type: #{type}"
      end)
    end
  end

  describe "concurrent access" do
    test "handles concurrent operations on same symbol" do
      symbol = "CONCURRENT_TEST"

      # Spawn multiple tasks operating on the same symbol
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            exchange = String.to_atom("exchange_#{i}")
            data = %{price: "#{i * 1000}.00", volume: "#{i * 100}.50"}

            Market.put_ticker(exchange, symbol, data)
            {:ok, ^data} = Market.get_ticker(exchange, symbol)

            :ok
          end)
        end)

      # All tasks should complete successfully
      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end

    test "handles concurrent updates to same key correctly" do
      # Multiple processes updating the same key - last write wins
      exchange = :test_exchange
      symbol = "RACE_CONDITION_TEST"

      # Spawn many tasks all writing to the same key
      tasks =
        Enum.map(1..100, fn i ->
          Task.async(fn ->
            Market.put_ticker(exchange, symbol, %{value: i, timestamp: System.monotonic_time()})
            # Small random delay to increase chance of race conditions
            if rem(i, 10) == 0, do: Process.sleep(1)
            Market.get_ticker(exchange, symbol)
          end)
        end)

      results = Task.await_many(tasks, 10_000)

      # All operations should succeed
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)

      # Final value should be one of the values we wrote
      {:ok, final_value} = Market.get_ticker(exchange, symbol)
      assert is_map(final_value)
      assert Map.has_key?(final_value, :value)
      assert final_value.value in 1..100
    end

    test "handles mixed read/write operations concurrently" do
      exchange = :stress_test
      base_symbol = "STRESS_"

      # Mix of reads, writes, and deletes
      tasks =
        Enum.map(1..50, fn i ->
          Task.async(fn ->
            # Use 5 different symbols
            symbol = "#{base_symbol}#{rem(i, 5)}"

            case rem(i, 3) do
              0 ->
                # Write operation
                Market.put_ticker(exchange, symbol, %{op: :write, id: i})
                {:write, i}

              1 ->
                # Read operation
                result = Market.get_ticker(exchange, symbol)
                {:read, result}

              2 ->
                # Write then read
                Market.put_ticker(exchange, symbol, %{op: :write_read, id: i})
                result = Market.get_ticker(exchange, symbol)
                {:write_read, result}
            end
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # No crashes, all operations complete
      assert length(results) == 50

      assert Enum.all?(results, fn
               {:write, _} -> true
               {:read, _} -> true
               {:write_read, {:ok, _}} -> true
               {:write_read, {:error, _}} -> true
               _ -> false
             end)
    end

    test "handles concurrent operations on different symbols" do
      # Spawn multiple tasks operating on different symbols
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            symbol = "SYMBOL_#{i}"
            ticker_data = %{price: "#{i * 1000}.00"}
            funding_data = %{rate: i * 0.0001}

            Market.put_ticker(:binance, symbol, ticker_data)
            Market.put_funding_rate(:bybit, symbol, funding_data)

            assert {:ok, ^ticker_data} = Market.get_ticker(:binance, symbol)
            assert {:ok, ^funding_data} = Market.get_funding_rate(:bybit, symbol)

            :ok
          end)
        end)

      # All tasks should complete successfully
      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "edge cases" do
    test "handles symbols with special characters" do
      special_symbols = ["BTC-USDT", "ETH_USDT", "DOT/USD", "BTC:USD-PERP"]

      Enum.each(special_symbols, fn symbol ->
        data = %{price: "1000.00", volume: "100.00"}
        Market.put_ticker(:binance, symbol, data)

        assert {:ok, ^data} = Market.get_ticker(:binance, symbol),
               "Failed for symbol: #{symbol}"
      end)
    end

    test "handles very long keys" do
      long_symbol = String.duplicate("A", 100)
      data = %{price: "1000.00"}

      Market.put_ticker(:very_long_exchange_name_test, long_symbol, data)
      assert {:ok, ^data} = Market.get_ticker(:very_long_exchange_name_test, long_symbol)
    end

    test "TTL validation in wrapper functions" do
      # Should accept positive integers
      assert :ok = Market.put_ticker(:binance, "BTCUSDT", %{}, 1)
      assert :ok = Market.put_ticker(:binance, "BTCUSDT", %{}, 3600)

      # Should reject non-positive integers
      assert_raise FunctionClauseError, fn ->
        Market.put_ticker(:binance, "BTCUSDT", %{}, 0)
      end

      assert_raise FunctionClauseError, fn ->
        Market.put_ticker(:binance, "BTCUSDT", %{}, -1)
      end
    end
  end
end
