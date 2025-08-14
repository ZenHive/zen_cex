defmodule ZenCex.Behaviors.MarketData do
  @moduledoc """
  Behavior defining the WebSocket market data contract for exchange adapters.

  CRITICAL: Only public market data streams are supported.
  No authentication, no user streams, no trading over WebSocket.
  """

  @doc """
  Starts the market data GenServer for this exchange.

  ## Parameters
    - opts: Keyword list of options

  ## Returns
    - `{:ok, pid}` on successful start
    - `{:error, reason}` on failure
  """
  @callback start_link(keyword()) :: GenServer.on_start()

  @doc """
  Subscribes to market data channels.

  ## Parameters
    - channels: List of channel names to subscribe to

  ## Returns
    - `:ok` if subscription request was sent
    - `{:error, reason}` if unable to subscribe

  ## Notes
    - Only PUBLIC channels allowed
    - No authenticated streams
    - Examples: ticker, trades, orderbook
  """
  @callback subscribe(list(String.t())) :: :ok | {:error, term()}

  @doc """
  Unsubscribes from market data channels.

  ## Parameters
    - channels: List of channel names to unsubscribe from

  ## Returns
    - `:ok` if unsubscribe request was sent
    - `{:error, reason}` if unable to unsubscribe
  """
  @callback unsubscribe(list(String.t())) :: :ok | {:error, term()}

  @doc """
  Returns the current WebSocket connection status.

  ## Returns
    - `:connected` - WebSocket is connected and healthy
    - `:connecting` - Currently attempting to connect
    - `:disconnected` - Not connected
    - `{:error, reason}` - Connection failed with reason
  """
  @callback connection_status() :: :connected | :connecting | :disconnected | {:error, term()}

  @doc """
  Returns list of currently subscribed channels.

  ## Returns
    - List of channel names currently subscribed to
  """
  @callback subscribed_channels() :: list(String.t())

  @doc """
  Handles incoming WebSocket frames.

  ## Parameters
    - frame: The WebSocket frame (text or binary)
    - state: Current GenServer state

  ## Returns
    - `{:ok, new_state}` after processing
    - `{:error, reason, state}` on processing error

  ## Notes
    - Binance: JSON text frames
    - Kraken: Binary compressed frames (gzip/zlib)
    - Deribit: JSON-RPC format
  """
  @callback handle_frame({:text | :binary, binary()}, term()) ::
              {:ok, term()} | {:error, term(), term()}

  @doc """
  Returns the WebSocket URL for public market data.

  ## Parameters
    - environment: `:prod` or `:test`

  ## Returns
    - String containing the WebSocket URL
  """
  @callback websocket_url(atom()) :: String.t()

  @doc """
  Returns the ping/heartbeat interval in milliseconds.

  ## Returns
    - Integer milliseconds between ping messages

  ## Notes
    - Binance: 20 minutes (1200000ms)
    - Kraken: 8 seconds (8000ms) CRITICAL
    - Deribit: 30 seconds (30000ms)
  """
  @callback ping_interval() :: pos_integer()

  @optional_callbacks handle_frame: 2
end
