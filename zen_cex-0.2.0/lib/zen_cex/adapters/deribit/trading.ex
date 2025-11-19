defmodule ZenCex.Adapters.Deribit.Trading do
  @moduledoc """
  Deribit trading operations via WebSocket.

  Ultra-thin wrappers over Deribit.Rpc trading methods.
  All operations use JSON-RPC 2.0 over WebSocket.

  ## Order Types
  - `:limit` - Limit order with specified price
  - `:market` - Market order (immediate execution)
  - `:stop_limit` - Stop-limit order with trigger price
  - `:stop_market` - Stop-market order

  ## Time in Force Options
  - `:good_til_cancelled` (GTC) - Order remains until filled or cancelled (default)
  - `:fill_or_kill` (FOK) - Fill entire order immediately or cancel
  - `:immediate_or_cancel` (IOC) - Fill what you can immediately, cancel rest

  ## Common Options
  - `type` - Order type (`:limit`, `:market`, `:stop_limit`, `:stop_market`)
  - `price` - Limit price (required for limit orders)
  - `time_in_force` - Time in force option (default: `:good_til_cancelled`)
  - `post_only` - Boolean, maker-only orders (no taker fee)
  - `reduce_only` - Boolean, only reduce position (cannot increase)
  - `label` - String, user-defined order label (max 32 chars)
  - `trigger_price` - Trigger price for stop orders
  - `trigger` - Trigger type (`:index_price`, `:mark_price`, `:last_price`)

  ## Examples

      # Connect and authenticate
      {:ok, client} = WebSocket.connect(client_id: "...", client_secret: "...")
      {:ok, client} = WebSocket.authenticate(client)

      # Place limit buy order
      {:ok, order} = Trading.buy(client, "BTC-PERPETUAL", 100, %{
        type: "limit",
        price: 45000
      })

      # Place market sell order
      {:ok, order} = Trading.sell(client, "ETH-PERPETUAL", 50, %{type: "market"})

      # Cancel order
      {:ok, cancelled} = Trading.cancel(client, order[:order_id])

      # Edit order
      {:ok, edited} = Trading.edit_order(client, order[:order_id], %{
        price: 46000,
        amount: 150
      })

      # Get open orders
      {:ok, orders} = Trading.get_open_orders(client, %{instrument_name: "BTC-PERPETUAL"})
  """

  alias ZenCex.Adapters.Deribit.Parser
  alias ZenCex.Adapters.Deribit.Rpc
  alias ZenCex.Adapters.Deribit.WebSocket

  @doc """
  Place a buy order.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `amount` - Order size in contracts
  - `opts` - Order options (type, price, time_in_force, etc.)

  ## Examples

      # Limit order
      buy(client, "BTC-PERPETUAL", 100, %{
        type: "limit",
        price: 45000,
        time_in_force: "good_til_cancelled"
      })

      # Market order
      buy(client, "BTC-PERPETUAL", 50, %{type: "market"})

      # Post-only limit order
      buy(client, "ETH-PERPETUAL", 10, %{
        type: "limit",
        price: 2800,
        post_only: true
      })
  """
  @spec buy(WebSocket.t(), String.t(), number(), map()) :: {:ok, map()} | {:error, term()}
  def buy(client, instrument, amount, opts \\ %{}) do
    request = Rpc.buy(instrument, amount, opts)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      Parser.parse_order(response)
    end
  end

  @doc """
  Place a sell order.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `instrument` - Instrument name
  - `amount` - Order size in contracts
  - `opts` - Order options (same as buy/4)

  ## Examples

      sell(client, "BTC-PERPETUAL", 100, %{type: "limit", price: 46000})
  """
  @spec sell(WebSocket.t(), String.t(), number(), map()) :: {:ok, map()} | {:error, term()}
  def sell(client, instrument, amount, opts \\ %{}) do
    request = Rpc.sell(instrument, amount, opts)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      Parser.parse_order(response)
    end
  end

  @doc """
  Cancel an order by ID.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `order_id` - Order ID to cancel (e.g., "ETH-349253")

  ## Examples

      cancel(client, "ETH-349253")
  """
  @spec cancel(WebSocket.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def cancel(client, order_id) do
    request = Rpc.cancel(order_id)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      Parser.parse_order(response)
    end
  end

  @doc """
  Edit an existing order.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `order_id` - Order ID to edit
  - `opts` - Update options (amount, price, etc.)

  ## Options
  - `amount` - New order size
  - `price` - New limit price
  - `post_only` - Change post-only status
  - `reduce_only` - Change reduce-only status

  ## Examples

      edit_order(client, "ETH-349253", %{price: 2850, amount: 15})
  """
  @spec edit_order(WebSocket.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def edit_order(client, order_id, opts \\ %{}) do
    request = Rpc.edit_order(order_id, opts)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      Parser.parse_order(response)
    end
  end

  @doc """
  Get all open orders with optional filters.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `opts` - Optional filters

  ## Options
  - `instrument_name` - Filter by specific instrument
  - `currency` - Filter by currency (e.g., "BTC", "ETH")
  - `kind` - Filter by kind ("future", "option", "spot")
  - `type` - Filter by order type ("limit", "market")

  ## Examples

      # All open orders
      get_open_orders(client)

      # Open orders for specific instrument
      get_open_orders(client, %{instrument_name: "BTC-PERPETUAL"})

      # All BTC open orders
      get_open_orders(client, %{currency: "BTC"})
  """
  @spec get_open_orders(WebSocket.t(), map()) :: {:ok, list(map())} | {:error, term()}
  def get_open_orders(client, opts \\ %{}) do
    request = Rpc.get_open_orders(opts)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      Parser.parse_orders(response)
    end
  end

  @doc """
  Cancel all orders with optional filters.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `opts` - Cancellation filters

  ## Options
  - `instrument_name` - Cancel for specific instrument
  - `currency` - Cancel all orders for currency
  - `kind` - Cancel by kind ("future", "option")
  - `type` - Cancel by order type

  ## Examples

      # Cancel all orders for BTC-PERPETUAL
      cancel_all(client, %{instrument_name: "BTC-PERPETUAL"})

      # Cancel all BTC orders
      cancel_all(client, %{currency: "BTC"})
  """
  @spec cancel_all(WebSocket.t(), map()) :: {:ok, integer()} | {:error, term()}
  def cancel_all(client, opts \\ %{}) do
    request = Rpc.cancel_all(opts)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      # Response is just the count of cancelled orders
      case response do
        %{"result" => count} when is_integer(count) -> {:ok, count}
        %{result: count} when is_integer(count) -> {:ok, count}
        other -> {:error, {:unexpected_response, other}}
      end
    end
  end

  @doc """
  Get order history with filters.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `opts` - History filters (instrument_name or currency REQUIRED)

  ## Options
  - `instrument_name` - Filter by instrument (required if currency not provided)
  - `currency` - Filter by currency (required if instrument not provided)
  - `count` - Number of orders to return (default: 20)
  - `offset` - Pagination offset

  ## Examples

      get_order_history(client, %{instrument_name: "BTC-PERPETUAL", count: 50})
      get_order_history(client, %{currency: "BTC"})
  """
  @spec get_order_history(WebSocket.t(), map()) :: {:ok, list(map())} | {:error, term()}
  def get_order_history(client, opts) do
    request = Rpc.get_order_history(opts)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      Parser.parse_orders(response)
    end
  end

  @doc """
  Get user trade history.

  ## Parameters
  - `client` - WebSocket adapter (authenticated)
  - `opts` - Trade history filters (instrument_name, currency, or order_id REQUIRED)

  ## Options
  - `instrument_name` - Filter by instrument
  - `currency` - Filter by currency
  - `order_id` - Filter by specific order
  - `count` - Number of trades to return (default: 20)
  - `offset` - Pagination offset

  ## Examples

      get_user_trades(client, %{instrument_name: "BTC-PERPETUAL"})
      get_user_trades(client, %{order_id: "ETH-349253"})
  """
  @spec get_user_trades(WebSocket.t(), map()) :: {:ok, list(map())} | {:error, term()}
  def get_user_trades(client, opts) do
    request = Rpc.get_user_trades(opts)

    with {:ok, response} <- WebSocket.send_request_sync(client, request) do
      Parser.parse_trades(response)
    end
  end
end
