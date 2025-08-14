defmodule ZenCex.Cache do
  @moduledoc """
  Simple caching layer with TTL management for exchange data.

  Uses ETS tables for concurrent access and automatic cleanup of expired entries.
  Separate tables for different data types to optimize memory and access patterns.

  ## Features
  - TTL-based expiration (default 60 seconds)
  - Automatic cleanup every 60 seconds
  - Memory-bounded operations with statistics
  - Separate tables for positions, balances, and market data
  - Concurrent read/write access via public ETS tables

  ## Usage

      # Store data with default TTL
      Cache.put(:binance, :positions, "btc_position", %{amount: 1.5})
      
      # Store with custom TTL
      Cache.put(:kraken, :market_data, "eth_price", %{price: 3000}, ttl: 30_000)
      
      # Retrieve data
      {:ok, data} = Cache.get(:binance, :positions, "btc_position")
      
      # Get data with age
      {:ok, data, age_ms} = Cache.get_with_age(:binance, :positions, "btc_position")
  """

  use GenServer
  require Logger

  @type exchange :: :binance | :kraken | :deribit | atom()
  @type data_type :: :positions | :balances | :market_data
  @type cache_key :: {exchange(), data_type(), String.t()}

  @default_ttl :timer.seconds(60)
  @cleanup_interval :timer.seconds(60)

  # Table names
  @positions_table :exchange_cache_positions
  @balances_table :exchange_cache_balances
  @market_data_table :exchange_cache_market_data

  @doc """
  Starts the cache process and creates ETS tables.

  ## Options
  - `:default_ttl` - Default TTL in milliseconds (default: 60000)
  - `:cleanup_interval` - Cleanup interval in milliseconds (default: 60000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores data in the cache with TTL.
  """
  @spec put(exchange(), data_type(), String.t(), map(), keyword()) :: :ok
  def put(exchange, data_type, key, value, opts \\ []) do
    start_time = System.monotonic_time()

    ttl = Keyword.get(opts, :ttl, get_default_ttl())
    now = System.system_time(:millisecond)
    expire_at = now + ttl

    table = get_table(data_type)
    cache_key = {exchange, data_type, key}

    # Store with creation time for accurate age calculation
    # Format: {{exchange, data_type, key}, value, expire_at, created_at}
    ensure_table_exists(table)
    :ets.insert(table, {cache_key, value, expire_at, now})

    # Emit telemetry event
    :telemetry.execute(
      [:zen_cex, :exchange, :cache, :put],
      %{duration: System.monotonic_time() - start_time},
      %{exchange: exchange, data_type: data_type, ttl: ttl}
    )

    :ok
  end

  @doc """
  Retrieves data from the cache if not expired.
  """
  @spec get(exchange(), data_type(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(exchange, data_type, key) do
    table = get_table(data_type)
    ensure_table_exists(table)
    cache_key = {exchange, data_type, key}
    now = System.system_time(:millisecond)

    case :ets.lookup(table, cache_key) do
      [{^cache_key, value, expire_at, _created_at}] when expire_at > now ->
        {:ok, value}

      [{^cache_key, _value, _expire_at, _created_at}] ->
        # Expired entry, remove it
        :ets.delete(table, cache_key)
        {:error, :not_found}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Retrieves data with its age in milliseconds.
  """
  @spec get_with_age(exchange(), data_type(), String.t()) ::
          {:ok, map(), non_neg_integer()} | {:error, :not_found}
  def get_with_age(exchange, data_type, key) do
    table = get_table(data_type)
    ensure_table_exists(table)
    cache_key = {exchange, data_type, key}
    now = System.system_time(:millisecond)

    case :ets.lookup(table, cache_key) do
      [{^cache_key, value, expire_at, created_at}] when expire_at > now ->
        age_ms = now - created_at
        {:ok, value, age_ms}

      [{^cache_key, _value, _expire_at, _created_at}] ->
        # Expired entry, remove it
        :ets.delete(table, cache_key)
        {:error, :not_found}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Deletes a specific key from the cache.
  """
  @spec delete(exchange(), data_type(), String.t()) :: :ok
  def delete(exchange, data_type, key) do
    table = get_table(data_type)
    ensure_table_exists(table)
    cache_key = {exchange, data_type, key}
    :ets.delete(table, cache_key)
    :ok
  end

  @doc """
  Clears all cache entries for a specific exchange and data type.
  """
  @spec clear(exchange(), data_type()) :: :ok
  def clear(exchange, data_type) do
    table = get_table(data_type)
    ensure_table_exists(table)
    :ets.match_delete(table, {{exchange, data_type, :_}, :_, :_, :_})
    :ok
  end

  @doc """
  Returns cache statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    %{
      positions: table_stats(@positions_table),
      balances: table_stats(@balances_table),
      market_data: table_stats(@market_data_table),
      total_entries: total_entries(),
      memory_bytes: total_memory()
    }
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    # Create ETS tables
    create_tables()

    # Store configuration
    state = %{
      default_ttl: Keyword.get(opts, :default_ttl, @default_ttl),
      cleanup_interval: Keyword.get(opts, :cleanup_interval, @cleanup_interval)
    }

    # Store default TTL in persistent term for fast access
    :persistent_term.put({__MODULE__, :default_ttl}, state.default_ttl)

    # Schedule first cleanup
    schedule_cleanup(state.cleanup_interval)

    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Clean up expired entries from all tables
    now = System.system_time(:millisecond)

    [@positions_table, @balances_table, @market_data_table]
    |> Enum.each(fn table ->
      cleanup_table(table, now)
    end)

    # Schedule next cleanup
    schedule_cleanup(state.cleanup_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Cache received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private functions

  defp create_tables do
    # Create public tables for concurrent access
    # Using ordered_set for consistent iteration order
    opts = [:ordered_set, :public, :named_table, {:read_concurrency, true}]

    :ets.new(@positions_table, opts)
    :ets.new(@balances_table, opts)
    :ets.new(@market_data_table, opts)
  end

  defp get_table(:positions), do: @positions_table
  defp get_table(:balances), do: @balances_table
  defp get_table(:market_data), do: @market_data_table

  defp get_default_ttl do
    :persistent_term.get({__MODULE__, :default_ttl}, @default_ttl)
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  defp cleanup_table(table, now) do
    start_time = System.monotonic_time()

    # Use select_delete for efficient bulk deletion
    # Storage format: {{exchange, data_type, key}, value, expire_at, created_at}
    # We need to match the third element (expire_at) of the outer tuple
    # First element is a 3-tuple, not a 4-tuple
    match_spec = [
      {{{:_, :_, :_}, :_, :"$1", :_}, [{:"=<", :"$1", now}], [true]}
    ]

    deleted = :ets.select_delete(table, match_spec)

    if deleted > 0 do
      Logger.debug("Cache cleanup removed #{deleted} expired entries from #{table}")

      # Emit telemetry event for monitoring
      :telemetry.execute(
        [:zen_cex, :exchange, :cache, :cleanup],
        %{
          entries_removed: deleted,
          duration: System.monotonic_time() - start_time
        },
        %{table: table}
      )
    end
  end

  defp table_stats(table) do
    %{
      count: :ets.info(table, :size),
      memory_bytes: :ets.info(table, :memory) * :erlang.system_info(:wordsize)
    }
  end

  defp total_entries do
    [@positions_table, @balances_table, @market_data_table]
    |> Enum.map(&:ets.info(&1, :size))
    |> Enum.sum()
  end

  defp total_memory do
    [@positions_table, @balances_table, @market_data_table]
    |> Enum.map(&(:ets.info(&1, :memory) * :erlang.system_info(:wordsize)))
    |> Enum.sum()
  end

  defp ensure_table_exists(table) do
    # Check if table exists, return immediately if it does
    case :ets.whereis(table) do
      :undefined ->
        # Table doesn't exist - try to create it
        # Multiple processes might try this simultaneously, so handle the race condition
        opts = [:ordered_set, :public, :named_table, {:read_concurrency, true}]

        try do
          :ets.new(table, opts)
          :ok
        rescue
          ArgumentError ->
            # Table was created by another process between our check and creation attempt
            # Verify it exists now
            case :ets.whereis(table) do
              :undefined ->
                # Still doesn't exist - this shouldn't happen but handle it
                raise "Failed to create or find ETS table #{table}"

              _pid ->
                :ok
            end
        end

      _pid ->
        :ok
    end
  end
end
