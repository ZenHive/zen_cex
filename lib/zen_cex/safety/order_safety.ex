defmodule ZenCex.Safety.OrderSafety do
  @moduledoc """
  Order safety module providing idempotency checks to prevent duplicate order placement.

  This module implements a 30-minute sliding window for idempotency checks, storing
  order IDs with timestamps in ETS tables for high-performance lookups.

  ## Features

  - 30-minute sliding window for duplicate detection
  - Deterministic client_order_id generation
  - Sub-50μs idempotency checks
  - Automatic cleanup of expired entries
  - Exchange-specific order tracking

  ## Implementation

  Uses ETS tables for atomic operations and high-performance lookups.
  Each order is stored as `{exchange, client_order_id, timestamp}`.
  """

  use GenServer

  require Logger

  @table_name :order_idempotency
  # 30 minutes in milliseconds
  @window_ms 30 * 60 * 1000
  # Clean every 60 seconds
  @cleanup_interval_ms 60 * 1000

  # Client API

  @doc """
  Starts the OrderSafety GenServer.

  ## Options
  - `:name` - The name to register the process under (default: `__MODULE__`)
  - `:cleanup_interval` - Cleanup interval in ms (default: 60,000)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks if an order with the given client_order_id already exists within the idempotency window.

  ## Parameters
  - `exchange` - The exchange atom (e.g., `:binance`)
  - `client_order_id` - The client-generated order ID

  ## Returns
  - `{:ok, :new}` - Order is new and can proceed
  - `{:error, :duplicate}` - Order already exists in the window

  ## Performance
  This operation is designed to complete in < 50μs.

  ## Examples

      iex> OrderSafety.check_existing_order(:binance, "order_123")
      {:ok, :new}

      iex> OrderSafety.check_existing_order(:binance, "order_123")
      {:error, :duplicate}
  """
  @spec check_existing_order(atom(), String.t()) :: {:ok, :new} | {:error, :duplicate}
  def check_existing_order(exchange, client_order_id) do
    now_ms = System.system_time(:millisecond)
    cutoff = now_ms - @window_ms
    key = {exchange, client_order_id}

    case :ets.lookup(@table_name, key) do
      [] ->
        # No existing order found
        {:ok, :new}

      [{^key, timestamp}] when timestamp > cutoff ->
        # Order exists and is within the window
        {:error, :duplicate}

      [{^key, _timestamp}] ->
        # Order exists but is outside the window (expired)
        {:ok, :new}
    end
  end

  @doc """
  Records an order placement with idempotency tracking.

  ## Parameters
  - `exchange` - The exchange atom
  - `client_order_id` - The client-generated order ID

  ## Returns
  - `:ok` - Order recorded successfully
  - `{:error, :duplicate}` - Order already exists

  ## Examples

      iex> OrderSafety.record_order(:binance, "order_123")
      :ok
  """
  @spec record_order(atom(), String.t()) :: :ok | {:error, :duplicate}
  def record_order(exchange, client_order_id) do
    now_ms = System.system_time(:millisecond)
    cutoff = now_ms - @window_ms
    key = {exchange, client_order_id}

    # Atomic check-and-insert operation
    case :ets.insert_new(@table_name, {key, now_ms}) do
      true ->
        # Successfully inserted new entry
        emit_telemetry(:order_recorded, exchange, client_order_id)
        :ok

      false ->
        # Entry already exists, check if it's within the window
        case :ets.lookup(@table_name, key) do
          [{^key, timestamp}] when timestamp > cutoff ->
            emit_telemetry(:duplicate_detected, exchange, client_order_id)
            {:error, :duplicate}

          [{^key, _old_timestamp}] ->
            # Old entry expired, update with new timestamp
            :ets.insert(@table_name, {key, now_ms})
            emit_telemetry(:order_recorded, exchange, client_order_id)
            :ok
        end
    end
  end

  @doc """
  Generates a deterministic client order ID based on input parameters.

  ## Parameters
  - `exchange` - The exchange atom
  - `params` - Order parameters map with keys like `:symbol`, `:side`, `:amount`
  - `opts` - Options including `:nonce` for uniqueness

  ## Returns
  A unique, deterministic client order ID string.

  ## Examples

      iex> OrderSafety.generate_client_order_id(:binance, %{symbol: "BTCUSDT", side: :buy})
      "binance_BTCUSDT_buy_1234567890"
  """
  @spec generate_client_order_id(atom(), map(), keyword()) :: String.t()
  def generate_client_order_id(exchange, params, opts \\ []) do
    nonce = Keyword.get(opts, :nonce, System.system_time(:millisecond))

    # Create deterministic ID from parameters
    base = "#{exchange}_#{params[:symbol]}_#{params[:side]}"

    # Add optional amount for more uniqueness
    base = if params[:amount], do: "#{base}_#{params[:amount]}", else: base

    # Add nonce for uniqueness
    "#{base}_#{nonce}"
  end

  @doc """
  Removes an order from tracking (e.g., after cancellation or rollback).

  ## Parameters
  - `exchange` - The exchange atom
  - `client_order_id` - The client order ID to remove

  ## Returns
  - `:ok` - Always returns ok

  ## Examples

      iex> OrderSafety.remove_order(:binance, "order_123")
      :ok
  """
  @spec remove_order(atom(), String.t()) :: :ok
  def remove_order(exchange, client_order_id) do
    key = {exchange, client_order_id}
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Cleans up expired entries from the idempotency cache.

  This is called automatically every 60 seconds but can be called manually.

  ## Returns
  The number of entries removed.

  ## Examples

      iex> OrderSafety.cleanup_expired()
      42
  """
  @spec cleanup_expired() :: non_neg_integer()
  def cleanup_expired do
    now_ms = System.system_time(:millisecond)
    cutoff = now_ms - @window_ms

    # Select and delete all entries older than the window
    match_spec = [
      {{{:"$1", :"$2"}, :"$3"}, [{:<, :"$3", cutoff}], [true]}
    ]

    num_deleted = :ets.select_delete(@table_name, match_spec)

    if num_deleted > 0 do
      Logger.debug("OrderSafety cleaned up #{num_deleted} expired entries")
    end

    num_deleted
  end

  @doc """
  Gets statistics about the idempotency cache.

  ## Returns
  Map with cache statistics including:
  - `:total_entries` - Total number of tracked orders
  - `:window_ms` - Idempotency window in milliseconds
  - `:memory_bytes` - Memory used by the cache

  ## Examples

      iex> OrderSafety.get_stats()
      %{total_entries: 150, window_ms: 1800000, memory_bytes: 12000}
  """
  @spec get_stats() :: map()
  def get_stats do
    %{
      total_entries: :ets.info(@table_name, :size),
      window_ms: @window_ms,
      memory_bytes: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    }
  end

  @doc """
  Clears all entries from the idempotency cache.

  Use with caution - this removes all duplicate protection!

  ## Returns
  `:ok`

  ## Examples

      iex> OrderSafety.clear_all()
      :ok
  """
  @spec clear_all() :: :ok
  def clear_all do
    :ets.delete_all_objects(@table_name)
    Logger.warning("OrderSafety cache cleared - all idempotency data removed")
    :ok
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    # Create ETS table if it doesn't exist
    unless table_exists?() do
      :ets.new(@table_name, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])
    end

    # Schedule periodic cleanup
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @cleanup_interval_ms)
    schedule_cleanup(cleanup_interval)

    {:ok, %{cleanup_interval: cleanup_interval}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup(state.cleanup_interval)
    {:noreply, state}
  end

  # Private functions

  defp table_exists? do
    case :ets.whereis(@table_name) do
      :undefined -> false
      _ -> true
    end
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end

  defp emit_telemetry(event, exchange, client_order_id) do
    :telemetry.execute(
      [:zen_cex, :order, event],
      %{count: 1},
      %{exchange: exchange, client_order_id: client_order_id}
    )
  end
end
