defmodule ZenCex.Safety.OrderSafety.Cache do
  @moduledoc """
  Cache management for OrderSafety module.

  Handles caching of market data including prices, symbol info, and minimum notionals
  with appropriate TTLs and cleanup strategies.
  """

  alias ZenCex.Config.TimeConstants

  require Logger

  # Cache table name
  @market_data_cache_table :market_data_cache

  # Get cache TTLs from TimeConstants based on environment
  @cache_ttls TimeConstants.cache_ttls()
  @symbol_info_ttl_ms @cache_ttls.symbol_info
  @min_notional_ttl_ms @cache_ttls.min_notional
  @price_cache_ttl_ms @cache_ttls.price

  # Public API

  @doc """
  Looks up a value in the cache.

  Returns `{:ok, value}` if found and not expired, `:miss` otherwise.
  """
  @spec lookup(atom(), term(), non_neg_integer()) :: {:ok, term()} | :miss
  def lookup(cache_type, key, ttl_ms) do
    now_ms = System.system_time(:millisecond)
    cache_key = {cache_type, key}

    # Safely handle case where table doesn't exist
    case safe_ets_lookup(@market_data_cache_table, cache_key) do
      [{^cache_key, value, timestamp}] ->
        if now_ms - timestamp <= ttl_ms do
          # Cache hit and not expired
          :telemetry.execute(
            [:zen_cex, :order_safety, :cache, :hit],
            %{count: 1},
            %{cache_type: cache_type, key: key}
          )

          {:ok, value}
        else
          # Cache expired
          :telemetry.execute(
            [:zen_cex, :order_safety, :cache, :expired],
            %{count: 1},
            %{cache_type: cache_type, key: key}
          )

          :miss
        end

      [] ->
        # Cache miss
        :telemetry.execute(
          [:zen_cex, :order_safety, :cache, :miss],
          %{count: 1},
          %{cache_type: cache_type, key: key}
        )

        :miss
    end
  end

  @doc """
  Stores a value in the cache.
  """
  @spec put(atom(), term(), term()) :: true | false
  def put(cache_type, key, value) do
    now_ms = System.system_time(:millisecond)
    cache_key = {cache_type, key}
    safe_ets_insert(@market_data_cache_table, {cache_key, value, now_ms})
  end

  @doc """
  Looks up a price in the cache.
  """
  @spec lookup_price({atom(), String.t()}) :: {:ok, Decimal.t()} | :miss
  def lookup_price(key) do
    lookup(:price, key, @price_cache_ttl_ms)
  end

  @doc """
  Stores a price in the cache.
  """
  @spec put_price({atom(), String.t()}, Decimal.t()) :: true
  def put_price(key, value) do
    put(:price, key, value)
  end

  @doc """
  Looks up symbol info in the cache.
  """
  @spec lookup_symbol_info({atom(), String.t()}) :: {:ok, map()} | :miss
  def lookup_symbol_info(key) do
    lookup(:symbol_info, key, @symbol_info_ttl_ms)
  end

  @doc """
  Stores symbol info in the cache.
  """
  @spec put_symbol_info({atom(), String.t()}, map()) :: true
  def put_symbol_info(key, value) do
    put(:symbol_info, key, value)
  end

  @doc """
  Looks up minimum notional in the cache.
  """
  @spec lookup_min_notional({atom(), String.t()}) :: {:ok, Decimal.t()} | :miss
  def lookup_min_notional(key) do
    lookup(:min_notional, key, @min_notional_ttl_ms)
  end

  @doc """
  Stores minimum notional in the cache.
  """
  @spec put_min_notional({atom(), String.t()}, Decimal.t()) :: true
  def put_min_notional(key, value) do
    put(:min_notional, key, value)
  end

  @doc """
  Invalidates cached price for a specific symbol.
  """
  @spec invalidate_price(atom(), String.t()) :: :ok
  def invalidate_price(exchange, symbol) do
    cache_key = {:price, {exchange, symbol}}
    safe_ets_delete(@market_data_cache_table, cache_key)
    :ok
  end

  @doc """
  Invalidates cached symbol info for a specific symbol.
  """
  @spec invalidate_symbol_info(atom(), String.t()) :: :ok
  def invalidate_symbol_info(exchange, symbol) do
    cache_key = {:symbol_info, {exchange, symbol}}
    safe_ets_delete(@market_data_cache_table, cache_key)
    # Also clear min notional since it depends on symbol info
    invalidate_min_notional(exchange, symbol)
    :ok
  end

  @doc """
  Invalidates cached minimum notional for a specific symbol.
  """
  @spec invalidate_min_notional(atom(), String.t()) :: :ok
  def invalidate_min_notional(exchange, symbol) do
    cache_key = {:min_notional, {exchange, symbol}}
    safe_ets_delete(@market_data_cache_table, cache_key)
    :ok
  end

  @doc """
  Invalidates all cached data for a specific exchange.
  """
  @spec invalidate_exchange(atom()) :: {:ok, non_neg_integer()}
  def invalidate_exchange(exchange) do
    # Match all entries for the exchange - format: {{cache_type, {exchange, symbol}}, value, timestamp}
    match_spec = [
      {{{:"$1", {:"$2", :"$3"}}, :"$4", :"$5"}, [{:==, :"$2", exchange}], [true]}
    ]

    count = safe_ets_select_delete(@market_data_cache_table, match_spec)

    Logger.info("Invalidated #{count} cache entries for exchange: #{exchange}")
    {:ok, count}
  end

  @doc """
  Clears all cached market data.
  """
  @spec clear_all() :: :ok
  def clear_all do
    try do
      :ets.delete_all_objects(@market_data_cache_table)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc """
  Cleans up expired cache entries.
  """
  @spec cleanup(non_neg_integer()) :: non_neg_integer()
  def cleanup(now_ms) do
    price_cutoff = now_ms - @price_cache_ttl_ms
    symbol_info_cutoff = now_ms - @symbol_info_ttl_ms
    min_notional_cutoff = now_ms - @min_notional_ttl_ms

    # Delete expired price entries
    # Format: {{cache_type, key}, value, timestamp}
    price_match_spec = [
      {{{:price, :"$1"}, :"$2", :"$3"}, [{:<, :"$3", price_cutoff}], [true]}
    ]

    num_prices_deleted = safe_ets_select_delete(@market_data_cache_table, price_match_spec)

    # Delete expired symbol info entries
    symbol_info_match_spec = [
      {{{:symbol_info, :"$1"}, :"$2", :"$3"}, [{:<, :"$3", symbol_info_cutoff}], [true]}
    ]

    num_symbol_info_deleted = safe_ets_select_delete(@market_data_cache_table, symbol_info_match_spec)

    # Delete expired min notional entries
    min_notional_match_spec = [
      {{{:min_notional, :"$1"}, :"$2", :"$3"}, [{:<, :"$3", min_notional_cutoff}], [true]}
    ]

    num_min_notional_deleted = safe_ets_select_delete(@market_data_cache_table, min_notional_match_spec)

    total_deleted = num_prices_deleted + num_symbol_info_deleted + num_min_notional_deleted

    if total_deleted > 0 do
      Logger.debug(
        "OrderSafety.Cache cleaned up: #{num_prices_deleted} prices, " <>
          "#{num_symbol_info_deleted} symbol info, #{num_min_notional_deleted} min notionals"
      )
    end

    total_deleted
  end

  @doc """
  Gets cache statistics for monitoring.
  """
  @spec stats() :: map()
  def stats do
    now_ms = System.system_time(:millisecond)

    # Get all cache entries safely
    all_entries =
      try do
        :ets.tab2list(@market_data_cache_table)
      rescue
        ArgumentError -> []
      end

    # Group by cache type
    # Format: {{cache_type, key}, value, timestamp}
    stats =
      all_entries
      |> Enum.group_by(fn
        {{cache_type, _}, _, _} when is_atom(cache_type) -> cache_type
        _ -> :other
      end)
      |> Map.new(fn {cache_type, entries} ->
        ages = Enum.map(entries, fn {_, _, timestamp} -> now_ms - timestamp end)
        avg_age = if length(ages) > 0, do: Enum.sum(ages) / length(ages), else: 0

        {cache_type,
         %{
           count: length(entries),
           avg_age_ms: round(avg_age),
           oldest_ms: if(length(ages) > 0, do: Enum.max(ages), else: 0)
         }}
      end)

    stats
  end

  # Private helpers for safe ETS operations

  defp safe_ets_lookup(table, key) do
    :ets.lookup(table, key)
  rescue
    ArgumentError ->
      # Table doesn't exist
      []
  end

  defp safe_ets_insert(table, entry) do
    :ets.insert(table, entry)
  rescue
    ArgumentError ->
      # Table doesn't exist, log warning and return false
      Logger.warning("Cache table #{inspect(table)} does not exist, skipping insert")
      false
  end

  defp safe_ets_delete(table, key) do
    :ets.delete(table, key)
  rescue
    ArgumentError ->
      # Table doesn't exist
      false
  end

  defp safe_ets_select_delete(table, match_spec) do
    :ets.select_delete(table, match_spec)
  rescue
    ArgumentError ->
      # Table doesn't exist
      0
  end
end
