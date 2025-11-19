defmodule ZenCex.Examples.DeribitTrading do
  @moduledoc """
  Complete trading workflow examples for Deribit WebSocket API.

  Demonstrates Deribit's WebSocket-first architecture with JSON-RPC 2.0 protocol.
  Unlike Binance/Bybit which are REST-first, all Deribit operations use WebSocket
  for both trading and market data.

  ## Product Types

  - **Perpetuals**: `"BTC-PERPETUAL"`, `"ETH-PERPETUAL"`, `"SOL-PERPETUAL"`
  - **Futures**: `"BTC-29MAR24"`, `"ETH-29MAR24"` (dated contracts)
  - **Options**: `"BTC-29MAR24-50000-C"`, `"ETH-29MAR24-3000-P"`
  - **Spot**: `"BTC_USDC"`, `"ETH_USDC"` (zero-fee markets)

  ## Usage

      # Connect and authenticate
      {:ok, client} = ZenCex.Examples.DeribitTrading.connect_and_authenticate()

      # Place limit buy order
      {:ok, order} = ZenCex.Examples.DeribitTrading.buy_limit(
        client,
        "BTC-PERPETUAL",
        100,
        45000
      )

      # Place market sell order
      {:ok, order} = ZenCex.Examples.DeribitTrading.sell_market(client, "BTC-PERPETUAL", 100)

      # Cancel order
      {:ok, result} = ZenCex.Examples.DeribitTrading.cancel_order(client, order[:order_id])

      # Get positions
      {:ok, positions} = ZenCex.Examples.DeribitTrading.get_positions(client, "BTC")

  ## Requirements

  - DERIBIT_TESTNET_API_KEY and DERIBIT_TESTNET_API_SECRET environment variables
  - Or DERIBIT_CLIENT_ID and DERIBIT_CLIENT_SECRET (OAuth credentials)
  - Testnet account at https://test.deribit.com/
  """

  alias ZenCex.Adapters.Deribit.{Trading, WebSocket}

  @doc """
  Connect to Deribit WebSocket and authenticate.

  This is the first step for all Deribit operations. The returned client
  maintains a persistent WebSocket connection with authentication.

  ## Examples

      {:ok, client} = ZenCex.Examples.DeribitTrading.connect_and_authenticate()
      # Client is now ready for trading and market data operations

  ## Returns

  - `{:ok, %WebSocket{authenticated: true, ...}}` - Authenticated client
  - `{:error, reason}` - Connection or authentication failed
  """
  @spec connect_and_authenticate(keyword()) :: {:ok, WebSocket.t()} | {:error, term()}
  def connect_and_authenticate(opts \\ []) do
    client_id = opts[:client_id] || System.get_env("DERIBIT_TESTNET_API_KEY")
    client_secret = opts[:client_secret] || System.get_env("DERIBIT_TESTNET_API_SECRET")

    with {:ok, client} <- WebSocket.connect(client_id: client_id, client_secret: client_secret),
         {:ok, client} <- WebSocket.authenticate(client) do
      {:ok, client}
    end
  end

  @doc """
  Place a limit buy order.

  Limit orders specify an exact price and will only execute at that price or better.

  ## Examples

      # Buy 100 contracts of BTC-PERPETUAL at $45,000
      {:ok, order} = ZenCex.Examples.DeribitTrading.buy_limit(
        client,
        "BTC-PERPETUAL",
        100,
        45000
      )

      order[:order_id]     # "12345678"
      order[:order_state]  # :open
      order[:price]        # 45000.0

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `amount` - Quantity in contracts (integer)
  - `price` - Limit price (number)

  ## Returns

  - `{:ok, %{order_id: ..., order_state: :open, ...}}` - Order placed
  - `{:error, reason}` - Order failed (invalid instrument, price, etc.)
  """
  @spec buy_limit(WebSocket.t(), String.t(), integer(), number()) ::
          {:ok, map()} | {:error, term()}
  def buy_limit(client, instrument, amount, price)
      when is_binary(instrument) and is_integer(amount) and is_number(price) do
    Trading.buy(client, instrument, amount, %{
      type: "limit",
      price: price
    })
  end

  @doc """
  Place a market buy order.

  Market orders execute immediately at the current best available price.

  ## Examples

      # Buy 100 contracts of BTC-PERPETUAL at market price
      {:ok, order} = ZenCex.Examples.DeribitTrading.buy_market(client, "BTC-PERPETUAL", 100)

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `instrument` - Instrument name
  - `amount` - Quantity in contracts

  ## Returns

  - `{:ok, %{order_id: ..., order_state: :filled, ...}}` - Order executed
  - `{:error, reason}` - Order failed
  """
  @spec buy_market(WebSocket.t(), String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def buy_market(client, instrument, amount)
      when is_binary(instrument) and is_integer(amount) do
    Trading.buy(client, instrument, amount, %{type: "market"})
  end

  @doc """
  Place a limit sell order.

  ## Examples

      # Sell 100 contracts of BTC-PERPETUAL at $50,000
      {:ok, order} = ZenCex.Examples.DeribitTrading.sell_limit(
        client,
        "BTC-PERPETUAL",
        100,
        50000
      )

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `instrument` - Instrument name
  - `amount` - Quantity in contracts
  - `price` - Limit price

  ## Returns

  - `{:ok, %{order_id: ..., order_state: :open, ...}}` - Order placed
  - `{:error, reason}` - Order failed
  """
  @spec sell_limit(WebSocket.t(), String.t(), integer(), number()) ::
          {:ok, map()} | {:error, term()}
  def sell_limit(client, instrument, amount, price)
      when is_binary(instrument) and is_integer(amount) and is_number(price) do
    Trading.sell(client, instrument, amount, %{
      type: "limit",
      price: price
    })
  end

  @doc """
  Place a market sell order.

  ## Examples

      # Sell 100 contracts of BTC-PERPETUAL at market price
      {:ok, order} = ZenCex.Examples.DeribitTrading.sell_market(client, "BTC-PERPETUAL", 100)

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `instrument` - Instrument name
  - `amount` - Quantity in contracts

  ## Returns

  - `{:ok, %{order_id: ..., order_state: :filled, ...}}` - Order executed
  - `{:error, reason}` - Order failed
  """
  @spec sell_market(WebSocket.t(), String.t(), integer()) :: {:ok, map()} | {:error, term()}
  def sell_market(client, instrument, amount)
      when is_binary(instrument) and is_integer(amount) do
    Trading.sell(client, instrument, amount, %{type: "market"})
  end

  @doc """
  Cancel an order.

  ## Examples

      {:ok, order} = ZenCex.Examples.DeribitTrading.buy_limit(client, "BTC-PERPETUAL", 100, 45000)
      {:ok, result} = ZenCex.Examples.DeribitTrading.cancel_order(client, order[:order_id])

      result[:order_id]     # "12345678"
      result[:order_state]  # :cancelled

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `order_id` - Order ID to cancel

  ## Returns

  - `{:ok, %{order_id: ..., order_state: :cancelled, ...}}` - Order canceled
  - `{:error, reason}` - Cancelation failed (order not found, already filled, etc.)
  """
  @spec cancel_order(WebSocket.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_order(client, order_id) when is_binary(order_id) do
    Trading.cancel(client, order_id)
  end

  @doc """
  Cancel all orders for an instrument or currency.

  ## Examples

      # Cancel all BTC-PERPETUAL orders
      {:ok, count} = ZenCex.Examples.DeribitTrading.cancel_all_orders(client, instrument: "BTC-PERPETUAL")

      # Cancel all BTC orders (all instruments)
      {:ok, count} = ZenCex.Examples.DeribitTrading.cancel_all_orders(client, currency: "BTC")

      # Cancel all orders
      {:ok, count} = ZenCex.Examples.DeribitTrading.cancel_all_orders(client)

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `opts` - Options keyword list:
    - `:instrument` - Instrument name to filter by
    - `:currency` - Currency to filter by ("BTC", "ETH", etc.)

  ## Returns

  - `{:ok, count}` - Number of orders canceled
  - `{:error, reason}` - Cancelation failed
  """
  @spec cancel_all_orders(WebSocket.t(), keyword()) :: {:ok, integer()} | {:error, term()}
  def cancel_all_orders(client, opts \\ []) do
    # Build options map for Trading.cancel_all
    cancel_opts = %{}

    cancel_opts =
      if Keyword.has_key?(opts, :instrument) do
        Map.put(cancel_opts, :instrument_name, Keyword.get(opts, :instrument))
      else
        cancel_opts
      end

    cancel_opts =
      if Keyword.has_key?(opts, :currency) do
        Map.put(cancel_opts, :currency, Keyword.get(opts, :currency))
      else
        cancel_opts
      end

    Trading.cancel_all(client, cancel_opts)
  end

  @doc """
  Get open orders for an instrument or currency.

  ## Examples

      # Get all open orders
      {:ok, orders} = ZenCex.Examples.DeribitTrading.get_open_orders(client)

      # Get open orders for specific instrument
      {:ok, orders} = ZenCex.Examples.DeribitTrading.get_open_orders(client, instrument: "BTC-PERPETUAL")

      # Get open orders for all BTC instruments
      {:ok, orders} = ZenCex.Examples.DeribitTrading.get_open_orders(client, currency: "BTC")

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `opts` - Options keyword list:
    - `:instrument` - Instrument name to filter by
    - `:currency` - Currency to filter by ("BTC", "ETH", etc.)

  ## Returns

  - `{:ok, [%{order_id: ..., price: ..., ...}, ...]}` - List of open orders
  - `{:error, reason}` - Query failed
  """
  @spec get_open_orders(WebSocket.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_open_orders(client, opts \\ []) do
    # Build options map for Trading.get_open_orders
    query_opts = %{}

    query_opts =
      if Keyword.has_key?(opts, :instrument) do
        Map.put(query_opts, :instrument_name, Keyword.get(opts, :instrument))
      else
        query_opts
      end

    query_opts =
      if Keyword.has_key?(opts, :currency) do
        Map.put(query_opts, :currency, Keyword.get(opts, :currency))
      else
        query_opts
      end

    Trading.get_open_orders(client, query_opts)
  end

  @doc """
  Edit an existing order.

  Changes the price and/or amount of an open order.

  ## Examples

      {:ok, order} = ZenCex.Examples.DeribitTrading.buy_limit(client, "BTC-PERPETUAL", 100, 45000)

      # Change price to 46000 and amount to 150
      {:ok, edited} = ZenCex.Examples.DeribitTrading.edit_order(client, order[:order_id], %{
        price: 46000,
        amount: 150
      })

      edited[:price]   # 46000.0
      edited[:amount]  # 150.0

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `order_id` - Order ID to edit
  - `options` - Map with `:price` and/or `:amount` keys

  ## Returns

  - `{:ok, %{order_id: ..., price: ..., amount: ..., ...}}` - Order edited
  - `{:error, reason}` - Edit failed
  """
  @spec edit_order(WebSocket.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def edit_order(client, order_id, options)
      when is_binary(order_id) and is_map(options) do
    Trading.edit_order(client, order_id, options)
  end

end
