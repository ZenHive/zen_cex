defmodule ZenCex.TestUtilities.Generators do
  @moduledoc """
  Test data generators for different exchange formats.

  Generates realistic test data matching actual exchange response formats.
  """

  # Time constants in milliseconds
  # 8 hours
  @funding_interval_ms 28_800_000
  # 1 minute minus 1ms
  @close_time_offset_ms 59_999
  # Maximum number of trades in a kline period
  @max_trades_per_kline 1000
  # Maximum order ID value
  @order_id_max 999_999_999

  @doc """
  Generates a test balance in exchange-specific format.
  """
  @spec generate_test_balance(atom(), String.t(), String.t() | number()) :: map()
  def generate_test_balance(exchange, asset, amount, locked \\ "0")

  def generate_test_balance(:binance, asset, amount, locked) do
    %{
      "asset" => asset,
      "free" => to_string(amount),
      "locked" => to_string(locked)
    }
  end

  def generate_test_balance(:bybit, asset, amount, locked) do
    total = add_decimal_strings(to_string(amount), to_string(locked))

    %{
      "coin" => asset,
      "free" => to_string(amount),
      "locked" => to_string(locked),
      "walletBalance" => total,
      "availableToWithdraw" => to_string(amount)
    }
  end

  def generate_test_balance(_exchange, asset, amount, locked) do
    # Generic format for future exchanges
    %{
      "asset" => asset,
      "available" => to_string(amount),
      "locked" => to_string(locked),
      "total" => add_decimal_strings(to_string(amount), to_string(locked))
    }
  end

  @doc """
  Generates a test position in exchange-specific format.
  """
  @spec generate_test_position(atom(), String.t(), String.t(), String.t() | number()) :: map()
  def generate_test_position(exchange, symbol, side, size, entry_price \\ "0", mark_price \\ "0")

  def generate_test_position(:binance, symbol, side, size, entry_price, mark_price) do
    %{
      "symbol" => symbol,
      "positionSide" => side,
      "positionAmt" => to_string(size),
      "entryPrice" => to_string(entry_price),
      "markPrice" => to_string(mark_price),
      "unRealizedProfit" => calculate_unrealized_pnl(size, entry_price, mark_price, side),
      "marginType" => "cross",
      "isolatedWallet" => "0",
      "leverage" => "20",
      "maxNotionalValue" => "1000000"
    }
  end

  def generate_test_position(:bybit, symbol, side, size, entry_price, mark_price) do
    %{
      "symbol" => symbol,
      "side" => capitalize_side(side),
      "size" => to_string(size),
      "avgPrice" => to_string(entry_price),
      "markPrice" => to_string(mark_price),
      "unrealisedPnl" => calculate_unrealized_pnl(size, entry_price, mark_price, side),
      "positionValue" => multiply_decimal_strings(to_string(size), to_string(mark_price)),
      "leverage" => "10",
      "positionIdx" => 0,
      "riskId" => 1
    }
  end

  def generate_test_position(_exchange, symbol, side, size, entry_price, mark_price) do
    # Generic format
    %{
      "symbol" => symbol,
      "side" => side,
      "quantity" => to_string(size),
      "entry_price" => to_string(entry_price),
      "mark_price" => to_string(mark_price),
      "unrealized_pnl" => calculate_unrealized_pnl(size, entry_price, mark_price, side)
    }
  end

  @doc """
  Generates a test order in exchange-specific format.
  """
  @spec generate_test_order(atom(), String.t(), String.t(), String.t(), String.t() | number(), String.t() | number()) ::
          map()
  def generate_test_order(exchange, symbol, side, order_type, quantity, price)

  def generate_test_order(:binance, symbol, side, order_type, quantity, price) do
    %{
      "symbol" => symbol,
      "orderId" => generate_order_id(),
      "orderListId" => -1,
      "clientOrderId" => "TD_#{:os.system_time(:millisecond)}_#{:rand.uniform(9999)}",
      "price" => to_string(price),
      "origQty" => to_string(quantity),
      "executedQty" => "0",
      "cummulativeQuoteQty" => "0",
      "status" => "NEW",
      "timeInForce" => "GTC",
      "type" => order_type,
      "side" => side,
      "stopPrice" => "0",
      "icebergQty" => "0",
      "time" => :os.system_time(:millisecond),
      "updateTime" => :os.system_time(:millisecond),
      "isWorking" => true,
      "origQuoteOrderQty" => "0"
    }
  end

  def generate_test_order(:bybit, symbol, side, order_type, quantity, price) do
    %{
      "orderId" => generate_order_id(),
      "orderLinkId" => "TD_#{:os.system_time(:millisecond)}_#{:rand.uniform(9999)}",
      "symbol" => symbol,
      "side" => capitalize_side(side),
      "orderType" => capitalize_order_type(order_type),
      "price" => to_string(price),
      "qty" => to_string(quantity),
      "cumExecQty" => "0",
      "cumExecValue" => "0",
      "avgPrice" => "0",
      "orderStatus" => "New",
      "timeInForce" => "GTC",
      "createdTime" => to_string(:os.system_time(:millisecond)),
      "updatedTime" => to_string(:os.system_time(:millisecond))
    }
  end

  def generate_test_order(_exchange, symbol, side, order_type, quantity, price) do
    # Generic format
    %{
      "symbol" => symbol,
      "order_id" => generate_order_id(),
      "side" => side,
      "type" => order_type,
      "quantity" => to_string(quantity),
      "price" => to_string(price),
      "status" => "open",
      "timestamp" => :os.system_time(:millisecond)
    }
  end

  @doc """
  Generates a test kline/candlestick in exchange-specific format.
  """
  @spec generate_test_kline(
          atom(),
          integer(),
          String.t() | number(),
          String.t() | number(),
          String.t() | number(),
          String.t() | number(),
          String.t() | number()
        ) :: list() | map()
  def generate_test_kline(exchange, timestamp, open, high, low, close, volume)

  def generate_test_kline(:binance, timestamp, open, high, low, close, volume) do
    # Binance returns 12-element arrays
    [
      # Open time
      timestamp,
      # Open
      to_string(open),
      # High
      to_string(high),
      # Low
      to_string(low),
      # Close
      to_string(close),
      # Volume
      to_string(volume),
      # Close time
      timestamp + @close_time_offset_ms,
      # Quote asset volume
      multiply_decimal_strings(to_string(volume), to_string(close)),
      # Number of trades
      :rand.uniform(@max_trades_per_kline),
      # Taker buy base asset volume
      multiply_decimal_strings(to_string(volume), "0.5"),
      # Taker buy quote asset volume
      multiply_decimal_strings(multiply_decimal_strings(to_string(volume), "0.5"), to_string(close)),
      # Ignore
      "0"
    ]
  end

  def generate_test_kline(:bybit, timestamp, open, high, low, close, volume) do
    # Bybit returns 7-element arrays
    [
      # Start time
      to_string(timestamp),
      # Open
      to_string(open),
      # High
      to_string(high),
      # Low
      to_string(low),
      # Close
      to_string(close),
      # Volume
      to_string(volume),
      # Turnover
      multiply_decimal_strings(to_string(volume), to_string(close))
    ]
  end

  def generate_test_kline(_exchange, timestamp, open, high, low, close, volume) do
    # Generic format as map
    %{
      "timestamp" => timestamp,
      "open" => to_string(open),
      "high" => to_string(high),
      "low" => to_string(low),
      "close" => to_string(close),
      "volume" => to_string(volume)
    }
  end

  @doc """
  Generates a test ticker in exchange-specific format.
  """
  @spec generate_test_ticker(atom(), String.t(), String.t() | number()) :: map()
  def generate_test_ticker(exchange, symbol, last_price)

  def generate_test_ticker(:binance, symbol, last_price) do
    %{
      "symbol" => symbol,
      "price" => to_string(last_price)
    }
  end

  def generate_test_ticker(:bybit, symbol, last_price) do
    %{
      "symbol" => symbol,
      "lastPrice" => to_string(last_price),
      "indexPrice" => to_string(last_price),
      "markPrice" => to_string(last_price),
      "prevPrice24h" => multiply_decimal_strings(to_string(last_price), "0.98"),
      "price24hPcnt" => "0.0204",
      "highPrice24h" => multiply_decimal_strings(to_string(last_price), "1.05"),
      "lowPrice24h" => multiply_decimal_strings(to_string(last_price), "0.95"),
      "volume24h" => "1000000",
      "turnover24h" => "50000000"
    }
  end

  def generate_test_ticker(_exchange, symbol, last_price) do
    # Generic format
    %{
      "symbol" => symbol,
      "last" => to_string(last_price),
      "bid" => multiply_decimal_strings(to_string(last_price), "0.9999"),
      "ask" => multiply_decimal_strings(to_string(last_price), "1.0001"),
      "volume" => "1000000"
    }
  end

  @doc """
  Generates a test funding rate in exchange-specific format.
  """
  @spec generate_test_funding_rate(atom(), String.t(), String.t() | number()) :: map()
  def generate_test_funding_rate(exchange, symbol, rate)

  def generate_test_funding_rate(:binance, symbol, rate) do
    %{
      "symbol" => symbol,
      "fundingRate" => to_string(rate),
      # Next funding time (8 hours from now)
      "fundingTime" => :os.system_time(:millisecond) + @funding_interval_ms
    }
  end

  def generate_test_funding_rate(:bybit, symbol, rate) do
    %{
      "symbol" => symbol,
      "fundingRate" => to_string(rate),
      "nextFundingTime" => to_string(:os.system_time(:millisecond) + @funding_interval_ms),
      "prevFundingRate" => multiply_decimal_strings(to_string(rate), "0.95"),
      "predictedFundingRate" => multiply_decimal_strings(to_string(rate), "1.02")
    }
  end

  def generate_test_funding_rate(_exchange, symbol, rate) do
    # Generic format
    %{
      "symbol" => symbol,
      "rate" => to_string(rate),
      "next_funding_time" => :os.system_time(:millisecond) + @funding_interval_ms
    }
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp generate_order_id do
    to_string(:rand.uniform(@order_id_max))
  end

  defp capitalize_side("BUY"), do: "Buy"
  defp capitalize_side("SELL"), do: "Sell"
  defp capitalize_side(side), do: side

  defp capitalize_order_type("LIMIT"), do: "Limit"
  defp capitalize_order_type("MARKET"), do: "Market"
  defp capitalize_order_type("STOP"), do: "Stop"
  defp capitalize_order_type(type), do: type

  defp calculate_unrealized_pnl(size, entry_price, mark_price, _side) when is_binary(size) do
    # Simple calculation for test data
    size_f = String.to_float(ensure_decimal(size))
    entry_f = String.to_float(ensure_decimal(entry_price))
    mark_f = String.to_float(ensure_decimal(mark_price))

    pnl = size_f * (mark_f - entry_f)
    Float.to_string(pnl)
  end

  defp calculate_unrealized_pnl(size, entry_price, mark_price, side) do
    calculate_unrealized_pnl(to_string(size), to_string(entry_price), to_string(mark_price), side)
  end

  defp add_decimal_strings(a, b) do
    a_f = String.to_float(ensure_decimal(a))
    b_f = String.to_float(ensure_decimal(b))
    Float.to_string(a_f + b_f)
  end

  defp multiply_decimal_strings(a, b) do
    a_f = String.to_float(ensure_decimal(a))
    b_f = String.to_float(ensure_decimal(b))
    Float.to_string(a_f * b_f)
  end

  defp ensure_decimal(str) when is_binary(str) do
    if String.contains?(str, "."), do: str, else: str <> ".0"
  end

  defp ensure_decimal(num), do: ensure_decimal(to_string(num))
end
