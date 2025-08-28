defmodule Mix.Tasks.ZenCex.GenerateBinanceMarketData do
  @shortdoc "Generate Binance market data endpoint definitions"

  @moduledoc """
  Generates Binance market data endpoint definitions from API documentation.

  Unlike Bybit which has a unified v5 API, Binance has separate APIs for spot and futures.
  This task generates market data endpoints for all Binance product types.

  ## Usage

      mix zen_cex.generate_binance_market_data

  This will:
  1. Define market data endpoints for spot and futures
  2. Generate the endpoint definitions file
  3. Save to lib/zen_cex/adapters/binance/generated_market_data_endpoints.ex
  """

  use Mix.Task

  require Logger

  # Constants for market data endpoint configuration
  @default_weight 1
  # 3 seconds
  @default_timeout_ms 3000
  @max_retry_attempts 3

  # Define market data endpoints for each API type
  # These are public endpoints that don't require authentication

  @spot_market_data_endpoints [
    %{
      operation: :get_ticker_price,
      method: :get,
      path: "/api/v3/ticker/price",
      doc: "Current price for a symbol or all symbols"
    },
    %{
      operation: :get_ticker_24hr,
      method: :get,
      path: "/api/v3/ticker/24hr",
      doc: "24hr ticker price change statistics"
    },
    %{
      operation: :get_order_book,
      method: :get,
      path: "/api/v3/depth",
      doc: "Order book depth"
    },
    %{
      operation: :get_recent_trades,
      method: :get,
      path: "/api/v3/trades",
      doc: "Recent trades list"
    },
    %{
      operation: :get_klines,
      method: :get,
      path: "/api/v3/klines",
      doc: "Kline/candlestick bars for a symbol"
    },
    %{
      operation: :get_avg_price,
      method: :get,
      path: "/api/v3/avgPrice",
      doc: "Current average price for a symbol"
    },
    %{
      operation: :get_exchange_info,
      method: :get,
      path: "/api/v3/exchangeInfo",
      doc: "Current exchange trading rules and symbol information"
    },
    %{
      operation: :get_book_ticker,
      method: :get,
      path: "/api/v3/ticker/bookTicker",
      doc: "Best price/qty on the order book for a symbol or symbols"
    }
  ]

  @usdm_futures_market_data_endpoints [
    %{
      operation: :usdm_get_ticker_price,
      method: :get,
      path: "/fapi/v1/ticker/price",
      doc: "Current price for USDM futures symbol"
    },
    %{
      operation: :usdm_get_ticker_24hr,
      method: :get,
      path: "/fapi/v1/ticker/24hr",
      doc: "24hr ticker price change statistics for USDM futures"
    },
    %{
      operation: :usdm_get_order_book,
      method: :get,
      path: "/fapi/v1/depth",
      doc: "Order book depth for USDM futures"
    },
    %{
      operation: :usdm_get_recent_trades,
      method: :get,
      path: "/fapi/v1/trades",
      doc: "Recent trades for USDM futures"
    },
    %{
      operation: :usdm_get_klines,
      method: :get,
      path: "/fapi/v1/klines",
      doc: "Kline/candlestick bars for USDM futures"
    },
    %{
      operation: :usdm_get_mark_price,
      method: :get,
      path: "/fapi/v1/premiumIndex",
      doc: "Mark price and funding rate for USDM futures"
    },
    %{
      operation: :usdm_get_funding_rate,
      method: :get,
      path: "/fapi/v1/fundingRate",
      doc: "Funding rate history for USDM futures"
    },
    %{
      operation: :usdm_get_open_interest,
      method: :get,
      path: "/fapi/v1/openInterest",
      doc: "Open interest for USDM futures"
    },
    %{
      operation: :usdm_get_exchange_info,
      method: :get,
      path: "/fapi/v1/exchangeInfo",
      doc: "Current exchange trading rules for USDM futures"
    }
  ]

  @coinm_futures_market_data_endpoints [
    %{
      operation: :coinm_get_ticker_price,
      method: :get,
      path: "/dapi/v1/ticker/price",
      doc: "Current price for COINM futures symbol"
    },
    %{
      operation: :coinm_get_ticker_24hr,
      method: :get,
      path: "/dapi/v1/ticker/24hr",
      doc: "24hr ticker price change statistics for COINM futures"
    },
    %{
      operation: :coinm_get_order_book,
      method: :get,
      path: "/dapi/v1/depth",
      doc: "Order book depth for COINM futures"
    },
    %{
      operation: :coinm_get_recent_trades,
      method: :get,
      path: "/dapi/v1/trades",
      doc: "Recent trades for COINM futures"
    },
    %{
      operation: :coinm_get_klines,
      method: :get,
      path: "/dapi/v1/klines",
      doc: "Kline/candlestick bars for COINM futures"
    },
    %{
      operation: :coinm_get_mark_price,
      method: :get,
      path: "/dapi/v1/premiumIndex",
      doc: "Mark price and funding rate for COINM futures"
    },
    %{
      operation: :coinm_get_funding_rate,
      method: :get,
      path: "/dapi/v1/fundingRate",
      doc: "Funding rate history for COINM futures"
    },
    %{
      operation: :coinm_get_open_interest,
      method: :get,
      path: "/dapi/v1/openInterest",
      doc: "Open interest for COINM futures"
    },
    %{
      operation: :coinm_get_exchange_info,
      method: :get,
      path: "/dapi/v1/exchangeInfo",
      doc: "Current exchange trading rules for COINM futures"
    }
  ]

  @impl Mix.Task
  def run(_args) do
    Logger.info("Generating Binance market data endpoints...")

    # Combine all endpoints
    all_endpoints =
      @spot_market_data_endpoints ++ @usdm_futures_market_data_endpoints ++ @coinm_futures_market_data_endpoints

    # Generate the endpoint definitions
    content = generate_endpoints_file(all_endpoints)

    # Write to file
    output_path = "lib/zen_cex/adapters/binance/generated_market_data_endpoints.ex"
    File.write!(output_path, content)

    Logger.info("Generated #{length(all_endpoints)} market data endpoints")
    Logger.info("Saved to #{output_path}")

    # Format the generated file
    System.cmd("mix", ["format", output_path])

    Logger.info("Formatted generated file")
    :ok
  end

  defp generate_endpoints_file(endpoints) do
    timestamp = DateTime.to_iso8601(DateTime.utc_now())

    endpoint_definitions = Enum.map_join(endpoints, ",\n", &format_endpoint/1)

    """
    # Generated from Binance API documentation - MARKET DATA
    # DO NOT EDIT - This file was auto-generated by Mix.Tasks.ZenCex.GenerateBinanceMarketData
    # Generated at: #{timestamp}
    # Run `mix zen_cex.generate_binance_market_data` to regenerate

    [
    #{endpoint_definitions}
    ]
    """

    # Fixed: closing heredoc delimiter
  end

  defp format_endpoint(endpoint) do
    # Determine API type from operation prefix
    api_type =
      cond do
        String.starts_with?(Atom.to_string(endpoint.operation), "usdm_") -> :usdm_futures
        String.starts_with?(Atom.to_string(endpoint.operation), "coinm_") -> :coinm_futures
        true -> :spot
      end

    """
      %{
        operation: :#{endpoint.operation},
        method: :#{endpoint.method},
        path: "#{endpoint.path}",
        api_type: :#{api_type},
        requires_auth: false,
        weight: #{@default_weight},
        timeout: #{@default_timeout_ms},
        max_retries: #{@max_retry_attempts},
        retry_on: [:timeout, :network_error],
        response_parser: &ZenCex.Adapters.Binance.Parser.parse_market_data_response/1,
        error_mapping: &ZenCex.Adapters.Binance.Parser.parse_error/1,
        doc: "#{endpoint.doc}"
      }\
    """
  end
end
