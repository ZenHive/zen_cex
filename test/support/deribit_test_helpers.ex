defmodule ZenCex.DeribitTestHelpers do
  @moduledoc """
  Test helpers for Deribit integration tests.

  Provides utilities for getting safe test prices from the real Deribit testnet
  to ensure orders are placed far enough from market to avoid fills while staying
  within Deribit's price rejection limits (~20% from market).

  ## Usage

      import ZenCex.DeribitTestHelpers

      setup do
        {:ok, client} = Deribit.WebSocket.connect(...)
        {:ok, client} = Deribit.WebSocket.authenticate(client)

        safe_buy_price = get_safe_buy_price(client, "BTC-PERPETUAL")
        safe_sell_price = get_safe_sell_price(client, "BTC-PERPETUAL")

        {:ok, client: client, safe_buy_price: safe_buy_price, safe_sell_price: safe_sell_price}
      end
  """

  alias ZenCex.Adapters.Deribit.Parser
  alias ZenCex.Adapters.Deribit.Rpc
  alias ZenCex.Adapters.Deribit.WebSocket

  @default_price 100_000.0
  @buy_price_offset 0.80
  @sell_price_offset 1.20

  @doc """
  Gets the current market price for an instrument from Deribit.

  Fetches the ticker data and returns the mark price (preferred) or last price.
  Falls back to a reasonable default (#{@default_price}) if the request fails.

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL", "ETH-PERPETUAL")

  ## Returns

  Float representing the current market price.

  ## Examples

      price = get_current_market_price(client, "BTC-PERPETUAL")
      # => 95432.5

      # Fallback on error
      price = get_current_market_price(bad_client, "INVALID")
      # => #{@default_price}
  """
  @spec get_current_market_price(WebSocket.t(), String.t()) :: float()
  def get_current_market_price(client, instrument) do
    request = Rpc.ticker(instrument)

    case WebSocket.send_request_sync(client, request) do
      {:ok, response} ->
        case Parser.parse_ticker(response) do
          {:ok, ticker} -> ticker[:mark_price] || ticker[:last_price] || @default_price
          {:error, _} -> @default_price
        end

      {:error, _} ->
        # Fallback to a reasonable default if ticker fails
        @default_price
    end
  end

  @doc """
  Calculates a safe buy price (20% below market).

  This ensures test orders won't fill while staying within Deribit's acceptable
  price range (Deribit rejects orders too far from market, e.g., 50%+).

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")

  ## Returns

  Integer representing a safe buy price (truncated).

  ## Examples

      # If market price is 100,000
      safe_buy_price = get_safe_buy_price(client, "BTC-PERPETUAL")
      # => 80000 (20% below market)
  """
  @spec get_safe_buy_price(WebSocket.t(), String.t()) :: integer()
  def get_safe_buy_price(client, instrument) do
    current_price = get_current_market_price(client, instrument)
    # Ensure we have a valid number before arithmetic
    safe_price = if is_number(current_price), do: current_price, else: @default_price
    # Place buy order 20% below market (safe from fills, within Deribit limits)
    trunc(safe_price * @buy_price_offset)
  end

  @doc """
  Calculates a safe sell price (20% above market).

  This ensures test orders won't fill while staying within Deribit's acceptable
  price range (Deribit rejects orders too far from market, e.g., 50%+).

  ## Parameters

  - `client` - Authenticated Deribit WebSocket client
  - `instrument` - Instrument name (e.g., "BTC-PERPETUAL")

  ## Returns

  Integer representing a safe sell price (truncated).

  ## Examples

      # If market price is 100,000
      safe_sell_price = get_safe_sell_price(client, "BTC-PERPETUAL")
      # => 120000 (20% above market)
  """
  @spec get_safe_sell_price(WebSocket.t(), String.t()) :: integer()
  def get_safe_sell_price(client, instrument) do
    current_price = get_current_market_price(client, instrument)
    # Ensure we have a valid number before arithmetic
    safe_price = if is_number(current_price), do: current_price, else: @default_price
    # Place sell order 20% above market (safe from fills, within Deribit limits)
    trunc(safe_price * @sell_price_offset)
  end
end
