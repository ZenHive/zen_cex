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

  import ZenCex.ParserMacros

  alias ZenCex.Core.ResponseParser

  require Logger

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
        parse_spot_balances_as_positions(extract_field(response, ["balances"], :identity))

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

      # Spot/Margin format with "balances" key
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

      # Futures V3 format - direct array
      response = [
        %{
          "accountAlias" => "SgsR",
          "asset" => "USDT",
          "balance" => "122607.35137903",
          "crossWalletBalance" => "23.72469206",
          "crossUnPnl" => "0.00000000",
          "availableBalance" => "23.72469206",
          "maxWithdrawAmount" => "23.72469206",
          "marginAvailable" => true,
          "updateTime" => 1617939110373
        }
      ]
      {:ok, balances} = parse_balances(response)
  """
  @impl true
  def parse_balances(%{"balances" => balances}) when is_list(balances) do
    # Spot/Margin format with "balances" key
    parsed =
      Enum.map(balances, fn balance ->
        free = extract_field(balance, ["free"], :decimal)
        locked = extract_field(balance, ["locked"], :decimal)

        %{
          asset: extract_field(balance, ["asset"], :string),
          free: free,
          locked: locked,
          total: Decimal.add(free, locked)
        }
      end)

    {:ok, parsed}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  def parse_balances(balances) when is_list(balances) do
    # Futures V3 format - validate first element has futures-specific fields
    case balances do
      [%{"availableBalance" => _, "balance" => _} | _] ->
        parse_futures_balances(balances)

      _ ->
        {:error,
         {:invalid_futures_format, "Expected futures balance format with 'availableBalance' and 'balance' fields"}}
    end
  end

  def parse_balances(response) do
    {:error, {:invalid_format, "Expected map with 'balances' key or futures balance array, got: #{inspect(response)}"}}
  end

  defp parse_futures_balances(balances) do
    parsed =
      Enum.map(balances, fn balance ->
        # Validate required fields
        if !(Map.has_key?(balance, "asset") and Map.has_key?(balance, "balance") and
               Map.has_key?(balance, "availableBalance")) do
          raise "Missing required futures balance fields: #{inspect(Map.keys(balance))}"
        end

        # For futures balances, use availableBalance as free and calculate locked
        available = extract_field(balance, ["availableBalance"], :decimal)
        total_balance = extract_field(balance, ["balance"], :decimal)
        # locked = total_balance - available_balance (futures margin calculation)
        locked = Decimal.sub(total_balance, available)

        %{
          asset: extract_field(balance, ["asset"], :string),
          free: available,
          locked: locked,
          total: total_balance
        }
      end)

    {:ok, parsed}
  rescue
    e -> {:error, {:parse_error, "futures: #{Exception.message(e)}"}}
  end

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
    with symbol when is_binary(symbol) and symbol != "" <- response["symbol"],
         side when is_binary(side) and side != "" <- response["side"],
         order_type when is_binary(order_type) and order_type != "" <- response["type"],
         status when is_binary(status) and status != "" <- response["status"] do
      try do
        order = %{
          order_id: extract_field(response, ["orderId", "id"], :string),
          client_order_id: extract_field(response, ["clientOrderId"], :string),
          symbol: symbol,
          side: side |> String.downcase() |> String.to_atom(),
          type: order_type |> String.downcase() |> String.to_atom(),
          price: extract_field(response, ["price"], :decimal),
          quantity: extract_field(response, ["origQty", "quantity"], :decimal),
          filled_quantity: extract_field(response, ["executedQty"], :decimal),
          status: normalize_order_status(status),
          timestamp: extract_field(response, ["transactTime", "time", "updateTime"], :identity)
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
      {:error, {:binance_error, -2010, "Account has insufficient balance"}} = parse_error(response)

      # Rate limit error (special case - still mapped for rate limiting logic)
      response = %{"code" => 429, "msg" => "Too many requests"}
      {:error, :rate_limited} = parse_error(response)

      # Filter failure
      response = %{"code" => -1013, "msg" => "Filter failure: PERCENT_PRICE_BY_SIDE"}
      {:error, {:binance_error, -1013, "Filter failure: PERCENT_PRICE_BY_SIDE"}} = parse_error(response)
  """
  @impl true
  def parse_error(%{"code" => code} = response) when is_integer(code) do
    # Log the actual error response for debugging
    ResponseParser.log_error_response(response, "Binance")

    message = extract_field(response, ["msg"], :string)

    # Only handle special cases that need specific treatment in the library
    case code do
      429 ->
        # Rate limiting needs special handling for backoff
        {:error, :rate_limited}

      -1003 ->
        # Too many requests also needs rate limit handling
        {:error, :rate_limited}

      _ ->
        # Pass through the raw error with code and message
        # This preserves all context for the application to handle
        {:error, {:binance_error, code, message}}
    end
  end

  def parse_error(%{"msg" => message} = response) do
    # Log the actual error response for debugging
    ResponseParser.log_error_response(response, "Binance")

    # Use core standardization for message-based errors
    {:error, ResponseParser.standardize_error_message(message)}
  end

  def parse_error(response) when is_map(response) do
    # Log unexpected error format for debugging
    ResponseParser.log_error_response(response, "Binance")

    # Generic error handling for unexpected formats
    {:error, {:unknown_error, response}}
  end

  def parse_error(response) do
    # Delegate HTML error parsing to core module
    case response do
      html when is_binary(html) and byte_size(html) > 0 ->
        # Pass nil when status is unknown, let core module handle it
        ResponseParser.parse_html_error(html, nil)

      _ ->
        {:error, :unknown_error}
    end
  end

  @doc """
  Parses WebSocket market data (NOT IMPLEMENTED).

  This function is part of the Parser behavior but WebSocket support
  is explicitly out of scope for this REST-only library.

  Always returns `{:error, :not_implemented}`.
  """
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
  def parse_server_time(response) when is_map(response) do
    case extract_field(response, ["serverTime"], :integer) do
      0 -> {:error, :invalid_format}
      time -> {:ok, %{server_time: time}}
    end
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
  def parse_oco_response(response) when is_map(response) do
    with list_id when not is_nil(list_id) <- extract_field(response, ["orderListId"], :integer),
         orders when is_list(orders) <- extract_field(response, ["orders"], :identity) do
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
         list_status: extract_field(response, ["listOrderStatus"], :string),
         transaction_time: extract_field(response, ["transactionTime"], :integer)
       }}
    else
      _ -> {:error, :invalid_oco_format}
    end
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
      Enum.map(response, fn item ->
        case {extract_field(item, ["code"], :integer), extract_field(item, ["msg"], :string)} do
          {code, msg} when code != 0 and msg != "" ->
            {:error, %{code: code, message: msg}}

          _ ->
            case parse_order(item) do
              {:ok, parsed} -> {:ok, parsed}
              error -> error
            end
        end
      end)

    {:ok, results}
  end

  def parse_batch_cancel_response(_), do: {:error, :invalid_batch_response}

  @doc """
  Generic parser for simple Binance API responses.

  Used for endpoints like ping, time, openOrders, and other endpoints
  that return simple data structures or lists that don't need special processing.

  ## Examples

      # Ping response (empty object)
      response = %{}
      {:ok, %{}} = parse_generic(response)

      # Server time response
      response = %{"serverTime" => 1234567890000}
      {:ok, response} = parse_generic(response)

      # List of orders
      response = [%{"orderId" => 123, "symbol" => "BTCUSDT"}]
      {:ok, response} = parse_generic(response)
  """
  @spec parse_generic(term()) :: {:ok, term()} | {:error, atom()}
  def parse_generic(response) when is_map(response) do
    # For maps, return as-is since they contain valid data
    {:ok, response}
  end

  def parse_generic(response) when is_list(response) do
    # For lists, return as-is since they contain valid data
    {:ok, response}
  end

  def parse_generic(response) do
    # For other types (strings, numbers, etc.), wrap in ok tuple
    {:ok, response}
  end

  @doc """
  Parses trade history responses from the Binance API.

  ## Examples

      response = [
        %{
          "symbol" => "BTCUSDT",
          "id" => 123456,
          "orderId" => 789,
          "price" => "50000.00",
          "qty" => "0.1",
          "quoteQty" => "5000.00",
          "commission" => "0.001",
          "commissionAsset" => "BTC",
          "time" => 1234567890000,
          "isBuyer" => true,
          "isMaker" => false
        }
      ]
      {:ok, trades} = parse_trades(response)
  """
  @spec parse_trades(list() | term()) :: {:ok, list()} | {:error, atom()}
  def parse_trades(response) when is_list(response) do
    trades =
      Enum.map(response, fn trade ->
        %{
          trade_id: extract_field(trade, ["id", "tradeId"], :string),
          order_id: extract_field(trade, ["orderId"], :string),
          symbol: extract_field(trade, ["symbol"], :string),
          price: extract_field(trade, ["price"], :decimal),
          quantity: extract_field(trade, ["qty", "quantity"], :decimal),
          quote_quantity: extract_field(trade, ["quoteQty"], :decimal),
          commission: extract_field(trade, ["commission"], :decimal),
          commission_asset: extract_field(trade, ["commissionAsset"], :string),
          timestamp: extract_field(trade, ["time", "timestamp"], :identity),
          is_buyer: extract_field(trade, ["isBuyer"], fn val -> val || false end),
          is_maker: extract_field(trade, ["isMaker"], fn val -> val || false end)
        }
      end)

    {:ok, trades}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  def parse_trades(_), do: {:error, :invalid_format}

  @doc """
  Parses account information from Binance Futures API.

  Handles both v2 and v3 account information responses which contain
  account balances, positions, and configuration.

  ## Examples

      response = %{
        "feeTier" => 0,
        "canTrade" => true,
        "canDeposit" => true,
        "canWithdraw" => true,
        "updateTime" => 1234567890000,
        "totalInitialMargin" => "0.00000000",
        "totalMaintMargin" => "0.00000000",
        "totalWalletBalance" => "10000.00000000",
        "totalUnrealizedProfit" => "0.00000000",
        "totalMarginBalance" => "10000.00000000",
        "totalPositionInitialMargin" => "0.00000000",
        "totalOpenOrderInitialMargin" => "0.00000000",
        "totalCrossWalletBalance" => "10000.00000000",
        "totalCrossUnPnl" => "0.00000000",
        "availableBalance" => "10000.00000000",
        "maxWithdrawAmount" => "10000.00000000",
        "assets" => [
          %{
            "asset" => "USDT",
            "walletBalance" => "10000.00000000",
            "unrealizedProfit" => "0.00000000",
            "marginBalance" => "10000.00000000",
            "maintMargin" => "0.00000000",
            "initialMargin" => "0.00000000",
            "positionInitialMargin" => "0.00000000",
            "openOrderInitialMargin" => "0.00000000",
            "maxWithdrawAmount" => "10000.00000000",
            "crossWalletBalance" => "10000.00000000",
            "crossUnPnl" => "0.00000000",
            "availableBalance" => "10000.00000000"
          }
        ],
        "positions" => []
      }
      {:ok, account} = parse_account(response)
  """
  @spec parse_account(map() | term()) :: {:ok, map()} | {:error, atom()}
  def parse_account(response) when is_map(response) do
    account = %{
      fee_tier: extract_field(response, ["feeTier"], :integer),
      can_trade: extract_field(response, ["canTrade"], :identity),
      can_deposit: extract_field(response, ["canDeposit"], :identity),
      can_withdraw: extract_field(response, ["canWithdraw"], :identity),
      update_time: extract_field(response, ["updateTime"], :integer),
      total_initial_margin: extract_field(response, ["totalInitialMargin"], :decimal),
      total_maint_margin: extract_field(response, ["totalMaintMargin"], :decimal),
      total_wallet_balance: extract_field(response, ["totalWalletBalance"], :decimal),
      total_unrealized_profit: extract_field(response, ["totalUnrealizedProfit"], :decimal),
      total_margin_balance: extract_field(response, ["totalMarginBalance"], :decimal),
      total_position_initial_margin: extract_field(response, ["totalPositionInitialMargin"], :decimal),
      total_open_order_initial_margin: extract_field(response, ["totalOpenOrderInitialMargin"], :decimal),
      total_cross_wallet_balance: extract_field(response, ["totalCrossWalletBalance"], :decimal),
      total_cross_un_pnl: extract_field(response, ["totalCrossUnPnl"], :decimal),
      available_balance: extract_field(response, ["availableBalance"], :decimal),
      max_withdraw_amount: extract_field(response, ["maxWithdrawAmount"], :decimal)
    }

    # Add assets if present
    account =
      case extract_field(response, ["assets"], :identity) do
        assets when is_list(assets) ->
          parsed_assets =
            Enum.map(assets, fn asset ->
              %{
                asset: extract_field(asset, ["asset"], :string),
                wallet_balance: extract_field(asset, ["walletBalance"], :decimal),
                unrealized_profit: extract_field(asset, ["unrealizedProfit"], :decimal),
                margin_balance: extract_field(asset, ["marginBalance"], :decimal),
                maint_margin: extract_field(asset, ["maintMargin"], :decimal),
                initial_margin: extract_field(asset, ["initialMargin"], :decimal),
                position_initial_margin: extract_field(asset, ["positionInitialMargin"], :decimal),
                open_order_initial_margin: extract_field(asset, ["openOrderInitialMargin"], :decimal),
                max_withdraw_amount: extract_field(asset, ["maxWithdrawAmount"], :decimal),
                cross_wallet_balance: extract_field(asset, ["crossWalletBalance"], :decimal),
                cross_un_pnl: extract_field(asset, ["crossUnPnl"], :decimal),
                available_balance: extract_field(asset, ["availableBalance"], :decimal)
              }
            end)

          Map.put(account, :assets, parsed_assets)

        _ ->
          account
      end

    # Add positions if present
    account =
      case extract_field(response, ["positions"], :identity) do
        positions when is_list(positions) ->
          parsed_positions =
            Enum.map(positions, fn pos ->
              parse_futures_position(pos)
            end)

          Map.put(account, :positions, parsed_positions)

        _ ->
          account
      end

    {:ok, account}
  rescue
    ArgumentError -> {:error, :invalid_decimal_format}
    KeyError -> {:error, :missing_required_field}
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  def parse_account(_), do: {:error, :invalid_format}

  @doc """
  Parses income/transaction history from Binance Futures API.

  Returns a list of income records including trading fees, funding fees,
  realized PnL, and other transaction types.

  ## Examples

      response = [
        %{
          "symbol" => "BTCUSDT",
          "incomeType" => "REALIZED_PNL",
          "income" => "100.50000000",
          "asset" => "USDT",
          "time" => 1234567890000,
          "info" => "trade id",
          "tranId" => 987654321,
          "tradeId" => "123456"
        },
        %{
          "symbol" => "BTCUSDT",
          "incomeType" => "FUNDING_FEE",
          "income" => "-0.50000000",
          "asset" => "USDT",
          "time" => 1234567890000,
          "info" => "",
          "tranId" => 987654322,
          "tradeId" => ""
        }
      ]
      {:ok, income_history} = parse_income(response)
  """
  @spec parse_income(list() | term()) :: {:ok, list()} | {:error, atom()}
  def parse_income(response) when is_list(response) do
    income_records =
      Enum.map(response, fn record ->
        %{
          symbol: extract_field(record, ["symbol"], :string),
          income_type: normalize_income_type(extract_field(record, ["incomeType"], :string)),
          income: extract_field(record, ["income"], :decimal),
          asset: extract_field(record, ["asset"], :string),
          timestamp: extract_field(record, ["time"], :identity),
          info: extract_field(record, ["info"], :string),
          transaction_id: extract_field(record, ["tranId"], :integer),
          trade_id: extract_field(record, ["tradeId"], :string)
        }
      end)

    {:ok, income_records}
  rescue
    ArgumentError -> {:error, :invalid_decimal_format}
    KeyError -> {:error, :missing_required_field}
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  def parse_income(_), do: {:error, :invalid_format}

  # Helper to normalize income types
  defp normalize_income_type("TRANSFER"), do: :transfer
  defp normalize_income_type("WELCOME_BONUS"), do: :welcome_bonus
  defp normalize_income_type("REALIZED_PNL"), do: :realized_pnl
  defp normalize_income_type("FUNDING_FEE"), do: :funding_fee
  defp normalize_income_type("COMMISSION"), do: :commission
  defp normalize_income_type("INSURANCE_CLEAR"), do: :insurance_clear
  defp normalize_income_type("REFERRAL_KICKBACK"), do: :referral_kickback
  defp normalize_income_type("COMMISSION_REBATE"), do: :commission_rebate
  defp normalize_income_type("API_REBATE"), do: :api_rebate
  defp normalize_income_type("CONTEST_REWARD"), do: :contest_reward
  defp normalize_income_type("CROSS_COLLATERAL_TRANSFER"), do: :cross_collateral_transfer
  defp normalize_income_type("OPTIONS_PREMIUM_FEE"), do: :options_premium_fee
  defp normalize_income_type("OPTIONS_SETTLE_PROFIT"), do: :options_settle_profit
  defp normalize_income_type("INTERNAL_TRANSFER"), do: :internal_transfer
  defp normalize_income_type("AUTO_EXCHANGE"), do: :auto_exchange
  defp normalize_income_type("DELIVERED_SETTLEMENT"), do: :delivered_settlement
  defp normalize_income_type("COIN_SWAP_DEPOSIT"), do: :coin_swap_deposit
  defp normalize_income_type("COIN_SWAP_WITHDRAW"), do: :coin_swap_withdraw
  defp normalize_income_type("POSITION_LIMIT_INCREASE_FEE"), do: :position_limit_increase_fee
  defp normalize_income_type(type) when is_binary(type), do: type |> String.downcase() |> String.to_atom()
  defp normalize_income_type(_), do: :unknown

  @doc """
  Parses commission/fee responses from the Binance API.

  Handles both decimal strings and basis points formats:
  - **Decimal strings** ("0.001"): Used in symbol-specific commission rates
  - **Basis points** (10 = 0.001%): Used in account-wide commission settings
    where 1 basis point = 0.0001 (10 bps = 10/10000 = 0.001)

  ## Examples

      # Symbol-specific commission rates (decimal strings)
      response = %{
        "symbol" => "BTCUSDT",
        "makerCommission" => "0.001",
        "takerCommission" => "0.001"
      }
      {:ok, fees} = parse_fees(response)

      # Account-wide commission rates (basis points)
      response = %{
        "makerCommission" => 10,    # 10 basis points = 0.001
        "takerCommission" => 10,    # 10 basis points = 0.001
        "buyerCommission" => 0,
        "sellerCommission" => 0
      }
      {:ok, fees} = parse_fees(response)
  """
  @spec parse_fees(map() | term()) :: {:ok, map()} | {:error, atom()}
  def parse_fees(response) when is_map(response) do
    fees = %{
      symbol: response["symbol"],
      maker_commission: parse_commission_value(extract_field(response, ["makerCommission"], :identity)),
      taker_commission: parse_commission_value(extract_field(response, ["takerCommission"], :identity)),
      buyer_commission: parse_commission_value(extract_field(response, ["buyerCommission"], :identity)),
      seller_commission: parse_commission_value(extract_field(response, ["sellerCommission"], :identity))
    }

    {:ok, fees}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  def parse_fees(_), do: {:error, :invalid_format}

  # Private helper functions

  defp parse_spot_balances_as_positions(balances) when is_list(balances) do
    positions =
      balances
      |> Enum.filter(fn balance ->
        # Only include assets with non-zero balances
        free = extract_field(balance, ["free"], :decimal)
        locked = extract_field(balance, ["locked"], :decimal)

        not (Decimal.equal?(free, Decimal.new("0")) and Decimal.equal?(locked, Decimal.new("0")))
      end)
      |> Enum.map(&convert_balance_to_position/1)

    {:ok, positions}
  rescue
    e -> {:error, {:parse_error, Exception.message(e)}}
  end

  defp convert_balance_to_position(balance) do
    free = extract_field(balance, ["free"], :decimal)
    locked = extract_field(balance, ["locked"], :decimal)
    total = Decimal.add(free, locked)

    %{
      symbol: extract_field(balance, ["asset"], :string),
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
      symbol: extract_field(position, ["symbol"], :string),
      side: normalize_position_side(extract_field(position, ["positionSide"], :string)),
      size: extract_field(position, ["positionAmt"], :decimal),
      entry_price: extract_field(position, ["entryPrice"], :decimal),
      mark_price: extract_field(position, ["markPrice"], :decimal),
      pnl: extract_field(position, ["unRealizedProfit"], :decimal),
      margin: extract_field(position, ["isolatedMargin", "initialMargin"], :decimal),
      timestamp: extract_field(position, ["updateTime"], fn val -> val || System.system_time(:millisecond) end)
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

  # Helper for commission values that can be integers (basis points) or strings (decimals)
  defp parse_commission_value(value) when is_integer(value) do
    safe_decimal_field(value, basis_points: true)
  end

  defp parse_commission_value(value) do
    safe_decimal_field(value)
  end

  # The safe_decimal functionality is now provided by the safe_decimal_field macro
  # imported from ZenCex.ParserMacros at the top of the module

  @doc """
  Parses market data API responses.

  Market data responses from Binance can be:
  - Single objects (ticker, average price)
  - Arrays of objects (klines, trades, order book)
  - Objects with nested arrays (exchange info)

  ## Examples

      iex> parse_market_data_response(%{"symbol" => "BTCUSDT", "price" => "50000.00"})
      {:ok, %{"symbol" => "BTCUSDT", "price" => "50000.00"}}

      iex> parse_market_data_response([%{"symbol" => "BTCUSDT", "price" => "50000.00"}])
      {:ok, [%{"symbol" => "BTCUSDT", "price" => "50000.00"}]}
  """
  @spec parse_market_data_response(term()) :: {:ok, term()} | {:error, term()}
  def parse_market_data_response(response) when is_map(response) do
    # Check for error codes in the response
    case response do
      %{"code" => code, "msg" => msg} ->
        {:error, {code, msg}}

      _ ->
        # Valid market data response
        {:ok, response}
    end
  end

  def parse_market_data_response(response) when is_list(response) do
    # Arrays are valid market data responses (klines, trades, etc.)
    {:ok, response}
  end

  def parse_market_data_response(response) when is_binary(response) do
    # If response is still a string, try to decode it
    case Jason.decode(response) do
      {:ok, decoded} -> parse_market_data_response(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def parse_market_data_response(_), do: {:error, :invalid_format}
end
