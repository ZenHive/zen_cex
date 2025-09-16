defmodule ZenCex.Core.Cache do
  @moduledoc """
  Simple in-memory cache for exchange data using ETS.

  Provides fast access to frequently requested market data with automatic expiration
  and cleanup. Used by zen_cex adapters to avoid unnecessary API calls.

  ## Usage

      # Get cached value
      {:ok, ticker} = ZenCex.Core.Cache.get("ticker:binance:BTCUSDT")

      # Store value with TTL
      ZenCex.Core.Cache.put("ticker:binance:BTCUSDT", ticker_data, 60)

      # Clear all cached data
      ZenCex.Core.Cache.clear()

      # Get cache statistics
      %{cache_size: 1200, evictions: 45} = ZenCex.Core.Cache.stats()

  ## Configuration

  The cache is automatically managed by the zen_cex supervision tree:
  - Maximum cache size: 10,000 entries
  - Cleanup runs every 5 minutes
  - LRU eviction when cache is full (using efficient ordered_set table)
  - Pattern deletion batch size: 100 entries

  ## Telemetry Events

  The cache emits telemetry events for monitoring and observability:

  - `[:zen_cex, :cache, :hit]` - Cache hit with key and duration
  - `[:zen_cex, :cache, :miss]` - Cache miss with key and duration
  - `[:zen_cex, :cache, :expired]` - Expired entry accessed with key and duration
  - `[:zen_cex, :cache, :put]` - Entry stored with key, TTL, and duration
  - `[:zen_cex, :cache, :eviction]` - LRU eviction with evicted count and duration
  - `[:zen_cex, :cache, :pattern_delete]` - Pattern deletion with pattern, deleted count, and duration
  - `[:zen_cex, :cache, :cleanup]` - Periodic cleanup with expired count and duration

  Subscribe to these events for metrics collection:

      :telemetry.attach(
        "cache-metrics",
        [:zen_cex, :cache, :pattern_delete],
        &MyApp.Telemetry.handle_cache_event/4,
        nil
      )
  """

  use GenServer

  require Logger

  @table_name :zen_cex_cache
  @lru_table_name :zen_cex_cache_lru

  # Cleanup configuration
  @cleanup_interval_minutes 5
  @cleanup_interval_ms @cleanup_interval_minutes * 60 * 1000

  # Cache size configuration
  # Assuming average entry size of 1KB, this gives us ~10MB max memory usage
  @average_entry_size_kb 1
  @max_cache_memory_mb 10
  @max_cache_size div(@max_cache_memory_mb * 1024, @average_entry_size_kb)

  # Eviction configuration
  # Evict 10% of cache when full
  @eviction_percentage 10
  @eviction_batch_size div(@max_cache_size * @eviction_percentage, 100)

  # Pattern deletion batch size for memory-efficient processing
  @pattern_batch_size 100

  # Public API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns a list of telemetry events emitted by the cache.

  Useful for understanding what events are available for monitoring and metrics collection.

  ## Example

      events = ZenCex.Core.Cache.telemetry_events()

      Enum.each(events, fn {event_name, measurements, metadata} ->
        :telemetry.attach(
          "my-handler-\#{inspect(event_name)}",
          event_name,
          &MyApp.Telemetry.handle_event/4,
          nil
        )
      end)

  ## Returns

  A list of tuples containing:
  - Event name (e.g., `[:zen_cex, :cache, :hit]`)
  - Measurements map with types (e.g., `%{duration: :integer}`)
  - Metadata map with types (e.g., `%{key: :binary}`)

  """
  @spec telemetry_events() :: [
          {event_name :: [atom()], measurements :: map(), metadata :: map()}
        ]
  def telemetry_events do
    [
      {[:zen_cex, :cache, :hit], %{duration: :integer}, %{key: :binary}},
      {[:zen_cex, :cache, :miss], %{duration: :integer}, %{key: :binary}},
      {[:zen_cex, :cache, :expired], %{duration: :integer}, %{key: :binary}},
      {[:zen_cex, :cache, :put], %{duration: :integer}, %{key: :binary, ttl: :integer}},
      {[:zen_cex, :cache, :eviction], %{duration: :integer}, %{evicted_count: :integer}},
      {[:zen_cex, :cache, :pattern_delete], %{duration: :integer}, %{pattern: :binary, deleted: :integer}},
      {[:zen_cex, :cache, :cleanup], %{duration: :integer}, %{expired_count: :integer}}
    ]
  end

  @doc """
  Gets a value from the cache.

  Returns `{:ok, value}` if found and not expired, `{:error, reason}` otherwise.

  ## Examples

      {:ok, ticker} = ZenCex.Core.Cache.get("ticker:binance:BTCUSDT")
      {:error, :not_found} = ZenCex.Core.Cache.get("non_existent_key")
      {:error, :expired} = ZenCex.Core.Cache.get("expired_key")

  """
  @spec get(binary()) :: {:ok, term()} | {:error, :not_found | :expired}
  def get(key) when is_binary(key) do
    start_time = System.monotonic_time()

    case lookup_and_validate(key) do
      {:ok, value} ->
        # Update access time via GenServer for LRU tracking
        if Process.whereis(__MODULE__) do
          GenServer.cast(__MODULE__, {:update_access_time, key})
        end

        emit_telemetry(:hit, start_time, %{key: key})
        {:ok, value}

      {:expired, _value} ->
        emit_telemetry(:expired, start_time, %{key: key})
        {:error, :expired}

      :not_found ->
        emit_telemetry(:miss, start_time, %{key: key})
        {:error, :not_found}
    end
  end

  @doc """
  Puts a value in the cache with a TTL in seconds.

  ## Examples

      # Cache ticker for 60 seconds
      ZenCex.Core.Cache.put("ticker:binance:BTCUSDT", ticker_data, 60)

      # Cache funding rate for 5 minutes
      ZenCex.Core.Cache.put("funding:bybit:ETHUSDT", funding_data, 300)

  """
  @spec put(binary(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_seconds) when is_binary(key) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:put, key, value, ttl_seconds})
    else
      :ok
    end
  end

  @doc """
  Removes a specific key from the cache.

  ## Examples

      ZenCex.Core.Cache.delete("ticker:binance:BTCUSDT")

  """
  @spec delete(binary()) :: :ok
  def delete(key) when is_binary(key) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:delete, key})
    else
      :ok
    end
  end

  @doc """
  Clears all entries from the cache.

  ## Examples

      ZenCex.Core.Cache.clear()

  """
  @spec clear() :: :ok
  def clear do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :clear)
    else
      :ok
    end
  end

  @doc """
  Clears all cache entries matching a pattern with wildcard support.

  ## Pattern Syntax

  Supports flexible wildcard patterns for efficient cache management:

  - **Prefix match**: `"market:"` - matches all keys starting with "market:"
  - **Suffix match**: `"*:BTCUSDT"` - matches all keys ending with ":BTCUSDT"
  - **Middle wildcard**: `"market:*:binance:*"` - matches keys with "market:" prefix and ":binance:" in middle
  - **End wildcard**: `"market:ticker:*"` - matches all keys starting with "market:ticker:"
  - **Complex patterns**: Multiple wildcards are converted to regex for maximum flexibility

  ## Performance Notes

  - Uses ETS batch processing with continuations to avoid memory spikes
  - Processes deletions in chunks of 100 entries (configurable via @pattern_batch_size)
  - Emits telemetry events for monitoring deletion performance

  ## Examples

      # Clear all Binance market data (matches "market:ticker:binance:BTCUSDT", etc.)
      {:ok, count} = ZenCex.Core.Cache.clear_pattern("market:*:binance:*")

      # Clear all ticker data across all exchanges
      {:ok, count} = ZenCex.Core.Cache.clear_pattern("market:ticker:*")

      # Clear all BTCUSDT data regardless of exchange or type
      {:ok, count} = ZenCex.Core.Cache.clear_pattern("*:BTCUSDT")

      # Clear everything in market namespace
      {:ok, count} = ZenCex.Core.Cache.clear_pattern("market:")

  """
  @spec clear_pattern(binary()) :: {:ok, non_neg_integer()}
  def clear_pattern(pattern) when is_binary(pattern) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:clear_pattern, pattern})
    else
      {:ok, 0}
    end
  end

  @doc """
  Gets cache statistics including size, evictions, and cleanup counts.

  ## Examples

      %{
        cache_size: 1200,
        evictions: 45,
        cleanup_count: 12,
        max_cache_size: 10000,
        eviction_batch_size: 1000
      } = ZenCex.Core.Cache.stats()

  """
  @spec stats() :: %{
          cache_size: non_neg_integer(),
          evictions: non_neg_integer(),
          cleanup_count: non_neg_integer(),
          max_cache_size: pos_integer(),
          eviction_batch_size: pos_integer()
        }
  def stats do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :stats)
    else
      %{
        cache_size: 0,
        evictions: 0,
        cleanup_count: 0,
        max_cache_size: @max_cache_size,
        eviction_batch_size: @eviction_batch_size
      }
    end
  end

  # GenServer implementation

  @impl true
  def init(_) do
    :ets.new(@table_name, [:set, :protected, :named_table, read_concurrency: true])
    # LRU table: {access_time, key} -> true for efficient ordering by access time
    :ets.new(@lru_table_name, [:ordered_set, :protected, :named_table])
    schedule_cleanup()
    {:ok, %{cleanup_count: 0, cache_size: 0, evictions: 0}}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@lru_table_name)
    {:reply, :ok, %{state | cache_size: 0}}
  end

  @impl true
  def handle_call({:clear_pattern, pattern}, _from, state) do
    start_time = System.monotonic_time()
    deleted_count = delete_by_pattern(pattern)

    # Emit telemetry for pattern deletion performance
    emit_telemetry(:pattern_delete, start_time, %{
      pattern: pattern,
      deleted: deleted_count
    })

    new_state = Map.update(state, :cache_size, 0, &max(&1 - deleted_count, 0))
    {:reply, {:ok, deleted_count}, new_state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    old_entry = :ets.lookup(@table_name, key)
    was_present = old_entry != []

    if was_present do
      [{^key, _value, _expiry, access_time}] = old_entry
      :ets.delete(@table_name, key)
      :ets.delete(@lru_table_name, {access_time, key})
    end

    new_state =
      if was_present do
        Map.update(state, :cache_size, 0, &max(&1 - 1, 0))
      else
        state
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      cache_size: Map.get(state, :cache_size, 0),
      evictions: Map.get(state, :evictions, 0),
      cleanup_count: Map.get(state, :cleanup_count, 0),
      max_cache_size: @max_cache_size,
      eviction_batch_size: @eviction_batch_size
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl_seconds}, _from, state) do
    start_time = System.monotonic_time()

    # Check cache size and evict if necessary
    new_state = ensure_cache_capacity(state)

    expiry = DateTime.add(DateTime.utc_now(), ttl_seconds, :second)
    access_time = System.monotonic_time(:nanosecond)

    # Check if key already exists to clean up old LRU entry
    old_entry = :ets.lookup(@table_name, key)
    is_new = old_entry == []

    if !is_new do
      # Remove old LRU entry
      [{^key, _value, _expiry, old_access_time}] = old_entry
      :ets.delete(@lru_table_name, {old_access_time, key})
    end

    # Insert/update main entry with new access time
    :ets.insert(@table_name, {key, value, expiry, access_time})
    # Insert new LRU entry
    :ets.insert(@lru_table_name, {{access_time, key}, true})

    emit_telemetry(:put, start_time, %{key: key, ttl: ttl_seconds})

    updated_state =
      if is_new do
        Map.update(new_state, :cache_size, 1, &(&1 + 1))
      else
        new_state
      end

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_cast({:delete, key}, state) do
    old_entry = :ets.lookup(@table_name, key)
    was_present = old_entry != []

    if was_present do
      [{^key, _value, _expiry, access_time}] = old_entry
      :ets.delete(@table_name, key)
      :ets.delete(@lru_table_name, {access_time, key})
    end

    new_state =
      if was_present do
        Map.update(state, :cache_size, 0, &max(&1 - 1, 0))
      else
        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_access_time, key}, state) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry, old_access_time}] ->
        # Update access time for LRU tracking
        new_access_time = System.monotonic_time(:nanosecond)
        :ets.insert(@table_name, {key, value, expiry, new_access_time})
        # Update LRU table (delete old entry, insert new)
        :ets.delete(@lru_table_name, {old_access_time, key})
        :ets.insert(@lru_table_name, {{new_access_time, key}, true})

      [] ->
        # Key doesn't exist, nothing to update
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    start_time = System.monotonic_time()
    count = cleanup_expired_entries()

    if count > 0 do
      Logger.debug("ZenCex cache cleanup: removed #{count} expired entries")
    end

    # Emit telemetry for cleanup monitoring
    emit_telemetry(:cleanup, start_time, %{expired_count: count})

    schedule_cleanup()

    new_state =
      state
      |> Map.update(:cleanup_count, count, &(&1 + count))
      |> Map.update(:cache_size, 0, &max(&1 - count, 0))

    {:noreply, new_state}
  end

  # Private functions

  defp lookup_and_validate(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry, _access_time}] ->
        if DateTime.before?(DateTime.utc_now(), expiry) do
          {:ok, value}
        else
          cleanup_expired_key(key)
          {:expired, value}
        end

      [] ->
        :not_found
    end
  end

  defp delete_by_pattern(pattern) do
    # Optimized pattern-based deletion using ETS match specifications
    # For patterns like "market:ticker:*", we can use efficient ETS operations

    deleted_count =
      if String.contains?(pattern, "*") do
        delete_by_wildcard_pattern(pattern)
      else
        # Simple prefix pattern - use optimized match_delete for efficiency
        delete_by_prefix_pattern_optimized(pattern)
      end

    deleted_count
  end

  defp delete_by_prefix_pattern_optimized(prefix) do
    # Optimized deletion for simple prefix patterns using match_delete
    # This is more efficient than iterating and deleting one by one
    # Build a match spec that matches keys starting with prefix

    # We use "￿" (U+FFFF) as it's the highest Unicode character in the BMP
    # This ensures we capture all strings that start with the prefix
    # For example: prefix="abc" will match "abc", "abcd", "abc123", etc.
    # but not "abd" because "abc￿" sorts before "abd"

    # First, get all matching entries to delete from LRU table
    match_spec = [
      {{:"$1", :"$2", :"$3", :"$4"}, [{:andalso, {:is_binary, :"$1"}, {:>=, :"$1", prefix}, {:<, :"$1", prefix <> "￿"}}],
       [{{:"$1", :"$4"}}]}
    ]

    # Get keys with access times for LRU cleanup
    keys_with_times = :ets.select(@table_name, match_spec)

    # Delete from LRU table
    Enum.each(keys_with_times, fn {key, access_time} ->
      :ets.delete(@lru_table_name, {access_time, key})
    end)

    # Now use match_delete for efficient deletion from main table
    delete_match_spec = [
      {{:"$1", :_, :_, :_}, [{:andalso, {:is_binary, :"$1"}, {:>=, :"$1", prefix}, {:<, :"$1", prefix <> "￿"}}], [true]}
    ]

    :ets.select_delete(@table_name, delete_match_spec)
  end

  defp delete_by_prefix_pattern(prefix) do
    # Use ETS match_object with continuation for memory efficiency
    # This avoids loading all entries at once
    match_spec = [{{:"$1", :_, :_, :_}, [{:is_binary, :"$1"}], [:"$_"]}]

    delete_matching_entries(match_spec, fn {key, _, _, _} ->
      String.starts_with?(key, prefix)
    end)
  end

  defp delete_by_wildcard_pattern(pattern) do
    parts = String.split(pattern, "*")

    case parts do
      [prefix, ""] ->
        # Pattern ends with *, simple prefix match
        delete_by_prefix_pattern(prefix)

      ["", suffix] ->
        # Pattern starts with *, suffix match
        match_spec = [{{:"$1", :_, :_, :_}, [{:is_binary, :"$1"}], [:"$_"]}]

        delete_matching_entries(match_spec, fn {key, _, _, _} ->
          String.ends_with?(key, suffix)
        end)

      [prefix, suffix] ->
        # Pattern has * in middle, e.g., "market:*:binance:*"
        match_spec = [{{:"$1", :_, :_, :_}, [{:is_binary, :"$1"}], [:"$_"]}]

        delete_matching_entries(match_spec, fn {key, _, _, _} ->
          String.starts_with?(key, prefix) && String.ends_with?(key, suffix)
        end)

      _ ->
        # Complex pattern with multiple *, convert to regex
        regex_pattern = "^" <> String.replace(pattern, "*", ".*") <> "$"
        {:ok, regex} = Regex.compile(regex_pattern)

        match_spec = [{{:"$1", :_, :_, :_}, [{:is_binary, :"$1"}], [:"$_"]}]

        delete_matching_entries(match_spec, fn {key, _, _, _} ->
          Regex.match?(regex, key)
        end)
    end
  end

  defp delete_matching_entries(match_spec, filter_fun) do
    # Use select with continuation to handle large tables efficiently
    # Process in batches to avoid memory spikes
    delete_batch_initial(match_spec, filter_fun, 0)
  end

  defp delete_batch_initial(match_spec, filter_fun, count) do
    case :ets.select(@table_name, match_spec, @pattern_batch_size) do
      :"$end_of_table" ->
        count

      {entries, continuation} ->
        deleted = process_deletion_batch(entries, filter_fun)
        delete_batch_cont(continuation, filter_fun, count + deleted)
    end
  end

  defp delete_batch_cont(continuation, filter_fun, count) do
    case :ets.select(continuation) do
      :"$end_of_table" ->
        count

      {entries, new_continuation} ->
        deleted = process_deletion_batch(entries, filter_fun)
        delete_batch_cont(new_continuation, filter_fun, count + deleted)
    end
  end

  defp process_deletion_batch(entries, filter_fun) do
    Enum.reduce(entries, 0, fn entry, acc ->
      {key, _value, _expiry, access_time} = entry

      if filter_fun.(entry) do
        # Delete from both tables
        :ets.delete(@table_name, key)
        :ets.delete(@lru_table_name, {access_time, key})
        acc + 1
      else
        acc
      end
    end)
  end

  defp cleanup_expired_key(key) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:delete, key})
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end

  defp ensure_cache_capacity(state) do
    cache_size = Map.get(state, :cache_size, 0)

    if cache_size >= @max_cache_size do
      start_time = System.monotonic_time()
      evicted = evict_oldest_entries(@eviction_batch_size)

      # Emit telemetry for eviction monitoring
      emit_telemetry(:eviction, start_time, %{evicted_count: evicted})

      state
      |> Map.update(:cache_size, 0, &max(&1 - evicted, 0))
      |> Map.update(:evictions, evicted, &(&1 + evicted))
    else
      state
    end
  end

  defp evict_oldest_entries(count) do
    # Optimized LRU eviction using ordered_set table
    # The LRU table is ordered by {access_time, key} so :ets.first/1
    # always gives us the oldest entry efficiently
    # This is O(log n) per deletion, much better than loading all entries

    evict_oldest_batch(count, 0)
  end

  defp evict_oldest_batch(0, evicted_count), do: evicted_count

  defp evict_oldest_batch(remaining, evicted_count) do
    # Get the oldest entry by taking the first key from ordered_set
    # This is efficient because ordered_set maintains order internally
    case :ets.first(@lru_table_name) do
      :"$end_of_table" ->
        # No more entries to evict
        evicted_count

      {_access_time, key} = lru_key ->
        # Delete from both tables atomically
        :ets.delete(@table_name, key)
        :ets.delete(@lru_table_name, lru_key)

        evict_oldest_batch(remaining - 1, evicted_count + 1)
    end
  end

  defp cleanup_expired_entries do
    now = DateTime.utc_now()

    # Use foldl to iterate and delete expired entries from both tables
    # This is more memory-efficient than select_delete for our use case
    # since we need to count deletions and track state
    :ets.foldl(
      fn {key, _value, expiry, access_time}, acc ->
        if DateTime.before?(expiry, now) do
          :ets.delete(@table_name, key)
          :ets.delete(@lru_table_name, {access_time, key})
          acc + 1
        else
          acc
        end
      end,
      0,
      @table_name
    )
  end

  defp emit_telemetry(event, start_time, metadata) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:zen_cex, :cache, event],
      %{duration: duration},
      metadata
    )
  end
end
