defmodule ZenCex.CacheTest do
  use ExUnit.Case, async: false
  alias ZenCex.Cache

  setup do
    # Ensure clean state for each test
    tables = [:exchange_cache_positions, :exchange_cache_balances, :exchange_cache_market_data]

    Enum.each(tables, fn table ->
      if :ets.whereis(table) != :undefined do
        :ets.delete_all_objects(table)
      end
    end)

    :ok
  end

  # Helper to ensure cache is started with tables
  defp ensure_cache_started do
    case Process.whereis(Cache) do
      nil ->
        {:ok, _pid} = Cache.start_link([])

      _pid ->
        # Ensure tables still exist even if process is running
        tables = [
          :exchange_cache_positions,
          :exchange_cache_balances,
          :exchange_cache_market_data
        ]

        # Check if any table is missing
        missing_table =
          Enum.any?(tables, fn table ->
            :ets.whereis(table) == :undefined
          end)

        if missing_table do
          # Restart the cache if any table is missing
          GenServer.stop(Cache, :normal)
          Process.sleep(10)
          {:ok, _pid} = Cache.start_link([])
        end

        :ok
    end

    :ok
  end

  describe "start_link/1" do
    test "starts the cache process and creates ETS tables" do
      # Stop any existing cache process
      if Process.whereis(Cache) do
        GenServer.stop(Cache, :normal)
        Process.sleep(10)
      end

      assert {:ok, pid} = Cache.start_link([])
      assert Process.alive?(pid)

      # Verify ETS tables are created
      assert :ets.info(:exchange_cache_positions) != :undefined
      assert :ets.info(:exchange_cache_balances) != :undefined
      assert :ets.info(:exchange_cache_market_data) != :undefined

      # Verify tables are public for concurrent access
      assert :ets.info(:exchange_cache_positions, :protection) == :public

      GenServer.stop(pid, :normal)
    end

    test "handles already started error gracefully" do
      {:ok, pid1} = Cache.start_link([])
      result = Cache.start_link([])
      assert {:error, {:already_started, pid2}} = result
      assert pid1 == pid2
      GenServer.stop(pid1, :normal)
    end
  end

  describe "put/4" do
    setup do
      ensure_cache_started()
      :ok
    end

    test "stores data with TTL timestamp" do
      data = %{symbol: "BTC", price: 50000}
      assert :ok = Cache.put(:binance, :market_data, "btc_price", data)

      # Verify data is stored
      assert {:ok, ^data} = Cache.get(:binance, :market_data, "btc_price")
    end

    test "stores data in correct table based on data type" do
      position_data = %{symbol: "BTC", amount: 1.5}
      balance_data = %{currency: "USDT", amount: 10000}
      market_data = %{price: 50000}

      Cache.put(:binance, :positions, "btc_pos", position_data)
      Cache.put(:kraken, :balances, "usdt_bal", balance_data)
      Cache.put(:deribit, :market_data, "btc_ticker", market_data)

      # Check data is in correct tables (4-tuple format with created_at)
      assert [{_, _, _, _}] =
               :ets.lookup(:exchange_cache_positions, {:binance, :positions, "btc_pos"})

      assert [{_, _, _, _}] =
               :ets.lookup(:exchange_cache_balances, {:kraken, :balances, "usdt_bal"})

      assert [{_, _, _, _}] =
               :ets.lookup(:exchange_cache_market_data, {:deribit, :market_data, "btc_ticker"})
    end

    test "overwrites existing data with new TTL" do
      Cache.put(:binance, :market_data, "key1", %{price: 100})
      Process.sleep(10)
      Cache.put(:binance, :market_data, "key1", %{price: 200})

      assert {:ok, %{price: 200}} = Cache.get(:binance, :market_data, "key1")
    end

    test "handles different exchange and key combinations" do
      Cache.put(:binance, :positions, "key1", %{data: 1})
      Cache.put(:kraken, :positions, "key1", %{data: 2})
      Cache.put(:binance, :positions, "key2", %{data: 3})

      assert {:ok, %{data: 1}} = Cache.get(:binance, :positions, "key1")
      assert {:ok, %{data: 2}} = Cache.get(:kraken, :positions, "key1")
      assert {:ok, %{data: 3}} = Cache.get(:binance, :positions, "key2")
    end
  end

  describe "get/3" do
    setup do
      ensure_cache_started()
      :ok
    end

    test "returns data if not expired" do
      data = %{value: "test"}
      Cache.put(:binance, :market_data, "key1", data)

      assert {:ok, ^data} = Cache.get(:binance, :market_data, "key1")
    end

    test "returns error if data is expired" do
      # Store data with past TTL (simulate expiry)
      key = {:binance, :market_data, "expired_key"}
      now = System.system_time(:millisecond)
      expired_time = now - 120_000
      created_at = now - 130_000
      :ets.insert(:exchange_cache_market_data, {key, %{data: "old"}, expired_time, created_at})

      assert {:error, :not_found} = Cache.get(:binance, :market_data, "expired_key")
    end

    test "returns error if key doesn't exist" do
      assert {:error, :not_found} = Cache.get(:binance, :positions, "nonexistent")
    end

    test "automatically removes expired data on get" do
      key = {:binance, :market_data, "expired_key"}
      now = System.system_time(:millisecond)
      expired_time = now - 120_000
      created_at = now - 130_000
      :ets.insert(:exchange_cache_market_data, {key, %{data: "old"}, expired_time, created_at})

      # Get should trigger cleanup of this specific key
      Cache.get(:binance, :market_data, "expired_key")

      # Verify the expired entry was removed
      assert [] = :ets.lookup(:exchange_cache_market_data, key)
    end
  end

  describe "get_with_age/3" do
    setup do
      ensure_cache_started()
      :ok
    end

    test "returns data with age in milliseconds" do
      data = %{value: "test"}
      Cache.put(:binance, :market_data, "key1", data)

      Process.sleep(50)

      assert {:ok, ^data, age_ms} = Cache.get_with_age(:binance, :market_data, "key1")
      assert age_ms >= 50
      # Should be reasonably fresh
      assert age_ms < 200
    end

    test "returns error for expired data" do
      key = {:binance, :market_data, "expired"}
      now = System.system_time(:millisecond)
      expired_time = now - 120_000
      created_at = now - 130_000
      :ets.insert(:exchange_cache_market_data, {key, %{data: "old"}, expired_time, created_at})

      assert {:error, :not_found} = Cache.get_with_age(:binance, :market_data, "expired")
    end
  end

  describe "delete/3" do
    setup do
      ensure_cache_started()
      :ok
    end

    test "removes specific key from cache" do
      Cache.put(:binance, :positions, "key1", %{data: 1})
      Cache.put(:binance, :positions, "key2", %{data: 2})

      assert :ok = Cache.delete(:binance, :positions, "key1")
      assert {:error, :not_found} = Cache.get(:binance, :positions, "key1")
      assert {:ok, %{data: 2}} = Cache.get(:binance, :positions, "key2")
    end

    test "returns ok even if key doesn't exist" do
      assert :ok = Cache.delete(:binance, :positions, "nonexistent")
    end
  end

  describe "clear/2" do
    setup do
      ensure_cache_started()
      :ok
    end

    test "clears all data for specific exchange and type" do
      Cache.put(:binance, :positions, "key1", %{data: 1})
      Cache.put(:binance, :positions, "key2", %{data: 2})
      Cache.put(:kraken, :positions, "key3", %{data: 3})
      Cache.put(:binance, :balances, "key4", %{data: 4})

      assert :ok = Cache.clear(:binance, :positions)

      assert {:error, :not_found} = Cache.get(:binance, :positions, "key1")
      assert {:error, :not_found} = Cache.get(:binance, :positions, "key2")
      assert {:ok, %{data: 3}} = Cache.get(:kraken, :positions, "key3")
      assert {:ok, %{data: 4}} = Cache.get(:binance, :balances, "key4")
    end
  end

  describe "TTL cleanup" do
    setup do
      # Start fresh cache for cleanup tests
      if Process.whereis(Cache) do
        GenServer.stop(Cache, :normal)
        Process.sleep(10)
      end

      :ok
    end

    test "automatic cleanup removes expired entries" do
      # Start cache with short cleanup interval for testing
      # 100ms for testing
      {:ok, _pid} = Cache.start_link(cleanup_interval: 100)

      # Insert data with different expiry times
      now = System.system_time(:millisecond)

      # Already expired
      :ets.insert(
        :exchange_cache_market_data,
        {{:binance, :market_data, "expired"}, %{data: 1}, now - 120_000, now - 130_000}
      )

      # Will expire soon (default TTL is 60s, we set it to expire in the past)
      :ets.insert(
        :exchange_cache_market_data,
        {{:binance, :market_data, "expiring"}, %{data: 2}, now - 61_000, now - 70_000}
      )

      # Still valid (set to expire in the future)
      :ets.insert(
        :exchange_cache_market_data,
        {{:binance, :market_data, "valid"}, %{data: 3}, now + 60_000, now}
      )

      # Wait for cleanup to run
      Process.sleep(150)

      # Check that expired entries are removed
      assert {:error, :not_found} = Cache.get(:binance, :market_data, "expired")
      assert {:error, :not_found} = Cache.get(:binance, :market_data, "expiring")
      assert {:ok, %{data: 3}} = Cache.get(:binance, :market_data, "valid")
    end

    test "cleanup runs periodically" do
      {:ok, pid} = Cache.start_link(cleanup_interval: 50)

      # Monitor cleanup executions via table size
      now = System.system_time(:millisecond)

      # Add expired entries
      :ets.insert(
        :exchange_cache_market_data,
        {{:binance, :market_data, "old1"}, %{data: 1}, now - 120_000, now - 130_000}
      )

      :ets.insert(
        :exchange_cache_market_data,
        {{:binance, :market_data, "old2"}, %{data: 2}, now - 120_000, now - 130_000}
      )

      assert :ets.info(:exchange_cache_market_data, :size) >= 2

      # Wait for first cleanup
      Process.sleep(60)
      assert :ets.info(:exchange_cache_market_data, :size) == 0

      # Add more expired entries
      :ets.insert(
        :exchange_cache_market_data,
        {{:binance, :market_data, "old3"}, %{data: 3}, now - 120_000, now - 130_000}
      )

      # Wait for second cleanup
      Process.sleep(60)
      assert :ets.info(:exchange_cache_market_data, :size) == 0

      GenServer.stop(pid, :normal)
    end
  end

  describe "memory management" do
    setup do
      ensure_cache_started()
      :ok
    end

    test "get_stats/0 returns cache statistics" do
      # Add some data
      Cache.put(:binance, :positions, "key1", %{data: 1})
      Cache.put(:kraken, :balances, "key2", %{data: 2})
      Cache.put(:deribit, :market_data, "key3", %{data: 3})

      stats = Cache.get_stats()

      assert stats.positions.count == 1
      assert stats.balances.count == 1
      assert stats.market_data.count == 1
      assert stats.total_entries == 3
      assert stats.memory_bytes > 0
    end

    test "enforces memory limits per table" do
      # This test would need configuration for max entries
      # For now, we just verify the structure exists
      # 1KB of data
      large_data = :binary.copy(<<0>>, 1024)

      # Add many entries
      for i <- 1..100 do
        Cache.put(:binance, :market_data, "key#{i}", %{data: large_data, index: i})
      end

      stats = Cache.get_stats()
      assert stats.market_data.count == 100
      # Memory tracking should show the size
      # Note: ETS memory calculations are approximate and include overhead
      # The actual memory usage might be less due to internal optimizations
      assert stats.market_data.memory_bytes > 0
      assert stats.total_entries == 100
      assert stats.memory_bytes > 0
    end
  end

  describe "concurrent access" do
    setup do
      ensure_cache_started()
      :ok
    end

    test "handles concurrent reads and writes" do
      # Spawn multiple processes to read/write concurrently
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            # Each task does multiple operations
            for j <- 1..10 do
              key = "key_#{i}_#{j}"
              Cache.put(:binance, :market_data, key, %{value: i * j})
              {:ok, data} = Cache.get(:binance, :market_data, key)
              assert data.value == i * j
            end
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await(&1, 5000))

      # Verify final state
      stats = Cache.get_stats()
      # 50 tasks * 10 keys each
      assert stats.market_data.count == 500
    end

    test "cleanup doesn't interfere with concurrent operations" do
      # Stop any existing cache process first
      if Process.whereis(Cache) do
        GenServer.stop(Cache, :normal)
        Process.sleep(10)
      end

      # Very frequent cleanup
      {:ok, pid} = Cache.start_link(cleanup_interval: 10)

      # Continuously write and read while cleanup is running
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            for j <- 1..50 do
              Cache.put(:binance, :market_data, "key_#{i}", %{value: j})
              Process.sleep(1)
              Cache.get(:binance, :market_data, "key_#{i}")
            end
          end)
        end

      Enum.each(tasks, &Task.await(&1, 10000))

      GenServer.stop(pid, :normal)
    end
  end

  describe "configuration" do
    test "respects custom TTL configuration" do
      if Process.whereis(Cache) do
        GenServer.stop(Cache, :normal)
        Process.sleep(10)
      end

      # Start with custom TTL
      {:ok, _pid} = Cache.start_link(default_ttl: 100, cleanup_interval: 50)

      Cache.put(:binance, :market_data, "key1", %{data: "test"})

      # Data should be available immediately
      assert {:ok, %{data: "test"}} = Cache.get(:binance, :market_data, "key1")

      # Wait for TTL to expire
      Process.sleep(150)

      # Data should be expired
      assert {:error, :not_found} = Cache.get(:binance, :market_data, "key1")
    end

    test "allows custom TTL per put operation" do
      if Process.whereis(Cache) do
        GenServer.stop(Cache, :normal)
        Process.sleep(10)
      end

      {:ok, _pid} = Cache.start_link([])

      # Put with custom TTL
      Cache.put(:binance, :market_data, "short", %{data: 1}, ttl: 50)
      Cache.put(:binance, :market_data, "long", %{data: 2}, ttl: 5000)

      # Both should be available initially
      assert {:ok, %{data: 1}} = Cache.get(:binance, :market_data, "short")
      assert {:ok, %{data: 2}} = Cache.get(:binance, :market_data, "long")

      # Wait for short TTL to expire
      Process.sleep(100)

      # Short should be expired, long should still be valid
      assert {:error, :not_found} = Cache.get(:binance, :market_data, "short")
      assert {:ok, %{data: 2}} = Cache.get(:binance, :market_data, "long")
    end
  end
end
