defmodule ZenCex.Safety.OrderSafety.MarketData do
  @moduledoc """
  Market data fetching for OrderSafety module.

  Handles fetching symbol information, prices, balances, and other market data
  from various exchanges with proper caching.
  """

  alias ZenCex.Adapters.Binance.CoinmFutures
  alias ZenCex.Adapters.Binance.Margin
  alias ZenCex.Adapters.Binance.MarketData, as: BinanceMarketData
  alias ZenCex.Adapters.Binance.PortfolioMargin
  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Adapters.Binance.UsdmFutures
  alias ZenCex.Adapters.Bybit.MarketData, as: BybitMarketData
  alias ZenCex.Adapters.Bybit.Unified
  alias ZenCex.Cache.Market
  alias ZenCex.Safety.OrderSafety.Cache
  alias ZenCex.Safety.OrderSafety.Config
  alias ZenCex.Safety.OrderSafety.DecimalUtils

  # Binance adapters

  # Bybit adapters
  require Logger

  # Binance default minimum notional - now configurable
  @binance_default_min_notional Config.default_min_notional(:binance)

  # WebSocket data freshness threshold - now configurable
  @websocket_data_max_age_ms Config.websocket_data_max_age_ms()

  # Public API

  @doc """
  Fetches symbol information from an exchange with caching.

  ## Parameters
  - `exchange` - The exchange atom (:binance, :bybit, etc.)
  - `symbol` - The trading symbol (e.g., "BTCUSDT")

  ## Returns
  - `{:ok, map()}` - Symbol information including status, filters, etc.
  - `{:error, term()}` - Error details
  """
  @spec fetch_symbol_info(atom(), String.t()) :: {:ok, map()} | {:error, term()}
  def fetch_symbol_info(exchange, symbol) do
    cache_key = {exchange, symbol}

    case Cache.lookup_symbol_info(cache_key) do
      {:ok, cached_info} ->
        {:ok, cached_info}

      :miss ->
        # Cache miss, fetch from exchange
        result = fetch_symbol_info_from_exchange(exchange, symbol)

        # Cache successful results
        case result do
          {:ok, info} ->
            Cache.put_symbol_info(cache_key, info)
            {:ok, info}

          error ->
            error
        end
    end
  end

  @doc """
  Fetches the current price for a symbol with caching.

  Prefers WebSocket data when available and fresh, falling back to REST API.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol

  ## Returns
  - `{:ok, Decimal.t()}` - Current price
  - `{:error, term()}` - Error details
  """
  @spec fetch_current_price(atom(), String.t()) :: {:ok, Decimal.t()} | {:error, term()}
  def fetch_current_price(exchange, symbol) do
    # First check OrderSafety cache (shortest TTL)
    cache_key = {exchange, symbol}

    case Cache.lookup_price(cache_key) do
      {:ok, cached_price} ->
        {:ok, cached_price}

      :miss ->
        # Try WebSocket cache first
        case fetch_price_from_websocket(exchange, symbol) do
          {:ok, price} ->
            # Cache with shorter TTL since WebSocket data is continuously updated
            # 5 seconds TTL for WebSocket data
            Cache.put_price(cache_key, price)
            {:ok, price}

          {:error, :stale_data} ->
            # WebSocket data is stale, fall back to REST
            fetch_and_cache_rest_price(exchange, symbol, cache_key)

          {:error, :not_found} ->
            # No WebSocket data, fall back to REST
            fetch_and_cache_rest_price(exchange, symbol, cache_key)

          error ->
            # Other WebSocket error, try REST as fallback
            Logger.debug("WebSocket price fetch failed: #{inspect(error)}, falling back to REST")
            fetch_and_cache_rest_price(exchange, symbol, cache_key)
        end
    end
  end

  # Fetches price from WebSocket cache
  defp fetch_price_from_websocket(exchange, symbol) do
    case Market.get_book_ticker(exchange, symbol) do
      {:ok, %{bid_price: bid_str, ask_price: ask_str, timestamp: timestamp}} ->
        # Check if data is fresh (less than 5 seconds old)
        now_ms = System.system_time(:millisecond)
        age_ms = now_ms - timestamp

        if age_ms <= @websocket_data_max_age_ms do
          # Calculate mid price from bid/ask
          with {:ok, bid} <- DecimalUtils.safe_parse_decimal(bid_str),
               {:ok, ask} <- DecimalUtils.safe_parse_decimal(ask_str) do
            mid_price = Decimal.div(Decimal.add(bid, ask), Decimal.new("2"))
            {:ok, mid_price}
          end
        else
          {:error, :stale_data}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :expired} ->
        {:error, :not_found}

      error ->
        error
    end
  end

  # Fetches price via REST and caches with longer TTL
  defp fetch_and_cache_rest_price(exchange, symbol, cache_key) do
    result = fetch_price_from_exchange(exchange, symbol)

    # Cache successful results with standard TTL (30 seconds for REST)
    case result do
      {:ok, price} ->
        # REST data uses standard cache TTL (handled by Cache module)
        Cache.put_price(cache_key, price)
        {:ok, price}

      error ->
        error
    end
  end

  @doc """
  Fetches account balances from an exchange.

  ## Parameters
  - `exchange` - The exchange atom
  - `params` - Parameters including account_type and auth_credentials

  ## Returns
  - `{:ok, map()}` - Balance information
  - `{:error, term()}` - Error details
  """
  @spec fetch_balances(atom(), map()) :: {:ok, map()} | {:error, term()}
  def fetch_balances(exchange, params) do
    case exchange do
      :binance ->
        fetch_binance_balances(params)

      :bybit ->
        fetch_bybit_balances(params)

      _ ->
        {:error, {:unsupported_exchange, exchange}}
    end
  end

  @doc """
  Gets the current market price for a symbol.

  This is a convenience function that wraps `fetch_current_price/2`.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol

  ## Returns
  - `{:ok, Decimal.t()}` - Current market price
  - `{:error, term()}` - Error details
  """
  @spec get_market_price(atom(), String.t()) :: {:ok, Decimal.t()} | {:error, term()}
  def get_market_price(exchange, symbol) do
    fetch_current_price(exchange, symbol)
  end

  @doc """
  Fetches order book data for a symbol.

  Prefers WebSocket data when available and fresh, falling back to REST API.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol
  - `opts` - Options including `:depth` (default: 20)

  ## Returns
  - `{:ok, %{bids: list(), asks: list()}}` - Order book data
  - `{:error, term()}` - Error details
  """
  @spec fetch_orderbook(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_orderbook(exchange, symbol, opts \\ []) do
    depth = Keyword.get(opts, :depth, 20)

    # Try WebSocket cache first
    case fetch_orderbook_from_websocket(exchange, symbol) do
      {:ok, orderbook} ->
        # Limit depth if needed
        limited_book = %{
          bids: Enum.take(orderbook.bids || [], depth),
          asks: Enum.take(orderbook.asks || [], depth),
          timestamp: orderbook[:timestamp]
        }

        {:ok, limited_book}

      {:error, :stale_data} ->
        # WebSocket data is stale, fall back to REST
        fetch_orderbook_from_rest(exchange, symbol, depth)

      {:error, :not_found} ->
        # No WebSocket data, fall back to REST
        fetch_orderbook_from_rest(exchange, symbol, depth)
    end
  end

  # Fetches orderbook from WebSocket cache
  defp fetch_orderbook_from_websocket(exchange, symbol) do
    case Market.get_orderbook(exchange, symbol) do
      {:ok, %{timestamp: timestamp} = orderbook} when is_integer(timestamp) ->
        # Check if data is fresh (less than 5 seconds old)
        now_ms = System.system_time(:millisecond)
        age_ms = now_ms - timestamp

        if age_ms <= @websocket_data_max_age_ms do
          {:ok, orderbook}
        else
          {:error, :stale_data}
        end

      {:ok, orderbook} ->
        # No timestamp, treat as potentially stale
        {:ok, orderbook}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :expired} ->
        {:error, :not_found}
    end
  end

  # Fetches orderbook via REST API
  defp fetch_orderbook_from_rest(exchange, symbol, depth) do
    case exchange do
      :binance ->
        case BinanceMarketData.get_order_book(%{symbol: symbol, limit: depth}) do
          {:ok, %{"bids" => bids, "asks" => asks} = book} ->
            {:ok,
             %{
               bids: bids,
               asks: asks,
               timestamp: Map.get(book, "lastUpdateId", System.system_time(:millisecond))
             }}

          error ->
            error
        end

      :bybit ->
        case BybitMarketData.get_orderbook(%{symbol: symbol, category: "spot", limit: depth}) do
          {:ok, %{"b" => bids, "a" => asks, "ts" => timestamp}} ->
            {:ok,
             %{
               bids: bids,
               asks: asks,
               timestamp: timestamp
             }}

          error ->
            error
        end

      _ ->
        {:error, {:unsupported_exchange, exchange}}
    end
  end

  @doc """
  Ensures WebSocket connection is active for the given symbol.

  This can be used to proactively start WebSocket connections for symbols
  that will be traded.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol

  ## Returns
  - `:ok` - Connection is active or started
  - `{:error, term()}` - Error details
  """
  @spec ensure_websocket_connection(atom(), String.t()) :: :ok | {:error, term()}
  def ensure_websocket_connection(exchange, symbol) do
    alias ZenCex.Websocket.ConnectionRegistry

    case ConnectionRegistry.get(exchange, symbol) do
      {:ok, client} ->
        # Check if connection is still healthy
        # Handle case where client process might be dead
        try do
          case ZenWebsocket.Client.get_state(client) do
            :connected ->
              Logger.debug("WebSocket connection healthy for #{exchange}:#{symbol}")
              :ok

            state ->
              Logger.info("WebSocket connection #{state} for #{exchange}:#{symbol}, reconnecting...")
              reconnect_or_create(exchange, symbol)
          end
        catch
          :exit, _ ->
            Logger.info("WebSocket connection dead for #{exchange}:#{symbol}, creating new connection...")
            # Unregister the dead connection first
            ConnectionRegistry.unregister(exchange, symbol)
            reconnect_or_create(exchange, symbol)
        end

      {:error, :not_found} ->
        Logger.info("No WebSocket connection for #{exchange}:#{symbol}, establishing...")
        reconnect_or_create(exchange, symbol)
    end
  end

  # Private helper to reconnect or create WebSocket connection
  @spec reconnect_or_create(atom(), String.t()) :: :ok | {:error, term()}
  defp reconnect_or_create(exchange, symbol) do
    case exchange do
      :binance ->
        ensure_binance_connection(symbol)

      :bybit ->
        ensure_bybit_connection(symbol)

      _ ->
        {:error, {:unsupported_exchange, exchange}}
    end
  end

  @spec ensure_binance_connection(String.t()) :: :ok | {:error, term()}
  defp ensure_binance_connection(symbol) do
    alias ZenCex.Adapters.Binance.WebSocket
    alias ZenCex.Websocket.ConnectionRegistry

    # Convert symbol to lowercase stream format for Binance
    stream = String.downcase(symbol)
    streams = ["#{stream}@depth20", "#{stream}@ticker"]

    case WebSocket.ensure_connection(streams, supervised: true) do
      {:ok, client} ->
        ConnectionRegistry.register(:binance, symbol, client)
        :ok

      {:error, reason} ->
        Logger.error("Failed to establish Binance WebSocket for #{symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec ensure_bybit_connection(String.t()) :: :ok | {:error, term()}
  defp ensure_bybit_connection(symbol) do
    alias ZenCex.Adapters.Bybit.WebSocket
    alias ZenCex.Websocket.ConnectionRegistry

    # Bybit uses different topic format
    topics = ["orderbook.50.#{symbol}", "tickers.#{symbol}"]

    case WebSocket.ensure_connection(topics, supervised: true) do
      {:ok, client} ->
        ConnectionRegistry.register(:bybit, symbol, client)
        :ok

      {:error, reason} ->
        Logger.error("Failed to establish Bybit WebSocket for #{symbol}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the minimum notional value for a symbol.

  ## Parameters
  - `exchange` - The exchange atom
  - `symbol` - The trading symbol

  ## Returns
  - `Decimal.t()` - Minimum notional value
  """
  @spec get_min_notional(atom(), String.t()) :: Decimal.t()
  def get_min_notional(exchange, symbol) do
    cache_key = {exchange, symbol}

    case Cache.lookup_min_notional(cache_key) do
      {:ok, cached_min} ->
        cached_min

      :miss ->
        # Cache miss, fetch symbol info and extract min notional
        min_notional =
          case fetch_symbol_info(exchange, symbol) do
            {:ok, symbol_info} ->
              extract_min_notional(exchange, symbol_info)

            {:error, _reason} ->
              # Fallback to default if fetch fails
              default_min = Config.default_min_notional(exchange)
              Decimal.new(default_min)
          end

        # Cache the result
        Cache.put_min_notional(cache_key, min_notional)
        min_notional
    end
  end

  # Private functions - Exchange-specific implementations

  # Validates auth credentials to prevent credential leakage
  defp validate_auth_credentials(credentials) when is_map(credentials) do
    # Only allow known credential keys to prevent data leakage
    allowed_keys = [:api_key, :api_secret, :passphrase, :auth_credentials, :testnet]
    credential_keys = Map.keys(credentials)

    # Find any unauthorized keys
    unauthorized_keys =
      Enum.filter(credential_keys, fn key ->
        key not in allowed_keys
      end)

    if unauthorized_keys == [] do
      # Additional validation: ensure no values contain obvious secrets
      case validate_credential_values(credentials) do
        :ok -> {:ok, credentials}
        error -> error
      end
    else
      {:error, {:invalid_credential_keys, unauthorized_keys}}
    end
  end

  defp validate_auth_credentials(_credentials) do
    {:error, {:invalid_credentials_format, "Credentials must be a map"}}
  end

  defp validate_credential_values(credentials) do
    # Check for suspicious patterns that might indicate credential leakage
    suspicious_patterns = [
      ~r/password/i,
      ~r/token/i,
      ~r/bearer/i,
      ~r/oauth/i
    ]

    credential_strings =
      credentials
      |> Map.values()
      |> Enum.filter(&is_binary/1)

    has_suspicious =
      Enum.any?(credential_strings, fn value ->
        Enum.any?(suspicious_patterns, &Regex.match?(&1, value))
      end)

    if has_suspicious do
      {:error, {:suspicious_credential_content, "Credentials contain suspicious patterns"}}
    else
      :ok
    end
  end

  defp fetch_symbol_info_from_exchange(:binance, symbol) do
    case BinanceMarketData.get_exchange_info(%{symbol: symbol}) do
      {:ok, response} ->
        symbols = Map.get(response, "symbols", [])

        case List.first(symbols) do
          nil ->
            {:error, :not_found}

          symbol_data ->
            {:ok,
             %{
               status: symbol_data["status"],
               base_asset: symbol_data["baseAsset"],
               quote_asset: symbol_data["quoteAsset"],
               filters: symbol_data["filters"] || []
             }}
        end

      {:error, {:binance_error, -1121, _msg}} ->
        {:error, {:invalid_symbol, symbol}}

      error ->
        error
    end
  end

  defp fetch_symbol_info_from_exchange(:bybit, symbol) do
    case BybitMarketData.get_instruments_info(%{symbol: symbol, category: "spot"}) do
      {:ok, %{"result" => %{"list" => [instrument | _]}}} ->
        {:ok,
         %{
           status: instrument["status"],
           base_coin: instrument["baseCoin"],
           quote_coin: instrument["quoteCoin"],
           lot_size_filter: instrument["lotSizeFilter"],
           price_filter: instrument["priceFilter"]
         }}

      {:ok, %{"result" => %{"list" => []}}} ->
        {:error, :not_found}

      {:error, {:bybit_error, 10_002, _msg}} ->
        {:error, {:invalid_symbol, symbol}}

      error ->
        error
    end
  end

  defp fetch_symbol_info_from_exchange(exchange, _symbol) do
    {:error, {:unsupported_exchange, exchange}}
  end

  defp fetch_price_from_exchange(:binance, symbol) do
    case BinanceMarketData.get_ticker_price(%{symbol: symbol}) do
      {:ok, %{"price" => price_str}} when is_binary(price_str) ->
        DecimalUtils.safe_parse_decimal(price_str)

      {:ok, ticker} when is_list(ticker) ->
        # Handle list response (shouldn't happen with symbol param)
        case List.first(ticker) do
          %{"price" => price_str} when is_binary(price_str) ->
            DecimalUtils.safe_parse_decimal(price_str)

          _ ->
            {:error, {:unexpected_format, "Expected price field in ticker"}}
        end

      {:error, _reason} = error ->
        error

      unexpected ->
        {:error, {:unexpected_response, unexpected}}
    end
  end

  defp fetch_price_from_exchange(:bybit, symbol) do
    # Bybit requires category for tickers
    case BybitMarketData.get_tickers(%{symbol: symbol, category: "spot"}) do
      {:ok, %{"result" => %{"list" => [ticker | _]}}} ->
        case ticker do
          %{"lastPrice" => price_str} when is_binary(price_str) ->
            DecimalUtils.safe_parse_decimal(price_str)

          _ ->
            {:error, {:unexpected_format, "Expected lastPrice field in ticker"}}
        end

      {:ok, %{"result" => %{"list" => []}}} ->
        {:error, {:symbol_not_found, symbol}}

      {:error, _reason} = error ->
        error

      unexpected ->
        {:error, {:unexpected_response, unexpected}}
    end
  end

  defp fetch_price_from_exchange(exchange, _symbol) do
    {:error, {:unsupported_exchange, exchange}}
  end

  defp fetch_binance_balances(params) do
    account_type = Map.get(params, :account_type, :spot)
    auth_credentials = Map.get(params, :auth_credentials, %{})

    case account_type do
      :spot ->
        fetch_binance_spot_balances(auth_credentials)

      :margin ->
        fetch_binance_margin_balances(auth_credentials)

      :usdm_futures ->
        fetch_binance_usdm_futures_balances(auth_credentials)

      :coinm_futures ->
        fetch_binance_coinm_futures_balances(auth_credentials)

      :portfolio_margin ->
        fetch_binance_portfolio_margin_balances(auth_credentials)

      _ ->
        {:error, {:unsupported_account_type, account_type}}
    end
  end

  defp fetch_binance_spot_balances(auth_credentials) do
    with {:ok, validated_credentials} <- validate_auth_credentials(auth_credentials),
         {:ok, balances} <- call_spot_api(validated_credentials) do
      {:ok, %{type: :spot, balances: normalize_spot_balances(balances)}}
    end
  end

  defp call_spot_api(validated_credentials) do
    opts = if map_size(validated_credentials) > 0, do: [auth_credentials: validated_credentials], else: []

    case Spot.get_balances(%{}, opts) do
      {:ok, balances} when is_list(balances) -> {:ok, balances}
      {:error, _reason} = error -> error
      unexpected -> {:error, {:unexpected_response, unexpected}}
    end
  end

  defp normalize_spot_balances(balances) do
    Map.new(balances, fn b ->
      {b.asset,
       %{
         free: Decimal.to_string(b.free),
         locked: Decimal.to_string(b.locked),
         total: Decimal.to_string(Decimal.add(b.free, b.locked))
       }}
    end)
  end

  defp fetch_binance_margin_balances(auth_credentials) do
    with {:ok, validated_credentials} <- validate_auth_credentials(auth_credentials),
         {:ok, assets} <- call_margin_api(validated_credentials) do
      {:ok, %{type: :margin, balances: normalize_margin_balances(assets)}}
    end
  end

  defp call_margin_api(validated_credentials) do
    opts = if map_size(validated_credentials) > 0, do: [auth_credentials: validated_credentials], else: []

    case Margin.get_cross_margin_account(%{}, opts) do
      {:ok, %{"userAssets" => assets}} when is_list(assets) -> {:ok, assets}
      {:error, _reason} = error -> error
      unexpected -> {:error, {:unexpected_response, unexpected}}
    end
  end

  defp normalize_margin_balances(assets) do
    Map.new(assets, fn a ->
      {a["asset"],
       %{
         free: a["free"],
         locked: a["locked"],
         borrowed: a["borrowed"],
         interest: a["interest"],
         net: a["netAsset"]
       }}
    end)
  end

  defp fetch_binance_usdm_futures_balances(auth_credentials) do
    with {:ok, validated_credentials} <- validate_auth_credentials(auth_credentials),
         {:ok, assets} <- call_usdm_futures_api(validated_credentials) do
      {:ok, %{type: :usdm_futures, balances: normalize_futures_balances(assets)}}
    end
  end

  defp call_usdm_futures_api(validated_credentials) do
    opts = if map_size(validated_credentials) > 0, do: [auth_credentials: validated_credentials], else: []

    case UsdmFutures.account_information_v3(%{}, opts) do
      {:ok, %{"assets" => assets}} when is_list(assets) -> {:ok, assets}
      {:error, _reason} = error -> error
      unexpected -> {:error, {:unexpected_response, unexpected}}
    end
  end

  defp normalize_futures_balances(assets) do
    Map.new(assets, fn a ->
      {a["asset"],
       %{
         wallet_balance: a["walletBalance"],
         unrealized_profit: a["unrealizedProfit"],
         margin_balance: a["marginBalance"],
         available_balance: a["availableBalance"]
       }}
    end)
  end

  defp fetch_binance_coinm_futures_balances(auth_credentials) do
    with {:ok, validated_credentials} <- validate_auth_credentials(auth_credentials),
         {:ok, assets} <- call_coinm_futures_api(validated_credentials) do
      {:ok, %{type: :coinm_futures, balances: normalize_futures_balances(assets)}}
    end
  end

  defp call_coinm_futures_api(validated_credentials) do
    opts = if map_size(validated_credentials) > 0, do: [auth_credentials: validated_credentials], else: []

    case CoinmFutures.get_account(%{}, opts) do
      {:ok, %{"assets" => assets}} when is_list(assets) -> {:ok, assets}
      {:error, _reason} = error -> error
      unexpected -> {:error, {:unexpected_response, unexpected}}
    end
  end

  defp fetch_binance_portfolio_margin_balances(auth_credentials) do
    # Validate auth credentials before use
    case validate_auth_credentials(auth_credentials) do
      {:ok, validated_credentials} ->
        opts = if map_size(validated_credentials) > 0, do: [auth_credentials: validated_credentials], else: []

        case PortfolioMargin.account_information(%{}, opts) do
          {:ok, %{"uniMMR" => uni_mmr, "accountEquity" => equity, "accountMaintMargin" => margin}} ->
            # Portfolio margin returns unified metrics instead of individual balances
            {:ok,
             %{
               type: :portfolio_margin,
               uni_mmr: uni_mmr,
               account_equity: equity,
               maint_margin: margin
             }}

          {:error, _reason} = error ->
            error

          unexpected ->
            {:error, {:unexpected_response, unexpected}}
        end

      {:error, _reason} = error ->
        # Return auth validation error
        error
    end
  end

  defp fetch_bybit_balances(params) do
    auth_credentials = Map.get(params, :auth_credentials, %{})
    account_type = Map.get(params, :account_type, :unified)

    with {:ok, validated_credentials} <- validate_auth_credentials(auth_credentials),
         {:ok, coins} <- call_bybit_api(validated_credentials, account_type) do
      {:ok, %{type: account_type, balances: normalize_bybit_balances(coins)}}
    end
  end

  defp call_bybit_api(validated_credentials, account_type) do
    opts = if map_size(validated_credentials) > 0, do: [auth_credentials: validated_credentials], else: []

    case Unified.get_wallet_balance(%{accountType: to_string(account_type)}, opts) do
      {:ok, %{"result" => %{"list" => [account | _]}}} -> {:ok, Map.get(account, "coin", [])}
      {:error, _reason} = error -> error
      unexpected -> {:error, {:unexpected_response, unexpected}}
    end
  end

  defp normalize_bybit_balances(coins) do
    Map.new(coins, fn c ->
      {c["coin"],
       %{
         wallet_balance: c["walletBalance"],
         available: c["availableToWithdraw"],
         total_position_value: c["totalPositionValue"],
         total_order_margin: c["totalOrderMargin"],
         equity: c["equity"]
       }}
    end)
  end

  defp extract_min_notional(:binance, %{filters: filters}) when is_list(filters) do
    # Find NOTIONAL or MIN_NOTIONAL filter
    notional_filter =
      Enum.find(filters, fn
        %{"filterType" => "NOTIONAL"} -> true
        %{"filterType" => "MIN_NOTIONAL"} -> true
        _ -> false
      end)

    case notional_filter do
      %{"minNotional" => min_str} when is_binary(min_str) ->
        Decimal.new(min_str)

      _ ->
        # Default for Binance
        Decimal.new(@binance_default_min_notional)
    end
  end

  defp extract_min_notional(:bybit, _symbol_info) do
    # Bybit doesn't provide minNotional in instrument info directly
    # It's typically in the risk limit tier info
    # Use conservative default
    Decimal.new("1.00")
  end

  defp extract_min_notional(exchange, _symbol_info) do
    # Fallback to default for unknown exchanges
    default_min = Config.default_min_notional(exchange)
    Decimal.new(default_min)
  end

  # Helper functions
end
