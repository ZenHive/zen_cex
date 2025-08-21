# ZenCex IEx Configuration
# Loads helpful aliases and functions for interactive Binance trading

IO.puts """
================================================================================
ZenCex Interactive Console - Binance Trading Operations
================================================================================

Available modules loaded:
  - Spot:           Binance spot trading operations
  - UsdmFutures:    USD-M Futures trading
  - PortfolioMargin: Portfolio Margin trading (production only)
  - RateLimiter:    Rate limit monitoring
  - Config:         Environment configuration

Helper functions (use H. prefix):
  - H.env()           Show current environment (testnet/production)
  - H.credentials()   Check if API credentials are configured
  - H.spot_demo()     Run a basic spot trading demo
  - H.futures_demo()  Run a futures trading demo
  - H.rate_status()   Show rate limiter status
  - H.help()          Show this help message

Quick start:
  1. Set environment variables:
     - For testnet: BINANCE_TESTNET=true, BINANCE_TESTNET_API_KEY, BINANCE_TESTNET_API_SECRET
     - For production: BINANCE_API_KEY, BINANCE_API_SECRET
  2. Run H.env() to check configuration
  3. Try H.spot_demo() or H.futures_demo()

================================================================================
"""

# Core aliases
alias ZenCex.Config
alias ZenCex.Core.{HTTP, Registry, Telemetry}

# Binance adapters
alias ZenCex.Adapters.Binance.{
  Spot,
  UsdmFutures,
  PortfolioMargin,
  RateLimiter,
  Auth,
  Parser,
  RequestHelper
}

# Other useful modules
alias ZenCex.Safety.OrderSafety

# Import common functions for convenience
import Decimal, only: [new: 1, to_string: 1, mult: 2, div: 2]

