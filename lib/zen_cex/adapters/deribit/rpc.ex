defmodule ZenCex.Adapters.Deribit.Rpc do
  @moduledoc """
  Deribit JSON-RPC method definitions and request builders.

  This module centralizes all Deribit RPC method definitions
  for use with the WebSocket adapter.

  All methods use `ZenWebsocket.JsonRpc.build_request/2` for
  JSON-RPC 2.0 protocol compliance.
  """

  alias ZenWebsocket.JsonRpc

  # Authentication & Session

  @doc """
  Builds an authentication request for Deribit API.

  ## Parameters
  - `client_id` - Your Deribit API client ID
  - `client_secret` - Your Deribit API client secret

  ## Returns
  A JSON-RPC request map for authentication.

  ## Example
      request = auth_request("client_id", "client_secret")
  """
  @spec auth_request(String.t(), String.t()) :: map()
  def auth_request(client_id, client_secret) do
    {:ok, request} =
      JsonRpc.build_request("public/auth", %{
        grant_type: "client_credentials",
        client_id: client_id,
        client_secret: client_secret
      })

    request
  end

  @doc """
  Sets the heartbeat interval for the WebSocket connection.

  ## Parameters
  - `interval` - Heartbeat interval in seconds (default: 30)

  ## Returns
  A JSON-RPC request map for setting heartbeat.

  ## Example
      request = set_heartbeat(30)
  """
  @spec set_heartbeat(integer()) :: map()
  def set_heartbeat(interval \\ 30) do
    {:ok, request} = JsonRpc.build_request("public/set_heartbeat", %{interval: interval})
    request
  end

  @doc """
  Builds a test request to verify the connection is alive.

  ## Returns
  A JSON-RPC request map for connection testing.

  ## Example
      request = test_request()
  """
  @spec test_request() :: map()
  def test_request do
    {:ok, request} = JsonRpc.build_request("public/test", %{})
    request
  end

  # Subscriptions

  @doc """
  Subscribes to one or more channels for real-time data.

  ## Parameters
  - `channels` - List of channel names to subscribe to

  ## Returns
  A JSON-RPC request map for subscription.

  ## Example
      request = subscribe(["book.BTC-PERPETUAL.raw", "ticker.ETH-PERPETUAL.raw"])
  """
  @spec subscribe(list(String.t())) :: map()
  def subscribe(channels) when is_list(channels) do
    {:ok, request} = JsonRpc.build_request("public/subscribe", %{channels: channels})
    request
  end

  @doc """
  Unsubscribes from one or more channels.

  ## Parameters
  - `channels` - List of channel names to unsubscribe from

  ## Returns
  A JSON-RPC request map for unsubscription.

  ## Example
      request = unsubscribe(["book.BTC-PERPETUAL.raw"])
  """
  @spec unsubscribe(list(String.t())) :: map()
  def unsubscribe(channels) when is_list(channels) do
    {:ok, request} = JsonRpc.build_request("public/unsubscribe", %{channels: channels})
    request
  end

  # Market Data

  @doc """
  Retrieves available trading instruments for a currency.

  ## Parameters
  - `currency` - Currency code (e.g., "BTC", "ETH")

  ## Returns
  A JSON-RPC request map for retrieving instruments.

  ## Example
      request = get_instruments("BTC")
  """
  @spec get_instruments(String.t()) :: map()
  def get_instruments(currency) do
    {:ok, request} = JsonRpc.build_request("public/get_instruments", %{currency: currency})
    request
  end

  @doc """
  Retrieves the order book for a specific instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `depth` - Order book depth (default: 10)

  ## Returns
  A JSON-RPC request map for order book data.

  ## Example
      request = get_order_book("BTC-PERPETUAL", 10)
  """
  @spec get_order_book(String.t(), integer()) :: map()
  def get_order_book(instrument, depth \\ 10) do
    {:ok, request} =
      JsonRpc.build_request("public/get_order_book", %{
        instrument_name: instrument,
        depth: depth
      })

    request
  end

  @doc """
  Gets ticker data for a specific instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")

  ## Returns
  A JSON-RPC request map for ticker data.

  ## Example
      request = ticker("BTC-PERPETUAL")
  """
  @spec ticker(String.t()) :: map()
  def ticker(instrument) do
    {:ok, request} = JsonRpc.build_request("public/ticker", %{instrument_name: instrument})
    request
  end

  # Trading (Private)

  @doc """
  Creates a buy order for the specified instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `amount` - Order amount in contracts
  - `opts` - Additional order options (type, price, etc.)

  ## Returns
  A JSON-RPC request map for buy order.

  ## Example
      request = buy("BTC-PERPETUAL", 100, %{type: "limit", price: 45000})
  """
  @spec buy(String.t(), number(), map()) :: map()
  def buy(instrument, amount, opts \\ %{}) do
    params =
      Map.merge(
        %{
          instrument_name: instrument,
          amount: amount
        },
        opts
      )

    {:ok, request} = JsonRpc.build_request("private/buy", params)
    request
  end

  @doc """
  Creates a sell order for the specified instrument.

  ## Parameters
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")
  - `amount` - Order amount in contracts
  - `opts` - Additional order options (type, price, etc.)

  ## Returns
  A JSON-RPC request map for sell order.

  ## Example
      request = sell("BTC-PERPETUAL", 100, %{type: "limit", price: 46000})
  """
  @spec sell(String.t(), number(), map()) :: map()
  def sell(instrument, amount, opts \\ %{}) do
    params =
      Map.merge(
        %{
          instrument_name: instrument,
          amount: amount
        },
        opts
      )

    {:ok, request} = JsonRpc.build_request("private/sell", params)
    request
  end

  @doc """
  Cancels an existing order by ID.

  ## Parameters
  - `order_id` - The order ID to cancel

  ## Returns
  A JSON-RPC request map for order cancellation.

  ## Example
      request = cancel("ETH-12345678")
  """
  @spec cancel(String.t()) :: map()
  def cancel(order_id) do
    {:ok, request} = JsonRpc.build_request("private/cancel", %{order_id: order_id})
    request
  end

  @doc """
  Retrieves all open orders with optional filters.

  ## Parameters
  - `opts` - Optional filters (instrument, type, etc.)

  ## Returns
  A JSON-RPC request map for retrieving open orders.

  ## Example
      request = get_open_orders(%{instrument_name: "BTC-PERPETUAL"})
      request = get_open_orders(%{})
  """
  @spec get_open_orders(map()) :: map()
  def get_open_orders(opts \\ %{}) do
    {:ok, request} = JsonRpc.build_request("private/get_open_orders", opts)
    request
  end
end
