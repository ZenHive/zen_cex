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

  # Symbol length constraints for margin trading pairs
  @min_symbol_length 2
  @max_symbol_length 10

  # Compiled regex patterns for better performance
  # USD-M Futures: ends with USDT/USDC, optional 6-digit date suffix (YYMMDD format)
  @um_futures_pattern ~r/^[A-Z]+(?:USDT|USDC)(?:_\d{6})?$/i

  # COIN-M Futures: ends with USD_ followed by contract type or 6-digit date
  @cm_futures_pattern ~r/^[A-Z]+USD_(?:PERP|QUARTER|CURRENT_QUARTER|NEXT_QUARTER|\d{6})$/i

  # Margin: standard trading pair format with 2-10 chars for each asset
  @margin_pattern Regex.compile!(
                    "^[A-Z]{#{@min_symbol_length},#{@max_symbol_length}}[A-Z]{#{@min_symbol_length},#{@max_symbol_length}}$",
                    "i"
                  )

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

      # USD-M Futures: Ends with USDC (supported since 2024)
      String.ends_with?(symbol_upper, "USDC") ->
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
  # Note: This function is only called with values from detect_from_symbol/1,
  # which never returns :unknown (it defaults to :margin for unrecognized patterns)
  defp valid_symbol_format?(symbol, product_type) do
    case product_type do
      :um_futures ->
        # Must end with USDT or USDC, may have date suffix
        String.match?(symbol, @um_futures_pattern)

      :cm_futures ->
        # Must have underscore with PERP, QUARTER, or date
        String.match?(symbol, @cm_futures_pattern)

      :margin ->
        # Standard trading pair format
        String.match?(symbol, @margin_pattern)
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
      :unknown -> nil
    end
  end
end
