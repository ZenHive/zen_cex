defmodule ZenCex.Adapters.Bybit.MarketData do
  @moduledoc """
  Market data endpoints for Bybit v5 API.

  This module provides access to all Bybit v5 market data endpoints which are
  public and don't require authentication. These endpoints provide real-time
  and historical market information for spot, linear (USDT perpetual), inverse
  (coin perpetual), and options trading.

  ## Available Endpoints

  ### Price Data
  - `get_tickers/1` - Get ticker information (24hr stats)
  - `get_orderbook/1` - Get order book depth
  - `get_recent_trades/1` - Get recent trades

  ### Historical Data
  - `get_klines/1` - Get candlestick/OHLCV data
  - `get_mark_price_klines/1` - Get mark price candlesticks
  - `get_index_price_klines/1` - Get index price candlesticks
  - `get_premium_index_klines/1` - Get premium index candlesticks

  ### Derivatives Data
  - `get_open_interest/1` - Get open interest for derivatives
  - `get_funding_history/1` - Get funding rate history
  - `get_delivery_price/1` - Get delivery price (options)
  - `get_historical_volatility/1` - Get historical volatility

  ### Reference Data
  - `get_instruments_info/1` - Get trading rules and instrument info
  - `get_risk_limit/1` - Get risk limit info
  - `get_insurance_info/1` - Get insurance pool data

  ## Usage

  All market data endpoints require a `category` parameter:

      # Get spot ticker
      MarketData.get_tickers(%{category: "spot", symbol: "BTCUSDT"})
      
      # Get futures order book
      MarketData.get_orderbook(%{category: "linear", symbol: "BTCUSDT", limit: 25})
      
      # Get klines/candlesticks
      MarketData.get_klines(%{
        category: "spot",
        symbol: "BTCUSDT",
        interval: "1h",
        limit: 100
      })

  Or use the category-prefixed convenience functions from the main Endpoints module:

      Endpoints.spot_get_tickers(%{symbol: "BTCUSDT"})
      Endpoints.linear_get_orderbook(%{symbol: "BTCUSDT", limit: 25})
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Bybit.Endpoints

  alias ZenCex.Adapters.Bybit.EndpointLoader
  alias ZenCex.Adapters.Bybit.Parser
  alias ZenCex.Adapters.Bybit.RequestHelper

  require EndpointLoader

  # Load market data endpoints from generated file
  EndpointLoader.load_endpoints("generated_market_data_endpoints.ex")

  # The EndpointRegistry macro automatically generates functions for all operations

  # Custom implementation for execute_endpoint_request
  # Market data endpoints don't require auth, so we use a simplified helper
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Market data is always public, set skip_auth
    opts_with_no_auth = Keyword.put(opts, :skip_auth, true)

    # Use the unified API helper (market endpoints are part of v5 unified API)
    RequestHelper.execute_request_for_unified_api(config, params, opts_with_no_auth)
  end
end
