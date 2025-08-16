defmodule ZenCex.Adapters.Binance.Parser do
  @moduledoc """
  Binance response parser implementing the ZenCex.Behaviors.Parser contract.

  Parses Binance-specific JSON responses and normalizes them to common formats
  used throughout the ZenCex library. Handles type conversions, null fields,
  and exchange-specific error codes.

  ## Supported Response Types

  - **Positions**: Spot and futures position data
  - **Balances**: Account balance information  
  - **Orders**: Order placement and query responses
  - **Errors**: Binance error codes and messages

  ## Error Code Mapping

  Binance uses negative integer error codes:
  - `-1121` -> `:invalid_symbol`
  - `-2010` -> `:insufficient_balance`
  - `-1013` -> `:invalid_quantity`
  - `429` -> `:rate_limited`

  ## Type Conversions

  All financial values are converted from strings to `Decimal.t()`:
  - Prices: `"50000.00"` -> `Decimal.new("50000.00")`
  - Quantities: `"0.5"` -> `Decimal.new("0.5")`
  - PnL values: `"125.50"` -> `Decimal.new("125.50")`

  Null or missing values default to `Decimal.new("0")`.
  """

  @behaviour ZenCex.Behaviors.Parser

  require Logger

  # Constants for error mapping
  @error_codes %{
    -1121 => :invalid_symbol,
    -1013 => :invalid_quantity,
    -2010 => :insufficient_balance,
    -1125 => :invalid_listen_key,
    -1100 => :illegal_chars,
    -1104 => :not_found,
    -1003 => :too_many_requests,
    -1022 => :signature_not_valid,
    -2011 => :unknown_order,
    -2013 => :order_does_not_exist,
    -1006 => :unexpected_resp,
    429 => :rate_limited
  }

  @doc """
  Parses Binance position responses into normalized format.

  ## Supported Formats
  - Spot account info with balances
  - Futures position risk data
  - Portfolio margin positions

  ## Examples

      # Spot balances (treated as positions)
      response = %{
        "balances" => [
          %{
            "asset" => "BTC",
            "free" => "0.5",
            "locked" => "0.1"
          }
        ]
      }
      {:ok, positions} = parse_positions(response)

      # Futures positions
      response = [
        %{
          "symbol" => "BTCUSDT",
          "positionSide" => "LONG", 
          "positionAmt" => "0.5",
          "entryPrice" => "50000",
          "markPrice" => "51000",
          "unRealizedProfit" => "500",
          "isolatedMargin" => "5000",
          "updateTime" => 1234567890
        }
      ]
      {:ok, positions} = parse_positions(response)
  """
  @impl true
  def parse_positions(response) when is_map(response) do
    cond do
      # Spot account info format
      Map.has_key?(response, "balances") ->
        parse_spot_balances_as_positions(response["balances"])

      # Single position format (wrapped in list)
      Map.has_key?(response, "symbol") ->
        {:ok, [parse_futures_position(response)]}

      true ->
        {:error, :invalid_format}
    end
  end

  def parse_positions(response) when is_list(response) do
    # Futures positions array
    positions = Enum.map(response, &parse_futures_position/1)
    {:ok, positions}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  def parse_positions(_), do: {:error, :invalid_format}

  @doc """
  Parses Binance balance responses into normalized format.

  ## Examples

      response = %{
        "balances" => [
          %{
            "asset" => "BTC",
            "free" => "0.5",
            "locked" => "0.1"
          },
          %{
            "asset" => "USDT", 
            "free" => "1000",
            "locked" => "500"
          }
        ]
      }
      {:ok, balances} = parse_balances(response)
  """
  @impl true
  def parse_balances(%{"balances" => balances}) when is_list(balances) do
    parsed =
      Enum.map(balances, fn balance ->
        free = safe_decimal(balance["free"])
        locked = safe_decimal(balance["locked"])

        %{
          asset: balance["asset"],
          free: free,
          locked: locked,
          total: Decimal.add(free, locked)
        }
      end)

    {:ok, parsed}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  def parse_balances(_), do: {:error, :invalid_format}

  @doc """
  Parses Binance order responses into normalized format.

  ## Examples

      response = %{
        "symbol" => "BTCUSDT",
        "orderId" => 123456,
        "clientOrderId" => "my_order_1",
        "side" => "BUY",
        "type" => "LIMIT",
        "price" => "50000",
        "origQty" => "0.1",
        "status" => "FILLED",
        "transactTime" => 1234567890
      }
      {:ok, order} = parse_order(response)
  """
  @impl true
  def parse_order(response) when is_map(response) do
    # Basic validation - require symbol and side as minimum
    with symbol when is_binary(symbol) <- response["symbol"],
         side when is_binary(side) <- response["side"],
         order_type when is_binary(order_type) <- response["type"],
         status when is_binary(status) <- response["status"] do
      try do
        order = %{
          order_id: to_string(response["orderId"] || response["id"] || ""),
          client_order_id: response["clientOrderId"],
          symbol: symbol,
          side: String.downcase(side) |> String.to_atom(),
          type: String.downcase(order_type) |> String.to_atom(),
          price: safe_decimal(response["price"]),
          quantity: safe_decimal(response["origQty"] || response["quantity"]),
          filled_quantity: safe_decimal(response["executedQty"] || "0"),
          status: normalize_order_status(status),
          timestamp: response["transactTime"] || response["time"] || response["updateTime"]
        }

        {:ok, order}
      rescue
        e -> {:error, {:parse_error, Exception.message(e)}}
      end
    else
      _ -> {:error, :invalid_format}
    end
  end

  def parse_order(_), do: {:error, :invalid_format}

  @doc """
  Parses Binance error responses into normalized error atoms.

  ## Examples

      # Standard error format
      response = %{"code" => -2010, "msg" => "Account has insufficient balance"}
      {:error, :insufficient_balance} = parse_error(response)

      # Rate limit error
      response = %{"code" => 429, "msg" => "Too many requests"}
      {:error, :rate_limited} = parse_error(response)

      # Unknown error with details
      response = %{"code" => -9999, "msg" => "Unknown error"}
      {:error, {:exchange_error, "Unknown error"}} = parse_error(response)
  """
  @impl true
  def parse_error(%{"code" => code} = response) when is_integer(code) do
    case Map.get(@error_codes, code) do
      nil ->
        message = response["msg"] || "Unknown error"
        {:error, {:exchange_error, message}}

      error_atom ->
        {:error, error_atom}
    end
  end

  def parse_error(%{"msg" => message}) do
    # Some responses only have message field
    cond do
      String.contains?(String.downcase(message), "insufficient") ->
        {:error, :insufficient_balance}

      String.contains?(String.downcase(message), "invalid symbol") ->
        {:error, :invalid_symbol}

      String.contains?(String.downcase(message), "unauthorized") ->
        {:error, :invalid_credentials}

      true ->
        {:error, {:exchange_error, message}}
    end
  end

  def parse_error(response) when is_map(response) do
    # Generic error handling for unexpected formats
    {:error, {:unknown_error, response}}
  end

  def parse_error(_), do: {:error, :unknown_error}

  # WebSocket parsing - marked as not implemented per project scope
  @impl true
  def parse_market_data(_data) do
    # TODO: WebSocket market data parsing deferred to WebSocket implementation phase
    {:error, :not_implemented}
  end

  # Private helper functions

  defp parse_spot_balances_as_positions(balances) when is_list(balances) do
    positions =
      balances
      |> Enum.filter(fn balance ->
        # Only include assets with non-zero balances
        free = safe_decimal(balance["free"])
        locked = safe_decimal(balance["locked"])

        not (Decimal.equal?(free, Decimal.new("0")) and Decimal.equal?(locked, Decimal.new("0")))
      end)
      |> Enum.map(&convert_balance_to_position/1)

    {:ok, positions}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  defp convert_balance_to_position(balance) do
    free = safe_decimal(balance["free"])
    locked = safe_decimal(balance["locked"])
    total = Decimal.add(free, locked)

    %{
      symbol: balance["asset"],
      side: :long,
      size: total,
      entry_price: Decimal.new("0"),
      mark_price: Decimal.new("0"),
      pnl: Decimal.new("0"),
      margin: locked,
      timestamp: System.system_time(:millisecond)
    }
  end

  defp parse_futures_position(position) do
    %{
      symbol: position["symbol"],
      side: normalize_position_side(position["positionSide"]),
      size: safe_decimal(position["positionAmt"]),
      entry_price: safe_decimal(position["entryPrice"]),
      mark_price: safe_decimal(position["markPrice"]),
      pnl: safe_decimal(position["unRealizedProfit"]),
      margin: safe_decimal(position["isolatedMargin"] || position["initialMargin"] || "0"),
      timestamp: position["updateTime"] || System.system_time(:millisecond)
    }
  end

  defp normalize_position_side("LONG"), do: :long
  defp normalize_position_side("SHORT"), do: :short
  defp normalize_position_side("BOTH"), do: :long
  defp normalize_position_side(_), do: :long

  defp normalize_order_status("NEW"), do: :new
  defp normalize_order_status("PARTIALLY_FILLED"), do: :partially_filled
  defp normalize_order_status("FILLED"), do: :filled
  defp normalize_order_status("CANCELED"), do: :cancelled
  defp normalize_order_status("REJECTED"), do: :rejected
  defp normalize_order_status("EXPIRED"), do: :expired
  defp normalize_order_status(_), do: :unknown

  defp safe_decimal(nil), do: Decimal.new("0")
  defp safe_decimal(""), do: Decimal.new("0")

  defp safe_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> Decimal.new("0")
    end
  end

  defp safe_decimal(value) when is_number(value), do: Decimal.new(to_string(value))
  defp safe_decimal(_), do: Decimal.new("0")
end
