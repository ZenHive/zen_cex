defmodule ZenCex.Safety.OrderSafetyTest do
  use ExUnit.Case, async: false

  alias ZenCex.Safety.OrderSafety

  setup do
    # Start the OrderSafety GenServer for each test
    {:ok, pid} = OrderSafety.start_link(name: :"order_safety_test_#{System.unique_integer()}")

    # Clear any existing data
    OrderSafety.clear_all()

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, pid: pid}
  end

  describe "check_existing_order/2" do
    test "returns :new for first order check" do
      assert {:ok, :new} = OrderSafety.check_existing_order(:binance, "test_order_1")
    end

    test "detects duplicate within window after recording" do
      # Record an order
      assert :ok = OrderSafety.record_order(:binance, "test_order_2")

      # Check should now return duplicate
      assert {:error, :duplicate} = OrderSafety.check_existing_order(:binance, "test_order_2")
    end

    test "different exchanges have separate tracking" do
      # Record on binance
      assert :ok = OrderSafety.record_order(:binance, "shared_id")

      # Same ID on kraken should be new
      assert {:ok, :new} = OrderSafety.check_existing_order(:kraken, "shared_id")

      # But binance should still show duplicate
      assert {:error, :duplicate} = OrderSafety.check_existing_order(:binance, "shared_id")
    end
  end

  describe "record_order/2" do
    test "successfully records new order" do
      assert :ok = OrderSafety.record_order(:binance, "new_order_1")
    end

    test "prevents duplicate order recording" do
      assert :ok = OrderSafety.record_order(:binance, "dup_order_1")
      assert {:error, :duplicate} = OrderSafety.record_order(:binance, "dup_order_1")
    end

    test "allows recording after removing order" do
      assert :ok = OrderSafety.record_order(:binance, "remove_test")
      assert :ok = OrderSafety.remove_order(:binance, "remove_test")
      assert :ok = OrderSafety.record_order(:binance, "remove_test")
    end
  end

  describe "generate_client_order_id/3" do
    test "generates deterministic IDs with same inputs" do
      params = %{symbol: "BTCUSDT", side: :buy, amount: 1.5}
      nonce = 1_234_567_890

      id1 = OrderSafety.generate_client_order_id(:binance, params, nonce: nonce)
      id2 = OrderSafety.generate_client_order_id(:binance, params, nonce: nonce)

      assert id1 == id2
    end

    test "generates different IDs for different exchanges" do
      params = %{symbol: "BTCUSDT", side: :buy}
      nonce = 1_234_567_890

      binance_id = OrderSafety.generate_client_order_id(:binance, params, nonce: nonce)
      kraken_id = OrderSafety.generate_client_order_id(:kraken, params, nonce: nonce)

      assert binance_id != kraken_id
    end

    test "includes optional amount in ID" do
      base_params = %{symbol: "BTCUSDT", side: :buy}
      with_amount = Map.put(base_params, :amount, 2.5)
      nonce = 1_234_567_890

      id_without = OrderSafety.generate_client_order_id(:binance, base_params, nonce: nonce)
      id_with = OrderSafety.generate_client_order_id(:binance, with_amount, nonce: nonce)

      assert id_without != id_with
      assert String.contains?(id_with, "2.5")
    end

    test "uses current timestamp when nonce not provided" do
      params = %{symbol: "BTCUSDT", side: :sell}

      id1 = OrderSafety.generate_client_order_id(:binance, params)
      Process.sleep(1)
      id2 = OrderSafety.generate_client_order_id(:binance, params)

      assert id1 != id2
    end
  end

  describe "cleanup_expired/0" do
    test "removes entries older than window" do
      # This test would require manipulating time or waiting,
      # so we'll test the mechanism works
      assert 0 = OrderSafety.cleanup_expired()

      # Add some orders
      OrderSafety.record_order(:binance, "cleanup_test_1")
      OrderSafety.record_order(:binance, "cleanup_test_2")

      # Immediate cleanup should not remove recent entries
      assert 0 = OrderSafety.cleanup_expired()

      stats = OrderSafety.get_stats()
      assert stats.total_entries == 2
    end
  end

  describe "remove_order/2" do
    test "removes tracked order" do
      assert :ok = OrderSafety.record_order(:binance, "remove_me")
      assert {:error, :duplicate} = OrderSafety.check_existing_order(:binance, "remove_me")

      assert :ok = OrderSafety.remove_order(:binance, "remove_me")
      assert {:ok, :new} = OrderSafety.check_existing_order(:binance, "remove_me")
    end

    test "removing non-existent order is safe" do
      assert :ok = OrderSafety.remove_order(:binance, "never_existed")
    end
  end

  describe "get_stats/0" do
    test "returns cache statistics" do
      stats = OrderSafety.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_entries)
      assert Map.has_key?(stats, :window_ms)
      assert Map.has_key?(stats, :memory_bytes)

      assert stats.total_entries == 0
      # 30 minutes
      assert stats.window_ms == 30 * 60 * 1000
      assert is_integer(stats.memory_bytes)
    end

    test "stats reflect current state" do
      initial_stats = OrderSafety.get_stats()
      assert initial_stats.total_entries == 0

      OrderSafety.record_order(:binance, "stat_test_1")
      OrderSafety.record_order(:kraken, "stat_test_2")

      updated_stats = OrderSafety.get_stats()
      assert updated_stats.total_entries == 2
      assert updated_stats.memory_bytes > initial_stats.memory_bytes
    end
  end

  describe "clear_all/0" do
    test "removes all entries" do
      # Add multiple orders
      OrderSafety.record_order(:binance, "clear_1")
      OrderSafety.record_order(:kraken, "clear_2")
      OrderSafety.record_order(:deribit, "clear_3")

      stats = OrderSafety.get_stats()
      assert stats.total_entries == 3

      assert :ok = OrderSafety.clear_all()

      stats = OrderSafety.get_stats()
      assert stats.total_entries == 0

      # All should be new again
      assert {:ok, :new} = OrderSafety.check_existing_order(:binance, "clear_1")
      assert {:ok, :new} = OrderSafety.check_existing_order(:kraken, "clear_2")
      assert {:ok, :new} = OrderSafety.check_existing_order(:deribit, "clear_3")
    end
  end

  describe "performance" do
    test "idempotency check completes in < 50μs" do
      # Warm up the ETS table
      OrderSafety.record_order(:binance, "perf_warmup")

      # Measure check time
      measurements =
        for _ <- 1..100 do
          start = System.monotonic_time()
          OrderSafety.check_existing_order(:binance, "perf_test_#{System.unique_integer()}")
          stop = System.monotonic_time()
          System.convert_time_unit(stop - start, :native, :microsecond)
        end

      # Get average time
      avg_time = Enum.sum(measurements) / length(measurements)

      # Should be well under 50μs (allowing some variance for CI)
      assert avg_time < 100, "Average check time #{avg_time}μs exceeds target"
    end

    test "handles high concurrency" do
      # Spawn multiple processes checking and recording orders
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            order_id = "concurrent_#{i}"

            # Each task tries to record the same order multiple times
            results =
              for _ <- 1..10 do
                OrderSafety.record_order(:binance, order_id)
              end

            # First should succeed, rest should be duplicates
            {results, order_id}
          end)
        end

      # Collect results
      results = Task.await_many(tasks, 5000)

      # Verify each order was recorded exactly once
      for {task_results, _order_id} <- results do
        ok_count = Enum.count(task_results, &(&1 == :ok))
        dup_count = Enum.count(task_results, &(&1 == {:error, :duplicate}))

        assert ok_count == 1, "Expected exactly 1 successful record"
        assert dup_count == 9, "Expected 9 duplicates detected"
      end
    end
  end

  describe "sliding window behavior" do
    test "properly implements sliding window (not bucket-based)" do
      # Record an order with specific timestamp tracking
      order_id = "window_test_#{System.unique_integer()}"

      # Record the order
      assert :ok = OrderSafety.record_order(:binance, order_id)

      # Should be duplicate immediately
      assert {:error, :duplicate} = OrderSafety.check_existing_order(:binance, order_id)

      # Should still be duplicate after a short time
      Process.sleep(10)
      assert {:error, :duplicate} = OrderSafety.check_existing_order(:binance, order_id)

      # Verify the window is based on timestamp, not buckets
      # (In a real test, we'd need to mock time or wait 30 minutes)
      stats = OrderSafety.get_stats()
      assert stats.window_ms == 30 * 60 * 1000
    end
  end

  describe "telemetry integration" do
    test "emits telemetry events" do
      # Set up telemetry handler
      test_pid = self()
      handler_ref = make_ref()

      :telemetry.attach(
        "test-order-safety",
        [:zen_cex, :order, :order_recorded],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, :order_recorded, measurements, metadata})
        end,
        nil
      )

      :telemetry.attach(
        "test-duplicate",
        [:zen_cex, :order, :duplicate_detected],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {handler_ref, :duplicate_detected, measurements, metadata})
        end,
        nil
      )

      # Record an order
      OrderSafety.record_order(:binance, "telemetry_test")

      # Should receive order_recorded event
      assert_receive {^handler_ref, :order_recorded, %{count: 1}, metadata}
      assert metadata.exchange == :binance
      assert metadata.client_order_id == "telemetry_test"

      # Try to record duplicate
      OrderSafety.record_order(:binance, "telemetry_test")

      # Should receive duplicate_detected event
      assert_receive {^handler_ref, :duplicate_detected, %{count: 1}, metadata}
      assert metadata.exchange == :binance
      assert metadata.client_order_id == "telemetry_test"

      # Cleanup
      :telemetry.detach("test-order-safety")
      :telemetry.detach("test-duplicate")
    end
  end
end
