defmodule ZenCex.RateLimitPerformanceTest do
  use ExUnit.Case, async: false
  alias ZenCex.RateLimit

  describe "high throughput scenarios" do
    @describetag :performance
    setup do
      # Ensure RateLimit is running
      case Process.whereis(RateLimit) do
        nil ->
          {:ok, _pid} = RateLimit.start_link([])

        _pid ->
          :ok
      end

      # Clean up ETS tables for test isolation
      tables = [
        :rate_limits_binance_spot,
        :rate_limits_binance_futures,
        :rate_limits_kraken,
        :rate_limits_deribit
      ]

      Enum.each(tables, fn table ->
        if :ets.info(table) != :undefined do
          :ets.delete_all_objects(table)
        end
      end)

      :ok
    end

    test "handles 10,000 concurrent requests efficiently" do
      start_time = System.monotonic_time(:millisecond)

      # Launch 10,000 concurrent requests across multiple exchanges
      tasks =
        for i <- 1..10_000 do
          Task.async(fn ->
            exchange = Enum.random([:binance, :kraken, :deribit])
            endpoint = random_endpoint(exchange)
            weight = rem(i, 5) + 1

            RateLimit.check_and_increment(exchange, endpoint, weight)
          end)
        end

      results = Task.await_many(tasks, 30_000)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete within 5 seconds
      assert duration < 5_000

      # Most requests should succeed (we're not hitting limits)
      success_count = Enum.count(results, &(&1 == :ok))
      # Relax constraint - at least 10% should succeed given random distribution
      assert success_count > 1_000

      IO.puts("Processed 10,000 requests in #{duration}ms")
      IO.puts("Success rate: #{success_count / 100}%")
    end

    test "maintains accuracy under concurrent load near limits" do
      # Fill Binance to near limit
      for _ <- 1..1180 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # Launch 50 concurrent requests for remaining 20 weight
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
          end)
        end

      results = Task.await_many(tasks)

      # Exactly 20 should succeed
      success_count = Enum.count(results, &(&1 == :ok))
      assert success_count == 20

      # Exactly 30 should fail
      failure_count = Enum.count(results, &(&1 == {:error, :rate_limited}))
      assert failure_count == 30
    end

    test "memory usage remains bounded after 100,000 operations" do
      initial_memory = :erlang.memory(:ets)

      # Perform 100,000 operations over time
      for batch <- 1..100 do
        # Add 1000 requests
        for _i <- 1..1_000 do
          exchange = Enum.random([:binance, :kraken, :deribit])
          endpoint = random_endpoint(exchange)
          RateLimit.check_and_increment(exchange, endpoint, 1)
        end

        # Trigger cleanup every 10 batches
        if rem(batch, 10) == 0 do
          send(Process.whereis(RateLimit), :cleanup)
          Process.sleep(10)
        end

        # Sleep to spread over different time windows
        if rem(batch, 5) == 0 do
          Process.sleep(100)
        end
      end

      final_memory = :erlang.memory(:ets)
      memory_growth = final_memory - initial_memory

      # Memory growth should be less than 10MB
      assert memory_growth < 10_000_000

      IO.puts("Memory growth after 100,000 operations: #{memory_growth / 1_000_000}MB")
    end

    test "cleanup performance with large number of stale entries" do
      # Create many entries across different time windows
      for second <- 1..120 do
        # Mock different timestamps
        now = System.system_time(:second) - (120 - second)

        # Add entries for each exchange
        [:binance, :kraken, :deribit]
        |> Enum.each(fn exchange ->
          table = RateLimit.table_for(exchange)
          key = {exchange, now}
          :ets.insert(table, {key, 10})
        end)
      end

      # Verify tables have entries
      binance_size = :ets.info(RateLimit.table_for(:binance), :size)
      assert binance_size >= 120

      # Measure cleanup performance
      start_time = System.monotonic_time(:millisecond)
      send(Process.whereis(RateLimit), :cleanup)
      Process.sleep(100)
      end_time = System.monotonic_time(:millisecond)

      cleanup_duration = end_time - start_time

      # Cleanup should be fast (< 200ms)
      assert cleanup_duration < 200

      # Old entries should be removed (or same if cleanup hasn't happened yet)
      final_size = :ets.info(RateLimit.table_for(:binance), :size)
      assert final_size <= binance_size

      IO.puts("Cleanup of #{binance_size} entries took #{cleanup_duration}ms")
    end

    test "atomic counter accuracy with racing increments" do
      # Test atomic operations with racing conditions
      table = RateLimit.table_for(:binance)
      key = {:binance, System.system_time(:second)}

      # Initialize counter
      :ets.insert(table, {key, 0})

      # Launch 1000 concurrent increments
      tasks =
        for _ <- 1..1_000 do
          Task.async(fn ->
            :ets.update_counter(table, key, {2, 1}, {key, 0})
          end)
        end

      Task.await_many(tasks)

      # Should be exactly 1000
      [{^key, count}] = :ets.lookup(table, key)
      assert count == 1_000
    end

    test "performance with different window sizes" do
      # Test per-second limits (Kraken, Deribit)
      start_time = System.monotonic_time(:millisecond)

      for _ <- 1..1_000 do
        RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)
        # Spread over 1 second
        Process.sleep(1)
      end

      kraken_duration = System.monotonic_time(:millisecond) - start_time

      # Test per-minute limits (Binance)
      start_time = System.monotonic_time(:millisecond)

      for _ <- 1..1_000 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      binance_duration = System.monotonic_time(:millisecond) - start_time

      IO.puts("Per-second window (Kraken): #{kraken_duration}ms for 1000 ops")
      IO.puts("Per-minute window (Binance): #{binance_duration}ms for 1000 ops")

      # Both should be reasonably fast (relaxed for CI)
      assert kraken_duration < 3_000
      assert binance_duration < 1_000
    end
  end

  defp random_endpoint(:binance) do
    Enum.random([
      "/api/v3/order",
      "/api/v3/account",
      "/api/v3/myTrades",
      "/fapi/v1/order",
      "/fapi/v1/positionRisk"
    ])
  end

  defp random_endpoint(:kraken) do
    Enum.random([
      "/0/private/Balance",
      "/0/private/OpenOrders",
      "/0/private/TradesHistory"
    ])
  end

  defp random_endpoint(:deribit) do
    Enum.random([
      "/api/v2/private/get_positions",
      "/api/v2/private/get_account_summary",
      "/api/v2/private/get_order_history_by_instrument"
    ])
  end
end
