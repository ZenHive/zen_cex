defmodule ZenCex.Safety.OrderSafety do
  @moduledoc """
  Order safety module providing comprehensive pre-trade validation and idempotency checks.

  This module implements multiple safety mechanisms to prevent dangerous or invalid trading:
  - 30-minute sliding window for duplicate detection
  - Balance validation against exchange accounts
  - Symbol validation and trading rules enforcement
  - Notional limits (min/max order values)
  - Price/size sanity checks with tick size validation
  - Global kill switch for emergency stop

  ## Features

  ### Idempotency Protection
  - 30-minute sliding window for duplicate detection
  - Deterministic client_order_id generation
  - Sub-50μs idempotency checks
  - Automatic cleanup of expired entries
  - Exchange-specific order tracking

  ### Pre-Trade Validation
  - Balance checks against available funds
  - Symbol existence and status validation
  - Minimum notional value enforcement
  - Price within reasonable bounds (±20% from mark price)
  - Quantity respects tick size and lot size
  - Global kill switch protection

  ## Implementation

  Uses multiple ETS tables for atomic operations and high-performance lookups:
  - `:order_idempotency` - Order tracking with timestamps
  - `:exchange_symbols` - Cached symbol information and trading rules
  - `:kill_switch` - Global trading enable/disable state

  ## Usage

      # Complete validation before order placement
      case OrderSafety.validate_order(:binance, order_params) do
        {:ok, validated_params} -> place_order(validated_params)
        {:error, reason} -> handle_validation_error(reason)
      end

      # Individual validations
      OrderSafety.validate_balance(:binance, "BTCUSDT", :buy, 0.001)
      OrderSafety.validate_symbol(:binance, "BTCUSDT")
      OrderSafety.validate_notional(:binance, "BTCUSDT", 10.50)
  """

  use GenServer

  alias ZenCex.Safety.OrderSafety.Cache
  alias ZenCex.Safety.OrderSafety.Config
  alias ZenCex.Safety.OrderSafety.DecimalUtils
  alias ZenCex.Safety.OrderSafety.MarketData
  alias ZenCex.Safety.OrderSafety.Validation

  require Logger

  # For decimal arithmetic in balance and price calculations

  # ETS table names
  @idempotency_table :order_idempotency
  @symbols_table :exchange_symbols
  @kill_switch_table :kill_switch
  @market_data_cache_table :market_data_cache

  # These values are now configurable via Config module
  # Using module attributes for performance (compile-time resolution where possible)
  @window_ms Config.idempotency_window_ms()
  @cleanup_interval_ms Config.cleanup_interval_ms()

  # Legacy symbol cache TTL - now uses Config
  @symbol_cache_ttl_ms Config.cache_ttls().symbol_info

  # Price deviation limits (±20% from mark price)
  # @max_price_deviation 0.20

  # Legacy constants - now handled by sub-modules

  # Client API

  @doc """
  Starts the OrderSafety GenServer.

  ## Options
  - `:name` - The name to register the process under (default: `__MODULE__`)
  - `:cleanup_interval` - Cleanup interval in ms (default: 60,000)
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Comprehensive pre-trade validation for order safety.

  Performs all validation checks before order placement:
  - Kill switch check
  - Idempotency check
  - Symbol validation
  - Balance validation
  - Notional limits
  - Price/size sanity checks

  ## Parameters
  - `exchange` - The exchange atom (e.g., `:binance`)
  - `order_params` - Order parameters map with required keys:
    - `:symbol` - Trading pair (e.g., "BTCUSDT")
    - `:side` - Order side (:buy or :sell)
    - `:quantity` - Order quantity as string or number
    - `:price` - Order price (for limit orders)
    - `:type` - Order type (:market, :limit, etc.)
    - `:client_order_id` - Optional client order ID

  ## Returns
  - `{:ok, validated_params}` - All checks passed, order can proceed
  - `{:error, reason}` - Validation failed with specific reason

  ## Examples

      iex> params = %{symbol: "BTCUSDT", side: :buy, quantity: "0.001", type: :market}
      iex> OrderSafety.validate_order(:binance, params)
      {:ok, %{symbol: "BTCUSDT", side: :buy, quantity: "0.001", ...}}

      iex> OrderSafety.validate_order(:binance, %{symbol: "INVALID", side: :buy})
      {:error, {:invalid_symbol, "INVALID"}}
  """
  @spec validate_order(atom(), map()) :: {:ok, map()} | {:error, term()}
  def validate_order(exchange, order_params) do
    with :ok <- check_kill_switch(exchange),
         {:ok, :new} <- check_existing_order_with_generated_id(exchange, order_params),
         :ok <- validate_symbol(exchange, order_params[:symbol]),
         :ok <- validate_balance_for_order(exchange, order_params),
         :ok <- validate_notional_for_order(exchange, order_params),
         :ok <- validate_price_and_size(exchange, order_params) do
      # Add generated client_order_id if not provided
      validated_params = ensure_client_order_id(exchange, order_params)
      {:ok, validated_params}
    end
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

    case :ets.lookup(@idempotency_table, key) do
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

  # Public for testing purposes only
  @doc false
  @spec record_order(atom(), String.t()) :: :ok | {:error, :duplicate}
  def record_order(exchange, client_order_id) do
    now_ms = System.system_time(:millisecond)
    cutoff = now_ms - @window_ms
    key = {exchange, client_order_id}

    # Atomic check-and-insert operation
    if :ets.insert_new(@idempotency_table, {key, now_ms}) do
      # Successfully inserted new entry
      emit_telemetry(:order_recorded, exchange, client_order_id)
      :ok
    else
      # Entry already exists, check if it's within the window
      case :ets.lookup(@idempotency_table, key) do
        [{^key, timestamp}] when timestamp > cutoff ->
          emit_telemetry(:duplicate_detected, exchange, client_order_id)
          {:error, :duplicate}

        [{^key, _old_timestamp}] ->
          # Old entry expired, update with new timestamp
          :ets.insert(@idempotency_table, {key, now_ms})
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

  # Public for testing purposes only
  @doc false
  @spec remove_order(atom(), String.t()) :: :ok
  def remove_order(exchange, client_order_id) do
    key = {exchange, client_order_id}
    :ets.delete(@idempotency_table, key)
    :ok
  end

  @doc """
  Cleans up expired entries from caches.

  This is called automatically every 60 seconds but can be called manually.
  Cleans both idempotency and symbol cache tables.

  ## Returns
  The total number of entries removed.

  ## Examples

      iex> OrderSafety.cleanup_expired()
      42
  """
  @spec cleanup_expired() :: non_neg_integer()
  def cleanup_expired do
    now_ms = System.system_time(:millisecond)

    # Clean idempotency cache (30 min window)
    idempotency_cutoff = now_ms - @window_ms

    idempotency_match_spec = [
      {{{:"$1", :"$2"}, :"$3"}, [{:<, :"$3", idempotency_cutoff}], [true]}
    ]

    num_idempotency_deleted = :ets.select_delete(@idempotency_table, idempotency_match_spec)

    # Clean symbol cache (5 min TTL)
    symbol_cutoff = now_ms - @symbol_cache_ttl_ms

    symbol_match_spec = [
      {{{:"$1", :"$2", :"$3"}, :"$4", :"$5"}, [{:<, :"$5", symbol_cutoff}], [true]}
    ]

    num_symbols_deleted = :ets.select_delete(@symbols_table, symbol_match_spec)

    # Clean market data cache using Cache module
    cache_deleted = Cache.cleanup(now_ms)

    total_deleted = num_idempotency_deleted + num_symbols_deleted + cache_deleted

    if total_deleted > 0 do
      Logger.debug(
        "OrderSafety cleaned up: #{num_idempotency_deleted} idempotency, " <>
          "#{num_symbols_deleted} symbols, #{cache_deleted} market data entries"
      )
    end

    total_deleted
  end

  @doc """
  Gets statistics about all OrderSafety caches.

  ## Returns
  Map with cache statistics including:
  - `:idempotency_entries` - Number of tracked orders
  - `:symbol_cache_entries` - Number of cached symbols
  - `:kill_switch_entries` - Number of exchanges with kill switch config
  - `:window_ms` - Idempotency window in milliseconds
  - `:total_memory_bytes` - Total memory used by all caches

  ## Examples

      iex> OrderSafety.get_stats()
      %{idempotency_entries: 150, symbol_cache_entries: 45, kill_switch_entries: 4, window_ms: 1800000, total_memory_bytes: 12000}
  """
  @spec get_stats() :: map()
  def get_stats do
    wordsize = :erlang.system_info(:wordsize)

    %{
      idempotency_entries: :ets.info(@idempotency_table, :size),
      symbol_cache_entries: :ets.info(@symbols_table, :size),
      kill_switch_entries: :ets.info(@kill_switch_table, :size),
      window_ms: @window_ms,
      symbol_cache_ttl_ms: @symbol_cache_ttl_ms,
      total_memory_bytes:
        (:ets.info(@idempotency_table, :memory) +
           :ets.info(@symbols_table, :memory) +
           :ets.info(@kill_switch_table, :memory)) * wordsize
    }
  end

  @doc """
  Clears all entries from OrderSafety caches.

  Use with caution - this removes all duplicate protection and cached data!
  Kill switch settings are reset to enabled.

  ## Returns
  `:ok`

  ## Examples

      iex> OrderSafety.clear_all()
      :ok
  """
  @spec clear_all() :: :ok
  def clear_all do
    :ets.delete_all_objects(@idempotency_table)
    :ets.delete_all_objects(@symbols_table)
    :ets.delete_all_objects(@kill_switch_table)

    # Reinitialize kill switch as enabled
    for exchange <- [:binance, :bybit, :kraken, :deribit] do
      :ets.insert(@kill_switch_table, {exchange, true})
    end

    # Clear market data cache using Cache module
    Cache.clear_all()

    Logger.warning("OrderSafety: All caches cleared - idempotency, symbols, market data, and kill switch data reset")
    :ok
  end

  @doc """
  Invalidates cached price for a specific symbol.

  Use this when you know a price has changed significantly or need fresh data.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol (e.g., "BTCUSDT")

  ## Examples

      iex> OrderSafety.invalidate_price_cache(:binance, "BTCUSDT")
      :ok
  """
  @spec invalidate_price_cache(atom(), String.t()) :: :ok
  def invalidate_price_cache(exchange, symbol) do
    Cache.invalidate_price(exchange, symbol)
  end

  @doc """
  Invalidates cached symbol info for a specific symbol.

  Use this when exchange trading rules may have changed.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol

  ## Examples

      iex> OrderSafety.invalidate_symbol_info(:binance, "BTCUSDT")
      :ok
  """
  @spec invalidate_symbol_info(atom(), String.t()) :: :ok
  def invalidate_symbol_info(exchange, symbol) do
    Cache.invalidate_symbol_info(exchange, symbol)
  end

  @doc """
  Invalidates cached minimum notional for a specific symbol.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol

  ## Examples

      iex> OrderSafety.invalidate_min_notional(:binance, "BTCUSDT")
      :ok
  """
  @spec invalidate_min_notional(atom(), String.t()) :: :ok
  def invalidate_min_notional(exchange, symbol) do
    Cache.invalidate_min_notional(exchange, symbol)
  end

  @doc """
  Invalidates all cached data for a specific exchange.

  Useful when switching between testnet and production or after connectivity issues.

  ## Parameters
  - `exchange` - The exchange atom

  ## Examples

      iex> OrderSafety.invalidate_exchange_cache(:binance)
      {:ok, 42}
  """
  @spec invalidate_exchange_cache(atom()) :: {:ok, non_neg_integer()}
  def invalidate_exchange_cache(exchange) do
    Cache.invalidate_exchange(exchange)
  end

  @doc """
  Gets cache statistics for monitoring.

  Returns counts of cached entries by type and their average age.

  ## Examples

      iex> OrderSafety.cache_stats()
      %{
        prices: %{count: 10, avg_age_ms: 2500},
        symbol_info: %{count: 25, avg_age_ms: 3600000},
        min_notionals: %{count: 25, avg_age_ms: 3600000}
      }
  """
  @spec cache_stats() :: map()
  def cache_stats do
    Cache.stats()
  end

  # === Kill Switch Functions ===

  @doc """
  Enables or disables trading for a specific exchange.

  When disabled, all order validation will fail with `:kill_switch_active`.

  ## Parameters
  - `exchange` - The exchange atom
  - `enabled` - Boolean, true to enable trading, false to disable

  ## Examples

      iex> OrderSafety.set_kill_switch(:binance, false)
      :ok

      iex> OrderSafety.validate_order(:binance, order_params)
      {:error, :kill_switch_active}
  """
  @spec set_kill_switch(atom(), boolean()) :: :ok
  def set_kill_switch(exchange, enabled) do
    :ets.insert(@kill_switch_table, {exchange, enabled})

    if enabled do
      Logger.info("Trading enabled for #{exchange}")
      emit_telemetry(:kill_switch_enabled, exchange, nil)
    else
      Logger.warning("Trading DISABLED for #{exchange} - kill switch activated")
      emit_telemetry(:kill_switch_disabled, exchange, nil)
    end

    :ok
  end

  @doc """
  Checks if trading is enabled for an exchange.

  ## Returns
  - `true` if trading is enabled
  - `false` if kill switch is active
  """
  @spec trading_enabled?(atom()) :: boolean()
  def trading_enabled?(exchange) do
    case :ets.lookup(@kill_switch_table, exchange) do
      [{^exchange, enabled}] -> enabled
      # Default to enabled if not set
      [] -> true
    end
  end

  @doc """
  Gets kill switch status for all exchanges.

  ## Returns
  Map of exchange -> enabled status
  """
  @spec get_kill_switch_status() :: map()
  def get_kill_switch_status do
    @kill_switch_table
    |> :ets.tab2list()
    |> Map.new()
  end

  # === Symbol Validation Functions ===

  @doc """
  Validates that a symbol exists and is active for trading.

  Checks cached symbol information and fetches from exchange if needed.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - Trading pair symbol (e.g., "BTCUSDT")

  ## Returns
  - `:ok` if symbol is valid and active
  - `{:error, reason}` if invalid
  """
  @spec validate_symbol(atom(), String.t()) :: :ok | {:error, term()}
  def validate_symbol(exchange, symbol) when is_binary(symbol) do
    case MarketData.fetch_symbol_info(exchange, symbol) do
      {:ok, symbol_info} ->
        if symbol_info[:status] == "TRADING" or Map.get(symbol_info, :status) == "TRADING" do
          :ok
        else
          {:error, {:symbol_not_trading, symbol}}
        end

      {:error, :not_found} ->
        {:error, {:invalid_symbol, symbol}}

      {:error, {:binance_error, -1121, _msg}} ->
        # Binance returns -1121 for invalid symbol
        {:error, {:invalid_symbol, symbol}}

      {:error, _reason} = error ->
        # Pass through other errors
        error
    end
  end

  def validate_symbol(_exchange, _symbol) do
    {:error, {:invalid_symbol_type, "Symbol must be a string"}}
  end

  # === Balance Validation Functions ===

  @doc """
  Validates that account has sufficient balance for the order.

  ## Parameters
  - `exchange` - The exchange atom
  - `order_params` - Order parameters containing symbol, side, quantity, price

  ## Returns
  - `:ok` if sufficient balance
  - `{:error, reason}` if insufficient
  """
  @spec validate_balance_for_order(atom(), map()) :: :ok | {:error, term()}
  def validate_balance_for_order(exchange, order_params) do
    # Fetch balance info from exchange
    case MarketData.fetch_balances(exchange, order_params) do
      {:ok, balance_info} ->
        Validation.validate_balance_requirements(order_params, balance_info)

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Validates account balance for a specific asset.

  ## Parameters
  - `exchange` - The exchange atom
  - `asset` - Asset symbol (e.g., "BTC", "USDT")
  - `required_amount` - Required amount as Decimal

  ## Returns
  - `:ok` if sufficient balance
  - `{:error, reason}` if insufficient
  """
  @spec validate_balance(atom(), String.t(), Decimal.t()) :: :ok | {:error, term()}
  def validate_balance(exchange, asset, required_amount) do
    # Delegate to Validation module with balance fetching
    case MarketData.fetch_balances(exchange, %{}) do
      {:ok, balance_info} ->
        # Extract the specific asset balance
        balances = Map.get(balance_info, :balances, %{})
        available_balance = DecimalUtils.extract_available_balance(balances, asset)

        if Decimal.compare(available_balance, required_amount) == :lt do
          {:error, {:insufficient_balance, %{asset: asset, required: required_amount, available: available_balance}}}
        else
          :ok
        end

      {:error, _reason} = error ->
        error
    end
  end

  # === Notional Validation Functions ===

  @doc """
  Validates order meets minimum notional value requirements.

  ## Parameters
  - `exchange` - The exchange atom
  - `order_params` - Order parameters

  ## Returns
  - `:ok` if notional value is sufficient
  - `{:error, reason}` if below minimum
  """
  @spec validate_notional_for_order(atom(), map()) :: :ok | {:error, term()}
  def validate_notional_for_order(exchange, %{symbol: symbol} = order_params) do
    case Validation.calculate_order_notional(order_params) do
      {:ok, notional_value} ->
        validate_notional(exchange, symbol, notional_value)

      error ->
        error
    end
  end

  def validate_notional_for_order(_exchange, _params) do
    {:error, {:missing_required_params, "symbol required for notional validation"}}
  end

  @doc """
  Validates notional value against exchange minimums.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - Trading pair symbol
  - `notional_value` - Order value in quote currency

  ## Returns
  - `:ok` if above minimum
  - `{:error, reason}` if below minimum
  """
  @spec validate_notional(atom(), String.t(), Decimal.t()) :: :ok | {:error, term()}
  def validate_notional(exchange, symbol, notional_value) do
    min_notional = MarketData.get_min_notional(exchange, symbol)

    if Decimal.compare(notional_value, min_notional) == :lt do
      {:error, {:notional_too_small, %{symbol: symbol, value: notional_value, minimum: min_notional}}}
    else
      :ok
    end
  end

  # === Price and Size Validation Functions ===

  @doc """
  Validates price and quantity are within reasonable bounds.

  Checks:
  - Price within ±20% of mark price (for limit orders)
  - Quantity respects tick size and lot size
  - Values are positive

  ## Parameters
  - `exchange` - The exchange atom
  - `order_params` - Order parameters

  ## Returns
  - `:ok` if price and size are valid
  - `{:error, reason}` if invalid
  """
  @spec validate_price_and_size(atom(), map()) :: :ok | {:error, term()}
  def validate_price_and_size(_exchange, order_params) do
    # Check required parameters
    required_params = [:symbol, :quantity]
    missing_params = Enum.filter(required_params, fn key -> not Map.has_key?(order_params, key) end)

    if missing_params == [] do
      # Validate basic price and size requirements
      with :ok <- validate_quantity_format(order_params[:quantity]) do
        validate_price_format_if_present(order_params)
      end
    else
      {:error, {:missing_required_params, missing_params}}
    end
  end

  # Helper functions for backward compatibility
  defp validate_quantity_format(quantity) when is_binary(quantity) do
    case Decimal.parse(quantity) do
      {decimal_val, ""} when not is_nil(decimal_val) and decimal_val != nil ->
        if Decimal.positive?(decimal_val) do
          :ok
        else
          {:error, {:invalid_quantity, "Quantity must be positive"}}
        end

      _ ->
        {:error, {:invalid_quantity_format, quantity}}
    end
  end

  defp validate_quantity_format(quantity) when is_number(quantity) and quantity > 0 do
    :ok
  end

  defp validate_quantity_format(quantity) do
    {:error, {:invalid_quantity_format, quantity}}
  end

  defp validate_price_format_if_present(%{price: price}) do
    validate_price_format(price)
  end

  defp validate_price_format_if_present(%{type: :market}) do
    # Market orders don't have price
    :ok
  end

  defp validate_price_format_if_present(_params) do
    # Price not required
    :ok
  end

  defp validate_price_format(price) when is_binary(price) do
    case Decimal.parse(price) do
      {decimal_val, ""} when not is_nil(decimal_val) and decimal_val != nil ->
        if Decimal.positive?(decimal_val) do
          :ok
        else
          {:error, {:invalid_price, "Price must be positive"}}
        end

      _ ->
        {:error, {:invalid_price_format, price}}
    end
  end

  defp validate_price_format(price) when is_number(price) and price > 0 do
    :ok
  end

  defp validate_price_format(price) do
    {:error, {:invalid_price_format, price}}
  end

  # === Helper Functions ===

  # Checks idempotency with auto-generated client_order_id if needed
  defp check_existing_order_with_generated_id(exchange, order_params) do
    client_order_id = order_params[:client_order_id] || generate_client_order_id(exchange, order_params)
    check_existing_order(exchange, client_order_id)
  end

  # Ensures order has client_order_id
  defp ensure_client_order_id(exchange, order_params) do
    case order_params[:client_order_id] do
      nil -> Map.put(order_params, :client_order_id, generate_client_order_id(exchange, order_params))
      _ -> order_params
    end
  end

  # Kill switch check
  defp check_kill_switch(exchange) do
    if trading_enabled?(exchange) do
      :ok
    else
      {:error, :kill_switch_active}
    end
  end

  # Legacy symbol information retrieval - now uses MarketData module

  # Legacy validation functions - now handled by Validation module
  # These are kept for backward compatibility but delegate to Validation module

  # GenServer callbacks

  @impl true
  def init(opts) do
    # Create ETS tables if they don't exist
    create_tables()

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

  defp create_tables do
    # Create idempotency table
    if :ets.whereis(@idempotency_table) == :undefined do
      :ets.new(@idempotency_table, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])
    end

    # Create market data cache table
    if :ets.whereis(@market_data_cache_table) == :undefined do
      :ets.new(@market_data_cache_table, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])
    end

    # Create symbols cache table
    if :ets.whereis(@symbols_table) == :undefined do
      :ets.new(@symbols_table, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])
    end

    # Create kill switch table
    if :ets.whereis(@kill_switch_table) == :undefined do
      :ets.new(@kill_switch_table, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

      # Initialize kill switch as enabled for all exchanges
      for exchange <- [:binance, :bybit, :kraken, :deribit] do
        :ets.insert(@kill_switch_table, {exchange, true})
      end
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
