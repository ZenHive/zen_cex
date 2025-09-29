defmodule ZenCex.Safety.OrderSafety.Validation do
  @moduledoc """
  Order validation logic for OrderSafety module.

  Handles validation of order parameters including size limits, price checks,
  balance verification, and notional requirements.
  """

  alias ZenCex.Safety.OrderSafety.Config
  alias ZenCex.Safety.OrderSafety.DecimalUtils
  alias ZenCex.Safety.OrderSafety.MarketData

  require Logger

  # Zero balance constant
  @zero_balance "0"

  # Public API

  @doc """
  Validates an order against exchange rules and safety limits.

  ## Parameters
  - `order_params` - Order parameters including symbol, side, type, quantity, price
  - `exchange` - The exchange atom

  ## Returns
  - `:ok` - Order is valid
  - `{:error, reason}` - Validation failed with specific reason
  """
  @spec validate_order(map(), atom()) :: :ok | {:error, term()}
  def validate_order(order_params, exchange) do
    with :ok <- validate_required_fields(order_params),
         :ok <- validate_symbol_exists(exchange, order_params.symbol),
         :ok <- validate_order_size(exchange, order_params),
         :ok <- validate_price_levels(exchange, order_params) do
      validate_notional_requirements(exchange, order_params)
    end
  end

  @doc """
  Validates balance requirements for an order.

  ## Parameters
  - `order_params` - Order parameters
  - `balance_info` - Account balance information

  ## Returns
  - `:ok` - Balance is sufficient
  - `{:error, reason}` - Insufficient balance
  """
  @spec validate_balance_requirements(map(), map()) :: :ok | {:error, term()}
  def validate_balance_requirements(order_params, balance_info) do
    # Check required parameters
    required_params = [:side, :symbol]
    missing_params = Enum.filter(required_params, fn key -> not Map.has_key?(order_params, key) end)

    if missing_params == [] do
      case order_params.side do
        :buy ->
          validate_buy_balance(order_params, balance_info)

        :sell ->
          validate_sell_balance(order_params, balance_info)

        _ ->
          {:error, {:invalid_side, order_params.side}}
      end
    else
      {:error, {:missing_required_params, missing_params}}
    end
  end

  @doc """
  Calculates the required quote amount for a buy order.

  ## Parameters
  - `order_params` - Order parameters including type, quantity, price, symbol

  ## Returns
  - `{:ok, Decimal.t()}` - Required quote amount
  - `{:error, reason}` - Calculation failed
  """
  @spec calculate_required_quote_amount(map()) :: {:ok, Decimal.t()} | {:error, term()}
  def calculate_required_quote_amount(%{type: :market, quantity: quantity} = params) do
    quantity_decimal = DecimalUtils.parse_decimal(quantity)
    exchange = Map.get(params, :exchange, :binance)
    symbol = Map.get(params, :symbol, "BTCUSDT")

    case MarketData.fetch_current_price(exchange, symbol) do
      {:ok, price} ->
        {:ok, Decimal.mult(quantity_decimal, price)}

      {:error, reason} ->
        Logger.error("Cannot calculate required quote amount without current price",
          exchange: exchange,
          symbol: symbol,
          reason: reason
        )

        {:error,
         {:price_required_for_market_order,
          %{
            reason: "Market orders require current price for validation",
            exchange: exchange,
            symbol: symbol,
            price_fetch_error: reason
          }}}
    end
  end

  def calculate_required_quote_amount(%{price: price, quantity: quantity}) do
    price_decimal = DecimalUtils.parse_decimal(price)
    quantity_decimal = DecimalUtils.parse_decimal(quantity)
    {:ok, Decimal.mult(price_decimal, quantity_decimal)}
  end

  def calculate_required_quote_amount(_params) do
    {:error, {:missing_price_or_quantity, %{reason: "Order must have price and quantity or be a market order"}}}
  end

  @doc """
  Calculates the notional value of an order.

  ## Parameters
  - `order_params` - Order parameters

  ## Returns
  - `{:ok, Decimal.t()}` - Order notional value
  - `{:error, reason}` - Calculation failed
  """
  @spec calculate_order_notional(map()) :: {:ok, Decimal.t()} | {:error, term()}
  def calculate_order_notional(%{price: price, quantity: quantity}) do
    price_decimal = DecimalUtils.parse_decimal(price)
    quantity_decimal = DecimalUtils.parse_decimal(quantity)
    notional = Decimal.mult(price_decimal, quantity_decimal)
    {:ok, notional}
  end

  def calculate_order_notional(%{type: :market, quantity: quantity} = params) do
    quantity_decimal = DecimalUtils.parse_decimal(quantity)
    exchange = Map.get(params, :exchange, :binance)
    symbol = Map.get(params, :symbol, "BTCUSDT")

    case MarketData.fetch_current_price(exchange, symbol) do
      {:ok, price} ->
        {:ok, Decimal.mult(quantity_decimal, price)}

      {:error, reason} ->
        # Emit telemetry event for failed notional calculation
        :telemetry.execute(
          [:zen_cex, :order_safety, :notional_calc, :failed],
          %{count: 1},
          %{exchange: exchange, symbol: symbol, reason: reason}
        )

        # Return clear error - don't guess!
        {:error,
         {:price_unavailable,
          %{
            reason: "Cannot calculate notional without current price",
            exchange: exchange,
            symbol: symbol,
            price_fetch_error: reason
          }}}
    end
  end

  def calculate_order_notional(_params) do
    {:error, {:missing_price_or_quantity, %{reason: "Cannot calculate notional without price and quantity"}}}
  end

  # Private validation functions

  defp validate_required_fields(order_params) do
    required_fields = [:symbol, :side, :type, :quantity]

    missing_fields = Enum.filter(required_fields, &(!Map.has_key?(order_params, &1)))

    case missing_fields do
      [] ->
        :ok

      fields ->
        {:error, {:missing_required_fields, fields}}
    end
  end

  defp validate_symbol_exists(exchange, symbol) do
    case MarketData.fetch_symbol_info(exchange, symbol) do
      {:ok, %{status: "TRADING"}} ->
        :ok

      {:ok, %{status: status}} ->
        {:error, {:symbol_not_trading, "Symbol #{symbol} status: #{status}"}}

      {:ok, _info} ->
        # Bybit and other exchanges may not have status field
        :ok

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

  defp validate_order_size(exchange, %{quantity: quantity, symbol: symbol}) do
    case MarketData.fetch_symbol_info(exchange, symbol) do
      {:ok, symbol_info} ->
        validate_size_against_filters(exchange, quantity, symbol_info)

      {:error, _reason} ->
        # If we can't fetch symbol info, allow the order (exchange will validate)
        Logger.warning("Could not validate order size for #{symbol} on #{exchange}")
        :ok
    end
  end

  defp validate_size_against_filters(:binance, quantity, %{filters: filters}) do
    quantity_decimal = DecimalUtils.parse_decimal(quantity)

    lot_size_filter =
      Enum.find(filters, fn
        %{"filterType" => "LOT_SIZE"} -> true
        _ -> false
      end)

    case lot_size_filter do
      %{"minQty" => min_qty_str, "maxQty" => max_qty_str, "stepSize" => step_size_str} ->
        min_qty = Decimal.new(min_qty_str)
        max_qty = Decimal.new(max_qty_str)
        step_size = Decimal.new(step_size_str)

        cond do
          Decimal.compare(quantity_decimal, min_qty) == :lt ->
            {:error, {:quantity_too_small, "Minimum quantity: #{min_qty_str}"}}

          Decimal.compare(quantity_decimal, max_qty) == :gt ->
            {:error, {:quantity_too_large, "Maximum quantity: #{max_qty_str}"}}

          not valid_step_size?(quantity_decimal, min_qty, step_size) ->
            {:error, {:invalid_step_size, "Step size: #{step_size_str}"}}

          true ->
            :ok
        end

      _ ->
        # No LOT_SIZE filter found
        :ok
    end
  end

  defp validate_size_against_filters(:bybit, quantity, %{lot_size_filter: lot_size_filter})
       when is_map(lot_size_filter) do
    quantity_decimal = DecimalUtils.parse_decimal(quantity)

    min_qty = Decimal.new(lot_size_filter["minOrderQty"])
    max_qty = Decimal.new(lot_size_filter["maxOrderQty"])
    step_size = Decimal.new(lot_size_filter["qtyStep"])

    cond do
      Decimal.compare(quantity_decimal, min_qty) == :lt ->
        {:error, {:quantity_too_small, "Minimum quantity: #{lot_size_filter["minOrderQty"]}"}}

      Decimal.compare(quantity_decimal, max_qty) == :gt ->
        {:error, {:quantity_too_large, "Maximum quantity: #{lot_size_filter["maxOrderQty"]}"}}

      not valid_step_size?(quantity_decimal, min_qty, step_size) ->
        {:error, {:invalid_step_size, "Step size: #{lot_size_filter["qtyStep"]}"}}

      true ->
        :ok
    end
  end

  defp validate_size_against_filters(_exchange, _quantity, _symbol_info) do
    # Unknown exchange or missing filters - let exchange validate
    :ok
  end

  defp validate_price_levels(exchange, %{type: :limit, price: price, symbol: symbol}) do
    case MarketData.fetch_current_price(exchange, symbol) do
      {:ok, current_price} ->
        validate_price_deviation(price, current_price, symbol, exchange)

      {:error, _reason} ->
        # If we can't get current price, skip price deviation check
        Logger.warning("Could not validate price levels for #{symbol} on #{exchange}")
        :ok
    end
  end

  defp validate_price_levels(_exchange, _order_params) do
    # Not a limit order, skip price validation
    :ok
  end

  defp validate_price_deviation(order_price, current_price, symbol, exchange) do
    order_price_decimal = DecimalUtils.parse_decimal(order_price)

    # Calculate percentage deviation
    deviation =
      order_price_decimal
      |> Decimal.sub(current_price)
      |> Decimal.div(current_price)
      |> Decimal.mult(Decimal.new("100"))
      |> Decimal.abs()

    max_deviation_percent = Config.max_price_deviation_percent(exchange)
    max_deviation = Decimal.new(to_string(max_deviation_percent))

    if Decimal.compare(deviation, max_deviation) == :gt do
      {:error,
       {:price_deviation_too_large,
        "Price deviation #{Decimal.to_string(deviation)}% exceeds maximum #{max_deviation_percent}% for #{symbol}"}}
    else
      :ok
    end
  end

  defp validate_notional_requirements(exchange, order_params) do
    case calculate_order_notional(order_params) do
      {:ok, notional} ->
        min_notional = MarketData.get_min_notional(exchange, order_params.symbol)

        if Decimal.compare(notional, min_notional) == :lt do
          {:error,
           {:notional_too_small,
            "Order notional #{Decimal.to_string(notional)} below minimum #{Decimal.to_string(min_notional)}"}}
        else
          :ok
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_buy_balance(%{side: :buy} = order_params, balance_info) do
    case calculate_required_quote_amount(order_params) do
      {:ok, required_amount} ->
        quote_asset = extract_quote_asset(order_params.symbol)
        balances = Map.get(balance_info, :balances, %{})
        available_balance = DecimalUtils.extract_available_balance(balances, quote_asset)

        if Decimal.compare(available_balance, required_amount) == :lt do
          {:error,
           {:insufficient_balance,
            "Required: #{Decimal.to_string(required_amount)} #{quote_asset}, Available: #{Decimal.to_string(available_balance)}"}}
        else
          :ok
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_sell_balance(%{side: :sell, quantity: quantity} = order_params, balance_info) do
    base_asset = extract_base_asset(order_params.symbol)
    balances = Map.get(balance_info, :balances, %{})
    available_balance = DecimalUtils.extract_available_balance(balances, base_asset)
    required_quantity = DecimalUtils.parse_decimal(quantity)

    if Decimal.compare(available_balance, required_quantity) == :lt do
      {:error,
       {:insufficient_balance,
        "Required: #{Decimal.to_string(required_quantity)} #{base_asset}, Available: #{Decimal.to_string(available_balance)}"}}
    else
      :ok
    end
  end

  # Helper functions

  defp valid_step_size?(quantity, min_qty, step_size) do
    # Check if (quantity - min_qty) is divisible by step_size
    diff = Decimal.sub(quantity, min_qty)
    remainder = Decimal.rem(diff, step_size)
    Decimal.equal?(remainder, Decimal.new(@zero_balance))
  end

  # Extract quote asset from symbol - uses cached symbol info when available
  defp extract_quote_asset(symbol) do
    # Try to get from cached symbol info first (this would need exchange context)
    # For now, fall back to string heuristics as a default
    extract_quote_asset_heuristic(symbol)
  end

  # Heuristic extraction when symbol info is not available
  defp extract_quote_asset_heuristic(symbol) do
    # Common quote assets in order of likelihood
    quote_assets = ["USDT", "USDC", "BUSD", "BTC", "ETH", "BNB", "EUR", "GBP", "USD"]

    Enum.find(quote_assets, "USDT", fn asset ->
      String.ends_with?(symbol, asset)
    end)
  end

  defp extract_base_asset(symbol) do
    quote_asset = extract_quote_asset(symbol)
    String.replace_suffix(symbol, quote_asset, "")
  end

  # Enhanced version that uses symbol info from exchange
  @spec extract_assets_from_symbol_info(atom(), String.t()) ::
          {:ok, %{base: String.t(), quote: String.t()}} | {:error, term()}
  def extract_assets_from_symbol_info(exchange, symbol) do
    case MarketData.fetch_symbol_info(exchange, symbol) do
      {:ok, info} ->
        extract_assets_from_info(exchange, info)

      {:error, _reason} ->
        # Fall back to heuristic extraction
        base = extract_base_asset(symbol)
        quote = extract_quote_asset(symbol)
        {:ok, %{base: base, quote: quote}}
    end
  end

  defp extract_assets_from_info(:binance, info) do
    {:ok,
     %{
       base: Map.get(info, :base_asset, ""),
       quote: Map.get(info, :quote_asset, "")
     }}
  end

  defp extract_assets_from_info(:bybit, info) do
    {:ok,
     %{
       base: Map.get(info, :base_coin, ""),
       quote: Map.get(info, :quote_coin, "")
     }}
  end

  defp extract_assets_from_info(_exchange, _info) do
    {:error, :unsupported_exchange}
  end
end
