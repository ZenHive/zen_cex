defmodule ZenCex.Adapters.Deribit.MarketData do
  @moduledoc """
  Market data access layer for Deribit exchange.

  Provides thin wrappers around the ETS cache (populated by WebSocket subscriptions)
  and direct request functions for non-subscription data.

  ## Architecture

  Unlike Binance/Bybit which are REST-first, Deribit is WebSocket-first. Market data
  flows through two paths:

  ### Subscription-based data (WebSocket → ETS → MarketData)
  1. Subscribe to channels via `WebSocket.subscribe/2`
  2. WebSocket handlers automatically update ETS cache
  3. This module reads from ETS cache

  Subscription functions return `{:error, :not_subscribed}` when no active subscription exists.

  ### Direct request data (MarketData → WebSocket → Deribit)
  1. Make one-time requests via WebSocket
  2. Cache results with appropriate TTL
  3. No subscription required

  ## Usage

      # Connect and authenticate
      {:ok, client} = Deribit.WebSocket.connect(
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      )
      {:ok, client} = Deribit.WebSocket.authenticate(client)

      # Subscribe to market data (enables subscription-based functions)
      {:ok, client} = MarketData.subscribe_order_book(client, "BTC-PERPETUAL")
      {:ok, client} = MarketData.subscribe_ticker(client, "BTC-PERPETUAL")

      # Read from ETS cache (requires active subscription)
      {:ok, orderbook} = MarketData.get_order_book("BTC-PERPETUAL")
      {:ok, ticker} = MarketData.get_ticker("BTC-PERPETUAL")

      # Direct requests (no subscription needed)
      {:ok, instruments} = MarketData.get_instruments(client, "BTC")

  ## Instrument Names

  Deribit uses instrument names instead of symbols:
  - Perpetuals: `"BTC-PERPETUAL"`, `"ETH-PERPETUAL"`
  - Futures: `"BTC-29MAR24"`, `"ETH-29MAR24"`
  - Options: `"BTC-29MAR24-50000-C"`, `"ETH-29MAR24-3000-P"`
  """

  alias ZenCex.Adapters.Deribit.Parser
  alias ZenCex.Adapters.Deribit.Rpc
  alias ZenCex.Adapters.Deribit.WebSocket
  alias ZenCex.Cache.Market

  # Cache TTLs (in seconds)
  @instruments_cache_ttl 300
  @price_index_cache_ttl 1

  # Subscription-based functions (read from ETS cache)

  @doc """
  Gets order book data from ETS cache.

  Requires an active WebSocket subscription to the order book channel.
  Use `subscribe_order_book/2` to start receiving updates.

  ## Parameters
  - `instrument` - Instrument name (e.g., `"BTC-PERPETUAL"`)

  ## Returns
  - `{:ok, orderbook}` - Order book data with bids/asks
  - `{:error, :not_subscribed}` - No active subscription for this instrument

  ## Examples

      # First, subscribe to order book updates
      {:ok, client} = MarketData.subscribe_order_book(client, "BTC-PERPETUAL")

      # Then read from cache
      {:ok, %{bids: bids, asks: asks}} = MarketData.get_order_book("BTC-PERPETUAL")

  """
  @spec get_order_book(String.t()) :: {:ok, map()} | {:error, :not_subscribed}
  def get_order_book(instrument) when is_binary(instrument) do
    case Market.get_orderbook(:deribit, instrument) do
      {:ok, orderbook} -> {:ok, orderbook}
      {:error, _} -> {:error, :not_subscribed}
    end
  end

  @doc """
  Gets ticker data from ETS cache.

  Requires an active WebSocket subscription to the ticker channel.
  Use `subscribe_ticker/2` to start receiving updates.

  ## Parameters
  - `instrument` - Instrument name (e.g., `"BTC-PERPETUAL"`)

  ## Returns
  - `{:ok, ticker}` - Ticker data with prices and volume
  - `{:error, :not_subscribed}` - No active subscription for this instrument

  ## Examples

      # First, subscribe to ticker updates
      {:ok, client} = MarketData.subscribe_ticker(client, "BTC-PERPETUAL")

      # Then read from cache
      {:ok, ticker} = MarketData.get_ticker("BTC-PERPETUAL")

  """
  @spec get_ticker(String.t()) :: {:ok, map()} | {:error, :not_subscribed}
  def get_ticker(instrument) when is_binary(instrument) do
    case Market.get_ticker(:deribit, instrument) do
      {:ok, ticker} -> {:ok, ticker}
      {:error, _} -> {:error, :not_subscribed}
    end
  end

  @doc """
  Gets the last trade from ETS cache.

  Requires an active WebSocket subscription to the trades channel.
  Use `subscribe_trades/2` to start receiving updates.

  ## Parameters
  - `instrument` - Instrument name (e.g., `"BTC-PERPETUAL"`)

  ## Returns
  - `{:ok, trade}` - Last trade data
  - `{:error, :not_subscribed}` - No active subscription for this instrument

  ## Examples

      # First, subscribe to trade updates
      {:ok, client} = MarketData.subscribe_trades(client, "BTC-PERPETUAL")

      # Then read from cache
      {:ok, trade} = MarketData.get_last_trade("BTC-PERPETUAL")

  """
  @spec get_last_trade(String.t()) :: {:ok, map()} | {:error, :not_subscribed}
  def get_last_trade(instrument) when is_binary(instrument) do
    case Market.get_last_trade(:deribit, instrument) do
      {:ok, trade} -> {:ok, trade}
      {:error, _} -> {:error, :not_subscribed}
    end
  end

  # Direct request functions (make WebSocket requests)

  @doc """
  Gets list of available instruments for a currency.

  Makes a direct WebSocket request (no subscription needed) and caches
  the result for 5 minutes since instruments don't change frequently.

  ## Parameters
  - `client` - WebSocket client
  - `currency` - Currency code (`"BTC"`, `"ETH"`, `"SOL"`, etc.)

  ## Returns
  - `{:ok, instruments}` - List of instrument definitions
  - `{:error, reason}` - Request failed

  ## Examples

      {:ok, instruments} = MarketData.get_instruments(client, "BTC")

      # instruments is a list of maps like:
      # [%{
      #   instrument_name: "BTC-PERPETUAL",
      #   kind: :future,
      #   base_currency: "BTC",
      #   quote_currency: "USD",
      #   tick_size: 0.5,
      #   contract_size: 10.0,
      #   ...
      # }]

  """
  @spec get_instruments(WebSocket.t(), String.t()) :: {:ok, list(map())} | {:error, term()}
  def get_instruments(client, currency) when is_binary(currency) do
    # Check cache first
    cache_key = "instruments_#{currency}"

    case Market.get_market_data(:deribit, "", cache_key) do
      {:ok, cached} ->
        {:ok, cached}

      {:error, _} ->
        # Make direct WebSocket request
        request = Rpc.get_instruments(currency)

        with {:ok, response} <- WebSocket.send_request_sync(client, request),
             {:ok, instruments} <- Parser.parse_instruments(response) do
          # Cache for 5 minutes
          Market.put_market_data(:deribit, "", cache_key, instruments, @instruments_cache_ttl)
          {:ok, instruments}
        end
    end
  end

  @doc """
  Gets the current price index for an instrument.

  Makes a direct WebSocket request and caches the result for 1 second.
  The price index is used for mark price calculations.

  ## Parameters
  - `client` - WebSocket client
  - `index_name` - Index name (e.g., `"btc_usd"`, `"eth_usd"`)

  ## Returns
  - `{:ok, price_index}` - Price index data
  - `{:error, reason}` - Request failed

  ## Examples

      {:ok, price_index} = MarketData.get_price_index(client, "btc_usd")

  """
  @spec get_price_index(WebSocket.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_price_index(client, index_name) when is_binary(index_name) do
    # Check cache first (very short TTL)
    cache_key = "price_index_#{index_name}"

    case Market.get_market_data(:deribit, "", cache_key) do
      {:ok, cached} ->
        {:ok, cached}

      {:error, _} ->
        # Make direct WebSocket request
        with {:ok, response} <-
               WebSocket.send_request(client, "public/get_index_price", %{index_name: index_name}),
             {:ok, price_index} <- Parser.parse_generic(response) do
          # Cache for 1 second
          Market.put_market_data(:deribit, "", cache_key, price_index, @price_index_cache_ttl)
          {:ok, price_index}
        end
    end
  end

  @doc """
  Gets funding rate history for a perpetual instrument.

  Makes a direct WebSocket request for historical funding data.
  Results are not cached as they're typically used for one-time analysis.

  ## Parameters
  - `client` - WebSocket client
  - `instrument` - Instrument name (e.g., `"BTC-PERPETUAL"`)
  - `opts` - Options:
    - `:start_timestamp` - Start time in milliseconds (optional)
    - `:end_timestamp` - End time in milliseconds (optional)
    - `:limit` - Maximum number of records (default: 100)

  ## Returns
  - `{:ok, funding_history}` - List of funding rate records
  - `{:error, reason}` - Request failed

  ## Examples

      {:ok, history} = MarketData.get_funding_history(client, "BTC-PERPETUAL", %{limit: 50})

  """
  @spec get_funding_history(WebSocket.t(), String.t(), map()) ::
          {:ok, list(map())} | {:error, term()}
  def get_funding_history(client, instrument, opts \\ %{}) when is_binary(instrument) do
    params =
      Map.merge(
        %{instrument_name: instrument},
        opts
      )

    with {:ok, response} <-
           WebSocket.send_request(client, "public/get_funding_rate_history", params) do
      Parser.parse_generic(response)
    end
  end

  # Subscription helper functions

  @doc """
  Subscribes to order book updates for an instrument.

  Convenience wrapper around `WebSocket.subscribe/2` that builds the
  correct Deribit channel name.

  ## Parameters
  - `client` - WebSocket client
  - `instrument` - Instrument name (e.g., `"BTC-PERPETUAL"`)
  - `opts` - Options:
    - `:interval` - Update interval (`:100ms`, `:raw`, default: `:raw`)

  ## Returns
  - `{:ok, client}` - Updated client with subscription
  - `{:error, reason}` - Subscription failed

  ## Channel Format
  - Raw updates: `"book.{instrument}.raw"`
  - 100ms updates: `"book.{instrument}.100ms"`

  ## Examples

      # Subscribe to raw order book updates (every change)
      {:ok, client} = MarketData.subscribe_order_book(client, "BTC-PERPETUAL")

      # Subscribe to 100ms aggregated updates
      {:ok, client} = MarketData.subscribe_order_book(client, "BTC-PERPETUAL", %{interval: :100ms})

  """
  @spec subscribe_order_book(WebSocket.t(), String.t(), map()) ::
          {:ok, WebSocket.t()} | {:error, term()}
  def subscribe_order_book(client, instrument, opts \\ %{}) when is_binary(instrument) do
    interval = Map.get(opts, :interval, :raw)
    channel = "book.#{instrument}.#{interval}"
    WebSocket.subscribe(client, [channel])
  end

  @doc """
  Subscribes to ticker updates for an instrument.

  Convenience wrapper around `WebSocket.subscribe/2` that builds the
  correct Deribit channel name.

  ## Parameters
  - `client` - WebSocket client
  - `instrument` - Instrument name (e.g., `"BTC-PERPETUAL"`)
  - `opts` - Options:
    - `:interval` - Update interval (`:100ms`, `:raw`, default: `:raw`)

  ## Returns
  - `{:ok, client}` - Updated client with subscription
  - `{:error, reason}` - Subscription failed

  ## Channel Format
  - Raw updates: `"ticker.{instrument}.raw"`
  - 100ms updates: `"ticker.{instrument}.100ms"`

  ## Examples

      # Subscribe to raw ticker updates
      {:ok, client} = MarketData.subscribe_ticker(client, "BTC-PERPETUAL")

      # Subscribe to 100ms aggregated updates
      {:ok, client} = MarketData.subscribe_ticker(client, "BTC-PERPETUAL", %{interval: :100ms})

  """
  @spec subscribe_ticker(WebSocket.t(), String.t(), map()) ::
          {:ok, WebSocket.t()} | {:error, term()}
  def subscribe_ticker(client, instrument, opts \\ %{}) when is_binary(instrument) do
    interval = Map.get(opts, :interval, :raw)
    channel = "ticker.#{instrument}.#{interval}"
    WebSocket.subscribe(client, [channel])
  end

  @doc """
  Subscribes to trade updates for an instrument.

  Convenience wrapper around `WebSocket.subscribe/2` that builds the
  correct Deribit channel name.

  ## Parameters
  - `client` - WebSocket client
  - `instrument` - Instrument name (e.g., `"BTC-PERPETUAL"`)
  - `opts` - Options:
    - `:interval` - Update interval (`:100ms`, `:raw`, default: `:raw`)

  ## Returns
  - `{:ok, client}` - Updated client with subscription
  - `{:error, reason}` - Subscription failed

  ## Channel Format
  - Raw updates: `"trades.{instrument}.raw"`
  - 100ms updates: `"trades.{instrument}.100ms"`

  ## Examples

      # Subscribe to raw trade updates (every trade)
      {:ok, client} = MarketData.subscribe_trades(client, "BTC-PERPETUAL")

      # Subscribe to 100ms aggregated updates
      {:ok, client} = MarketData.subscribe_trades(client, "BTC-PERPETUAL", %{interval: :100ms})

  """
  @spec subscribe_trades(WebSocket.t(), String.t(), map()) ::
          {:ok, WebSocket.t()} | {:error, term()}
  def subscribe_trades(client, instrument, opts \\ %{}) when is_binary(instrument) do
    interval = Map.get(opts, :interval, :raw)
    channel = "trades.#{instrument}.#{interval}"
    WebSocket.subscribe(client, [channel])
  end
end