# Helper functions
defmodule IExHelpers do
  @moduledoc false

  def env do
    env = Config.environment(:binance)
    url = Config.base_url(:binance)
    
    IO.puts """
    
    Current Environment:
    --------------------
    Mode:     #{env}
    Base URL: #{url}
    Testnet:  #{Config.testnet?(:binance)}
    """
    
    env
  end

  def credentials do
    creds = Config.credentials(:binance)
    
    IO.puts """
    
    API Credentials Status:
    -----------------------
    API Key:    #{if creds.api_key, do: "✓ Configured (#{String.slice(creds.api_key, 0..7)}...)", else: "✗ Missing"}
    API Secret: #{if creds.api_secret, do: "✓ Configured", else: "✗ Missing"}
    """
    
    case Config.validate_credentials(:binance) do
      :ok -> 
        IO.puts "Status:     Ready for authenticated operations ✓"
        :ok
      {:error, reason} ->
        IO.puts "Status:     #{reason} - Only public endpoints available"
        {:error, reason}
    end
  end

  def spot_demo do
    IO.puts """
    
    Running Spot Trading Demo
    =========================
    """

    # 1. Get server time (public endpoint)
    IO.puts "\n1. Fetching server time..."
    case Spot.get_time() do
      {:ok, %{"serverTime" => time}} ->
        IO.puts "   Server time: #{time}"
      {:error, reason} ->
        IO.puts "   Error: #{inspect(reason)}"
    end

    # 2. Get open orders (public info not available without ticker)
    IO.puts "\n2. Checking for open orders (requires auth)..."
    if Config.validate_credentials(:binance) == :ok do
      case Spot.get_openOrders(%{symbol: "BTCUSDT"}) do
        {:ok, orders} ->
          IO.puts "   Open orders: #{length(orders)}"
        {:error, reason} ->
          IO.puts "   Error: #{inspect(reason)}"
      end
    else
      IO.puts "   Skipping (no credentials)"
    end

    # 3. Check if we can do authenticated operations
    if Config.validate_credentials(:binance) == :ok do
      IO.puts "\n3. Getting account balances (requires auth)..."
      case Spot.get_balances() do
        {:ok, balances} ->
          non_zero = Enum.filter(balances, fn b -> 
            String.to_float(b["free"]) > 0 || String.to_float(b["locked"]) > 0
          end)
          
          if Enum.empty?(non_zero) do
            IO.puts "   No balances found (testnet account may be empty)"
          else
            Enum.each(non_zero, fn balance ->
              IO.puts "   #{balance["asset"]}: free=#{balance["free"]}, locked=#{balance["locked"]}"
            end)
          end
        {:error, reason} ->
          IO.puts "   Error: #{inspect(reason)}"
      end

      # 4. Show how to place an order (but don't actually place it)
      IO.puts "\n4. Example order placement (not executed):"
      IO.puts """
         # To place a limit buy order:
         Spot.place_order(%{
           symbol: "BTCUSDT",
           side: "BUY",
           type: "LIMIT",
           timeInForce: "GTC",
           quantity: "0.001",
           price: "30000"
         })
      """
    else
      IO.puts "\n3. Skipping authenticated operations (no credentials)"
    end

    IO.puts "\nDemo complete! ✓"
  end

  def futures_demo do
    IO.puts """
    
    Running USD-M Futures Demo
    ==========================
    """

    # 1. Check futures account configuration
    IO.puts "\n1. Getting futures account configuration..."
    if Config.validate_credentials(:binance) == :ok do
      case UsdmFutures.get_account_config() do
        {:ok, config} ->
          IO.puts "   Position mode: #{config["dualSidePosition"]}"
        {:error, reason} ->
          IO.puts "   Error: #{inspect(reason)}"
      end
    else
      IO.puts "   Skipping (no credentials)"
    end

    # 2. Check if we can do authenticated operations
    if Config.validate_credentials(:binance) == :ok do
      IO.puts "\n2. Getting futures account info (requires auth)..."
      case UsdmFutures.get_balances() do
        {:ok, balances} ->
          usdt = Enum.find(balances, &(&1["asset"] == "USDT"))
          if usdt do
            IO.puts "   USDT Balance: #{usdt["balance"]}"
            IO.puts "   Available: #{usdt["availableBalance"]}"
          else
            IO.puts "   No USDT balance found"
          end
        {:error, reason} ->
          IO.puts "   Error: #{inspect(reason)}"
      end

      # 3. Get positions
      IO.puts "\n3. Getting open positions..."
      case UsdmFutures.get_positions() do
        {:ok, positions} ->
          open_positions = Enum.filter(positions, fn p ->
            String.to_float(p["positionAmt"]) != 0
          end)
          
          if Enum.empty?(open_positions) do
            IO.puts "   No open positions"
          else
            Enum.each(open_positions, fn pos ->
              IO.puts "   #{pos["symbol"]}: #{pos["positionAmt"]} @ #{pos["entryPrice"]}"
            end)
          end
        {:error, reason} ->
          IO.puts "   Error: #{inspect(reason)}"
      end

      # 4. Show how to place a futures order
      IO.puts "\n4. Example futures order (not executed):"
      IO.puts """
         # To open a long position:
         UsdmFutures.place_order(%{
           symbol: "BTCUSDT",
           side: "BUY",
           type: "LIMIT",
           quantity: "0.001",
           price: "30000",
           timeInForce: "GTC"
         })
      """
    else
      IO.puts "\n2. Skipping authenticated operations (no credentials)"
    end

    IO.puts "\nDemo complete! ✓"
  end

  def rate_status do
    IO.puts """
    
    Rate Limiter Status
    ===================
    """
    
    limits = RateLimiter.get_limits()
    
    IO.puts "\nConfigured Limits:"
    IO.puts "  Spot:           #{limits.spot.limit} req/min"
    IO.puts "  USD-M Futures:  #{limits.usdm_futures.limit} req/min"
    IO.puts "  COIN-M Futures: #{limits.coinm_futures.limit} req/min"
    IO.puts "  Portfolio:      #{limits.portfolio.limit} req/min"
    IO.puts "  SAPI:           #{limits.sapi.limit} req/min"
    
    # Get current usage for common endpoints
    spot_status = RateLimiter.get_status(:spot_request)
    futures_status = RateLimiter.get_status(:usdm_futures_request)
    
    IO.puts "\nCurrent Usage:"
    IO.puts "  Spot:     #{spot_status.used}/#{spot_status.limit} (#{spot_status.usage_percent}%)"
    IO.puts "  Futures:  #{futures_status.used}/#{futures_status.limit} (#{futures_status.usage_percent}%)"
    
    :ok
  end

  def help do
    IO.puts """
    
    ZenCex IEx Helper Functions
    ===========================
    
    Environment & Config:
      H.env()         - Show current environment (testnet/production)
      H.credentials() - Check API credentials status
      
    Demo Functions:
      H.spot_demo()    - Run spot trading demo
      H.futures_demo() - Run futures trading demo
      H.rate_status()  - Show rate limiter status
      
    Direct Module Usage:
      # Get spot balances
      Spot.get_balances()
      
      # Get ticker price
      Spot.get_ticker_price(%{symbol: "BTCUSDT"})
      
      # Place spot order
      Spot.place_order(%{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.001",
        price: "30000",
        timeInForce: "GTC"
      })
      
      # Get futures positions
      UsdmFutures.get_positions()
      
      # Place futures order
      UsdmFutures.place_order(%{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "MARKET",
        quantity: "0.001"
      })
    
    Rate Limiting:
      RateLimiter.get_status(:spot_request)
      RateLimiter.get_limits()
      RateLimiter.reset(:spot)
    
    Configuration:
      Config.testnet?(:binance)
      Config.base_url(:binance)
      Config.credentials(:binance)
    """
  end
end

# Make helper functions available
alias IExHelpers, as: H

# Show initial status
H.env()
H.credentials()

IO.puts """

Type H.help() for available commands and examples.
"""