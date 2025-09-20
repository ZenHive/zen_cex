defmodule ZenCex.WebSocket.Base do
  @moduledoc """
  Base behavior for WebSocket adapters.

  Provides common interface for exchange-specific WebSocket implementations.
  Each exchange adapter must implement this behavior to ensure consistent
  WebSocket handling across different exchanges.

  ## Implementation Notes

  - Start simple: Direct connections for development
  - Add supervision only for production
  - Maximum 5 public functions per module (zen_websocket rule)
  - Store market data in ETS for fast access
  - Use telemetry for monitoring
  """

  @doc """
  Connects to the exchange WebSocket endpoint.

  ## Returns
  - `{:ok, connection}` - WebSocket connection client
  - `{:error, reason}` - Connection failure
  """
  @callback connect(opts :: keyword()) :: {:ok, ZenWebsocket.Client.t()} | {:error, term()}

  @doc """
  Subscribes to market data streams.

  ## Parameters
  - `connection` - WebSocket connection client
  - `streams` - List of streams to subscribe to

  ## Returns
  - `:ok` - Successfully subscribed
  - `{:error, reason}` - Subscription failure
  """
  @callback subscribe(connection :: ZenWebsocket.Client.t(), streams :: list(String.t())) :: :ok | {:error, term()}

  @doc """
  Unsubscribes from market data streams.

  ## Parameters
  - `connection` - WebSocket connection client
  - `streams` - List of streams to unsubscribe from

  ## Returns
  - `:ok` - Successfully unsubscribed
  - `{:error, reason}` - Unsubscription failure
  """
  @callback unsubscribe(connection :: ZenWebsocket.Client.t(), streams :: list(String.t())) :: :ok | {:error, term()}

  @doc """
  Gets the current connection state.

  ## Parameters
  - `connection` - WebSocket connection client

  ## Returns
  - `{:ok, state}` - Connection state
  - `{:error, reason}` - Failed to get state
  """
  @callback state(connection :: ZenWebsocket.Client.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Closes the WebSocket connection.

  ## Parameters
  - `connection` - WebSocket connection client

  ## Returns
  - `:ok` - Connection closed
  """
  @callback close(connection :: ZenWebsocket.Client.t()) :: :ok
end
