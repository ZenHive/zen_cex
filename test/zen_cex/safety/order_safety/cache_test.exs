defmodule ZenCex.Safety.OrderSafety.CacheTest do
  @moduledoc """
  Tests for OrderSafety.Cache module.
  """

  use ExUnit.Case, async: true

  alias ZenCex.Safety.OrderSafety.Cache

  @market_data_cache_table :market_data_cache

  setup do
    # Ensure table exists for tests
    if :ets.info(@market_data_cache_table) == :undefined do
      :ets.new(@market_data_cache_table, [:set, :public, :named_table])
    else
      :ets.delete_all_objects(@market_data_cache_table)
    end

    :ok
  end

  describe "lookup/3 and put/3" do
    test "returns :miss for non-existent key" do
      assert Cache.lookup(:price, {:binance, "BTCUSDT"}, 5_000) == :miss
    end

    test "returns cached value within TTL" do
      key = {:binance, "BTCUSDT"}
      value = Decimal.new("50000.00")

      Cache.put(:price, key, value)
      assert {:ok, ^value} = Cache.lookup(:price, key, 5_000)
    end

    test "returns :miss for expired cache" do
      key = {:binance, "BTCUSDT"}
      value = Decimal.new("50000.00")

      # Put value with past timestamp to simulate expiry
      now_ms = System.system_time(:millisecond)
      old_timestamp = now_ms - 10_000
      :ets.insert(@market_data_cache_table, {{:price, key}, value, old_timestamp})

      # Should return :miss with 5 second TTL
      assert Cache.lookup(:price, key, 5_000) == :miss
    end

    test "emits telemetry events on cache hit" do
      key = {:binance, "BTCUSDT"}
      value = Decimal.new("50000.00")

      :telemetry.attach(
        "test-cache-hit",
        [:zen_cex, :order_safety, :cache, :hit],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      Cache.put(:price, key, value)
      Cache.lookup(:price, key, 5_000)

      assert_receive {:telemetry_event, %{count: 1}, %{cache_type: :price, key: ^key}}

      :telemetry.detach("test-cache-hit")
    end

    test "emits telemetry events on cache miss" do
      # Clear all caches to ensure a clean test
      Cache.clear_all()
      ZenCex.Cache.Market.clear_all()

      key = {:binance, "BTCUSDT"}

      :telemetry.attach(
        "test-cache-miss",
        [:zen_cex, :order_safety, :cache, :miss],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      Cache.lookup(:price, key, 5_000)

      assert_receive {:telemetry_event, %{count: 1}, %{cache_type: :price, key: ^key}}

      :telemetry.detach("test-cache-miss")
    end
  end

  describe "price cache helpers" do
    test "lookup_price and put_price work correctly" do
      key = {:binance, "BTCUSDT"}
      price = Decimal.new("50000.00")

      assert Cache.lookup_price(key) == :miss

      Cache.put_price(key, price)
      assert {:ok, ^price} = Cache.lookup_price(key)
    end
  end

  describe "symbol info cache helpers" do
    test "lookup_symbol_info and put_symbol_info work correctly" do
      key = {:binance, "BTCUSDT"}

      info = %{
        status: "TRADING",
        base_asset: "BTC",
        quote_asset: "USDT",
        filters: []
      }

      assert Cache.lookup_symbol_info(key) == :miss

      Cache.put_symbol_info(key, info)
      assert {:ok, ^info} = Cache.lookup_symbol_info(key)
    end
  end

  describe "min notional cache helpers" do
    test "lookup_min_notional and put_min_notional work correctly" do
      key = {:binance, "BTCUSDT"}
      min_notional = Decimal.new("10.00")

      assert Cache.lookup_min_notional(key) == :miss

      Cache.put_min_notional(key, min_notional)
      assert {:ok, ^min_notional} = Cache.lookup_min_notional(key)
    end
  end

  describe "invalidation functions" do
    test "invalidate_price removes price cache entry" do
      key = {:binance, "BTCUSDT"}
      price = Decimal.new("50000.00")

      Cache.put_price(key, price)
      assert {:ok, ^price} = Cache.lookup_price(key)

      :ok = Cache.invalidate_price(:binance, "BTCUSDT")
      assert Cache.lookup_price(key) == :miss
    end

    test "invalidate_symbol_info removes symbol info and min notional" do
      key = {:binance, "BTCUSDT"}
      info = %{status: "TRADING"}
      min_notional = Decimal.new("10.00")

      Cache.put_symbol_info(key, info)
      Cache.put_min_notional(key, min_notional)

      :ok = Cache.invalidate_symbol_info(:binance, "BTCUSDT")

      assert Cache.lookup_symbol_info(key) == :miss
      assert Cache.lookup_min_notional(key) == :miss
    end

    test "invalidate_min_notional removes min notional cache entry" do
      key = {:binance, "BTCUSDT"}
      min_notional = Decimal.new("10.00")

      Cache.put_min_notional(key, min_notional)
      assert {:ok, ^min_notional} = Cache.lookup_min_notional(key)

      :ok = Cache.invalidate_min_notional(:binance, "BTCUSDT")
      assert Cache.lookup_min_notional(key) == :miss
    end

    test "invalidate_exchange removes all entries for an exchange" do
      # Add entries for multiple exchanges
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))
      Cache.put_price({:binance, "ETHUSDT"}, Decimal.new("3000"))
      Cache.put_price({:bybit, "BTCUSDT"}, Decimal.new("50100"))
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING"})
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10"))

      {:ok, count} = Cache.invalidate_exchange(:binance)
      assert count >= 3

      # Binance entries should be gone
      assert Cache.lookup_price({:binance, "BTCUSDT"}) == :miss
      assert Cache.lookup_price({:binance, "ETHUSDT"}) == :miss
      assert Cache.lookup_symbol_info({:binance, "BTCUSDT"}) == :miss
      assert Cache.lookup_min_notional({:binance, "BTCUSDT"}) == :miss

      # Bybit entry should remain
      assert {:ok, _} = Cache.lookup_price({:bybit, "BTCUSDT"})
    end
  end

  describe "clear_all/0" do
    test "removes all cache entries" do
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))
      Cache.put_symbol_info({:bybit, "ETHUSDT"}, %{status: "TRADING"})
      Cache.put_min_notional({:kraken, "BTCUSD"}, Decimal.new("5"))

      :ok = Cache.clear_all()

      assert Cache.lookup_price({:binance, "BTCUSDT"}) == :miss
      assert Cache.lookup_symbol_info({:bybit, "ETHUSDT"}) == :miss
      assert Cache.lookup_min_notional({:kraken, "BTCUSD"}) == :miss
    end
  end

  describe "cleanup/1" do
    test "removes expired entries based on TTL" do
      now_ms = System.system_time(:millisecond)

      # In test config, we have:
      # price_cache_ttl_ms: 10 seconds (10_000ms)
      # symbol_info_cache_ttl_ms: 5 minutes (300_000ms)
      # min_notional_cache_ttl_ms: 5 minutes (300_000ms)

      # Insert entries with different ages
      # Recent price (within 10 second TTL)
      :ets.insert(@market_data_cache_table, {{:price, {:binance, "NEW"}}, Decimal.new("100"), now_ms - 5_000})

      # Old price (exceeds 10 second TTL)
      :ets.insert(@market_data_cache_table, {{:price, {:binance, "OLD"}}, Decimal.new("200"), now_ms - 15_000})

      # Very old symbol info (exceeds 5 minute TTL)
      :ets.insert(@market_data_cache_table, {{:symbol_info, {:binance, "OLDBTC"}}, %{}, now_ms - 400_000})

      # Very old min notional (exceeds 5 minute TTL)
      :ets.insert(@market_data_cache_table, {{:min_notional, {:binance, "OLDBTC"}}, Decimal.new("10"), now_ms - 400_000})

      # Recent symbol info (within 5 minute TTL, should remain)
      :ets.insert(@market_data_cache_table, {{:symbol_info, {:binance, "BTCUSDT"}}, %{}, now_ms - 30_000})

      # Recent min notional (within 5 minute TTL, should remain)
      :ets.insert(@market_data_cache_table, {{:min_notional, {:binance, "BTCUSDT"}}, Decimal.new("10"), now_ms - 30_000})

      deleted_count = Cache.cleanup(now_ms)

      # Should delete: 1 old price + 1 old symbol_info + 1 old min_notional = 3 entries
      assert deleted_count >= 3
      assert {:ok, _} = Cache.lookup_price({:binance, "NEW"})
      assert Cache.lookup_price({:binance, "OLD"}) == :miss
      assert Cache.lookup_symbol_info({:binance, "OLDBTC"}) == :miss
      assert Cache.lookup_min_notional({:binance, "OLDBTC"}) == :miss
      # These should still exist
      assert {:ok, _} = Cache.lookup_symbol_info({:binance, "BTCUSDT"})
      assert {:ok, _} = Cache.lookup_min_notional({:binance, "BTCUSDT"})
    end
  end

  describe "stats/0" do
    test "returns cache statistics" do
      # Clear cache first to ensure clean test
      Cache.clear_all()

      # Add some cache entries
      Cache.put_price({:binance, "BTCUSDT"}, Decimal.new("50000"))
      Cache.put_price({:binance, "ETHUSDT"}, Decimal.new("3000"))
      Cache.put_symbol_info({:binance, "BTCUSDT"}, %{status: "TRADING"})
      Cache.put_min_notional({:binance, "BTCUSDT"}, Decimal.new("10"))

      stats = Cache.stats()

      assert is_map(stats)
      # Use Map.get with defaults since the cache_type atom might vary
      price_stats = Map.get(stats, :price, %{})
      symbol_info_stats = Map.get(stats, :symbol_info, %{})
      min_notional_stats = Map.get(stats, :min_notional, %{})

      assert price_stats[:count] == 2
      assert symbol_info_stats[:count] == 1
      assert min_notional_stats[:count] == 1

      # Check that avg_age_ms and oldest_ms are present and reasonable
      assert is_number(price_stats[:avg_age_ms])
      assert is_number(price_stats[:oldest_ms])
      assert price_stats[:avg_age_ms] >= 0
      assert price_stats[:oldest_ms] >= 0
    end

    test "returns empty stats when cache is empty" do
      Cache.clear_all()
      stats = Cache.stats()

      assert is_map(stats)
      assert map_size(stats) == 0 or Enum.all?(stats, fn {_k, v} -> v[:count] == 0 end)
    end
  end
end
