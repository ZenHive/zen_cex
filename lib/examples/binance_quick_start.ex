defmodule ZenCex.Examples.BinanceQuickStart do
  @moduledoc """
  Quick start examples for Binance API integration.

  Demonstrates the basic workflow from README.md:
  - Checking server connectivity
  - Getting account balances
  - Passing custom authentication credentials

  All functions return `{:ok, result}` or `{:error, reason}` tuples.

  ## Usage

      # Check if server is reachable
      {:ok, _time} = ZenCex.Examples.BinanceQuickStart.check_connectivity()

      # Get account balances (requires API credentials in env)
      {:ok, balances} = ZenCex.Examples.BinanceQuickStart.get_account_balances()

      # Use custom credentials
      creds = %{api_key: "key", api_secret: "secret"}
      {:ok, balances} = ZenCex.Examples.BinanceQuickStart.get_balances_with_credentials(creds)

  ## Requirements

  - For authenticated operations: Set BINANCE_TESTNET_API_KEY and BINANCE_TESTNET_API_SECRET
  - For testnet: Credentials should be testnet credentials
  """

  alias ZenCex.Adapters.Binance.Common
  alias ZenCex.Adapters.Binance.Spot

  @doc """
  Check server connectivity by getting server time.

  This is the first step in any integration - verify you can reach the exchange.

  ## Examples

      iex> {:ok, time_data} = ZenCex.Examples.BinanceQuickStart.check_connectivity()
      iex> is_map(time_data)
      true

  ## Returns

  - `{:ok, %{"serverTime" => timestamp}}` - Server is reachable
  - `{:error, reason}` - Connection failed
  """
  @spec check_connectivity() :: {:ok, map()} | {:error, term()}
  def check_connectivity do
    Common.get_server_time()
  end

  @doc """
  Get account balances using environment variable credentials.

  Reads API_KEY and API_SECRET from environment and returns all asset balances.

  ## Examples

      # With testnet credentials in environment
      {:ok, balances} = ZenCex.Examples.BinanceQuickStart.get_account_balances()
      # Returns list of balance objects

  ## Returns

  - `{:ok, [%{"asset" => "BTC", "free" => "0.001", ...}, ...]}` - Account balances
  - `{:error, reason}` - Authentication failed or other error

  ## Environment Variables

  - BINANCE_TESTNET_API_KEY
  - BINANCE_TESTNET_API_SECRET
  """
  @spec get_account_balances(keyword()) :: {:ok, list(map())} | {:error, term()}
  def get_account_balances(opts \\ []) do
    Spot.get_balances(%{}, opts)
  end

  @doc """
  Get balances using custom authentication credentials.

  Demonstrates passing credentials directly without using environment variables.
  Useful for multi-account scenarios or credential rotation.

  ## Examples

      creds = %{
        api_key: "your_api_key",
        api_secret: "your_api_secret",
        testnet: true
      }
      {:ok, balances} = ZenCex.Examples.BinanceQuickStart.get_balances_with_credentials(creds)

  ## Parameters

  - `credentials` - Map with `:api_key`, `:api_secret`, and optionally `:testnet`

  ## Returns

  - `{:ok, [%{"asset" => ..., "free" => ..., ...}, ...]}` - Account balances
  - `{:error, reason}` - Authentication failed or other error
  """
  @spec get_balances_with_credentials(map()) :: {:ok, list(map())} | {:error, term()}
  def get_balances_with_credentials(credentials) when is_map(credentials) do
    opts = [auth_credentials: credentials]
    Spot.get_balances(%{}, opts)
  end

  @doc """
  Place a simple market buy order with custom credentials.

  Demonstrates the full workflow: credentials → order placement → response.

  ## Examples

      creds = %{api_key: "key", api_secret: "secret", testnet: true}
      params = %{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: "0.001"}
      {:ok, order} = ZenCex.Examples.BinanceQuickStart.place_market_order(params, creds)

  ## Parameters

  - `order_params` - Map with `:symbol`, `:side`, `:type`, `:quantity`
  - `credentials` - Map with `:api_key`, `:api_secret`, `:testnet`

  ## Returns

  - `{:ok, %{"orderId" => ..., "status" => ..., ...}}` - Order placed successfully
  - `{:error, reason}` - Order placement failed

  ## Security Warning

  This is an example only. Never hardcode credentials in production code.
  """
  @spec place_market_order(map(), map()) :: {:ok, map()} | {:error, term()}
  def place_market_order(order_params, credentials) when is_map(order_params) and is_map(credentials) do
    opts = [auth_credentials: credentials]
    Spot.place_order(order_params, opts)
  end
end
