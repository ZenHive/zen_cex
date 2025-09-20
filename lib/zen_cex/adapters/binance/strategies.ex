defmodule ZenCex.Adapters.Binance.Strategies do
  @moduledoc """
  High-level trading strategies for Binance.

  Orchestrates multiple API endpoints to execute complex trading strategies
  like hedging, rebalancing, and arbitrage.

  All strategies require appropriate account permissions and may require
  Portfolio Margin mode for cross-margining between spot and futures.
  """

  alias ZenCex.Adapters.Binance.CoinmFutures
  alias ZenCex.Adapters.Binance.MarketData
  alias ZenCex.Adapters.Binance.PortfolioMargin
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Adapters.Binance.UsdmFutures
  alias ZenCex.Core.Cache

  require Logger

  # Performance constants
  @price_fetch_concurrency 10
  @price_fetch_timeout_ms 10_000
  @rebalance_task_timeout_ms 10_000

  # Cache TTL constants (in seconds)
  # 24 hours
  @contract_info_cache_ttl_seconds 86_400

  # Contract defaults
  @default_btc_contract_size 100

  # Rebalancing defaults
  @default_rebalance_threshold "0.02"
  @default_base_asset "USDT"

  @min_trade_value_usdt 10.0
  # :usdt_m or :coin_m
  @default_hedge_type :usdt_m

  # Safety: Maximum position limits to prevent accidental large trades
  @max_single_position_usdt 100_000.0
  @max_total_hedge_usdt 500_000.0
  # Max 25% of account balance per position
  @max_position_pct_of_balance 0.25

  # Per-asset maximum position sizes (in base asset units)
  @max_position_sizes %{
    "BTC" => Decimal.new("2.0"),
    "ETH" => Decimal.new("30.0"),
    "BNB" => Decimal.new("200.0"),
    "SOL" => Decimal.new("1000.0"),
    "PAXG" => Decimal.new("50.0")
    # Default for unlisted assets will be calculated based on USD value
  }

  @doc """
  Automatically hedge spot positions with futures contracts.

  Creates short futures positions to hedge long spot exposure based on the
  specified hedge percentage.

  ## Parameters
  - `hedge_percentage` - Percentage of spot value to hedge (0.0 to 1.0)
  - `opts` - Options:
    - `:hedge_type` - `:usdt_m` (linear) or `:coin_m` (inverse), default: `:usdt_m`
    - `:symbols` - List of symbols to hedge, default: all with futures markets
    - `:dry_run` - If true, calculate but don't execute orders, default: false

  ## Requirements
  - Portfolio Margin mode must be enabled for efficient cross-margining
  - Sufficient margin available for hedge positions
  - Futures trading permissions on the account

  ## Returns
  - `{:ok, %{executed_hedges: [...], total_hedged_value: Decimal, hedge_ratio: float}}`
  - `{:error, reason}` if validation fails or orders cannot be placed

  ## Example
      iex> Strategies.auto_hedge_spot_positions(0.5, hedge_type: :usdt_m)
      {:ok, %{
        executed_hedges: [
          %{symbol: "BTCUSDT", spot_value: "50000", hedge_value: "25000", futures_qty: "0.5"},
          %{symbol: "ETHUSDT", spot_value: "10000", hedge_value: "5000", futures_qty: "2.5"}
        ],
        total_hedged_value: "30000",
        hedge_ratio: 0.5
      }}
  """
  @spec auto_hedge_spot_positions(float(), keyword()) :: {:ok, map()} | {:error, any()}
  def auto_hedge_spot_positions(hedge_percentage, opts \\ [])
      when is_float(hedge_percentage) and hedge_percentage >= 0.0 and hedge_percentage <= 1.0 do
    hedge_type = Keyword.get(opts, :hedge_type, @default_hedge_type)
    symbols_filter = Keyword.get(opts, :symbols, :all)
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, :portfolio_margin} <- check_account_mode(),
         {:ok, spot_positions} <- get_spot_positions_with_values(),
         {:ok, futures_positions} <- get_current_futures_positions(hedge_type),
         {:ok, margin_info} <- PortfolioMargin.account_information(),
         :ok <- validate_margin_requirements(margin_info, hedge_percentage),
         hedge_orders =
           calculate_hedge_orders(
             spot_positions,
             futures_positions,
             hedge_percentage,
             hedge_type,
             symbols_filter,
             margin_info
           ),
         {:ok, results} <- execute_hedge_orders(hedge_orders, dry_run) do
      total_hedged = calculate_total_hedged_value(results)

      {:ok,
       %{
         executed_hedges: results,
         total_hedged_value: total_hedged,
         hedge_ratio: hedge_percentage,
         hedge_type: hedge_type,
         dry_run: dry_run
       }}
    end
  end

  @doc """
  Opens a PAXGUSDT perpetual long position equal to the total value of hedged portfolio.

  This strategy creates gold exposure by going long PAXGUSDT perp with a size equal
  to the combined USD value of spot holdings and their perpetual hedges.

  ## Parameters
  - `opts` - Options:
    - `:dry_run` - Calculate but don't execute (default: false)
    - `:leverage` - Leverage for PAXG position (default: 1)

  ## Returns
  - `{:ok, %{paxg_position: map, portfolio_value: Decimal, order_result: map}}`
  - `{:error, reason}` if validation fails or order cannot be placed

  ## Example
      iex> Strategies.hedge_with_paxg_long()
      {:ok, %{
        portfolio_value: "100000.00",
        paxg_position: %{
          symbol: "PAXGUSDT",
          side: "BUY",
          quantity: "50.0",
          notional: "100000.00"
        },
        order_result: %{orderId: "12345", status: "FILLED"}
      }}
  """
  @spec hedge_with_paxg_long(keyword()) :: {:ok, map()} | {:error, any()}
  def hedge_with_paxg_long(opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    leverage = Keyword.get(opts, :leverage, 1)

    with {:ok, portfolio_value} <- calculate_hedged_portfolio_value(),
         {:ok, paxg_price} <- get_paxg_price(),
         {:ok, paxg_position} <- calculate_paxg_position(portfolio_value, paxg_price, leverage),
         {:ok, order_result} <- execute_paxg_long(paxg_position, dry_run) do
      {:ok,
       %{
         portfolio_value: portfolio_value,
         paxg_position: paxg_position,
         order_result: order_result,
         dry_run: dry_run
       }}
    end
  end

  @doc """
  Rebalances profitable PAXG perpetual position into spot PAXG holdings.

  This strategy converts perpetual profits into actual gold-backed PAXG tokens,
  reducing counterparty risk and locking in gains.

  ## Parameters
  - `opts` - Options:
    - `:profit_threshold` - Minimum profit % to trigger rebalance (default: 0.05 or 5%)
    - `:rebalance_ratio` - Portion of profit to convert (default: 0.5 or 50%)
    - `:min_rebalance_usdt` - Minimum USDT value to rebalance (default: 100)
    - `:dry_run` - Calculate but don't execute (default: false)

  ## Returns
  - `{:ok, %{pnl: Decimal, amount_to_rebalance: Decimal, orders: list}}`
  - `{:error, reason}` if no position or not profitable

  ## Example
      iex> Strategies.rebalance_paxg_perp_to_spot(profit_threshold: 0.03)
      {:ok, %{
        current_pnl: "500.00",
        pnl_percentage: 0.05,
        amount_to_rebalance: "250.00",
        orders: [
          %{type: "reduce_perp", quantity: "0.125", status: "FILLED"},
          %{type: "buy_spot", quantity: "0.125", status: "FILLED"}
        ]
      }}
  """
  @spec rebalance_paxg_perp_to_spot(keyword()) :: {:ok, map()} | {:error, any()}
  def rebalance_paxg_perp_to_spot(opts \\ []) do
    # 5% default
    profit_threshold = Keyword.get(opts, :profit_threshold, 0.05)
    # 50% of profit
    rebalance_ratio = Keyword.get(opts, :rebalance_ratio, 0.5)
    min_rebalance_usdt = Keyword.get(opts, :min_rebalance_usdt, 100)
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, paxg_perp_position} <- get_paxg_perp_position(),
         {:ok, pnl_data} <- calculate_paxg_pnl(paxg_perp_position),
         :ok <- validate_rebalance_conditions(pnl_data, profit_threshold, min_rebalance_usdt),
         {:ok, rebalance_plan} <- plan_rebalance(pnl_data, rebalance_ratio),
         {:ok, executed_orders} <- execute_rebalance(rebalance_plan, dry_run) do
      {:ok,
       %{
         current_pnl: pnl_data.unrealized_pnl,
         pnl_percentage: pnl_data.pnl_percentage,
         amount_to_rebalance: rebalance_plan.usdt_amount,
         paxg_quantity: rebalance_plan.paxg_quantity,
         orders: executed_orders,
         dry_run: dry_run
       }}
    end
  end

  @doc """
  Rebalance portfolio to target allocation.

  ## Parameters
  - `target_allocation` - Map of symbol to target percentage (must sum to 1.0)
  - `opts` - Options:
    - `:threshold` - Minimum deviation to trigger rebalance (default: 0.02 or 2%)
    - `:base_asset` - Quote asset for rebalancing (default: "USDT")
    - `:dry_run` - Calculate but don't execute (default: false)

  ## Example
      iex> Strategies.rebalance_portfolio(%{"BTC" => 0.5, "ETH" => 0.3, "USDT" => 0.2})
      {:ok, %{rebalanced: true, trades_executed: [...]}}
  """
  @spec rebalance_portfolio(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def rebalance_portfolio(target_allocation, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, Decimal.new(@default_rebalance_threshold))
    base_asset = Keyword.get(opts, :base_asset, @default_base_asset)
    dry_run = Keyword.get(opts, :dry_run, false)

    with {:ok, current_portfolio} <- get_portfolio_with_values(),
         {:ok, trades} <- calculate_rebalance_trades(current_portfolio, target_allocation, threshold, base_asset),
         {:ok, results} <- execute_rebalance_trades(trades, dry_run) do
      {:ok,
       %{
         rebalanced: true,
         trades_executed: results,
         current_allocation: calculate_allocation_percentages(current_portfolio),
         target_allocation: target_allocation,
         dry_run: dry_run
       }}
    end
  end

  defp get_portfolio_with_values do
    with {:ok, balances} <- Spot.get_balances(),
         {:ok, prices} <- get_current_prices(balances) do
      # Calculate portfolio values
      portfolio =
        balances
        |> Enum.map(fn balance ->
          asset = balance["asset"]
          free = Decimal.new(balance["free"])
          locked = Decimal.new(balance["locked"])
          total = Decimal.add(free, locked)

          # Get price or use 1.0 for stablecoins
          price =
            if asset in ["USDT", "USDC", "BUSD"] do
              Decimal.new("1")
            else
              Map.get(prices, asset <> "USDT", Decimal.new("0"))
            end

          value = Decimal.mult(total, price)

          %{
            asset: asset,
            balance: total,
            price: price,
            value_usdt: value
          }
        end)
        |> Enum.filter(fn pos ->
          # Filter out zero balances
          Decimal.compare(pos.value_usdt, Decimal.new("0")) == :gt
        end)

      {:ok, portfolio}
    end
  end

  defp calculate_allocation_percentages(portfolio) do
    total_value =
      Enum.reduce(portfolio, Decimal.new("0"), fn pos, acc ->
        Decimal.add(acc, pos.value_usdt)
      end)

    if Decimal.compare(total_value, Decimal.new("0")) == :eq do
      %{}
    else
      Enum.reduce(portfolio, %{}, fn pos, acc ->
        percentage = Decimal.div(pos.value_usdt, total_value)
        Map.put(acc, pos.asset, percentage)
      end)
    end
  end

  defp calculate_rebalance_trades(current_portfolio, target_allocation, threshold, base_asset) do
    # Calculate total portfolio value
    total_value =
      Enum.reduce(current_portfolio, Decimal.new("0"), fn pos, acc ->
        Decimal.add(acc, pos.value_usdt)
      end)

    # Calculate current allocation percentages
    current_allocation = calculate_allocation_percentages(current_portfolio)

    # Build a map of current positions by asset for easy lookup
    current_map =
      Enum.reduce(current_portfolio, %{}, fn pos, acc ->
        Map.put(acc, pos.asset, pos)
      end)

    # Calculate required trades
    trades =
      Enum.flat_map(target_allocation, fn {asset, target_pct} ->
        current_pct = Map.get(current_allocation, asset, Decimal.new("0"))
        deviation = target_pct |> Decimal.sub(current_pct) |> Decimal.abs()
        # Only rebalance if deviation exceeds threshold
        if Decimal.compare(deviation, threshold) == :gt do
          target_value = Decimal.mult(total_value, target_pct)
          current_value = Map.get(current_map, asset, %{value_usdt: Decimal.new("0")}).value_usdt
          diff_value = Decimal.sub(target_value, current_value)
          # Create trade order
          if Decimal.compare(diff_value, Decimal.new("0")) == :gt do
            # Need to buy this asset
            [
              {
                :buy,
                asset,
                diff_value,
                asset <> base_asset
              }
            ]
          else
            # Need to sell this asset
            [
              {
                :sell,
                asset,
                Decimal.abs(diff_value),
                asset <> base_asset
              }
            ]
          end
        else
          []
        end
      end)

    # Validate we have enough base asset for buys
    base_balance =
      current_map
      |> Map.get(base_asset, %{balance: Decimal.new("0")})
      |> Map.get(:balance)

    total_buy_value =
      trades
      |> Enum.filter(fn {action, _, _, _} -> action == :buy end)
      |> Enum.reduce(Decimal.new("0"), fn {_, _, value, _}, acc ->
        Decimal.add(acc, value)
      end)

    if Decimal.compare(total_buy_value, base_balance) == :gt do
      {:error, {:insufficient_balance, base_asset, base_balance, total_buy_value}}
    else
      {:ok, trades}
    end
  end

  defp execute_rebalance_trades(trades, dry_run) do
    if dry_run do
      # Simulate trades without execution
      results =
        Enum.map(trades, fn {action, asset, value, symbol} ->
          %{
            status: "DRY_RUN",
            action: action,
            asset: asset,
            value_usdt: value,
            symbol: symbol
          }
        end)

      {:ok, results}
    else
      # Execute trades in parallel
      results =
        trades
        |> Enum.map(fn trade ->
          Task.async(fn ->
            execute_single_rebalance_trade(trade)
          end)
        end)
        |> Enum.map(&Task.await(&1, @rebalance_task_timeout_ms))

      {:ok, results}
    end
  end

  defp execute_single_rebalance_trade({action, asset, value_usdt, symbol}) do
    # Calculate quantity based on current price
    case MarketData.get_ticker_price(%{symbol: symbol}) do
      {:ok, ticker} ->
        price =
          case ticker do
            [t | _] -> Decimal.new(t["price"])
            %{"price" => p} -> Decimal.new(p)
          end

        quantity = value_usdt |> Decimal.div(price) |> Decimal.round(4)

        # Generate unique client order ID for idempotency
        client_order_id = generate_client_order_id(symbol, action)

        params = %{
          symbol: symbol,
          side: if(action == :buy, do: "BUY", else: "SELL"),
          type: "MARKET",
          quantity: Decimal.to_string(quantity),
          newClientOrderId: client_order_id
        }

        case Spot.place_order(params) do
          {:ok, result} ->
            %{
              status: "EXECUTED",
              action: action,
              asset: asset,
              value_usdt: value_usdt,
              symbol: symbol,
              order_id: result["orderId"],
              executed_qty: result["executedQty"]
            }

          {:error, reason} ->
            Logger.error("Failed to execute rebalance trade for #{symbol}: #{inspect(reason)}")

            %{
              status: "FAILED",
              action: action,
              asset: asset,
              value_usdt: value_usdt,
              symbol: symbol,
              error: reason
            }
        end

      {:error, reason} ->
        %{
          status: "FAILED",
          action: action,
          asset: asset,
          value_usdt: value_usdt,
          symbol: symbol,
          error: {:price_fetch_failed, reason}
        }
    end
  end

  # Private functions

  defp check_account_mode do
    case PortfolioMargin.account_information() do
      {:ok, %{"accountStatus" => "NORMAL"}} ->
        {:ok, :portfolio_margin}

      {:ok, _config} ->
        {:error, :portfolio_margin_not_enabled}

      {:error, reason} ->
        Logger.error("Failed to check account mode: #{inspect(reason)}")
        {:error, {:account_check_failed, reason}}
    end
  end

  defp get_spot_positions_with_values do
    with {:ok, balances} <- Spot.get_balances(),
         {:ok, prices} <- get_current_prices(balances) do
      positions =
        balances
        |> Enum.reduce([], fn balance, acc ->
          # Handle both atom and string keys
          asset = Map.get(balance, "asset") || Map.get(balance, :asset)

          # Skip stablecoins early
          if asset in ["USDT", "USDC", "BUSD"] do
            acc
          else
            free_str = Map.get(balance, "free") || Map.get(balance, :free) || "0"
            locked_str = Map.get(balance, "locked") || Map.get(balance, :locked) || "0"

            # Convert to Decimal, handling various input types
            free = to_decimal_safe(free_str)
            locked = to_decimal_safe(locked_str)
            total = Decimal.add(free, locked)

            # Skip tiny positions
            if Decimal.compare(total, "0.00001") == :lt do
              acc
            else
              price = Map.get(prices, asset <> "USDT", Decimal.new("0"))
              value_usdt = Decimal.mult(total, price)

              # Skip positions below minimum trade value
              if Decimal.compare(value_usdt, Decimal.new("#{@min_trade_value_usdt}")) == :lt do
                acc
              else
                position = %{
                  asset: asset,
                  amount: total,
                  price_usdt: price,
                  value_usdt: value_usdt
                }

                [position | acc]
              end
            end
          end
        end)
        # Maintain original order
        |> Enum.reverse()

      {:ok, positions}
    end
  end

  defp to_decimal_safe(%Decimal{} = d), do: d
  defp to_decimal_safe(str) when is_binary(str), do: Decimal.new(str)
  defp to_decimal_safe(num) when is_number(num), do: Decimal.new("#{num}")
  defp to_decimal_safe(_), do: Decimal.new("0")

  defp get_current_futures_positions(hedge_type) do
    # Use unified account data aggregation across spot/margin/futures
    # This properly aggregates all positions regardless of account type
    case hedge_type do
      :usdt_m ->
        # Get USDM positions with proper unified view
        get_unified_usdm_positions()

      :coin_m ->
        # Get COINM positions with proper unified view
        get_unified_coinm_positions()

      _ ->
        {:error, {:invalid_hedge_type, hedge_type}}
    end
  end

  # Get unified USDM positions across all account types
  defp get_unified_usdm_positions do
    # Check account mode first
    case check_account_mode() do
      {:ok, :portfolio_margin} ->
        PortfolioMargin.query_um_position_information()

      _ ->
        # For regular accounts, use standard futures endpoint
        UsdmFutures.get_positions()
    end
  end

  # Get unified COINM positions across all account types
  defp get_unified_coinm_positions do
    # Check account mode first
    case check_account_mode() do
      {:ok, :portfolio_margin} ->
        PortfolioMargin.query_cm_position_information()

      _ ->
        # For regular accounts, use standard coin futures endpoint
        CoinmFutures.get_positions()
    end
  end

  defp get_current_prices(balances) do
    # Fetch real prices from market data API
    # Works on both testnet and production
    get_current_prices_from_api(balances)
  end

  defp get_current_prices_from_api(balances) do
    # Get unique assets that need pricing, handling both atom and string keys
    assets =
      balances
      |> Enum.reduce(MapSet.new(), fn balance, acc ->
        asset = Map.get(balance, "asset") || Map.get(balance, :asset)

        # Single pass: skip nils and stablecoins, add to set for uniqueness
        if asset && asset not in ["USDT", "USDC", "BUSD"] do
          MapSet.put(acc, asset)
        else
          acc
        end
      end)
      |> MapSet.to_list()

    # Fetch all prices with limited concurrency to avoid connection pool exhaustion
    prices =
      assets
      |> Task.async_stream(
        fn asset ->
          fetch_single_ticker_price(asset)
        end,
        max_concurrency: @price_fetch_concurrency,
        timeout: @price_fetch_timeout_ms
      )
      |> Enum.reduce(%{}, fn
        {:ok, nil}, acc ->
          acc

        {:ok, {symbol, price}}, acc ->
          Map.put(acc, symbol, price)

        {:exit, reason}, acc ->
          Logger.error("Task failed: #{inspect(reason)}")
          acc
      end)

    validate_prices(prices)
  end

  defp validate_prices(prices) do
    # Check for zero or invalid prices
    # Single pass to find invalid prices
    invalid_prices =
      prices
      |> Enum.reduce([], fn {symbol, price}, acc ->
        if Decimal.compare(price, Decimal.new("0")) == :eq or
             Decimal.compare(price, Decimal.new("0")) == :lt do
          [symbol | acc]
        else
          acc
        end
      end)
      # Maintain discovery order for error messages
      |> Enum.reverse()

    if Enum.empty?(invalid_prices) do
      {:ok, prices}
    else
      Logger.error("Invalid prices detected for symbols: #{inspect(invalid_prices)}")
      {:error, {:invalid_prices, invalid_prices}}
    end
  end

  defp validate_margin_requirements(margin_info, hedge_percentage) do
    # Check unified maintenance margin ratio
    umr = Decimal.new(margin_info["uniMMR"] || "0")
    # 80% is a safe threshold
    max_safe_umr = Decimal.new("0.8")

    # Estimate new UMR after hedging
    # Use proper Decimal arithmetic instead of float operations
    base_factor = Decimal.new("1")
    adjustment = Decimal.mult(Decimal.new("#{hedge_percentage}"), Decimal.new("0.2"))
    multiplier = Decimal.add(base_factor, adjustment)
    estimated_umr = Decimal.mult(umr, multiplier)

    if Decimal.compare(estimated_umr, max_safe_umr) == :gt do
      {:error, {:insufficient_margin, %{current_umr: umr, estimated_umr: estimated_umr}}}
    else
      :ok
    end
  end

  defp calculate_hedge_orders(
         spot_positions,
         futures_positions,
         hedge_percentage,
         hedge_type,
         symbols_filter,
         margin_info
       ) do
    # Map existing futures positions by asset
    existing_hedges = build_existing_hedges_map(futures_positions)

    # Calculate required hedge for each spot position
    hedge_orders =
      spot_positions
      |> Enum.reduce([], fn spot_pos, acc ->
        # Single pass: filter, map, and reject nil
        if symbols_filter == :all or spot_pos.asset in symbols_filter do
          existing_hedge = Map.get(existing_hedges, spot_pos.asset, Decimal.new("0"))

          case calculate_single_hedge(spot_pos, existing_hedge, hedge_percentage, hedge_type, margin_info) do
            nil -> acc
            hedge_order -> [hedge_order | acc]
          end
        else
          acc
        end
      end)
      # Maintain original order
      |> Enum.reverse()

    # Validate total hedge value doesn't exceed limits
    # Pass account balance for comprehensive validation
    account_balance = extract_account_balance(margin_info)

    case validate_total_hedge_value(hedge_orders, account_balance) do
      :ok ->
        hedge_orders

      {:error, reason} ->
        Logger.error("Total hedge validation failed: #{inspect(reason)}")
        Logger.warning("Reducing hedge orders to stay within limits")
        # Return orders that fit within the limit
        limit_hedge_orders(hedge_orders)
    end
  end

  defp limit_hedge_orders(hedge_orders) do
    max_total = Decimal.new("#{@max_total_hedge_usdt}")

    # Sort by hedge value descending and take orders until we hit the limit
    hedge_orders
    |> Enum.sort_by(fn order -> Decimal.new(order.hedge_value) end, :desc)
    |> Enum.reduce_while({[], Decimal.new("0")}, fn order, {acc, total} ->
      order_value = Decimal.new(order.hedge_value)
      new_total = Decimal.add(total, order_value)

      if Decimal.compare(new_total, max_total) == :gt do
        {:halt, {acc, total}}
      else
        {:cont, {[order | acc], new_total}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp build_existing_hedges_map(futures_positions) do
    Map.new(futures_positions, fn pos ->
      # Extract base asset from symbol (e.g., "BTCUSDT" -> "BTC")
      asset = String.replace(pos["symbol"], ~r/USDT|BUSD/, "")
      {asset, Decimal.new(pos["positionAmt"])}
    end)
  end

  defp calculate_single_hedge(spot_pos, existing_hedge, hedge_percentage, hedge_type, margin_info) do
    # Runtime validation: ensure price is valid before calculations
    if !valid_price?(spot_pos.price_usdt) do
      Logger.error("Invalid price for #{spot_pos.asset}: #{spot_pos.price_usdt}")
      raise ArgumentError, "Cannot calculate hedge with invalid price for #{spot_pos.asset}"
    end

    # Calculate target hedge amount (negative for short)
    # Convert float hedge_percentage to Decimal
    target_hedge_value = Decimal.mult(spot_pos.value_usdt, Decimal.new("#{hedge_percentage}"))

    # Get current hedge value (absolute value since hedges are shorts)
    current_hedge_value =
      existing_hedge
      |> Decimal.mult(spot_pos.price_usdt)
      |> Decimal.abs()

    # Calculate additional hedge needed
    additional_hedge_value = Decimal.sub(target_hedge_value, current_hedge_value)

    # Only create order if above minimum trade value
    if Decimal.compare(additional_hedge_value, Decimal.new("#{@min_trade_value_usdt}")) == :gt do
      futures_qty = calculate_futures_quantity(additional_hedge_value, spot_pos.price_usdt, hedge_type)

      # Validate position limits before creating order
      # Extract account balance from margin_info if available
      account_balance = extract_account_balance(margin_info)

      case validate_position_limits(spot_pos.asset, futures_qty, additional_hedge_value, account_balance) do
        :ok ->
          build_hedge_order(spot_pos, futures_qty, additional_hedge_value, hedge_type)

        {:error, errors} ->
          Logger.error("Position limit violations for #{spot_pos.asset}: #{inspect(errors)}")
          # Return nil to be filtered out later
          nil
      end
    end
  end

  defp calculate_futures_quantity(hedge_value, price_usdt, hedge_type) do
    # Runtime validation: ensure price is valid for division
    if !valid_price?(price_usdt) do
      raise ArgumentError, "Cannot calculate futures quantity with invalid price: #{price_usdt}"
    end

    case hedge_type do
      :usdt_m ->
        # Linear futures: quantity in base asset
        hedge_value
        |> Decimal.div(price_usdt)
        # Most futures have 3 decimal precision
        |> Decimal.round(3)

      :coin_m ->
        # Inverse futures: quantity in contracts
        # Get contract size from exchange info (cached)
        contract_size = get_coinm_contract_size("BTCUSD_PERP")

        hedge_value
        |> Decimal.div(Decimal.new(contract_size))
        |> Decimal.round(0)
    end
  end

  # Gets the contract size for a COIN-M futures symbol from exchange info.
  # Results are cached for 24 hours to avoid repeated API calls.
  defp get_coinm_contract_size(symbol) do
    cache_key = "coinm_contract_size:#{symbol}"

    # Try to get from cache first
    case Cache.get(cache_key) do
      {:ok, size} ->
        size

      {:error, _} ->
        fetch_and_cache_contract_size(cache_key, symbol)
    end
  end

  defp fetch_and_cache_contract_size(cache_key, symbol) do
    size = fetch_contract_size_from_api(symbol)
    Cache.put(cache_key, size, @contract_info_cache_ttl_seconds)
    size
  end

  defp fetch_contract_size_from_api(symbol) do
    case MarketData.coinm_get_exchange_info() do
      {:ok, exchange_info} ->
        find_contract_size(exchange_info, symbol) || default_contract_size(symbol)

      {:error, reason} ->
        Logger.error("Failed to fetch COINM exchange info: #{inspect(reason)}")
        @default_btc_contract_size
    end
  end

  defp default_contract_size(symbol) do
    Logger.warning("Contract size not found for #{symbol}, using default #{@default_btc_contract_size}")
    @default_btc_contract_size
  end

  defp find_contract_size(exchange_info, symbol) do
    exchange_info["symbols"]
    |> Enum.find(fn sym -> sym["symbol"] == symbol end)
    |> case do
      nil -> nil
      symbol_info -> symbol_info["contractSize"]
    end
  end

  defp valid_price?(price) do
    Decimal.compare(price, Decimal.new("0")) == :gt
  end

  defp validate_position_limits(asset, quantity, value_usdt, account_balance) do
    # Check against maximum single position USD value
    max_value = Decimal.new("#{@max_single_position_usdt}")

    value_error =
      if Decimal.compare(value_usdt, max_value) == :gt do
        [{:exceeds_max_value, "Position value #{value_usdt} exceeds max #{max_value}"}]
      else
        []
      end

    # Check against per-asset position size limits
    quantity_error =
      case Map.get(@max_position_sizes, asset) do
        nil ->
          []

        max_size ->
          if Decimal.compare(quantity, max_size) == :gt do
            [{:exceeds_max_quantity, "Quantity #{quantity} exceeds max #{max_size} for #{asset}"}]
          else
            []
          end
      end

    # Check balance percentage if account balance is available
    balance_error =
      if account_balance && valid_decimal?(account_balance) do
        balance_dec = ensure_decimal(account_balance)
        max_position_value = Decimal.mult(balance_dec, Decimal.new("#{@max_position_pct_of_balance}"))

        if Decimal.compare(value_usdt, max_position_value) == :gt do
          pct = Decimal.mult(Decimal.new("#{@max_position_pct_of_balance}"), Decimal.new("100"))
          [{:exceeds_balance_pct, "Position value #{value_usdt} exceeds #{pct}% of account balance #{balance_dec}"}]
        else
          []
        end
      else
        []
      end

    errors = value_error ++ quantity_error ++ balance_error

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  defp valid_decimal?(value) do
    case value do
      %Decimal{} ->
        true

      val when is_binary(val) or is_number(val) ->
        try do
          Decimal.new(val)
          true
        rescue
          _ -> false
        end

      _ ->
        false
    end
  end

  defp ensure_decimal(value) do
    case value do
      %Decimal{} -> value
      val -> Decimal.new(val)
    end
  end

  # Extract account balance from margin_info response
  defp extract_account_balance(nil), do: nil

  defp extract_account_balance(margin_info) when is_map(margin_info) do
    # Try to get totalNetAssetOfBtc * BTC price or totalWalletBalance
    cond do
      Map.has_key?(margin_info, "totalWalletBalance") ->
        margin_info["totalWalletBalance"]

      Map.has_key?(margin_info, "totalNetAssetOfBtc") and Map.has_key?(margin_info, "indexPrice") ->
        btc_value = Decimal.new(margin_info["totalNetAssetOfBtc"])
        btc_price = Decimal.new(margin_info["indexPrice"])
        Decimal.mult(btc_value, btc_price)

      Map.has_key?(margin_info, "totalMarginBalance") ->
        margin_info["totalMarginBalance"]

      true ->
        nil
    end
  end

  defp validate_total_hedge_value(hedge_orders, account_balance) do
    total_value =
      Enum.reduce(hedge_orders, Decimal.new("0"), fn order, acc ->
        Decimal.add(acc, Decimal.new(order.hedge_value))
      end)

    max_total = Decimal.new("#{@max_total_hedge_usdt}")

    # Check absolute limit
    absolute_error =
      if Decimal.compare(total_value, max_total) == :gt do
        [{:total_hedge_exceeds_limit, "Total hedge value #{total_value} exceeds max #{max_total}"}]
      else
        []
      end

    # Check balance percentage if account balance is available
    balance_error =
      if account_balance && valid_decimal?(account_balance) do
        balance_dec = ensure_decimal(account_balance)
        # Total hedge shouldn't exceed 50% of account balance (conservative)
        max_hedge_pct = Decimal.new("0.50")
        max_hedge_value = Decimal.mult(balance_dec, max_hedge_pct)

        if Decimal.compare(total_value, max_hedge_value) == :gt do
          pct = Decimal.mult(max_hedge_pct, Decimal.new("100"))
          [{:exceeds_balance_pct, "Total hedge #{total_value} exceeds #{pct}% of account balance #{balance_dec}"}]
        else
          []
        end
      else
        []
      end

    errors = absolute_error ++ balance_error

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  # Account balance percentage validation is integrated in validate_position_limits/4
  # which checks that positions don't exceed @max_position_pct_of_balance of total balance

  defp build_hedge_order(spot_pos, futures_qty, hedge_value, hedge_type) do
    %{
      asset: spot_pos.asset,
      symbol: spot_pos.asset <> "USDT",
      # Short to hedge long spot
      side: "SELL",
      quantity: Decimal.to_string(futures_qty),
      spot_value: Decimal.to_string(spot_pos.value_usdt),
      hedge_value: Decimal.to_string(hedge_value),
      hedge_type: hedge_type
    }
  end

  defp execute_hedge_orders(hedge_orders, true = _dry_run) do
    # Dry run - just return the orders that would be placed
    Logger.info("Dry run - would execute #{length(hedge_orders)} hedge orders")

    results =
      Enum.map(hedge_orders, fn order ->
        Map.put(order, :status, "DRY_RUN")
      end)

    {:ok, results}
  end

  defp execute_hedge_orders(hedge_orders, false = _dry_run) do
    # Execute orders in parallel with error handling
    results =
      hedge_orders
      |> Enum.map(fn order ->
        Task.async(fn ->
          execute_single_hedge_order(order)
        end)
      end)
      |> Enum.map(&Task.await(&1, 10_000))

    # Check if any orders failed
    failed_orders = Enum.filter(results, &(&1[:status] == "FAILED"))

    if Enum.empty?(failed_orders) do
      {:ok, results}
    else
      Logger.warning("Some hedge orders failed: #{inspect(failed_orders)}")
      # Still return all results, caller can check status
      {:ok, results}
    end
  end

  defp execute_single_hedge_order(order) do
    params = %{
      symbol: order.symbol,
      side: order.side,
      type: "MARKET",
      quantity: order.quantity
    }

    case order.hedge_type do
      :usdt_m ->
        case PortfolioMargin.new_um_order(params) do
          {:ok, result} ->
            order
            |> Map.put(:status, "EXECUTED")
            |> Map.put(:order_id, result["orderId"])
            |> Map.put(:executed_qty, result["executedQty"])

          {:error, reason} ->
            Logger.error("Failed to place hedge order for #{order.symbol}: #{inspect(reason)}")

            order
            |> Map.put(:status, "FAILED")
            |> Map.put(:error, reason)
        end

      :coin_m ->
        case PortfolioMargin.new_cm_order(params) do
          {:ok, result} ->
            order
            |> Map.put(:status, "EXECUTED")
            |> Map.put(:order_id, result["orderId"])
            |> Map.put(:executed_qty, result["executedQty"])

          {:error, reason} ->
            Logger.error("Failed to place COIN-M hedge order for #{order.symbol}: #{inspect(reason)}")

            order
            |> Map.put(:status, "FAILED")
            |> Map.put(:error, reason)
        end
    end
  end

  defp calculate_total_hedged_value(results) do
    # Single pass: filter and sum in one reduce
    Enum.reduce(results, Decimal.new("0"), fn order, acc ->
      if order[:status] in ["EXECUTED", "DRY_RUN"] do
        Decimal.add(acc, Decimal.new(order.hedge_value))
      else
        acc
      end
    end)
  end

  # PAXG hedging private functions

  defp calculate_hedged_portfolio_value do
    with {:ok, spot_positions} <- get_spot_positions_with_values(),
         {:ok, futures_positions} <- get_all_futures_positions() do
      # Calculate total spot value
      spot_value =
        Enum.reduce(spot_positions, Decimal.new("0"), fn pos, acc ->
          Decimal.add(acc, pos.value_usdt)
        end)

      # Calculate total futures notional (absolute value since hedges are shorts)
      futures_value =
        Enum.reduce(futures_positions, Decimal.new("0"), fn pos, acc ->
          position_amt = Decimal.new(pos["positionAmt"] || "0")
          mark_price = Decimal.new(pos["markPrice"] || "0")
          notional = position_amt |> Decimal.mult(mark_price) |> Decimal.abs()
          Decimal.add(acc, notional)
        end)

      # Total hedged portfolio value = spot + perp hedge
      total_value = Decimal.add(spot_value, futures_value)

      Logger.info("""
      Hedged portfolio calculation:
      Spot value: #{spot_value}
      Futures hedge value: #{futures_value}
      Total portfolio value: #{total_value}
      """)

      {:ok, total_value}
    end
  end

  defp get_all_futures_positions do
    # Get both USDT-M and COIN-M positions for complete view
    with {:ok, usdt_positions} <- get_futures_positions_safe(:usdt_m),
         {:ok, coin_positions} <- get_futures_positions_safe(:coin_m) do
      {:ok, usdt_positions ++ coin_positions}
    end
  end

  defp get_futures_positions_safe(type) do
    case get_current_futures_positions(type) do
      {:ok, positions} when is_list(positions) ->
        # Filter only non-zero positions
        active_positions =
          Enum.filter(positions, fn pos ->
            amt = Decimal.new(pos["positionAmt"] || "0")
            Decimal.compare(amt, "0") != :eq
          end)

        {:ok, active_positions}

      {:ok, _} ->
        {:ok, []}

      # Return empty list on error for safety
      {:error, _} ->
        {:ok, []}
    end
  end

  defp get_paxg_price do
    # Fetch real PAXGUSDT price from market data API
    fetch_ticker_price_with_fallback("PAXGUSDT", "2000.00")
  end

  defp fetch_ticker_price_with_fallback(symbol, fallback_price) do
    case MarketData.get_ticker_price(%{symbol: symbol}) do
      {:ok, ticker} ->
        price = extract_price_from_ticker(ticker)
        {:ok, Decimal.new(price)}

      {:error, reason} ->
        handle_ticker_fetch_error(symbol, reason, fallback_price)
    end
  end

  defp extract_price_from_ticker(ticker) when is_list(ticker) do
    List.first(ticker)["price"]
  end

  defp extract_price_from_ticker(%{"price" => price}), do: price

  defp handle_ticker_fetch_error(symbol, reason, fallback_price) do
    Logger.error("Failed to fetch #{symbol} price: #{inspect(reason)}")
    env = ZenCex.Config.environment(:binance)

    if env == :test do
      Logger.warning("Using fallback price for #{symbol} on testnet")
      {:ok, Decimal.new(fallback_price)}
    else
      {:error, {:price_fetch_failed, symbol, reason}}
    end
  end

  defp fetch_single_ticker_price(asset) do
    symbol = asset <> "USDT"

    case MarketData.get_ticker_price(%{symbol: symbol}) do
      {:ok, ticker} ->
        price = extract_price_from_ticker(ticker)
        {symbol, Decimal.new(price)}

      {:error, reason} ->
        Logger.warning("Failed to fetch price for #{symbol}: #{inspect(reason)}")
        env = ZenCex.Config.environment(:binance)

        if env == :test do
          Logger.warning("Using fallback price for #{symbol} on testnet")
          {symbol, Decimal.new("1000")}
        end
    end
  end

  defp generate_client_order_id(symbol, action) do
    timestamp = System.system_time(:millisecond)
    random_suffix = 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    action_str = if action == :buy, do: "B", else: "S"
    "ZC_#{action_str}_#{symbol}_#{timestamp}_#{random_suffix}"
  end

  defp calculate_paxg_position(portfolio_value, paxg_price, leverage) do
    # Calculate the PAXG quantity needed
    # Notional = portfolio_value * leverage
    notional = Decimal.mult(portfolio_value, Decimal.new(leverage))

    # Quantity = Notional / Price
    quantity = Decimal.div(notional, paxg_price)

    # Round to appropriate precision (usually 3 decimals for PAXG)
    rounded_qty = Decimal.round(quantity, 3)

    # Validate minimum order size
    min_notional = Decimal.new("#{@min_trade_value_usdt}")

    if Decimal.compare(notional, min_notional) == :lt do
      {:error,
       {:below_minimum_notional,
        %{
          required: min_notional,
          calculated: notional
        }}}
    else
      {:ok,
       %{
         symbol: "PAXGUSDT",
         side: "BUY",
         quantity: Decimal.to_string(rounded_qty),
         notional: Decimal.to_string(notional),
         price: Decimal.to_string(paxg_price),
         leverage: leverage
       }}
    end
  end

  defp execute_paxg_long(position, true = _dry_run) do
    Logger.info("""
    [DRY RUN] Would open PAXG long position:
    Symbol: #{position.symbol}
    Side: #{position.side}
    Quantity: #{position.quantity}
    Notional: #{position.notional} USDT
    Leverage: #{position.leverage}x
    """)

    {:ok,
     %{
       status: "DRY_RUN",
       symbol: position.symbol,
       side: position.side,
       quantity: position.quantity,
       notional: position.notional
     }}
  end

  defp execute_paxg_long(position, false = _dry_run) do
    # Execute the PAXG long order via Portfolio Margin USDT-M endpoint
    params = %{
      symbol: position.symbol,
      side: position.side,
      type: "MARKET",
      quantity: position.quantity
    }

    Logger.info("Executing PAXG long order: #{inspect(params)}")

    case PortfolioMargin.new_um_order(params) do
      {:ok, result} ->
        Logger.info("PAXG long order executed successfully: #{inspect(result)}")
        {:ok, result}

      {:error, reason} = error ->
        Logger.error("Failed to execute PAXG long order: #{inspect(reason)}")
        error
    end
  end

  # PAXG rebalancing private functions

  defp get_paxg_perp_position do
    # Get PAXG perpetual position from futures
    with {:ok, positions} <- get_current_futures_positions(:usdt_m) do
      paxg_position =
        Enum.find(positions, fn pos ->
          pos["symbol"] == "PAXGUSDT"
        end)

      if paxg_position do
        # Only consider long positions for rebalancing
        position_amt = Decimal.new(paxg_position["positionAmt"] || "0")

        if Decimal.compare(position_amt, "0") == :gt do
          {:ok, paxg_position}
        else
          {:error, :no_long_paxg_position}
        end
      else
        {:error, :no_paxg_position}
      end
    end
  end

  defp calculate_paxg_pnl(position) do
    # Calculate PnL for the PAXG position
    position_amt = Decimal.new(position["positionAmt"] || "0")
    entry_price = Decimal.new(position["entryPrice"] || "0")
    mark_price = Decimal.new(position["markPrice"] || "0")

    # Unrealized PnL = (Mark Price - Entry Price) * Position Amount
    price_diff = Decimal.sub(mark_price, entry_price)
    unrealized_pnl = Decimal.mult(price_diff, position_amt)

    # Calculate PnL percentage
    entry_notional = Decimal.mult(entry_price, position_amt)

    pnl_percentage =
      if Decimal.compare(entry_notional, "0") == :gt do
        unrealized_pnl
        |> Decimal.div(entry_notional)
        |> Decimal.to_float()
      else
        0.0
      end

    {:ok,
     %{
       position_amt: position_amt,
       entry_price: entry_price,
       mark_price: mark_price,
       unrealized_pnl: unrealized_pnl,
       pnl_percentage: pnl_percentage,
       entry_notional: entry_notional
     }}
  end

  defp validate_rebalance_conditions(pnl_data, profit_threshold, min_rebalance_usdt) do
    cond do
      # Check if position is profitable enough
      pnl_data.pnl_percentage < profit_threshold ->
        {:error,
         {:below_profit_threshold,
          %{
            current: pnl_data.pnl_percentage,
            required: profit_threshold
          }}}

      # Check if PnL is large enough to rebalance
      Decimal.compare(pnl_data.unrealized_pnl, Decimal.new("#{min_rebalance_usdt}")) == :lt ->
        {:error,
         {:below_minimum_rebalance,
          %{
            current_pnl: pnl_data.unrealized_pnl,
            required: min_rebalance_usdt
          }}}

      true ->
        :ok
    end
  end

  defp plan_rebalance(pnl_data, rebalance_ratio) do
    # Calculate how much profit to convert to spot
    profit_to_convert = Decimal.mult(pnl_data.unrealized_pnl, Decimal.new("#{rebalance_ratio}"))

    # Calculate PAXG quantity to rebalance
    # We need to reduce perp position by this amount and buy equivalent spot
    paxg_quantity =
      profit_to_convert
      |> Decimal.div(pnl_data.mark_price)
      # PAXG typically has 3 decimal precision
      |> Decimal.round(3)

    # Ensure we don't try to rebalance more than the position
    # Max 50% of position
    max_rebalance = Decimal.mult(pnl_data.position_amt, Decimal.new("0.5"))

    final_quantity =
      if Decimal.compare(paxg_quantity, max_rebalance) == :gt do
        max_rebalance
      else
        paxg_quantity
      end

    {:ok,
     %{
       usdt_amount: profit_to_convert,
       paxg_quantity: final_quantity,
       current_price: pnl_data.mark_price,
       # Amount to sell from perp
       reduce_perp_qty: final_quantity,
       # Amount to buy in spot
       buy_spot_qty: final_quantity
     }}
  end

  defp execute_rebalance(plan, true = _dry_run) do
    Logger.info("""
    [DRY RUN] Would execute PAXG rebalance:
    1. Reduce PAXG perp by: #{plan.reduce_perp_qty} PAXG
    2. Buy PAXG spot: #{plan.buy_spot_qty} PAXG
    Total USDT value: #{plan.usdt_amount}
    Current PAXG price: #{plan.current_price}
    """)

    {:ok,
     [
       %{
         type: "reduce_perp",
         symbol: "PAXGUSDT",
         side: "SELL",
         quantity: Decimal.to_string(plan.reduce_perp_qty),
         status: "DRY_RUN"
       },
       %{
         type: "buy_spot",
         symbol: "PAXGUSDT",
         side: "BUY",
         quantity: Decimal.to_string(plan.buy_spot_qty),
         status: "DRY_RUN"
       }
     ]}
  end

  defp execute_rebalance(plan, false = _dry_run) do
    # Execute two orders: reduce perp and buy spot
    # Using Task.async for parallel execution but with error handling

    reduce_task =
      Task.async(fn ->
        execute_perp_reduction(plan.reduce_perp_qty)
      end)

    # Wait for perp reduction to complete before buying spot
    # This ensures we have the funds available
    case Task.await(reduce_task, 10_000) do
      {:ok, perp_result} ->
        # Now buy spot PAXG with the freed capital
        case execute_spot_purchase(plan.buy_spot_qty) do
          {:ok, spot_result} ->
            {:ok,
             [
               Map.put(perp_result, :type, "reduce_perp"),
               Map.put(spot_result, :type, "buy_spot")
             ]}

          {:error, reason} ->
            # Perp was reduced but spot purchase failed
            # Log this for manual intervention
            Logger.error("""
            CRITICAL: Perp position reduced but spot purchase failed!
            Reduced perp by: #{plan.reduce_perp_qty}
            Failed to buy spot: #{inspect(reason)}
            Manual intervention required to complete rebalance.
            """)

            {:error,
             {:partial_execution,
              %{
                perp_result: perp_result,
                spot_error: reason
              }}}
        end

      {:error, reason} ->
        # Perp reduction failed, no spot purchase attempted
        Logger.error("Failed to reduce PAXG perp position: #{inspect(reason)}")
        {:error, {:perp_reduction_failed, reason}}
    end
  end

  defp execute_perp_reduction(quantity) do
    params = %{
      symbol: "PAXGUSDT",
      # Selling to reduce long position
      side: "SELL",
      type: "MARKET",
      quantity: Decimal.to_string(quantity),
      # Important: only reduce existing position
      reduceOnly: true
    }

    Logger.info("Reducing PAXG perp position: #{inspect(params)}")

    case PortfolioMargin.new_um_order(params) do
      {:ok, result} ->
        Logger.info("PAXG perp reduction successful: #{inspect(result)}")

        {:ok,
         %{
           symbol: "PAXGUSDT",
           side: "SELL",
           quantity: result["executedQty"],
           status: result["status"],
           order_id: result["orderId"]
         }}

      error ->
        error
    end
  end

  defp execute_spot_purchase(quantity) do
    params = %{
      symbol: "PAXGUSDT",
      side: "BUY",
      type: "MARKET",
      quantity: Decimal.to_string(quantity)
    }

    Logger.info("Buying PAXG spot: #{inspect(params)}")

    case Spot.place_order(params) do
      {:ok, result} ->
        Logger.info("PAXG spot purchase successful: #{inspect(result)}")

        {:ok,
         %{
           symbol: "PAXGUSDT",
           side: "BUY",
           quantity: result["executedQty"] || result[:executedQty],
           status: result["status"] || result[:status],
           order_id: result["orderId"] || result[:orderId]
         }}

      error ->
        error
    end
  end
end
