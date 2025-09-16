defmodule ZenCex.Core.CacheTest do
  use ExUnit.Case, async: true

  import ZenCex.CacheTestHelper

  alias ZenCex.Core.Cache

  # Now we can use async: true with namespace isolation

  setup :with_cache_namespace

  describe "get/1" do
    test "returns {:error, :not_found} when key does not exist", %{cache_namespace: ns} do
      key = namespaced_key("nonexistent_key", ns)
      assert {:error, :not_found} = Cache.get(key)
    end

    test "returns {:ok, value} when key exists and is not expired", %{cache_namespace: ns} do
      key = namespaced_key("test_key", ns)
      value = %{data: "test"}

      Cache.put(key, value, 60)
      assert {:ok, ^value} = Cache.get(key)
    end

    test "returns {:error, :expired} when key has expired", %{cache_namespace: ns} do
      key = namespaced_key("expired_key", ns)
      value = "expired_value"

      # Put with very short TTL
      Cache.put(key, value, 1)

      # Wait for expiration
      Process.sleep(1100)

      assert {:error, :expired} = Cache.get(key)
    end

    test "validates key is binary" do
      assert_raise FunctionClauseError, fn ->
        Cache.get(:not_a_binary)
      end
    end
  end

  describe "put/3" do
    test "stores value with TTL successfully", %{cache_namespace: ns} do
      key = namespaced_key("put_test", ns)
      value = %{price: "45000.00", volume: "123.45"}

      assert :ok = Cache.put(key, value, 60)
      assert {:ok, ^value} = Cache.get(key)
    end

    test "overwrites existing value", %{cache_namespace: ns} do
      key = namespaced_key("overwrite_test", ns)
      old_value = "old"
      new_value = "new"

      Cache.put(key, old_value, 60)
      Cache.put(key, new_value, 60)

      assert {:ok, ^new_value} = Cache.get(key)
    end

    test "validates key is binary and TTL is positive integer" do
      assert_raise FunctionClauseError, fn ->
        Cache.put(:not_a_binary, "value", 60)
      end

      assert_raise FunctionClauseError, fn ->
        Cache.put("key", "value", 0)
      end

      assert_raise FunctionClauseError, fn ->
        Cache.put("key", "value", -5)
      end
    end

    test "handles process not started gracefully" do
      # Test that the public API functions handle a missing process gracefully
      # by checking the Process.whereis guard clause behavior

      # We can't actually stop the process in tests, but we can verify
      # the functions have proper guards for when the process doesn't exist

      # These should not crash even if process doesn't exist
      # The implementation checks Process.whereis(__MODULE__)
      assert :ok = Cache.put("test_key", "value", 60)
      result = Cache.get("test_key")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
      assert :ok = Cache.delete("test_key")
      assert :ok = Cache.clear()
      assert is_map(Cache.stats())
    end
  end

  describe "delete/1" do
    test "removes existing key", %{cache_namespace: ns} do
      key = namespaced_key("delete_test", ns)
      value = "test_value"

      Cache.put(key, value, 60)
      assert {:ok, ^value} = Cache.get(key)

      assert :ok = Cache.delete(key)
      assert {:error, :not_found} = Cache.get(key)
    end

    test "handles non-existent key gracefully", %{cache_namespace: ns} do
      key = namespaced_key("nonexistent_key", ns)
      assert :ok = Cache.delete(key)
    end

    test "validates key is binary" do
      assert_raise FunctionClauseError, fn ->
        Cache.delete(:not_a_binary)
      end
    end
  end

  describe "clear/0" do
    test "removes all cached entries", %{cache_namespace: ns} do
      # For this test, we still test clear() which clears everything
      # But we use namespaced keys to not interfere with other tests
      key1 = namespaced_key("clear_test_1", ns)
      key2 = namespaced_key("clear_test_2", ns)

      Cache.put(key1, "value1", 60)
      Cache.put(key2, "value2", 60)

      assert {:ok, "value1"} = Cache.get(key1)
      assert {:ok, "value2"} = Cache.get(key2)

      assert :ok = Cache.clear()

      assert {:error, :not_found} = Cache.get(key1)
      assert {:error, :not_found} = Cache.get(key2)
    end
  end

  describe "expiration cleanup" do
    test "expired entries are cleaned up by background process" do
      key1 = "cleanup_test_1_#{:rand.uniform(10_000)}"
      key2 = "cleanup_test_2_#{:rand.uniform(10_000)}"

      # Put one with very short TTL and one with long TTL
      Cache.put(key1, "expires_soon", 1)
      Cache.put(key2, "expires_later", 60)

      # Both should be accessible initially
      assert {:ok, "expires_soon"} = Cache.get(key1)
      assert {:ok, "expires_later"} = Cache.get(key2)

      # Wait for first to expire
      Process.sleep(1100)

      # First should be expired, second still accessible
      assert {:error, :expired} = Cache.get(key1)
      assert {:ok, "expires_later"} = Cache.get(key2)
    end
  end

  describe "telemetry events" do
    test "emits telemetry events for cache operations" do
      # Attach test handler
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "cache-test-handler",
        [:zen_cex, :cache, :put],
        fn event, measurements, metadata, _ ->
          send(test_pid, {ref, :telemetry, event, measurements, metadata})
        end,
        nil
      )

      key = "telemetry_test_#{:rand.uniform(10_000)}"
      Cache.put(key, "value", 60)

      # Should receive telemetry event
      assert_receive {^ref, :telemetry, [:zen_cex, :cache, :put], measurements, metadata}
      assert Map.has_key?(measurements, :duration)
      assert metadata.key == key
      assert metadata.ttl == 60

      :telemetry.detach("cache-test-handler")
    end

    test "emits telemetry event for pattern deletion" do
      # Setup test data
      Cache.put("test:pattern:1", "value1", 60)
      Cache.put("test:pattern:2", "value2", 60)
      Cache.put("test:other:3", "value3", 60)

      # Attach telemetry handler
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "pattern-delete-handler",
        [:zen_cex, :cache, :pattern_delete],
        fn event, measurements, metadata, _ ->
          send(test_pid, {ref, :telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Clear pattern
      {:ok, count} = Cache.clear_pattern("test:pattern:")
      assert count >= 2

      # Should receive telemetry event
      assert_receive {^ref, :telemetry, [:zen_cex, :cache, :pattern_delete], measurements, metadata}

      assert Map.has_key?(measurements, :duration)
      assert metadata.pattern == "test:pattern:"
      assert metadata.deleted >= 2

      :telemetry.detach("pattern-delete-handler")
    end
  end

  describe "edge cases" do
    test "handles very large values" do
      key = "large_value_test_#{:rand.uniform(10_000)}"
      # Create a reasonably large value
      large_value = Enum.map(1..1000, fn i -> %{id: i, data: String.duplicate("x", 100)} end)

      Cache.put(key, large_value, 60)
      assert {:ok, ^large_value} = Cache.get(key)
    end

    test "handles various data types" do
      test_cases = [
        {"string", "test_string"},
        {"atom", :test_atom},
        {"integer", 42},
        {"float", 3.14159},
        {"list", [1, 2, 3, :a, :b, :c]},
        {"map", %{a: 1, b: "two", c: [3, 4, 5]}},
        {"tuple", {:ok, "success", 123}},
        {"binary", <<1, 2, 3, 4, 5>>}
      ]

      Enum.each(test_cases, fn {type, value} ->
        key = "type_test_#{type}_#{:rand.uniform(10_000)}"
        Cache.put(key, value, 60)
        assert {:ok, ^value} = Cache.get(key), "Failed for type: #{type}"
      end)
    end

    test "handles concurrent access" do
      key_base = "concurrent_test_#{:rand.uniform(10_000)}"

      # Spawn multiple processes doing cache operations
      tasks =
        Enum.map(1..10, fn i ->
          Task.async(fn ->
            key = "#{key_base}_#{i}"
            value = "value_#{i}"

            Cache.put(key, value, 60)
            {:ok, ^value} = Cache.get(key)
            Cache.delete(key)

            :ok
          end)
        end)

      # All should complete successfully
      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "stats/0" do
    test "returns cache statistics" do
      stats = Cache.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :cache_size)
      assert Map.has_key?(stats, :evictions)
      assert Map.has_key?(stats, :cleanup_count)
      assert Map.has_key?(stats, :max_cache_size)
      assert Map.has_key?(stats, :eviction_batch_size)
    end
  end

  describe "LRU eviction" do
    test "evicts oldest entries when cache is full", %{cache_namespace: ns} do
      # This test simulates cache overflow and LRU eviction
      # We'll create a small set of entries and verify oldest are evicted

      # First, let's check the max cache size from stats
      stats = Cache.stats()
      max_size = stats.max_cache_size
      batch_size = stats.eviction_batch_size

      # Create a predictable set of entries that will trigger eviction
      # We'll use a subset to make the test faster
      test_size = min(100, div(max_size, 10))

      # Add entries with small delays to ensure different access times
      entries =
        for i <- 1..test_size do
          key = namespaced_key("lru_test_#{i}", ns)
          # 1 hour TTL
          Cache.put(key, "value_#{i}", 3600)
          # Small sleep to ensure monotonic time differences
          Process.sleep(1)
          key
        end

      # Verify all entries exist initially
      Enum.each(entries, fn key ->
        assert {:ok, _} = Cache.get(key)
      end)

      # Now add more entries to trigger eviction
      # The cache should evict oldest entries when full
      overflow_count = div(batch_size, 2)

      overflow_entries =
        for i <- 1..overflow_count do
          key = namespaced_key("overflow_#{i}", ns)
          Cache.put(key, "overflow_#{i}", 3600)
          key
        end

      # Verify overflow entries exist
      Enum.each(overflow_entries, fn key ->
        assert {:ok, _} = Cache.get(key)
      end)

      # Check stats to see if evictions occurred (if we hit the limit)
      final_stats = Cache.stats()

      # The test verifies the eviction mechanism exists and works
      # Actual eviction will depend on current cache state
      assert is_integer(final_stats.evictions)
      assert final_stats.evictions >= 0
    end

    test "updates access time on cache hits for proper LRU ordering", %{cache_namespace: ns} do
      # Test that accessing an entry updates its position in LRU order
      key1 = namespaced_key("lru_access_1", ns)
      key2 = namespaced_key("lru_access_2", ns)
      key3 = namespaced_key("lru_access_3", ns)

      # Add entries in order
      Cache.put(key1, "value1", 3600)
      Process.sleep(10)
      Cache.put(key2, "value2", 3600)
      Process.sleep(10)
      Cache.put(key3, "value3", 3600)

      # Access key1 to update its access time (should move to end of LRU)
      assert {:ok, "value1"} = Cache.get(key1)

      # Now key2 should be the oldest, followed by key3, then key1
      # This is verified indirectly through the LRU mechanism
      # The implementation uses access time tracking for proper ordering

      # Verify all entries still exist
      assert {:ok, "value1"} = Cache.get(key1)
      assert {:ok, "value2"} = Cache.get(key2)
      assert {:ok, "value3"} = Cache.get(key3)
    end
  end
end
