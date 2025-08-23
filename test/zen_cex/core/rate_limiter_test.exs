defmodule ZenCex.Core.RateLimiterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ZenCex.Core.RateLimiter

  @test_table_name :core_rate_limiter_test_table
  @test_limit 100

  setup do
    # Clean up any existing table
    if :ets.whereis(@test_table_name) != :undefined do
      :ets.delete(@test_table_name)
    end

    table = RateLimiter.init_table(@test_table_name)
    {:ok, table: table}
  end

  describe "init_table/2" do
    test "creates new ETS table with default options" do
      table_name = :test_init_table
      table = RateLimiter.init_table(table_name)

      assert :ets.whereis(table_name) != :undefined
      assert table == table_name

      # Verify table options
      info = :ets.info(table)
      assert info[:type] == :set
      assert info[:protection] == :public
      assert info[:write_concurrency] == true

      # Cleanup
      :ets.delete(table_name)
    end

    test "returns existing table if already created" do
      table_name = :test_existing_table
      table1 = RateLimiter.init_table(table_name)
      table2 = RateLimiter.init_table(table_name)

      assert table1 == table2
      assert :ets.whereis(table_name) != :undefined

      # Cleanup
      :ets.delete(table_name)
    end

    test "accepts custom ETS options" do
      table_name = :test_custom_options
      custom_opts = [{:read_concurrency, true}]
      table = RateLimiter.init_table(table_name, custom_opts)

      info = :ets.info(table)
      assert info[:read_concurrency] == true

      # Cleanup
      :ets.delete(table_name)
    end
  end

  describe "check_and_increment/4" do
    test "allows request within limits and increments counter", %{table: table} do
      assert :ok = RateLimiter.check_and_increment(table, :spot, 50, @test_limit)

      # Verify counter was incremented
      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 50}] = :ets.lookup(table, key)
    end

    test "allows multiple requests until limit is reached", %{table: table} do
      # First request within limit
      assert :ok = RateLimiter.check_and_increment(table, :spot, 40, @test_limit)
      # Second request still within limit
      assert :ok = RateLimiter.check_and_increment(table, :spot, 50, @test_limit)

      # Verify total usage
      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 90}] = :ets.lookup(table, key)
    end

    test "rejects request that would exceed limit", %{table: table} do
      # Use up most of the limit
      assert :ok = RateLimiter.check_and_increment(table, :spot, 95, @test_limit)

      # Next request would exceed limit
      assert {:error, :rate_limited} =
               RateLimiter.check_and_increment(table, :spot, 10, @test_limit)

      # Verify counter wasn't incremented for rejected request
      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 95}] = :ets.lookup(table, key)
    end

    test "handles different API types separately", %{table: table} do
      assert :ok = RateLimiter.check_and_increment(table, :spot, 50, @test_limit)
      assert :ok = RateLimiter.check_and_increment(table, :futures, 50, @test_limit)

      # Both should have their own counters
      spot_key = {:spot, RateLimiter.get_current_window(:minute)}
      futures_key = {:futures, RateLimiter.get_current_window(:minute)}

      assert [{^spot_key, 50}] = :ets.lookup(table, spot_key)
      assert [{^futures_key, 50}] = :ets.lookup(table, futures_key)
    end

    test "handles ETS failures gracefully and logs warning" do
      # Use invalid table reference to simulate failure
      invalid_table = :nonexistent_table

      log =
        capture_log([level: :warning], fn ->
          assert :ok = RateLimiter.check_and_increment(invalid_table, :spot, 10, @test_limit)
        end)

      assert log =~ "ETS operation failed in rate limiter, allowing request"
    end

    test "handles zero weight requests", %{table: table} do
      assert :ok = RateLimiter.check_and_increment(table, :spot, 0, @test_limit)

      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 0}] = :ets.lookup(table, key)
    end

    test "allows exact limit usage", %{table: table} do
      assert :ok = RateLimiter.check_and_increment(table, :spot, @test_limit, @test_limit)

      # Should reject next request
      assert {:error, :rate_limited} =
               RateLimiter.check_and_increment(table, :spot, 1, @test_limit)
    end
  end

  describe "update_from_headers/4" do
    test "updates tracking from valid header", %{table: table} do
      headers = %{"x-rate-limit-used" => "75"}

      :ok = RateLimiter.update_from_headers(table, :spot, headers, "x-rate-limit-used")

      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 75}] = :ets.lookup(table, key)
    end

    test "handles missing header gracefully", %{table: table} do
      headers = %{"other-header" => "value"}

      assert :ok = RateLimiter.update_from_headers(table, :spot, headers, "x-rate-limit-used")

      # Should not create any entries
      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [] = :ets.lookup(table, key)
    end

    test "handles header values as lists", %{table: table} do
      headers = %{"x-rate-limit-used" => ["85", "extra"]}

      :ok = RateLimiter.update_from_headers(table, :spot, headers, "x-rate-limit-used")

      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 85}] = :ets.lookup(table, key)
    end

    test "handles integer header values", %{table: table} do
      headers = %{"x-rate-limit-used" => 95}

      :ok = RateLimiter.update_from_headers(table, :spot, headers, "x-rate-limit-used")

      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 95}] = :ets.lookup(table, key)
    end

    test "handles ETS failures gracefully and logs warning" do
      headers = %{"x-rate-limit-used" => "50"}
      invalid_table = :nonexistent_table

      log =
        capture_log([level: :warning], fn ->
          assert :ok = RateLimiter.update_from_headers(invalid_table, :spot, headers, "x-rate-limit-used")
        end)

      assert log =~ "Failed to update rate limit from headers"
    end

    test "overwrites existing values", %{table: table} do
      # Set initial value
      :ok = RateLimiter.check_and_increment(table, :spot, 30, @test_limit)

      # Update from headers should overwrite
      headers = %{"x-rate-limit-used" => "60"}
      :ok = RateLimiter.update_from_headers(table, :spot, headers, "x-rate-limit-used")

      key = {:spot, RateLimiter.get_current_window(:minute)}
      assert [{^key, 60}] = :ets.lookup(table, key)
    end
  end

  describe "cleanup_old_windows/2" do
    test "removes entries older than cleanup age", %{table: table} do
      current_window = RateLimiter.get_current_window(:minute)

      # Insert old entries
      old_key1 = {:spot, current_window - 3}
      old_key2 = {:futures, current_window - 5}
      current_key = {:spot, current_window}

      :ets.insert(table, [{old_key1, 50}, {old_key2, 30}, {current_key, 25}])

      # Cleanup with default age (2 minutes)
      deleted_count = RateLimiter.cleanup_old_windows(table)

      assert deleted_count == 2

      # Verify only current entry remains
      assert [] = :ets.lookup(table, old_key1)
      assert [] = :ets.lookup(table, old_key2)
      assert [{^current_key, 25}] = :ets.lookup(table, current_key)
    end

    test "accepts custom cleanup age", %{table: table} do
      current_window = RateLimiter.get_current_window(:minute)

      # Insert entry that's 4 minutes old
      old_key = {:spot, current_window - 4}
      current_key = {:spot, current_window}

      :ets.insert(table, [{old_key, 50}, {current_key, 25}])

      # Cleanup with 5 minute age - should keep both
      deleted_count = RateLimiter.cleanup_old_windows(table, 5)
      assert deleted_count == 0

      # Cleanup with 3 minute age - should remove old entry
      deleted_count = RateLimiter.cleanup_old_windows(table, 3)
      assert deleted_count == 1

      assert [] = :ets.lookup(table, old_key)
      assert [{^current_key, 25}] = :ets.lookup(table, current_key)
    end

    test "handles ETS failures gracefully and logs warning" do
      invalid_table = :nonexistent_table

      log =
        capture_log([level: :warning], fn ->
          assert 0 = RateLimiter.cleanup_old_windows(invalid_table)
        end)

      assert log =~ "Failed to cleanup old rate limit entries"
    end

    test "returns zero when no entries to clean", %{table: table} do
      # Empty table
      assert 0 = RateLimiter.cleanup_old_windows(table)

      # Add current entry only
      current_key = {:spot, RateLimiter.get_current_window(:minute)}
      :ets.insert(table, {current_key, 50})

      assert 0 = RateLimiter.cleanup_old_windows(table)
    end
  end

  describe "get_current_window/1" do
    test "returns current minute window" do
      window = RateLimiter.get_current_window(:minute)
      expected = div(System.system_time(:second), 60)
      assert window == expected
    end

    test "returns current second window" do
      window = RateLimiter.get_current_window(:second)
      expected = System.system_time(:second)
      assert window == expected
    end

    test "returns current hour window" do
      window = RateLimiter.get_current_window(:hour)
      expected = div(System.system_time(:second), 3600)
      assert window == expected
    end

    test "minute windows are stable within the same minute" do
      window1 = RateLimiter.get_current_window(:minute)
      # 0.1 seconds
      Process.sleep(100)
      window2 = RateLimiter.get_current_window(:minute)
      assert window1 == window2
    end
  end

  describe "get_status/4" do
    test "returns correct status for active usage", %{table: table} do
      # Add some usage
      :ets.insert(table, {{:spot, RateLimiter.get_current_window(:minute)}, 45})

      status = RateLimiter.get_status(table, :spot, @test_limit)

      assert status.used == 45
      assert status.limit == @test_limit
      assert status.window == 60
      assert status.usage_percent == 45
      assert status.at_limit == false
      assert is_integer(status.reset_at)
      assert status.reset_at > System.system_time(:second)
    end

    test "returns zero usage when no data", %{table: table} do
      status = RateLimiter.get_status(table, :spot, @test_limit)

      assert status.used == 0
      assert status.limit == @test_limit
      assert status.usage_percent == 0
      assert status.at_limit == false
    end

    test "detects at-limit condition", %{table: table} do
      # Set usage at limit
      :ets.insert(table, {{:spot, RateLimiter.get_current_window(:minute)}, @test_limit})

      status = RateLimiter.get_status(table, :spot, @test_limit)

      assert status.used == @test_limit
      assert status.usage_percent == 100
      assert status.at_limit == true
    end

    test "handles custom window size", %{table: table} do
      status = RateLimiter.get_status(table, :spot, @test_limit, 30)
      assert status.window == 30
    end

    test "handles ETS failures gracefully", %{table: _table} do
      invalid_table = :nonexistent_table
      status = RateLimiter.get_status(invalid_table, :spot, @test_limit)

      assert status.used == 0
      assert status.limit == @test_limit
      assert status.usage_percent == 0
      assert status.at_limit == false
      assert status.reset_at == 0
    end

    test "calculates percentage correctly for partial usage", %{table: table} do
      # Use 33 out of 100 = 33%
      :ets.insert(table, {{:spot, RateLimiter.get_current_window(:minute)}, 33})

      status = RateLimiter.get_status(table, :spot, @test_limit)
      assert status.usage_percent == 33
    end
  end

  describe "reset/2" do
    test "resets specific API type", %{table: table} do
      # Add data for multiple API types
      current_window = RateLimiter.get_current_window(:minute)
      spot_key = {:spot, current_window}
      futures_key = {:futures, current_window}

      :ets.insert(table, [{spot_key, 50}, {futures_key, 30}])

      # Reset only spot
      assert :ok = RateLimiter.reset(table, :spot)

      # Spot should be gone, futures should remain
      assert [] = :ets.lookup(table, spot_key)
      assert [{^futures_key, 30}] = :ets.lookup(table, futures_key)
    end

    test "resets all API types with :all", %{table: table} do
      # Add data for multiple API types
      current_window = RateLimiter.get_current_window(:minute)
      spot_key = {:spot, current_window}
      futures_key = {:futures, current_window}

      :ets.insert(table, [{spot_key, 50}, {futures_key, 30}])

      # Reset all
      assert :ok = RateLimiter.reset(table, :all)

      # Both should be gone
      assert [] = :ets.lookup(table, spot_key)
      assert [] = :ets.lookup(table, futures_key)
      assert [] = :ets.tab2list(table)
    end

    test "handles ETS failures gracefully" do
      invalid_table = :nonexistent_table
      assert :ok = RateLimiter.reset(invalid_table, :spot)
      assert :ok = RateLimiter.reset(invalid_table, :all)
    end

    test "handles non-existent keys gracefully", %{table: table} do
      # Reset non-existent key should not crash
      assert :ok = RateLimiter.reset(table, :nonexistent)
    end
  end

  describe "calculate_retry_after/2" do
    test "calculates retry time for minute window" do
      retry_ms = RateLimiter.calculate_retry_after(:minute)

      # Should be between 0.1 and 60.1 seconds (in milliseconds)
      # At least 100ms buffer
      assert retry_ms > 100
      # At most 60s + 100ms buffer
      assert retry_ms <= 60_100
    end

    test "calculates retry time for second window" do
      retry_ms = RateLimiter.calculate_retry_after(:second)

      # Should be between 100ms and 1.1 seconds
      assert retry_ms > 100
      assert retry_ms <= 1_100
    end

    test "accepts custom buffer time" do
      retry_ms = RateLimiter.calculate_retry_after(:second, 500)

      # Should include the 500ms buffer
      assert retry_ms >= 500
      # 1s + 500ms buffer
      assert retry_ms <= 1_500
    end

    test "retry time decreases as we approach next window" do
      # Take two measurements close in time
      retry1 = RateLimiter.calculate_retry_after(:minute)
      # Wait 50ms
      Process.sleep(50)
      retry2 = RateLimiter.calculate_retry_after(:minute)

      # Second measurement should be smaller (closer to next minute)
      # Allow for some timing variance
      # Account for timing variance
      assert retry2 <= retry1 + 100
    end
  end

  describe "integration tests" do
    test "full rate limiting workflow", %{table: table} do
      api_type = :integration_test
      limit = 50

      # Start with clean state
      assert :ok = RateLimiter.reset(table, api_type)

      # Make several requests
      assert :ok = RateLimiter.check_and_increment(table, api_type, 20, limit)
      assert :ok = RateLimiter.check_and_increment(table, api_type, 15, limit)
      assert :ok = RateLimiter.check_and_increment(table, api_type, 10, limit)

      # Check status
      status = RateLimiter.get_status(table, api_type, limit)
      assert status.used == 45
      assert status.usage_percent == 90
      assert status.at_limit == false

      # Next request should hit limit
      assert {:error, :rate_limited} =
               RateLimiter.check_and_increment(table, api_type, 10, limit)

      # But exact limit should work
      assert :ok = RateLimiter.check_and_increment(table, api_type, 5, limit)

      # Now we're at limit
      final_status = RateLimiter.get_status(table, api_type, limit)
      assert final_status.used == 50
      assert final_status.at_limit == true

      # Reset to clean state
      assert :ok = RateLimiter.reset(table, api_type)

      # Should be clean now
      clean_status = RateLimiter.get_status(table, api_type, limit)
      assert clean_status.used == 0
    end
  end
end
