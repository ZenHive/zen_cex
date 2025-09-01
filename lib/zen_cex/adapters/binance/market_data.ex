defmodule ZenCex.Adapters.Binance.MarketData do
  @moduledoc """
  Market data endpoints for Binance APIs.

  This module provides access to all Binance market data endpoints which are
  public and don't require authentication. These endpoints provide real-time
  and historical market information for spot and futures trading.

  Unlike Bybit which has a unified API, Binance separates its APIs by product type:
  - Spot market data uses the main API
  - USDM futures (USDT-margined) use /fapi
  - COINM futures (coin-margined) use /dapi

  ## Available Endpoints

  ### Spot Market Data
  - `get_ticker_price/1` - Current price for symbol(s)
  - `get_ticker_24hr/1` - 24hr ticker statistics
  - `get_order_book/1` - Order book depth
  - `get_recent_trades/1` - Recent trades list
  - `get_klines/1` - Candlestick/OHLCV data
  - `get_avg_price/1` - Current average price
  - `get_exchange_info/0` - Trading rules and symbols
  - `get_book_ticker/1` - Best bid/ask prices

  ### USDM Futures Market Data
  - `usdm_get_ticker_price/1` - Current price
  - `usdm_get_ticker_24hr/1` - 24hr statistics
  - `usdm_get_order_book/1` - Order book depth
  - `usdm_get_recent_trades/1` - Recent trades
  - `usdm_get_klines/1` - Candlestick data
  - `usdm_get_mark_price/1` - Mark price and funding
  - `usdm_get_funding_rate/1` - Funding rate history
  - `usdm_get_open_interest/1` - Open interest
  - `usdm_get_exchange_info/0` - Trading rules

  ### COINM Futures Market Data
  - `coinm_get_ticker_price/1` - Current price
  - `coinm_get_ticker_24hr/1` - 24hr statistics
  - `coinm_get_order_book/1` - Order book depth
  - `coinm_get_recent_trades/1` - Recent trades
  - `coinm_get_klines/1` - Candlestick data
  - `coinm_get_mark_price/1` - Mark price and funding
  - `coinm_get_funding_rate/1` - Funding rate history
  - `coinm_get_open_interest/1` - Open interest
  - `coinm_get_exchange_info/0` - Trading rules

  ## Usage

  Market data endpoints don't require authentication:

      # Get spot ticker
      MarketData.get_ticker_price(%{symbol: "BTCUSDT"})

      # Get USDM futures order book
      MarketData.usdm_get_order_book(%{symbol: "BTCUSDT", limit: 100})

      # Get COINM futures klines
      MarketData.coinm_get_klines(%{
        symbol: "BTCUSD_PERP",
        interval: "1h",
        limit: 100
      })

  Note: Margin trading uses the same market data as spot trading.
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints

  alias ZenCex.Adapters.Binance.EndpointLoader
  alias ZenCex.Adapters.Binance.Parser
  alias ZenCex.Adapters.Binance.RequestHelper

  require EndpointLoader

  # Load market data endpoints from generated file
  EndpointLoader.load_endpoints("generated_market_data_endpoints.ex")

  # The EndpointRegistry macro automatically generates functions for all operations

  # Helper to normalize options to keyword list (accepts both maps and keyword lists)
  defp normalize_opts_to_keyword_list(opts) when is_list(opts), do: opts
  defp normalize_opts_to_keyword_list(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts_to_keyword_list(_), do: []

  # Custom implementation for execute_endpoint_request
  # Market data endpoints don't require auth, so we use a simplified helper
  defp execute_endpoint_request(config, params, opts, _adapter) do
    # Normalize opts to keyword list (accept both maps and keyword lists)
    opts_list = normalize_opts_to_keyword_list(opts)

    # Market data is always public, set skip_auth
    opts_with_no_auth = Keyword.put(opts_list, :skip_auth, true)

    # Determine API type from the endpoint config
    api_type = config[:api_type] || :spot

    # Use the unified request helper with API type
    operation_type_resolver = fn _ -> api_type end

    RequestHelper.execute_request_for_api_type(
      config,
      params,
      opts_with_no_auth,
      api_type,
      operation_type_resolver
    )
  end
end
