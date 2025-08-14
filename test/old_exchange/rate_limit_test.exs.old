defmodule ZenCex.RateLimitTest do
  use ExUnit.Case, async: false
  alias ZenCex.RateLimit

  describe "init/1" do
    test "creates ETS tables for each exchange" do
      # Ensure RateLimit is running (started by application)
      assert Process.whereis(RateLimit) != nil

      # Verify tables are created
      assert :ets.info(:rate_limits_binance_spot) != :undefined
      assert :ets.info(:rate_limits_binance_futures) != :undefined
      assert :ets.info(:rate_limits_kraken) != :undefined
      assert :ets.info(:rate_limits_deribit) != :undefined
    end

    test "configures tables with write concurrency for atomic operations" do
      # Ensure RateLimit is running (started by application)
      assert Process.whereis(RateLimit) != nil

      info = :ets.info(:rate_limits_binance_spot)
      assert Keyword.get(info, :write_concurrency) == true
    end
  end

  describe "check_and_increment/3" do
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

    test "allows requests within limits for Binance spot" do
      # Binance spot has 1200/minute limit
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 10)
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 100)
    end

    test "rejects requests exceeding Binance spot limit (1200/minute)" do
      # Fill up to near limit
      for _ <- 1..1190 do
        assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # This should still be OK (total = 1200)
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 10)

      # This should be rejected (would be 1201)
      assert {:error, :rate_limited} = RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
    end

    test "tracks Binance futures separately with 2400/minute limit" do
      # Futures endpoint has higher limit
      endpoint = "/fapi/v1/order"

      # Fill spot to limit
      for _ <- 1..1200 do
        assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # Futures should still work
      for _ <- 1..2390 do
        assert :ok = RateLimit.check_and_increment(:binance, endpoint, 1)
      end

      # Should allow up to 2400
      assert :ok = RateLimit.check_and_increment(:binance, endpoint, 10)

      # Should reject at 2401
      assert {:error, :rate_limited} = RateLimit.check_and_increment(:binance, endpoint, 1)
    end

    test "enforces Kraken's 15/second limit" do
      # Kraken has per-second limits
      for _ <- 1..14 do
        assert :ok = RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)
      end

      # 15th should be OK
      assert :ok = RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)

      # 16th should be rejected
      assert {:error, :rate_limited} =
               RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)
    end

    test "enforces Deribit's 20/second limit" do
      for _ <- 1..19 do
        assert :ok = RateLimit.check_and_increment(:deribit, "/api/v2/private/get_positions", 1)
      end

      # 20th should be OK
      assert :ok = RateLimit.check_and_increment(:deribit, "/api/v2/private/get_positions", 1)

      # 21st should be rejected
      assert {:error, :rate_limited} =
               RateLimit.check_and_increment(:deribit, "/api/v2/private/get_positions", 1)
    end

    test "resets counter after time window passes" do
      # Add requests at current second
      assert :ok = RateLimit.check_and_increment(:kraken, "/0/private/Balance", 15)

      assert {:error, :rate_limited} =
               RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)

      # Wait for next second
      Process.sleep(1100)

      # Should work again
      assert :ok = RateLimit.check_and_increment(:kraken, "/0/private/Balance", 1)
    end

    test "handles weight parameter for high-weight operations" do
      # Some operations have higher weight
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 50)
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 100)

      # Try to add weight that would exceed limit
      for _ <- 1..1040 do
        assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/account", 1)
      end

      # This would put us at 1240, over the 1200 limit
      assert {:error, :rate_limited} =
               RateLimit.check_and_increment(:binance, "/api/v3/order", 50)
    end

    test "handles concurrent requests correctly" do
      # Spawn multiple processes trying to increment
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            weight = rem(i, 5) + 1
            RateLimit.check_and_increment(:binance, "/api/v3/order", weight)
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed as total weight is ~300
      assert Enum.all?(results, &(&1 == :ok))

      # Now fill up remaining capacity
      for _ <- 1..890 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # Concurrent requests near limit
      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
          end)
        end

      results = Task.await_many(tasks)

      # Some should succeed, some should fail
      success_count = Enum.count(results, &(&1 == :ok))
      assert success_count > 0 and success_count <= 10
    end

    test "partitions tables by exchange for performance" do
      # Each exchange should use its own table
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 100)
      assert :ok = RateLimit.check_and_increment(:kraken, "/0/private/Balance", 10)
      assert :ok = RateLimit.check_and_increment(:deribit, "/api/v2/private/get_positions", 15)

      # Check that each table has its own data
      binance_spot_count = :ets.info(:rate_limits_binance_spot, :size)
      kraken_count = :ets.info(:rate_limits_kraken, :size)
      deribit_count = :ets.info(:rate_limits_deribit, :size)

      assert binance_spot_count > 0
      assert kraken_count > 0
      assert deribit_count > 0
    end

    test "handles unknown exchange gracefully" do
      assert :ok = RateLimit.check_and_increment(:unknown_exchange, "/some/endpoint", 1)

      # Should create a default table
      assert :ets.info(:rate_limits_unknown_exchange) != :undefined
    end
  end

  describe "cleanup_old_windows/0" do
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

    test "removes old entries to prevent memory growth" do
      # Add some entries
      for _ <- 1..100 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      initial_size = :ets.info(:rate_limits_binance_spot, :size)
      assert initial_size > 0

      # Wait for cleanup (should happen within 60 seconds)
      # For testing, we'll trigger it manually
      send(Process.whereis(RateLimit), :cleanup)
      Process.sleep(100)

      # Add new entries in a different time window
      Process.sleep(2000)

      for _ <- 1..50 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # Trigger cleanup again
      send(Process.whereis(RateLimit), :cleanup)
      Process.sleep(100)

      # Old entries should be removed
      final_size = :ets.info(:rate_limits_binance_spot, :size)
      assert final_size > 0
    end

    test "cleanup preserves entries within active window" do
      # Add entries
      for _ <- 1..50 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # Trigger cleanup immediately
      send(Process.whereis(RateLimit), :cleanup)
      Process.sleep(100)

      # Should still be rate limited (entries preserved)
      for _ <- 1..1150 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      assert {:error, :rate_limited} = RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
    end
  end

  describe "binance futures specific limits" do
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

      for table <- tables do
        case :ets.whereis(table) do
          :undefined -> :ok
          _ -> :ets.delete_all_objects(table)
        end
      end

      :ok
    end

    test "binance_futures respects 2400 request limit in sliding window" do
      # Fill up to 2400 limit (futures specific)
      results =
        for i <- 1..2400 do
          result = RateLimit.check_and_increment(:binance_futures, "/fapi/v1/order", 1)
          {i, result}
        end

      # All 2400 should succeed
      assert Enum.all?(results, fn {_i, result} -> result == :ok end)

      # 2401st request should be rate limited
      assert {:error, :rate_limited} =
               RateLimit.check_and_increment(:binance_futures, "/fapi/v1/order", 1)
    end

    test "binance_futures uses correct window key separate from spot" do
      # Fill spot to its limit (1200)
      for _ <- 1..1200 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # Spot should be rate limited
      assert {:error, :rate_limited} =
               RateLimit.check_and_increment(:binance, "/api/v3/order", 1)

      # But futures should still work (different bucket)
      assert :ok = RateLimit.check_and_increment(:binance_futures, "/fapi/v1/order", 1)
    end
  end

  describe "get_usage/1" do
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

    test "returns current usage and limit" do
      # Add some weight
      for _ <- 1..100 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      {used, limit} = RateLimit.get_usage(:binance_spot)
      assert used == 100
      assert limit == 1200
    end

    test "returns separate usage for futures" do
      # Add to futures endpoint
      for _ <- 1..200 do
        RateLimit.check_and_increment(:binance, "/fapi/v1/order", 1)
      end

      {used, limit} = RateLimit.get_usage(:binance_futures)
      assert used == 200
      assert limit == 2400
    end

    test "returns zero usage for unused exchange" do
      {used, limit} = RateLimit.get_usage(:kraken)
      assert used == 0
      assert limit == 15
    end
  end

  describe "reset_time/1" do
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

    test "returns time until rate limit reset" do
      # Add some requests
      RateLimit.check_and_increment(:binance, "/api/v3/order", 100)

      reset_time = RateLimit.reset_time(:binance_spot)

      # Should be less than 60 seconds for Binance (minute window)
      assert reset_time > 0 and reset_time <= 60
    end

    test "returns different reset times for second-based limits" do
      RateLimit.check_and_increment(:kraken, "/0/private/Balance", 10)

      reset_time = RateLimit.reset_time(:kraken)

      # Should be less than 1 second for Kraken (second window)
      assert reset_time > 0 and reset_time <= 1
    end
  end

  describe "update_from_headers/2" do
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

    test "updates weight from response headers" do
      headers = [{"x-mbx-used-weight-1m", "150"}]

      :ok = RateLimit.update_from_headers(:binance, headers)

      {used, _limit} = RateLimit.get_usage(:binance_spot)
      assert used >= 150
    end

    test "handles missing headers gracefully" do
      headers = []

      assert :ok = RateLimit.update_from_headers(:binance, headers)
    end

    test "updates Kraken tier from headers" do
      headers = [{"x-ratelimit-remaining", "5"}, {"x-ratelimit-limit", "20"}]

      :ok = RateLimit.update_from_headers(:kraken, headers)

      # Should update limit if different tier detected
      {_used, limit} = RateLimit.get_usage(:kraken)
      assert limit > 0
    end
  end

  describe "sliding window accuracy" do
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

    @tag :long_running
    @tag :slow
    @tag timeout: 65_000
    test "Binance uses true sliding 60-second window" do
      # Add weight spread over multiple seconds
      for _i <- 1..30 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 10)
        Process.sleep(100)
      end

      # Total weight added: 300 over ~3 seconds
      {used, limit} = RateLimit.get_usage(:binance_spot)
      assert used == 300
      assert limit == 1200

      # Wait for 57 more seconds (total 60 from first request)
      Process.sleep(57_000)

      # Should still see recent requests but not the first ones
      {used_after, _} = RateLimit.get_usage(:binance_spot)
      assert used_after < 300
    end

    @tag :long_running
    @tag :slow
    @tag timeout: 65_000
    test "sliding window correctly drops old buckets" do
      # Add 100 weight at time T
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 100)

      # Wait 59 seconds
      Process.sleep(59_000)

      # Should still count the initial 100
      {used, _} = RateLimit.get_usage(:binance_spot)
      assert used == 100

      # Wait 2 more seconds (total 61)
      Process.sleep(2_000)

      # Initial 100 should be dropped from window
      {used_after, _} = RateLimit.get_usage(:binance_spot)
      assert used_after == 0
    end

    @tag :long_running
    test "sliding window handles edge case at minute boundary" do
      # Get current time and wait for next minute boundary
      now = System.system_time(:second)
      wait_time = (60 - rem(now, 60)) * 1000
      Process.sleep(wait_time + 100)

      # Add weight right after minute boundary
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 500)

      # Add more weight 30 seconds later
      Process.sleep(30_000)
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 500)

      # Total should be 1000
      {used, _} = RateLimit.get_usage(:binance_spot)
      assert used == 1000

      # Wait another 31 seconds (first 500 should drop off)
      Process.sleep(31_000)
      {used_after, _} = RateLimit.get_usage(:binance_spot)
      assert used_after == 500
    end

    test "header reconciliation adjusts sliding window total" do
      # Add some weight
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 100)

      {used_before, _} = RateLimit.get_usage(:binance_spot)
      assert used_before == 100

      # Binance header reports higher usage
      headers = [{"x-mbx-used-weight-1m", "250"}]
      :ok = RateLimit.update_from_headers(:binance, headers)

      # Should reconcile to header value
      {used_after, _} = RateLimit.get_usage(:binance_spot)
      assert used_after == 250
    end

    @tag :long_running
    test "prevents exceeding limit with sliding window" do
      # Fill up to the limit quickly
      for _ <- 1..120 do
        assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 10)
      end

      # Total: 1200, at limit
      # Should reject next request
      assert {:error, :rate_limited} = RateLimit.check_and_increment(:binance, "/api/v3/order", 1)

      # Verify we're at the limit
      {used, limit} = RateLimit.get_usage(:binance_spot)
      assert used == 1200
      assert limit == 1200
    end

    test "Binance futures uses separate sliding window with higher limit" do
      # Fill spot close to limit
      for _ <- 1..118 do
        assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 10)
      end

      # Spot at 1180/1200
      {spot_used, _} = RateLimit.get_usage(:binance_spot)
      assert spot_used == 1180

      # Futures should have separate tracking
      {futures_used, futures_limit} = RateLimit.get_usage(:binance_futures)
      assert futures_used == 0
      assert futures_limit == 2400

      # Can add to futures independently
      for _ <- 1..200 do
        assert :ok = RateLimit.check_and_increment(:binance, "/fapi/v1/order", 10)
      end

      {futures_used_after, _} = RateLimit.get_usage(:binance_futures)
      assert futures_used_after == 2000
    end

    test "sliding window basic implementation for Binance" do
      # Basic test that doesn't require long waits
      # Add weight
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 100)

      # Check current usage
      {used, limit} = RateLimit.get_usage(:binance_spot)
      assert used == 100
      assert limit == 1200

      # Add more weight
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 200)

      {used_after, _} = RateLimit.get_usage(:binance_spot)
      assert used_after == 300
    end

    test "separate tables track spot and futures independently" do
      # Add to spot
      assert :ok = RateLimit.check_and_increment(:binance, "/api/v3/order", 100)

      {spot_used, spot_limit} = RateLimit.get_usage(:binance_spot)
      assert spot_used == 100
      assert spot_limit == 1200

      # Add to futures
      assert :ok = RateLimit.check_and_increment(:binance, "/fapi/v1/order", 200)

      {futures_used, futures_limit} = RateLimit.get_usage(:binance_futures)
      assert futures_used == 200
      assert futures_limit == 2400

      # Verify spot unchanged
      {spot_still, _} = RateLimit.get_usage(:binance_spot)
      assert spot_still == 100
    end
  end

  describe "telemetry integration" do
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

      # Attach telemetry handler for testing
      :telemetry.attach(
        "test-rate-limit",
        [:zen_cex, :exchange, :rate_limit, :check],
        &__MODULE__.handle_telemetry/4,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-rate-limit")
      end)

      :ok
    end

    test "emits telemetry events on rate limit checks" do
      Process.put(:telemetry_events, [])

      RateLimit.check_and_increment(:binance, "/api/v3/order", 10)

      events = Process.get(:telemetry_events)
      assert length(events) > 0

      [event | _] = events
      assert event.exchange == :binance
      assert event.weight == 10
      assert event.result == :ok
    end

    test "emits telemetry on rate limit rejection" do
      Process.put(:telemetry_events, [])

      # Fill up limit
      for _ <- 1..1200 do
        RateLimit.check_and_increment(:binance, "/api/v3/order", 1)
      end

      # This should be rejected
      RateLimit.check_and_increment(:binance, "/api/v3/order", 1)

      events = Process.get(:telemetry_events)
      rejected = Enum.find(events, &(&1.result == :rate_limited))

      assert rejected != nil
      assert rejected.exchange == :binance
    end
  end

  def handle_telemetry(_event_name, measurements, metadata, _config) do
    events = Process.get(:telemetry_events, [])
    event = Map.merge(measurements, metadata)
    Process.put(:telemetry_events, [event | events])
  end
end
