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

  def parse_error(response) do
    case response do
      html when is_binary(html) and byte_size(html) > 0 ->
        cond do
          String.contains?(html, ["DOCTYPE", "<html", "<HTML"]) ->
            # HTML error page from CDN/WAF
            error_msg = extract_html_error_message(html)
            {:error, {:html_error, error_msg}}

          String.contains?(html, "Request blocked") ->
            {:error, {:waf_blocked, "Request blocked by WAF"}}

          String.contains?(html, "CloudFlare") or String.contains?(html, "cloudflare") ->
            {:error, {:cdn_error, "CloudFlare protection triggered"}}

          true ->
            {:error, :unknown_error}
        end

      _ ->
        {:error, :unknown_error}
    end
  end

  # Helper to extract meaningful error from HTML pages
  defp extract_html_error_message(html) do
    cond do
      String.contains?(html, "403 Forbidden") ->
        "403 Forbidden - Access denied by server"

      String.contains?(html, "429 Too Many Requests") ->
        "429 Too Many Requests - Rate limit exceeded"

      String.contains?(html, "502 Bad Gateway") ->
        "502 Bad Gateway - Server temporarily unavailable"

      String.contains?(html, "503 Service Unavailable") ->
        "503 Service Unavailable - Server overloaded or under maintenance"

      true ->
        "Server returned HTML error page instead of JSON response"
    end
  end

  # WebSocket parsing - marked as not implemented per project scope
  @impl true
  def parse_market_data(_data) do
    # TODO: WebSocket market data parsing deferred to WebSocket implementation phase
    {:error, :not_implemented}
  end

  @doc """
  Parses a list of orders from the Binance API.

  ## Examples

      response = [
        %{
          "symbol" => "BTCUSDT",
          "orderId" => 123456,
          "side" => "BUY",
          "type" => "LIMIT",
          "status" => "FILLED"
        }
      ]
      {:ok, orders} = parse_orders_list(response)
  """
  @spec parse_orders_list(list() | term()) :: {:ok, list()} | {:error, atom()}
  def parse_orders_list(response) when is_list(response) do
    orders = Enum.map(response, &parse_order/1)

    # Check if any parsing failed
    case Enum.find(orders, &match?({:error, _}, &1)) do
      {:error, _} = error -> error
      nil -> {:ok, Enum.map(orders, fn {:ok, order} -> order end)}
    end
  end

  def parse_orders_list(_), do: {:error, :invalid_format}

  @doc """
  Parses server time response from the Binance API.

  ## Examples

      response = %{"serverTime" => 1234567890000}
      {:ok, %{server_time: 1234567890000}} = parse_server_time(response)
  """
  @spec parse_server_time(map() | term()) :: {:ok, map()} | {:error, atom()}
  def parse_server_time(%{"serverTime" => time}) do
    {:ok, %{server_time: time}}
  end

  def parse_server_time(_), do: {:error, :invalid_format}

  @doc """
  Parses One-Cancels-Other (OCO) order response from the Binance API.

  ## Examples

      response = %{
        "orderListId" => 123,
        "orders" => [
          %{"orderId" => 456, "side" => "BUY", "type" => "LIMIT"},
          %{"orderId" => 789, "side" => "BUY", "type" => "STOP_LOSS_LIMIT"}
        ],
        "listOrderStatus" => "EXECUTING",
        "transactionTime" => 1234567890000
      }
      {:ok, oco} = parse_oco_response(response)
  """
  @spec parse_oco_response(map() | term()) :: {:ok, map()} | {:error, atom()}
  def parse_oco_response(%{"orderListId" => list_id, "orders" => orders} = response) do
    {:ok,
     %{
       order_list_id: list_id,
       orders:
         Enum.map(orders, fn order ->
           case parse_order(order) do
             {:ok, parsed} -> parsed
             # Fallback to raw if parsing fails
             _ -> order
           end
         end),
       list_status: response["listOrderStatus"],
       transaction_time: response["transactionTime"]
     }}
  end

  def parse_oco_response(_), do: {:error, :invalid_oco_format}

  @doc """
  Parses batch cancel response from the Binance API.

  Returns a list of results where each element is either
  `{:ok, order}` for successful cancellations or
  `{:error, error_info}` for failed cancellations.

  ## Examples

      response = [
        %{"orderId" => 123, "status" => "CANCELED"},
        %{"code" => -2011, "msg" => "Unknown order"}
      ]
      {:ok, results} = parse_batch_cancel_response(response)
  """
  @spec parse_batch_cancel_response(list() | term()) :: {:ok, list()} | {:error, atom()}
  def parse_batch_cancel_response(response) when is_list(response) do
    results =
      Enum.map(response, fn
        %{"code" => code, "msg" => msg} ->
          {:error, %{code: code, message: msg}}

        order ->
          case parse_order(order) do
            {:ok, parsed} -> {:ok, parsed}
            error -> error
          end
      end)

    {:ok, results}
  end

  def parse_batch_cancel_response(_), do: {:error, :invalid_batch_response}

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
