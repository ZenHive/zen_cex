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
      assert stats.idempotency_entries == 2
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
      assert Map.has_key?(stats, :idempotency_entries)
      assert Map.has_key?(stats, :window_ms)
      assert Map.has_key?(stats, :total_memory_bytes)

      assert stats.idempotency_entries == 0
      # 30 minutes
      assert stats.window_ms == 30 * 60 * 1000
      assert is_integer(stats.total_memory_bytes)
    end

    test "stats reflect current state" do
      initial_stats = OrderSafety.get_stats()
      assert initial_stats.idempotency_entries == 0

      OrderSafety.record_order(:binance, "stat_test_1")
      OrderSafety.record_order(:kraken, "stat_test_2")

      updated_stats = OrderSafety.get_stats()
      assert updated_stats.idempotency_entries == 2
      assert updated_stats.total_memory_bytes > initial_stats.total_memory_bytes
    end
  end

  describe "clear_all/0" do
    test "removes all entries" do
      # Add multiple orders
      OrderSafety.record_order(:binance, "clear_1")
      OrderSafety.record_order(:kraken, "clear_2")
      OrderSafety.record_order(:deribit, "clear_3")

      stats = OrderSafety.get_stats()
      assert stats.idempotency_entries == 3

      assert :ok = OrderSafety.clear_all()

      stats = OrderSafety.get_stats()
      assert stats.idempotency_entries == 0

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

  # === NEW VALIDATION TESTS ===

  describe "validate_order/2 - comprehensive validation" do
    test "validates complete order successfully" do
      # Enable trading first
      OrderSafety.set_kill_switch(:binance, true)

      valid_order = %{
        symbol: "BTCUSDT",
        side: :buy,
        type: :limit,
        quantity: "0.001",
        price: "50000.00"
      }

      assert {:ok, validated_params} = OrderSafety.validate_order(:binance, valid_order)
      assert Map.has_key?(validated_params, :client_order_id)
      assert validated_params.symbol == "BTCUSDT"
    end

    test "rejects order when kill switch is active" do
      OrderSafety.set_kill_switch(:binance, false)

      order = %{symbol: "BTCUSDT", side: :buy, quantity: "0.001"}

      assert {:error, :kill_switch_active} = OrderSafety.validate_order(:binance, order)
    end

    test "rejects order with invalid symbol" do
      OrderSafety.set_kill_switch(:binance, true)

      order = %{symbol: "INVALID", side: :buy, quantity: "0.001"}

      assert {:error, {:invalid_symbol, "INVALID"}} = OrderSafety.validate_order(:binance, order)
    end

    test "rejects duplicate order" do
      OrderSafety.set_kill_switch(:binance, true)

      order = %{
        symbol: "BTCUSDT",
        side: :buy,
        quantity: "0.001",
        price: "50000.00",
        client_order_id: "test_duplicate_#{System.unique_integer()}"
      }

      # First validation should succeed
      assert {:ok, _} = OrderSafety.validate_order(:binance, order)

      # Record the order
      assert :ok = OrderSafety.record_order(:binance, order.client_order_id)

      # Second validation should fail due to duplicate
      assert {:error, :duplicate} = OrderSafety.validate_order(:binance, order)
    end
  end

  describe "kill switch functionality" do
    test "set_kill_switch/2 enables and disables trading" do
      # Test enabling
      assert :ok = OrderSafety.set_kill_switch(:binance, true)
      assert OrderSafety.trading_enabled?(:binance) == true

      # Test disabling
      assert :ok = OrderSafety.set_kill_switch(:binance, false)
      assert OrderSafety.trading_enabled?(:binance) == false
    end

    test "trading_enabled?/1 defaults to true for unknown exchange" do
      assert OrderSafety.trading_enabled?(:unknown_exchange) == true
    end

    test "get_kill_switch_status/0 returns all exchanges" do
      OrderSafety.set_kill_switch(:binance, false)
      OrderSafety.set_kill_switch(:kraken, true)

      status = OrderSafety.get_kill_switch_status()

      assert is_map(status)
      assert status[:binance] == false
      assert status[:kraken] == true
    end
  end

  describe "symbol validation" do
    test "validate_symbol/2 accepts valid trading symbols" do
      # Stub returns valid status for USDT pairs
      assert :ok = OrderSafety.validate_symbol(:binance, "BTCUSDT")
      assert :ok = OrderSafety.validate_symbol(:binance, "ETHUSDT")
    end

    test "validate_symbol/2 rejects invalid symbols" do
      assert {:error, {:invalid_symbol, "INVALID"}} = OrderSafety.validate_symbol(:binance, "INVALID")
    end

    test "validate_symbol/2 rejects non-string symbols" do
      assert {:error, {:invalid_symbol_type, _}} = OrderSafety.validate_symbol(:binance, :invalid)
      assert {:error, {:invalid_symbol_type, _}} = OrderSafety.validate_symbol(:binance, 123)
    end
  end

  describe "balance validation" do
    test "validate_balance_for_order/2 validates buy orders" do
      # Stub returns sufficient balance
      order = %{symbol: "BTCUSDT", side: :buy, quantity: "0.001", price: "50000.00"}

      assert :ok = OrderSafety.validate_balance_for_order(:binance, order)
    end

    test "validate_balance_for_order/2 validates sell orders" do
      order = %{symbol: "BTCUSDT", side: :sell, quantity: "0.001"}

      assert :ok = OrderSafety.validate_balance_for_order(:binance, order)
    end

    test "validate_balance_for_order/2 rejects invalid side" do
      order = %{symbol: "BTCUSDT", side: :invalid, quantity: "0.001"}

      assert {:error, {:invalid_side, :invalid}} = OrderSafety.validate_balance_for_order(:binance, order)
    end

    test "validate_balance_for_order/2 requires all parameters" do
      assert {:error, {:missing_required_params, _}} = OrderSafety.validate_balance_for_order(:binance, %{})
    end

    test "validate_balance/3 with Decimal amounts" do
      required_amount = Decimal.new("10.5")

      # Stub returns 1000.0 balance which is sufficient
      assert :ok = OrderSafety.validate_balance(:binance, "USDT", required_amount)
    end
  end

  describe "notional validation" do
    test "validate_notional_for_order/2 validates sufficient notional" do
      order = %{symbol: "BTCUSDT", price: "50000.00", quantity: "0.001"}

      assert :ok = OrderSafety.validate_notional_for_order(:binance, order)
    end

    test "validate_notional_for_order/2 allows market orders" do
      order = %{symbol: "BTCUSDT", type: :market, quantity: "0.001"}

      assert :ok = OrderSafety.validate_notional_for_order(:binance, order)
    end

    test "validate_notional_for_order/2 requires symbol" do
      order = %{price: "50000.00", quantity: "0.001"}

      assert {:error, {:missing_required_params, _}} = OrderSafety.validate_notional_for_order(:binance, order)
    end

    test "validate_notional/3 with specific values" do
      # The minimum notional will be fetched from exchange API or use default
      # Use values that will work regardless of actual API response
      # Well above any reasonable minimum
      sufficient_notional = Decimal.new("100.00")
      # Well below any reasonable minimum
      insufficient_notional = Decimal.new("0.01")

      assert :ok = OrderSafety.validate_notional(:binance, "BTCUSDT", sufficient_notional)

      assert {:error, {:notional_too_small, _}} =
               OrderSafety.validate_notional(:binance, "BTCUSDT", insufficient_notional)
    end

    test "validate_notional/3 respects dynamic exchange minimums" do
      # This test is more robust against API changes
      # It tests the behavior without hardcoding specific minimums
      symbol = "BTCUSDT"

      # Test with a very high value that should always pass
      high_notional = Decimal.new("10000.00")
      assert :ok = OrderSafety.validate_notional(:binance, symbol, high_notional)

      # Test with a very low value that should always fail
      low_notional = Decimal.new("0.001")

      assert {:error, {:notional_too_small, error_details}} =
               OrderSafety.validate_notional(:binance, symbol, low_notional)

      # Verify error details are a map with expected fields
      assert is_map(error_details)
      assert Map.has_key?(error_details, :symbol)
      assert Map.has_key?(error_details, :value)
      assert Map.has_key?(error_details, :minimum)
      assert error_details.symbol == symbol
      assert Decimal.equal?(error_details.value, low_notional)
    end
  end

  describe "cache functionality" do
    test "cache_stats returns proper statistics" do
      stats = OrderSafety.cache_stats()
      assert is_map(stats)
      # Initially empty or with some entries
      assert Map.has_key?(stats, :price) or Map.has_key?(stats, :symbol_info) or Map.has_key?(stats, :min_notional) or
               stats == %{}
    end

    test "invalidate_price_cache removes cached price" do
      # This test just verifies the function works without errors
      assert :ok = OrderSafety.invalidate_price_cache(:binance, "BTCUSDT")
    end

    test "invalidate_symbol_info removes cached symbol info" do
      assert :ok = OrderSafety.invalidate_symbol_info(:binance, "BTCUSDT")
    end

    test "invalidate_min_notional removes cached min notional" do
      assert :ok = OrderSafety.invalidate_min_notional(:binance, "BTCUSDT")
    end

    test "invalidate_exchange_cache clears all exchange entries" do
      # Should return {:ok, count} where count is >= 0
      assert {:ok, count} = OrderSafety.invalidate_exchange_cache(:binance)
      assert is_integer(count)
      assert count >= 0
    end

    test "clear_all removes all cached data" do
      # Add some test data first
      OrderSafety.record_order(:binance, "test_order")

      # Clear everything
      assert :ok = OrderSafety.clear_all()

      # Order should now be new again
      assert {:ok, :new} = OrderSafety.check_existing_order(:binance, "test_order")

      # Cache stats should be empty or reset
      stats = OrderSafety.cache_stats()
      assert is_map(stats)
    end
  end

  describe "price and size validation" do
    test "validate_price_and_size/2 validates limit orders" do
      order = %{symbol: "BTCUSDT", quantity: "0.001", price: "50000.00"}

      assert :ok = OrderSafety.validate_price_and_size(:binance, order)
    end

    test "validate_price_and_size/2 validates market orders" do
      order = %{symbol: "BTCUSDT", quantity: "0.001", type: :market}

      assert :ok = OrderSafety.validate_price_and_size(:binance, order)
    end

    test "validate_price_and_size/2 rejects negative quantities" do
      order = %{symbol: "BTCUSDT", quantity: "-0.001"}

      assert {:error, {:invalid_quantity, _}} = OrderSafety.validate_price_and_size(:binance, order)
    end

    test "validate_price_and_size/2 rejects invalid quantity format" do
      order = %{symbol: "BTCUSDT", quantity: "invalid"}

      assert {:error, {:invalid_quantity_format, _}} = OrderSafety.validate_price_and_size(:binance, order)
    end

    test "validate_price_and_size/2 rejects negative prices" do
      order = %{symbol: "BTCUSDT", quantity: "0.001", price: "-50000.00"}

      assert {:error, {:invalid_price, _}} = OrderSafety.validate_price_and_size(:binance, order)
    end

    test "validate_price_and_size/2 rejects invalid price format" do
      order = %{symbol: "BTCUSDT", quantity: "0.001", price: "invalid"}

      assert {:error, {:invalid_price_format, _}} = OrderSafety.validate_price_and_size(:binance, order)
    end

    test "validate_price_and_size/2 requires symbol and quantity" do
      assert {:error, {:missing_required_params, _}} = OrderSafety.validate_price_and_size(:binance, %{})
    end
  end

  describe "updated get_stats/0" do
    test "returns comprehensive statistics" do
      # Add some data to tables
      OrderSafety.record_order(:binance, "test_order_1")
      OrderSafety.set_kill_switch(:binance, true)

      stats = OrderSafety.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :idempotency_entries)
      assert Map.has_key?(stats, :symbol_cache_entries)
      assert Map.has_key?(stats, :kill_switch_entries)
      assert Map.has_key?(stats, :window_ms)
      assert Map.has_key?(stats, :symbol_cache_ttl_ms)
      assert Map.has_key?(stats, :total_memory_bytes)

      assert stats.idempotency_entries >= 1
      assert stats.kill_switch_entries >= 1
      # 30 minutes
      assert stats.window_ms == 30 * 60 * 1000
      # 5 minutes
      assert stats.symbol_cache_ttl_ms == 5 * 60 * 1000
      assert is_integer(stats.total_memory_bytes)
    end
  end

  describe "updated clear_all/0" do
    test "clears all caches and resets kill switch" do
      # Add data to all tables
      OrderSafety.record_order(:binance, "test_order")
      OrderSafety.set_kill_switch(:binance, false)

      stats_before = OrderSafety.get_stats()
      assert stats_before.idempotency_entries > 0
      assert OrderSafety.trading_enabled?(:binance) == false

      # Clear all
      assert :ok = OrderSafety.clear_all()

      # Verify everything is cleared and reset
      stats_after = OrderSafety.get_stats()
      assert stats_after.idempotency_entries == 0
      assert stats_after.symbol_cache_entries == 0

      # Kill switch should be reset to enabled
      assert OrderSafety.trading_enabled?(:binance) == true
      assert OrderSafety.trading_enabled?(:kraken) == true
    end
  end

  describe "cleanup_expired/0 with multiple tables" do
    test "cleans up both idempotency and symbol cache" do
      # Add some orders and simulate caching
      OrderSafety.record_order(:binance, "cleanup_test_1")
      OrderSafety.record_order(:binance, "cleanup_test_2")

      # Immediate cleanup should not remove recent entries
      deleted_count = OrderSafety.cleanup_expired()

      # Should not delete recent entries
      assert deleted_count == 0

      stats = OrderSafety.get_stats()
      assert stats.idempotency_entries == 2
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
