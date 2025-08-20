defmodule ZenCex.Adapters.Binance.ProductDetector do
  @moduledoc """
  Detects Binance product types from symbols and order parameters.

  Portfolio Margin supports multiple product types:
  - **UM (USD-M Futures)**: USDT-margined perpetual and quarterly futures
  - **CM (COIN-M Futures)**: Coin-margined perpetual and quarterly futures  
  - **Margin**: Cross and isolated margin trading

  ## Symbol Patterns

  ### USD-M Futures (UM)
  - Perpetual: BTCUSDT, ETHUSDT (ends with USDT)
  - Quarterly: BTCUSDT_240329 (USDT with expiry date)

  ### COIN-M Futures (CM)
  - Perpetual: BTCUSD_PERP
  - Quarterly: BTCUSD_240329, ETHUSD_QUARTER

  ### Margin
  - Standard pairs: BTCUSDT, ETHBTC (spot symbols used in margin context)

  ## Usage

      iex> ProductDetector.detect_from_symbol("BTCUSDT")
      :um_futures

      iex> ProductDetector.detect_from_symbol("BTCUSD_PERP")
      :cm_futures

      iex> ProductDetector.detect(%{product_type: "UM"})
      :um_futures
  """

  @type product_type :: :um_futures | :cm_futures | :margin | :unknown

  @doc """
  Detects product type from order parameters.

  Checks for explicit product_type parameter first, then falls back to symbol analysis.
  """
  @spec detect(map()) :: product_type()
  def detect(%{product_type: type}) when is_binary(type) do
    detect_from_product_type(type)
  end

  def detect(%{symbol: symbol}) when is_binary(symbol) do
    detect_from_symbol(symbol)
  end

  def detect(_), do: :unknown

  @doc """
  Detects product type from explicit product_type parameter.

  Binance API accepts: "UM", "CM", "MARGIN"
  """
  @spec detect_from_product_type(String.t()) :: product_type()
  def detect_from_product_type(type) when is_binary(type) do
    case String.upcase(type) do
      "UM" -> :um_futures
      "CM" -> :cm_futures
      "MARGIN" -> :margin
      _ -> :unknown
    end
  end

  @doc """
  Detects product type from trading symbol.

  Uses pattern matching to identify futures vs margin products:
  - Symbols with underscores are typically futures (BTCUSD_PERP, BTCUSD_240329)
  - Symbols ending in USDT without underscores are typically UM futures
  - Standard pairs without special suffixes are margin when used in portfolio context
  """
  @spec detect_from_symbol(String.t()) :: product_type()
  def detect_from_symbol(symbol) when is_binary(symbol) do
    symbol_upper = String.upcase(symbol)

    cond do
      # COIN-M Futures: Contains underscore (BTCUSD_PERP, BTCUSD_240329)
      String.contains?(symbol_upper, "_") ->
        :cm_futures

      # USD-M Futures: Ends with USDT (most common perpetuals)
      String.ends_with?(symbol_upper, "USDT") ->
        :um_futures

      # USD-M Futures: Ends with BUSD (less common but valid)
      String.ends_with?(symbol_upper, "BUSD") ->
        :um_futures

      # Default to margin for standard pairs in portfolio context
      # This includes pairs like BTCETH, ETHBTC, etc.
      true ->
        :margin
    end
  end

  @doc """
  Validates if a symbol is valid for the detected product type.

  Returns `{:ok, product_type}` if valid, `{:error, reason}` if invalid.
  """
  @spec validate_symbol(String.t()) :: {:ok, product_type()} | {:error, String.t()}
  def validate_symbol(symbol) when is_binary(symbol) do
    product_type = detect_from_symbol(symbol)

    if valid_symbol_format?(symbol, product_type) do
      {:ok, product_type}
    else
      {:error, "Invalid symbol format for #{product_type}: #{symbol}"}
    end
  end

  # Validates symbol format based on product type
  defp valid_symbol_format?(symbol, product_type) do
    case product_type do
      :um_futures ->
        # Must end with USDT or BUSD, may have date suffix
        String.match?(symbol, ~r/^[A-Z]+(?:USDT|BUSD)(?:_\d{6})?$/i)

      :cm_futures ->
        # Must have underscore with PERP, QUARTER, or date
        String.match?(symbol, ~r/^[A-Z]+USD_(?:PERP|QUARTER|CURRENT_QUARTER|NEXT_QUARTER|\d{6})$/i)

      :margin ->
        # Standard trading pair format
        String.match?(symbol, ~r/^[A-Z]{2,10}[A-Z]{2,10}$/i)

      _ ->
        false
    end
  end

  @doc """
  Returns the appropriate endpoint module for the detected product type.
  """
  @spec get_endpoint_module(product_type()) :: module() | nil
  def get_endpoint_module(product_type) do
    case product_type do
      :um_futures -> ZenCex.Adapters.Binance.UsdmFutures
      :cm_futures -> ZenCex.Adapters.Binance.CoinmFutures
      :margin -> ZenCex.Adapters.Binance.Spot
      _ -> nil
    end
  end
end
