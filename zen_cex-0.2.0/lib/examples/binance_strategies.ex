defmodule ZenCex.Examples.BinanceStrategies do
  @moduledoc """
  Example module demonstrating high-level trading strategies with Binance.

  This module shows how to:
  - Auto-hedge spot positions with futures
  - Create PAXG gold hedge positions
  - Rebalance portfolio to target allocations

  ## Prerequisites

  All strategies require:
  - Portfolio Margin mode enabled on Binance
  - Sufficient margin for futures positions
  - API credentials with futures trading permissions

  Set these environment variables:
  - `BINANCE_API_KEY` (or `BINANCE_TESTNET_API_KEY` for testnet)
  - `BINANCE_API_SECRET` (or `BINANCE_TESTNET_API_SECRET` for testnet)

  ## Safety Features

  All strategies support dry-run mode for testing without execution.
  Always test with `dry_run: true` before running with real funds.

  ## Usage

      alias ZenCex.Examples.BinanceStrategies

      # Test with dry run first
      {:ok, result} = BinanceStrategies.auto_hedge_spot_positions(0.5, dry_run: true)

      # Execute when ready
      {:ok, result} = BinanceStrategies.auto_hedge_spot_positions(0.5)
  """

  alias ZenCex.Adapters.Binance.Strategies

  @doc """
  Automatically hedge spot positions with futures contracts.

  Creates short futures positions to hedge long spot exposure based on the
  specified hedge percentage.

  ## Parameters
    * `hedge_percentage` - Percentage of spot value to hedge (0.0 to 1.0)
    * `opts` - Options keyword list

  ## Options
    * `:hedge_type` - `:usdt_m` (linear) or `:coin_m` (inverse), default: `:usdt_m`
    * `:symbols` - List of symbols to hedge, default: all with futures markets
    * `:dry_run` - If true, calculate but don't execute orders, default: false
    * `:auth_credentials` - Map with `:api_key`, `:api_secret`, `:testnet` boolean

  ## Returns
    * `{:ok, map()}` - Hedge execution summary with:
      - `:executed_hedges` - List of executed hedge orders
      - `:total_hedged_value` - Total USD value hedged
      - `:hedge_ratio` - The hedge percentage used
      - `:dry_run` - Whether this was a dry run

  ## Examples

      # Hedge 50% of spot holdings with linear futures (dry run)
      {:ok, result} = auto_hedge_spot_positions(0.5, dry_run: true)

      # Result structure:
      # %{
      #   executed_hedges: [
      #     %{symbol: "BTCUSDT", spot_value: "50000", hedge_value: "25000", status: "DRY_RUN"},
      #     %{symbol: "ETHUSDT", spot_value: "10000", hedge_value: "5000", status: "DRY_RUN"}
      #   ],
      #   total_hedged_value: "30000",
      #   hedge_ratio: 0.5,
      #   dry_run: true
      # }

      # Hedge 75% with inverse futures for specific symbols
      {:ok, result} = auto_hedge_spot_positions(0.75,
        hedge_type: :coin_m,
        symbols: ["BTC", "ETH"],
        dry_run: false
      )

      # Use custom credentials
      credentials = %{
        api_key: "your_key",
        api_secret: "your_secret",
        testnet: true
      }
      {:ok, result} = auto_hedge_spot_positions(0.5,
        auth_credentials: credentials,
        dry_run: true
      )
  """
  @spec auto_hedge_spot_positions(float(), keyword()) :: {:ok, map()} | {:error, term()}
  def auto_hedge_spot_positions(hedge_percentage, opts \\ [])
      when is_float(hedge_percentage) and hedge_percentage >= 0.0 and hedge_percentage <= 1.0 do
    Strategies.auto_hedge_spot_positions(hedge_percentage, opts)
  end

  @doc """
  Opens a PAXGUSDT perpetual long position equal to the total hedged portfolio value.

  This strategy creates gold exposure by going long PAXGUSDT perp with a size equal
  to the combined USD value of spot holdings and their perpetual hedges.

  ## Parameters
    * `opts` - Options keyword list

  ## Options
    * `:dry_run` - Calculate but don't execute (default: false)
    * `:leverage` - Leverage for PAXG position (default: 1)
    * `:auth_credentials` - Map with `:api_key`, `:api_secret`, `:testnet` boolean

  ## Returns
    * `{:ok, map()}` - PAXG position summary with:
      - `:portfolio_value` - Total hedged portfolio value
      - `:paxg_position` - Position details
      - `:order_result` - Order execution result
      - `:dry_run` - Whether this was a dry run

  ## Examples

      # Test PAXG hedge with dry run
      {:ok, result} = hedge_with_paxg_long(dry_run: true)

      # Result structure:
      # %{
      #   portfolio_value: "100000.00",
      #   paxg_position: %{
      #     symbol: "PAXGUSDT",
      #     side: "BUY",
      #     quantity: "50.0",
      #     notional: "100000.00"
      #   },
      #   order_result: %{status: "DRY_RUN"},
      #   dry_run: true
      # }

      # Execute with 2x leverage
      {:ok, result} = hedge_with_paxg_long(leverage: 2)

      # Use custom credentials
      credentials = %{
        api_key: "your_key",
        api_secret: "your_secret",
        testnet: false
      }
      {:ok, result} = hedge_with_paxg_long(
        leverage: 1,
        auth_credentials: credentials,
        dry_run: true
      )
  """
  @spec hedge_with_paxg_long(keyword()) :: {:ok, map()} | {:error, term()}
  def hedge_with_paxg_long(opts \\ []) do
    Strategies.hedge_with_paxg_long(opts)
  end

  @doc """
  Rebalance portfolio to target allocation percentages.

  Calculates required trades to reach target allocation and executes them
  as market orders. Only rebalances assets that exceed the deviation threshold.

  ## Parameters
    * `target_allocation` - Map of asset to target percentage (must sum to 1.0)
    * `opts` - Options keyword list

  ## Options
    * `:threshold` - Minimum deviation to trigger rebalance (default: 0.02 or 2%)
    * `:base_asset` - Quote asset for rebalancing (default: "USDT")
    * `:dry_run` - Calculate but don't execute (default: false)
    * `:auth_credentials` - Map with `:api_key`, `:api_secret`, `:testnet` boolean

  ## Returns
    * `{:ok, map()}` - Rebalance summary with:
      - `:rebalanced` - Boolean indicating if rebalance was executed
      - `:trades_executed` - List of executed trades
      - `:current_allocation` - Portfolio allocation before rebalancing
      - `:target_allocation` - Target allocation requested
      - `:dry_run` - Whether this was a dry run

  ## Examples

      # Define target allocation (must sum to 1.0)
      target = %{
        "BTC" => 0.5,   # 50% Bitcoin
        "ETH" => 0.3,   # 30% Ethereum
        "USDT" => 0.2   # 20% cash
      }

      # Test rebalance with dry run
      {:ok, result} = rebalance_portfolio(target, dry_run: true)

      # Result structure:
      # %{
      #   rebalanced: true,
      #   trades_executed: [
      #     %{action: :buy, asset: "BTC", value_usdt: "1000", status: "DRY_RUN"},
      #     %{action: :sell, asset: "ETH", value_usdt: "500", status: "DRY_RUN"}
      #   ],
      #   current_allocation: %{"BTC" => 0.4, "ETH" => 0.35, "USDT" => 0.25},
      #   target_allocation: %{"BTC" => 0.5, "ETH" => 0.3, "USDT" => 0.2},
      #   dry_run: true
      # }

      # Execute rebalance with custom threshold
      {:ok, result} = rebalance_portfolio(target,
        threshold: 0.05,  # 5% deviation threshold
        base_asset: "USDT",
        dry_run: false
      )

      # Use custom credentials
      credentials = %{
        api_key: "your_key",
        api_secret: "your_secret",
        testnet: true
      }
      {:ok, result} = rebalance_portfolio(target,
        auth_credentials: credentials,
        dry_run: true
      )
  """
  @spec rebalance_portfolio(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def rebalance_portfolio(target_allocation, opts \\ []) when is_map(target_allocation) do
    # Validate that allocations sum to 1.0
    total =
      target_allocation
      |> Map.values()
      |> Enum.reduce(0.0, &+/2)

    if abs(total - 1.0) > 0.001 do
      {:error, {:invalid_allocation, "Allocations must sum to 1.0, got #{total}"}}
    else
      Strategies.rebalance_portfolio(target_allocation, opts)
    end
  end

  @doc """
  Complete example demonstrating the full hedging workflow.

  This function demonstrates:
  1. Hedging spot positions with futures
  2. Creating a PAXG gold hedge
  3. Rebalancing to target allocation

  All operations run in dry-run mode for safety.

  ## Examples

      # Run the complete workflow
      run_complete_example()
  """
  @spec run_complete_example() :: :ok
  def run_complete_example do
    IO.puts("=== Binance Strategy Examples ===\n")

    # Step 1: Auto-hedge spot positions
    IO.puts("Step 1: Auto-hedging 50% of spot positions (dry run)...")

    case auto_hedge_spot_positions(0.5, dry_run: true) do
      {:ok, hedge_result} ->
        IO.puts("✓ Hedge calculation complete:")
        IO.puts("  Total hedged value: #{hedge_result.total_hedged_value} USDT")
        IO.puts("  Number of hedges: #{length(hedge_result.executed_hedges)}\n")

      {:error, reason} ->
        IO.puts("✗ Auto-hedge failed: #{inspect(reason)}\n")
    end

    # Step 2: PAXG gold hedge
    IO.puts("Step 2: Creating PAXG gold hedge position (dry run)...")

    case hedge_with_paxg_long(dry_run: true) do
      {:ok, paxg_result} ->
        IO.puts("✓ PAXG hedge calculated:")
        IO.puts("  Portfolio value: #{paxg_result.portfolio_value} USDT")
        IO.puts("  PAXG quantity: #{paxg_result.paxg_position.quantity}\n")

      {:error, reason} ->
        IO.puts("✗ PAXG hedge failed: #{inspect(reason)}\n")
    end

    # Step 3: Portfolio rebalancing
    IO.puts("Step 3: Rebalancing portfolio (dry run)...")

    target_allocation = %{
      "BTC" => 0.4,
      "ETH" => 0.3,
      "BNB" => 0.1,
      "USDT" => 0.2
    }

    case rebalance_portfolio(target_allocation, dry_run: true) do
      {:ok, rebalance_result} ->
        IO.puts("✓ Rebalance calculated:")
        IO.puts("  Trades needed: #{length(rebalance_result.trades_executed)}")
        IO.puts("  Target allocation: BTC=40%, ETH=30%, BNB=10%, USDT=20%\n")

      {:error, reason} ->
        IO.puts("✗ Rebalance failed: #{inspect(reason)}\n")
    end

    IO.puts("=== Example Complete ===")
    IO.puts("All operations were in dry-run mode - no real trades executed.")
    :ok
  end
end
