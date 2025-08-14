defmodule ZenCex.Endpoints do
  @moduledoc """
  Standardized endpoint definitions with rate limit weights for exchange APIs.

  Provides a centralized location for endpoint configurations including
  their rate limit weights, allowing consistent usage across the application.

  ## Usage

      # Get endpoint configuration
      {:ok, config} = Endpoints.get(:binance, :ticker)
      
      # Use with HTTP module
      request = HTTP.base_request(:binance)
      |> ReqHelpers.put_private(:rate_limit_weight, config.weight)
      |> Req.get(config.path)

  ## Weight Guidelines

  - Market data (tickers, orderbook): 1-5 weight
  - Account data (balances, positions): 5-10 weight  
  - Order placement/cancellation: 20-50 weight
  - Historical data: 10-20 weight per request
  """

  @type exchange :: :binance | :binance_futures | :kraken | :deribit
  @type endpoint_type :: atom()
  @type endpoint_config :: %{
          path: String.t(),
          weight: pos_integer(),
          method: :get | :post | :put | :delete,
          requires_auth: boolean()
        }

  # Binance Spot endpoints
  @binance_endpoints %{
    # Market Data
    ticker: %{path: "/api/v3/ticker/price", weight: 1, method: :get, requires_auth: false},
    ticker_24h: %{path: "/api/v3/ticker/24hr", weight: 1, method: :get, requires_auth: false},
    orderbook: %{path: "/api/v3/depth", weight: 1, method: :get, requires_auth: false},
    trades: %{path: "/api/v3/trades", weight: 1, method: :get, requires_auth: false},
    klines: %{path: "/api/v3/klines", weight: 1, method: :get, requires_auth: false},
    server_time: %{path: "/api/v3/time", weight: 1, method: :get, requires_auth: false},

    # Account Data (requires auth)
    account: %{path: "/api/v3/account", weight: 10, method: :get, requires_auth: true},
    open_orders: %{path: "/api/v3/openOrders", weight: 3, method: :get, requires_auth: true},
    all_orders: %{path: "/api/v3/allOrders", weight: 10, method: :get, requires_auth: true},
    my_trades: %{path: "/api/v3/myTrades", weight: 10, method: :get, requires_auth: true},

    # Trading (requires auth)
    place_order: %{path: "/api/v3/order", weight: 20, method: :post, requires_auth: true},
    cancel_order: %{path: "/api/v3/order", weight: 10, method: :delete, requires_auth: true},
    cancel_all: %{path: "/api/v3/openOrders", weight: 10, method: :delete, requires_auth: true}
  }

  # Binance Futures endpoints
  @binance_futures_endpoints %{
    # Market Data
    ticker: %{path: "/fapi/v1/ticker/price", weight: 1, method: :get, requires_auth: false},
    ticker_24h: %{path: "/fapi/v1/ticker/24hr", weight: 1, method: :get, requires_auth: false},
    orderbook: %{path: "/fapi/v1/depth", weight: 1, method: :get, requires_auth: false},
    funding_rate: %{path: "/fapi/v1/fundingRate", weight: 1, method: :get, requires_auth: false},
    klines: %{path: "/fapi/v1/klines", weight: 1, method: :get, requires_auth: false},

    # Account Data (requires auth)
    account: %{path: "/fapi/v2/account", weight: 5, method: :get, requires_auth: true},
    positions: %{path: "/fapi/v2/positionRisk", weight: 5, method: :get, requires_auth: true},
    balance: %{path: "/fapi/v2/balance", weight: 5, method: :get, requires_auth: true},

    # Trading (requires auth)
    place_order: %{path: "/fapi/v1/order", weight: 20, method: :post, requires_auth: true},
    cancel_order: %{path: "/fapi/v1/order", weight: 10, method: :delete, requires_auth: true}
  }

  # Kraken endpoints (weight not used, but included for consistency)
  @kraken_endpoints %{
    # Public
    server_time: %{path: "/0/public/Time", weight: 1, method: :get, requires_auth: false},
    ticker: %{path: "/0/public/Ticker", weight: 1, method: :get, requires_auth: false},
    orderbook: %{path: "/0/public/Depth", weight: 1, method: :get, requires_auth: false},
    trades: %{path: "/0/public/Trades", weight: 1, method: :get, requires_auth: false},
    ohlc: %{path: "/0/public/OHLC", weight: 1, method: :get, requires_auth: false},

    # Private (requires auth)
    balance: %{path: "/0/private/Balance", weight: 1, method: :post, requires_auth: true},
    trade_balance: %{
      path: "/0/private/TradeBalance",
      weight: 1,
      method: :post,
      requires_auth: true
    },
    open_orders: %{path: "/0/private/OpenOrders", weight: 1, method: :post, requires_auth: true},
    closed_orders: %{
      path: "/0/private/ClosedOrders",
      weight: 1,
      method: :post,
      requires_auth: true
    },

    # Trading
    place_order: %{path: "/0/private/AddOrder", weight: 20, method: :post, requires_auth: true},
    cancel_order: %{
      path: "/0/private/CancelOrder",
      weight: 10,
      method: :post,
      requires_auth: true
    }
  }

  # Deribit endpoints (weight not used, but included for consistency)
  @deribit_endpoints %{
    # OAuth
    oauth_token: %{path: "/api/v2/public/auth", weight: 1, method: :get, requires_auth: false},

    # Public (Deribit uses JSON-RPC, so these are POST endpoints)
    server_time: %{
      path: "/api/v2/public/get_time",
      weight: 1,
      method: :post,
      requires_auth: false
    },
    ticker: %{path: "/api/v2/public/ticker", weight: 1, method: :get, requires_auth: false},
    orderbook: %{
      path: "/api/v2/public/get_order_book",
      weight: 1,
      method: :get,
      requires_auth: false
    },
    instruments: %{
      path: "/api/v2/public/get_instruments",
      weight: 1,
      method: :get,
      requires_auth: false
    },

    # Private (requires auth)
    account: %{
      path: "/api/v2/private/get_account_summary",
      weight: 1,
      method: :get,
      requires_auth: true
    },
    positions: %{
      path: "/api/v2/private/get_positions",
      weight: 1,
      method: :get,
      requires_auth: true
    },
    open_orders: %{
      path: "/api/v2/private/get_open_orders",
      weight: 1,
      method: :get,
      requires_auth: true
    },

    # Trading
    place_order: %{path: "/api/v2/private/buy", weight: 20, method: :post, requires_auth: true},
    cancel_order: %{
      path: "/api/v2/private/cancel",
      weight: 10,
      method: :post,
      requires_auth: true
    }
  }

  @doc """
  Gets endpoint configuration for a specific exchange and endpoint type.

  ## Examples

      iex> Endpoints.get(:binance, :ticker)
      {:ok, %{path: "/api/v3/ticker/price", weight: 1, method: :get, requires_auth: false}}
      
      iex> Endpoints.get(:binance, :place_order)
      {:ok, %{path: "/api/v3/order", weight: 1, method: :post, requires_auth: true}}
      
      iex> Endpoints.get(:invalid, :ticker)
      {:error, :unknown_exchange}
  """
  @spec get(exchange(), endpoint_type()) :: {:ok, endpoint_config()} | {:error, atom()}
  def get(exchange, endpoint_type) do
    endpoints = get_endpoints(exchange)

    case Map.get(endpoints, endpoint_type) do
      nil -> {:error, :unknown_endpoint}
      config -> {:ok, config}
    end
  end

  @doc """
  Gets all endpoints for an exchange.
  """
  @spec get_all(exchange()) :: {:ok, map()} | {:error, atom()}
  def get_all(exchange) do
    case get_endpoints(exchange) do
      nil -> {:error, :unknown_exchange}
      endpoints -> {:ok, endpoints}
    end
  end

  @doc """
  Lists available endpoint types for an exchange.
  """
  @spec list_endpoints(exchange()) :: {:ok, [atom()]} | {:error, atom()}
  def list_endpoints(exchange) do
    case get_endpoints(exchange) do
      nil -> {:error, :unknown_exchange}
      endpoints -> {:ok, Map.keys(endpoints)}
    end
  end

  @doc """
  Builds a configured request for a specific endpoint.

  ## Examples

      iex> {:ok, request} = Endpoints.build_request(:binance, :ticker, %{symbol: "BTCUSDT"})
      iex> Req.get!(request)
  """
  @spec build_request(exchange(), endpoint_type(), map()) ::
          {:ok, Req.Request.t()} | {:error, atom()}
  def build_request(exchange, endpoint_type, params \\ %{}) do
    alias ZenCex.{HTTP, ReqHelpers}

    with {:ok, config} <- get(exchange, endpoint_type) do
      request =
        HTTP.base_request(exchange)
        |> ReqHelpers.put_private(:rate_limit_weight, config.weight)

      # Build URL from base_url + path
      url = build_url(request.options[:base_url], config.path)

      request =
        case {exchange, config.method, config.requires_auth} do
          # Special handling for Deribit JSON-RPC
          {:deribit, :post, _} ->
            json_rpc_params = %{
              "jsonrpc" => "2.0",
              "method" => String.replace(config.path, "/api/v2/", ""),
              "params" => params,
              "id" => System.unique_integer([:positive])
            }

            request
            |> Req.merge(url: url, json: json_rpc_params)

          # Binance POST with auth needs params in query string for signing
          {exchange, :post, true} when exchange in [:binance, :binance_futures] ->
            request
            |> Req.merge(url: url, params: params)

          # Standard REST handling
          {_, :get, _} ->
            request
            |> Req.merge(url: url, params: params)

          {_, :post, _} ->
            request
            |> Req.merge(url: url, body: params)

          {_, :put, _} ->
            request
            |> Req.merge(url: url, body: params)

          {_, :delete, _} ->
            request
            |> Req.merge(url: url, params: params)
        end

      {:ok, request}
    end
  end

  # Private functions

  defp get_endpoints(:binance), do: @binance_endpoints
  defp get_endpoints(:binance_futures), do: @binance_futures_endpoints
  defp get_endpoints(:kraken), do: @kraken_endpoints
  defp get_endpoints(:deribit), do: @deribit_endpoints
  defp get_endpoints(_), do: nil

  defp build_url(base_url, path) when is_binary(base_url) and is_binary(path) do
    URI.merge(base_url, path) |> to_string()
  end
end
