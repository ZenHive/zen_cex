defmodule ZenCex.Adapters.Binance.PortfolioMargin do
  @moduledoc """
  Portfolio Margin trading endpoints for Binance.

  Portfolio Margin is Binance's advanced trading mode that provides unified margin
  and risk management across multiple trading products. It's designed for sophisticated
  traders who need capital efficiency across different markets.

  ## Supported Product Types

  - **USD-M Futures (UM)**: USDT-margined perpetual and quarterly futures
  - **COIN-M Futures (CM)**: Coin-margined perpetual and quarterly futures
  - **Margin Trading**: Cross and isolated margin trading (spot with leverage)

  ## Key Features

  ### Cross-Collateralization
  All assets in your portfolio can be used as collateral across different products.
  For example, your BTC holdings can secure USDT futures positions.

  ### Unified Risk Management
  - Single maintenance margin calculation across all positions
  - Portfolio-level liquidation instead of position-level
  - Advanced risk metrics including Greeks for options (when available)

  ### Enhanced Capital Efficiency
  - Lower margin requirements due to portfolio offsetting
  - Hedged positions require less collateral
  - Automatic borrowing and lending between products

  ## API Characteristics

  - **Base URL**: `https://papi.binance.com` (production only)
  - **Rate Limit**: 3,000 requests per minute (higher than standard APIs)
  - **Testnet Support**: NOT available - returns 404 on testnet
  - **Path Prefix**: All endpoints use `/papi/v1/` prefix

  ## Account Requirements

  1. **Activation Required**: Portfolio Margin must be activated on your account
  2. **VIP Level**: Generally requires VIP 1 or higher
  3. **API Permissions**: API key needs Portfolio Margin trading permission
  4. **IP Whitelist**: Recommended for security

  ## Common Use Cases

  ### 1. Unified Account View
  ```elixir
  # Get complete account information across all products
  {:ok, account} = PortfolioMargin.get_unified_account()
  ```

  ### 2. Cross-Product Orders
  ```elixir
  # Place order using cross-collateral
  {:ok, order} = PortfolioMargin.place_unified_order(%{
    symbol: "BTCUSDT",
    side: "BUY",
    type: "LIMIT",
    quantity: "0.001",
    price: "40000",
    product_type: "UM"  # Optional: auto-detected from symbol
  })
  ```

  ### 3. Risk Monitoring
  ```elixir
  # Get all positions with unified margin calculations
  {:ok, positions} = PortfolioMargin.get_all_positions()
  ```

  ## Important Considerations

  - **No Testnet**: All testing must be done carefully in production with small amounts
  - **Liquidation Risk**: Portfolio liquidation affects ALL positions
  - **Complexity**: Requires understanding of cross-margin and portfolio risk
  - **Product Limits**: Some features may be limited based on your VIP level

  ## Error Handling

  Common errors specific to Portfolio Margin:
  - `{:error, {:not_activated, _}}` - Portfolio Margin not activated on account
  - `{:error, {:insufficient_margin, _}}` - Not enough collateral across portfolio
  - `{:error, {:invalid_product_type, _}}` - Product type not supported or detected
  - `{:error, {:no_testnet_for_portfolio_margin}}` - Testnet access attempted

  ## Rate Limiting

  Portfolio Margin has a separate rate limit pool:
  - 3,000 weight per minute (compared to 1,200 for spot)
  - Shared across all /papi/ endpoints
  - Not affected by spot or futures rate limits
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints

  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.ProductDetector

  require Logger

  # Import generated endpoints from Postman collection
  # This is loaded at compile time as a module attribute for safety
  # Mark as external resource so recompilation happens when the file changes
  @external_resource "lib/zen_cex/adapters/binance/generated_portfolio_endpoints.ex"

  # Load the endpoints file at compile time and convert to AST
  @generated_endpoints (
                         path = Path.join([__DIR__, "generated_portfolio_endpoints.ex"])
                         {:ok, content} = File.read(path)
                         # Parse as Elixir code to get the AST
                         {:ok, ast} = Code.string_to_quoted(content)
                         # The file contains a list literal, evaluate it in a restricted context
                         {result, _} = Code.eval_quoted(ast, [Parser: Parser], __ENV__)
                         result
                       )

  # Use endpoints directly without renaming to maintain simplicity
  # This ensures generated tests match actual function names
  @endpoints @generated_endpoints

  # Custom operations that require special handling
  @doc """
  Get unified account information across all product types.

  Returns consolidated account data including UM, CM, and Margin positions
  with cross-collateralization details. This is the primary endpoint for
  understanding your portfolio margin account status.

  ## Response Structure

  The response includes:
  - `uniMMR`: Unified Maintenance Margin Ratio (critical for liquidation)
  - `accountEquity`: Total equity across all products
  - `actualEquity`: Equity after unrealized PnL
  - `accountInitialMargin`: Total initial margin required
  - `accountMaintMargin`: Total maintenance margin required
  - `accountStatus`: NORMAL, MARGIN_CALL, or LIQUIDATION
  - `virtualMaxWithdrawAmount`: Maximum withdrawable amount

  ## Parameters

  - `recvWindow` (optional): Request validity window in milliseconds (max 60000)

  ## Examples

      # Get basic account information
      {:ok, account} = PortfolioMargin.get_unified_account()

      # With custom receive window
      {:ok, account} = PortfolioMargin.get_unified_account(%{recvWindow: 5000})

  ## Error Responses

  - `{:error, {:not_activated, _}}` - Portfolio margin not activated
  - `{:error, {:unauthorized, _}}` - API key lacks portfolio margin permission
  """
  @spec get_unified_account(map()) :: {:ok, map()} | {:error, term()}
  def get_unified_account(params \\ %{}) do
    get_unified_account(params, [])
  end

  @spec get_unified_account(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_unified_account(params, opts) do
    # Use the primary account endpoint which provides unified view
    account_information(params, opts)
  end

  @doc """
  Place a unified order that can span multiple product types.

  This intelligently routes orders to the appropriate product endpoint while
  utilizing the cross-collateralization benefits of Portfolio Margin. The order
  will use available collateral from your entire portfolio.

  ## Product Type Detection

  The function automatically detects the product type from:
  1. Explicit `product_type` parameter ("UM", "CM", or "MARGIN")
  2. Symbol pattern analysis (see `ProductDetector` for patterns)

  ## Parameters

  Required:
  - `symbol`: Trading pair (e.g., "BTCUSDT", "BTCUSD_PERP", "ETHBTC")
  - `side`: "BUY" or "SELL"
  - `type`: Order type ("LIMIT", "MARKET", "STOP", etc.)
  - `quantity`: Order quantity as string

  Optional:
  - `product_type`: Explicit product type ("UM", "CM", "MARGIN")
  - `price`: Required for LIMIT orders
  - `stopPrice`: For STOP orders
  - `timeInForce`: "GTC", "IOC", "FOK" (default: "GTC")
  - `positionSide`: "BOTH", "LONG", "SHORT" (futures only)
  - `reduceOnly`: true/false (futures only)
  - `closePosition`: true/false to close entire position (futures)

  ## Examples

      # USD-M Futures order (auto-detected from USDT suffix)
      {:ok, order} = PortfolioMargin.place_unified_order(%{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.001",
        price: "40000"
      })

      # COIN-M Futures order (auto-detected from underscore)
      {:ok, order} = PortfolioMargin.place_unified_order(%{
        symbol: "BTCUSD_PERP",
        side: "SELL",
        type: "MARKET",
        quantity: "100"  # contracts
      })

      # Margin order with explicit type
      {:ok, order} = PortfolioMargin.place_unified_order(%{
        symbol: "ETHBTC",
        side: "BUY",
        type: "LIMIT",
        quantity: "0.1",
        price: "0.065",
        product_type: "MARGIN"
      })

  ## Error Responses

  - `{:error, {:invalid_product_type, _}}` - Unable to detect or invalid product type
  - `{:error, {:insufficient_margin, _}}` - Not enough collateral across portfolio
  - `{:error, {:invalid_symbol, _}}` - Symbol not valid for detected product type
  """
  @spec place_unified_order(map()) :: {:ok, map()} | {:error, term()}
  def place_unified_order(params) do
    place_unified_order(params, [])
  end

  @spec place_unified_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_unified_order(params, opts) do
    # Use ProductDetector for robust product type detection
    product_type = ProductDetector.detect(params)

    case product_type do
      :um_futures -> new_um_order(params, opts)
      :cm_futures -> new_cm_order(params, opts)
      :margin -> new_margin_order(params, opts)
      :unknown -> {:error, {:invalid_product_type, "Unable to detect product type from parameters"}}
    end
  end

  @doc """
  Get all positions across UM, CM, and Margin products.

  Returns a unified view of all positions with cross-margin calculations.
  This provides a complete picture of your portfolio risk exposure.

  ## Response Structure

  Returns a map with product types as keys:
  ```elixir
  %{
    um_futures: [
      %{
        "symbol" => "BTCUSDT",
        "positionAmt" => "0.001",
        "entryPrice" => "45000",
        "markPrice" => "46000",
        "unRealizedProfit" => "1.00",
        "marginType" => "cross",
        "positionSide" => "BOTH"
      }
    ],
    cm_futures: [
      %{
        "symbol" => "BTCUSD_PERP",
        "positionAmt" => "100",  # contracts
        "entryPrice" => "45000",
        "markPrice" => "46000",
        "unRealizedProfit" => "0.002",  # in BTC
        "marginType" => "cross"
      }
    ]
  }
  ```

  ## Parameters

  - `symbol` (optional): Filter for specific symbol
  - `recvWindow` (optional): Request validity window

  ## Examples

      # Get all positions
      {:ok, positions} = PortfolioMargin.get_all_positions()

      # Get positions for specific symbol
      {:ok, positions} = PortfolioMargin.get_all_positions(%{symbol: "BTCUSDT"})

      # Access specific product positions
      {:ok, %{um_futures: um, cm_futures: cm}} = PortfolioMargin.get_all_positions()

  ## Notes

  - Margin positions endpoint is not yet available from Binance
  - Empty positions are returned as empty lists
  - All positions use cross margin in Portfolio Margin mode
  """
  @spec get_all_positions(map()) :: {:ok, map()} | {:error, term()}
  def get_all_positions(params \\ %{}) do
    get_all_positions(params, [])
  end

  @spec get_all_positions(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_all_positions(params, opts) do
    with {:ok, um_positions} <- query_um_position_information(params, opts),
         {:ok, cm_positions} <- query_cm_position_information(params, opts) do
      # TODO: For now, combine UM and CM positions
      # In the future, add margin positions when endpoint is available
      combined_positions = %{
        um_futures: um_positions,
        cm_futures: cm_positions
      }

      {:ok, combined_positions}
    end
  end
end
