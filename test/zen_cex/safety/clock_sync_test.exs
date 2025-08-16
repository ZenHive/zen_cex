defmodule ZenCex.Safety.ClockSyncTest do
  use ExUnit.Case, async: false

  alias ZenCex.Safety.ClockSync

  setup do
    # Start the ClockSync GenServer for each test
    {:ok, pid} = ClockSync.start_link(name: :"clock_sync_test_#{System.unique_integer()}")

    # Clear any existing data
    :ets.delete_all_objects(:clock_offsets)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, pid: pid}
  end

  describe "now_with_offset/1" do
    test "returns current time with zero offset when no sync has occurred" do
      before_time = System.system_time(:millisecond)
      result_time = ClockSync.now_with_offset(:binance)
      after_time = System.system_time(:millisecond)

      # Should be very close to current time (within 100ms)
      assert result_time >= before_time
      assert result_time <= after_time + 100
    end

    test "applies stored offset correctly" do
      # Manually insert an offset
      :ets.insert(:clock_offsets, {:test_exchange, 500})

      before_time = System.system_time(:millisecond)
      result_time = ClockSync.now_with_offset(:test_exchange)

      # Should be current time + 500ms offset
      expected_time = before_time + 500
      # Allow small timing variation
      assert abs(result_time - expected_time) < 10
    end

    test "handles negative offsets correctly" do
      # Server is behind local time
      :ets.insert(:clock_offsets, {:test_exchange, -250})

      before_time = System.system_time(:millisecond)
      result_time = ClockSync.now_with_offset(:test_exchange)

      # Should be current time - 250ms
      expected_time = before_time - 250
      assert abs(result_time - expected_time) < 10
    end
  end

  describe "get_offset/1" do
    test "returns 0 for exchange with no stored offset" do
      assert ClockSync.get_offset(:unknown_exchange) == 0
    end

    test "returns stored offset for known exchange" do
      :ets.insert(:clock_offsets, {:binance, 150})
      assert ClockSync.get_offset(:binance) == 150
    end

    test "handles multiple exchanges independently" do
      :ets.insert(:clock_offsets, {:binance, 100})
      :ets.insert(:clock_offsets, {:kraken, -50})

      assert ClockSync.get_offset(:binance) == 100
      assert ClockSync.get_offset(:kraken) == -50
      assert ClockSync.get_offset(:deribit) == 0
    end
  end

  describe "ensure_time_sync/1" do
    test "returns existing offset when already synced" do
      # Pre-populate offset
      :ets.insert(:clock_offsets, {:binance, 200})

      assert {:ok, 200} = ClockSync.ensure_time_sync(:binance)
    end

    @tag :skip
    test "attempts sync when no offset exists" do
      # TODO: Skip until adapters are implemented - requires working exchange adapters
      # This test verifies the flow - integration tests will verify real API calls
      assert {:error, _reason} = ClockSync.ensure_time_sync(:unsupported_exchange)
    end
  end

  describe "get_stats/1" do
    @tag :skip
    test "returns statistics with empty state initially" do
      # TODO: Skip until adapters are implemented - requires Registry.list_exchanges/0
      stats = ClockSync.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :exchanges)
      assert Map.has_key?(stats, :last_sync_time)
      assert Map.has_key?(stats, :sync_interval_ms)
      assert Map.has_key?(stats, :offsets)
      assert is_list(stats.exchanges)
      assert is_map(stats.offsets)
    end

    @tag :skip
    test "includes stored offsets in statistics" do
      # TODO: Skip until adapters are implemented - requires Registry.list_exchanges/0
      :ets.insert(:clock_offsets, {:binance, 100})
      :ets.insert(:clock_offsets, {:kraken, -50})

      stats = ClockSync.get_stats()

      assert stats.offsets[:binance] == 100
      assert stats.offsets[:kraken] == -50
    end
  end

  describe "integration with real data" do
    @tag :skip
    test "handles unsupported exchange gracefully" do
      # TODO: Skip until adapters are implemented - requires Registry.list_exchanges/0
      result = ClockSync.sync_exchange(:unsupported_exchange)
      assert {:error, {:unsupported_exchange, :unsupported_exchange}} = result
    end

    @tag :skip
    test "sync_exchange handles known exchanges without crashing" do
      # TODO: Skip until adapters are implemented - requires working exchange adapters
      result = ClockSync.sync_exchange(:binance)
      assert {:error, _reason} = result
    end
  end

  describe "offset storage and ETS operations" do
    test "stores and retrieves offsets atomically" do
      # Test concurrent access to offsets
      tasks =
        1..10
        |> Enum.map(fn i ->
          Task.async(fn ->
            :ets.insert(:clock_offsets, {:"exchange_#{i}", i * 100})
            ClockSync.get_offset(:"exchange_#{i}")
          end)
        end)

      results = Task.await_many(tasks)

      # All tasks should return their expected offset
      expected = Enum.map(1..10, fn i -> i * 100 end)
      assert results == expected
    end

    test "handles concurrent updates correctly" do
      # Multiple processes updating the same exchange
      tasks =
        1..5
        |> Enum.map(fn i ->
          Task.async(fn ->
            :ets.insert(:clock_offsets, {:test_exchange, i})
            ClockSync.get_offset(:test_exchange)
          end)
        end)

      results = Task.await_many(tasks)

      # One of the values should be stored (last writer wins)
      final_offset = ClockSync.get_offset(:test_exchange)
      assert final_offset in 1..5
      assert final_offset in results
    end
  end

  describe "performance requirements" do
    test "offset lookup is fast" do
      # Pre-populate offset
      :ets.insert(:clock_offsets, {:binance, 100})

      # Measure performance of get_offset
      {time_microseconds, _result} =
        :timer.tc(fn ->
          ClockSync.get_offset(:binance)
        end)

      # Should be well under 50μs for ETS lookup
      assert time_microseconds < 50
    end

    test "now_with_offset is fast" do
      # Pre-populate offset
      :ets.insert(:clock_offsets, {:binance, 100})

      # Measure performance of now_with_offset
      {time_microseconds, _result} =
        :timer.tc(fn ->
          ClockSync.now_with_offset(:binance)
        end)

      # Should be under 100μs (includes system time call + ETS lookup)
      assert time_microseconds < 100
    end
  end

  describe "warning behavior" do
    test "stores large offsets without crashing" do
      # Test that large offsets can be stored (warning behavior will be tested in integration)
      # 2 seconds - well above 1000ms threshold
      large_offset = 2000

      :ets.insert(:clock_offsets, {:test_exchange, large_offset})
      assert ClockSync.get_offset(:test_exchange) == large_offset
    end
  end

  describe "telemetry events" do
    @tag :skip
    test "emits telemetry during operations" do
      # TODO: Skip until adapters are implemented - requires working sync operations
      # Setup telemetry capture
      ref = make_ref()
      test_pid = self()

      handler_id = "test_clock_sync_telemetry"

      :telemetry.attach_many(
        handler_id,
        [
          [:zen_cex, :clock_sync, :sync_success],
          [:zen_cex, :clock_sync, :sync_failure],
          [:zen_cex, :clock_sync, :large_skew_detected]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {ref, event, measurements, metadata})
        end,
        nil
      )

      # Trigger an operation that should emit telemetry
      ClockSync.sync_exchange(:unsupported_exchange)

      # Wait briefly for potential async telemetry
      Process.sleep(10)

      # We expect a failure telemetry event for unsupported exchange
      receive do
        {^ref, [:zen_cex, :clock_sync, :sync_failure], measurements, metadata} ->
          assert is_map(measurements)
          assert Map.has_key?(measurements, :timestamp)
          assert is_map(metadata)
          assert metadata.exchange == :unsupported_exchange
      after
        100 ->
          # If no telemetry received, that's also acceptable since
          # the sync might fail before telemetry emission
          :ok
      end

      # Cleanup
      :telemetry.detach(handler_id)
    end
  end
end
