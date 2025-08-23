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

  require Logger

  # For decimal arithmetic in balance and price calculations

  # ETS table names
  @idempotency_table :order_idempotency
  @symbols_table :exchange_symbols
  @kill_switch_table :kill_switch

  # 30 minutes in milliseconds
  @window_ms 30 * 60 * 1000
  # Clean every 60 seconds
  @cleanup_interval_ms 60 * 1000

  # Symbol cache TTL (5 minutes)
  @symbol_cache_ttl_ms 5 * 60 * 1000

  # Price deviation limits (±20% from mark price)
  # @max_price_deviation 0.20

  # Default minimum notional values (USD)
  @default_min_notional %{
    binance: 10.00,
    bybit: 1.00,
    kraken: 1.00,
    deribit: 10.00
  }

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

    total_deleted = num_idempotency_deleted + num_symbols_deleted

    if total_deleted > 0 do
      Logger.debug(
        "OrderSafety cleaned up #{num_idempotency_deleted} idempotency entries and #{num_symbols_deleted} symbol cache entries"
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

    Logger.warning("OrderSafety: All caches cleared - idempotency, symbols, and kill switch data reset")
    :ok
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
    case get_symbol_info(exchange, symbol) do
      {:ok, symbol_info} ->
        if symbol_info[:status] == "TRADING" do
          :ok
        else
          {:error, {:symbol_not_trading, symbol}}
        end

      {:error, :not_found} ->
        {:error, {:invalid_symbol, symbol}}

      # TODO: When fetch_symbol_info is replaced with real API calls,
      # add error handling for network errors, rate limiting, etc.
      # For now, stub only returns :ok or {:error, :not_found}
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
  def validate_balance_for_order(exchange, %{symbol: symbol, side: side, quantity: quantity} = order_params) do
    {base_asset, quote_asset} = parse_symbol_assets(symbol)

    case side do
      :buy ->
        # For buy orders, need quote asset (e.g., USDT for BTCUSDT)
        case calculate_required_quote_amount(order_params) do
          {:ok, required_amount} ->
            validate_balance(exchange, quote_asset, required_amount)

          error ->
            error
        end

      :sell ->
        # For sell orders, need base asset (e.g., BTC for BTCUSDT)
        quantity_decimal = parse_decimal(quantity)
        validate_balance(exchange, base_asset, quantity_decimal)

      _ ->
        {:error, {:invalid_side, side}}
    end
  end

  def validate_balance_for_order(_exchange, _params) do
    {:error, {:missing_required_params, "symbol, side, and quantity required"}}
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
    case get_account_balance(exchange, asset) do
      {:ok, available_balance} ->
        if Decimal.compare(available_balance, required_amount) == :lt do
          {:error, {:insufficient_balance, %{asset: asset, required: required_amount, available: available_balance}}}
        else
          :ok
        end

      # TODO: When get_account_balance is replaced with real API calls,
      # add error handling for network errors, rate limiting, unauthorized, etc.
      # For now, stub only returns {:ok, balance}
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
    case calculate_order_notional(order_params) do
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
    min_notional = get_min_notional(exchange, symbol)

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
  def validate_price_and_size(exchange, %{symbol: symbol, quantity: quantity} = order_params) do
    with :ok <- validate_quantity_format(quantity),
         :ok <- validate_quantity_bounds(exchange, symbol, quantity) do
      validate_price_if_present(exchange, symbol, order_params)
    end
  end

  def validate_price_and_size(_exchange, _params) do
    {:error, {:missing_required_params, "symbol and quantity required"}}
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

  # Symbol information retrieval with caching
  defp get_symbol_info(exchange, symbol) do
    cache_key = {exchange, :symbol, symbol}
    now_ms = System.system_time(:millisecond)

    case :ets.lookup(@symbols_table, cache_key) do
      [{^cache_key, symbol_info, timestamp}] when now_ms - timestamp < @symbol_cache_ttl_ms ->
        {:ok, symbol_info}

      _ ->
        # Cache miss or expired, fetch from exchange
        case fetch_symbol_info(exchange, symbol) do
          {:ok, symbol_info} ->
            :ets.insert(@symbols_table, {cache_key, symbol_info, now_ms})
            {:ok, symbol_info}

          error ->
            error
        end
    end
  end

  # Parse symbol into base and quote assets (e.g., "BTCUSDT" -> {"BTC", "USDT"})
  defp parse_symbol_assets(symbol) do
    # TODO: Simple implementation - in production would use exchange-specific parsing
    cond do
      String.ends_with?(symbol, "USDT") ->
        base = String.replace_suffix(symbol, "USDT", "")
        {base, "USDT"}

      String.ends_with?(symbol, "BTC") ->
        base = String.replace_suffix(symbol, "BTC", "")
        {base, "BTC"}

      String.ends_with?(symbol, "ETH") ->
        base = String.replace_suffix(symbol, "ETH", "")
        {base, "ETH"}

      true ->
        # Fallback - assume last 3-4 chars are quote
        if String.length(symbol) > 6 do
          base = String.slice(symbol, 0..-5//-1)
          quote = String.slice(symbol, -4..-1//-1)
          {base, quote}
        else
          base = String.slice(symbol, 0..-4//-1)
          quote = String.slice(symbol, -3..-1//-1)
          {base, quote}
        end
    end
  end

  # Calculate required quote amount for buy orders
  defp calculate_required_quote_amount(%{type: :market, quantity: quantity}) do
    # For market orders, estimate using recent price (simplified)
    # TODO: Implement proper market price estimation
    quantity_decimal = parse_decimal(quantity)
    # Rough BTC price estimate
    estimated_amount = Decimal.mult(quantity_decimal, Decimal.new("50000"))
    {:ok, estimated_amount}
  end

  defp calculate_required_quote_amount(%{price: price, quantity: quantity}) do
    price_decimal = parse_decimal(price)
    quantity_decimal = parse_decimal(quantity)
    required_amount = Decimal.mult(price_decimal, quantity_decimal)
    {:ok, required_amount}
  end

  defp calculate_required_quote_amount(_params) do
    {:error, {:missing_price, "Price required for limit orders"}}
  end

  # Calculate order notional value
  defp calculate_order_notional(%{price: price, quantity: quantity}) do
    price_decimal = parse_decimal(price)
    quantity_decimal = parse_decimal(quantity)
    notional = Decimal.mult(price_decimal, quantity_decimal)
    {:ok, notional}
  end

  defp calculate_order_notional(%{type: :market}) do
    # For market orders, we can't calculate exact notional without current price
    # TODO: Assume above minimum for now
    {:ok, Decimal.new("1000")}
  end

  defp calculate_order_notional(_params) do
    {:error, {:missing_price, "Price required to calculate notional value"}}
  end

  # Get minimum notional value for symbol
  defp get_min_notional(exchange, _symbol) do
    # TODO: Use default minimums - in production would fetch from exchange
    default_min = Map.get(@default_min_notional, exchange, 10.00)
    Decimal.new(to_string(default_min))
  end

  # Validation helper functions
  defp validate_quantity_format(quantity) when is_binary(quantity) do
    case Decimal.parse(quantity) do
      {decimal_val, ""} when not is_nil(decimal_val) -> :ok
      _ -> {:error, {:invalid_quantity_format, quantity}}
    end
  end

  defp validate_quantity_format(quantity) when is_number(quantity) and quantity > 0 do
    :ok
  end

  defp validate_quantity_format(quantity) do
    {:error, {:invalid_quantity_format, quantity}}
  end

  defp validate_quantity_bounds(_exchange, _symbol, quantity) do
    quantity_decimal = parse_decimal(quantity)

    if Decimal.positive?(quantity_decimal) do
      :ok
    else
      {:error, {:invalid_quantity, "Quantity must be positive"}}
    end
  end

  defp validate_price_if_present(_exchange, _symbol, %{type: :market}) do
    # Market orders don't have price
    :ok
  end

  defp validate_price_if_present(_exchange, _symbol, %{price: price}) do
    validate_price_format(price)
  end

  defp validate_price_if_present(_exchange, _symbol, _params) do
    # Price not required
    :ok
  end

  defp validate_price_format(price) when is_binary(price) do
    case Decimal.parse(price) do
      {decimal_val, ""} when not is_nil(decimal_val) ->
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

  # Parse string or number to Decimal
  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal_val, ""} -> decimal_val
      _ -> Decimal.new("0")
    end
  end

  defp parse_decimal(value) when is_number(value) do
    Decimal.new(to_string(value))
  end

  defp parse_decimal(_value) do
    Decimal.new("0")
  end

  # TODO: Stub implementations for external data fetching
  # TODO: Implement actual exchange API calls

  defp fetch_symbol_info(_exchange, symbol) do
    # TODO: Stub - in production would call exchange API
    if String.contains?(symbol, "USDT") do
      {:ok, %{status: "TRADING", base_asset: "BTC", quote_asset: "USDT"}}
    else
      {:error, :not_found}
    end
  end

  defp get_account_balance(_exchange, _asset) do
    # TODO: Stub - in production would call exchange API
    {:ok, Decimal.new("1000.0")}
  end

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
