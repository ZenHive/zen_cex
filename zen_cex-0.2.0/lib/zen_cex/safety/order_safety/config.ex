defmodule ZenCex.Safety.OrderSafety.Config do
  @moduledoc """
  Configuration for OrderSafety module.

  Provides configurable values for price deviation limits, cache TTLs,
  and other safety parameters. Values can be overridden via application
  configuration or environment variables.

  ## Configuration Priority

  1. Environment variables (highest priority)
  2. Application config
  3. Default values (lowest priority)

  ## Environment Variables

  - `ORDER_SAFETY_MAX_PRICE_DEVIATION_PERCENT` - Default price deviation for all exchanges (default: 20)
  - `ORDER_SAFETY_<EXCHANGE>_MAX_PRICE_DEVIATION_PERCENT` - Per-exchange price deviation
  - `ORDER_SAFETY_IDEMPOTENCY_WINDOW_MINUTES` - Duplicate order detection window (default: 30)
  - `ORDER_SAFETY_CLEANUP_INTERVAL_SECONDS` - Cache cleanup frequency (default: 60)
  - `ORDER_SAFETY_WEBSOCKET_DATA_MAX_AGE_SECONDS` - WebSocket data freshness (default: 5)
  - `ORDER_SAFETY_<EXCHANGE>_MIN_NOTIONAL` - Per-exchange minimum order value

  ## Application Config Example

      config :zen_cex, :order_safety,
        max_price_deviation_percent: 25,
        idempotency_window_minutes: 15,
        cleanup_interval_seconds: 30,
        websocket_data_max_age_seconds: 10,
        exchanges: [
          binance: [
            max_price_deviation_percent: 30,
            min_notional: "5.00"
          ],
          deribit: [
            max_price_deviation_percent: 50,  # Higher for derivatives
            min_notional: "10.00"
          ]
        ]
  """

  alias ZenCex.Config.TimeConstants

  # Default price deviation percentage (can be overridden)
  @default_max_price_deviation_percent 20

  # Get cache TTLs from TimeConstants (already environment-aware)
  @cache_ttls TimeConstants.cache_ttls()

  @doc """
  Gets the maximum allowed price deviation percentage.

  Can be configured via:
  - Application config: `config :zen_cex, :order_safety, max_price_deviation_percent: 15`
  - Environment variable: `ORDER_SAFETY_MAX_PRICE_DEVIATION_PERCENT=15`

  ## Returns
  Integer representing the maximum percentage deviation allowed (default: 20)

  ## Examples

      iex> Config.max_price_deviation_percent()
      20
  """
  @spec max_price_deviation_percent() :: non_neg_integer()
  def max_price_deviation_percent do
    # Check environment variable first
    case System.get_env("ORDER_SAFETY_MAX_PRICE_DEVIATION_PERCENT") do
      nil ->
        # Check application config
        :zen_cex
        |> Application.get_env(:order_safety, [])
        |> Keyword.get(:max_price_deviation_percent, @default_max_price_deviation_percent)

      env_value ->
        String.to_integer(env_value)
    end
  end

  @doc """
  Gets price deviation limits for a specific exchange.

  Allows per-exchange configuration of price deviation limits.

  ## Parameters
  - `exchange` - The exchange atom (e.g., :binance, :bybit)

  ## Returns
  Integer representing the maximum percentage deviation for that exchange

  ## Examples

      iex> Config.max_price_deviation_percent(:binance)
      20

      iex> Config.max_price_deviation_percent(:deribit)
      30  # Might allow higher deviation for derivatives
  """
  @spec max_price_deviation_percent(atom()) :: non_neg_integer()
  def max_price_deviation_percent(exchange) do
    # Check for exchange-specific override
    env_key = "ORDER_SAFETY_#{String.upcase(to_string(exchange))}_MAX_PRICE_DEVIATION_PERCENT"

    case System.get_env(env_key) do
      nil ->
        # Check application config for exchange-specific setting
        exchange_config =
          :zen_cex
          |> Application.get_env(:order_safety, [])
          |> Keyword.get(:exchanges, [])
          |> Keyword.get(exchange, [])
          |> Keyword.get(:max_price_deviation_percent)

        exchange_config || max_price_deviation_percent()

      env_value ->
        String.to_integer(env_value)
    end
  end

  @doc """
  Gets the idempotency window in milliseconds.

  Can be configured via:
  - Application config: `config :zen_cex, :order_safety, idempotency_window_minutes: 15`
  - Environment variable: `ORDER_SAFETY_IDEMPOTENCY_WINDOW_MINUTES=15`

  ## Returns
  Integer representing the window in milliseconds (default: 30 minutes)
  """
  @spec idempotency_window_ms() :: non_neg_integer()
  def idempotency_window_ms do
    minutes =
      case System.get_env("ORDER_SAFETY_IDEMPOTENCY_WINDOW_MINUTES") do
        nil ->
          :zen_cex
          |> Application.get_env(:order_safety, [])
          |> Keyword.get(:idempotency_window_minutes, 30)

        env_value ->
          String.to_integer(env_value)
      end

    minutes * 60 * 1000
  end

  @doc """
  Gets the cleanup interval in milliseconds.

  Can be configured via:
  - Application config: `config :zen_cex, :order_safety, cleanup_interval_seconds: 30`
  - Environment variable: `ORDER_SAFETY_CLEANUP_INTERVAL_SECONDS=30`

  ## Returns
  Integer representing the cleanup interval in milliseconds (default: 60 seconds)
  """
  @spec cleanup_interval_ms() :: non_neg_integer()
  def cleanup_interval_ms do
    seconds =
      case System.get_env("ORDER_SAFETY_CLEANUP_INTERVAL_SECONDS") do
        nil ->
          :zen_cex
          |> Application.get_env(:order_safety, [])
          |> Keyword.get(:cleanup_interval_seconds, 60)

        env_value ->
          String.to_integer(env_value)
      end

    seconds * 1000
  end

  @doc """
  Gets cache TTL configuration.

  Returns the cache TTLs from TimeConstants which are already environment-aware.

  ## Returns
  Map with TTL values in milliseconds for :symbol_info, :price, :min_notional
  """
  @spec cache_ttls() :: map()
  def cache_ttls do
    @cache_ttls
  end

  @doc """
  Gets WebSocket data freshness threshold.

  Can be configured via:
  - Application config: `config :zen_cex, :order_safety, websocket_data_max_age_seconds: 10`
  - Environment variable: `ORDER_SAFETY_WEBSOCKET_DATA_MAX_AGE_SECONDS=10`

  ## Returns
  Integer representing maximum age in milliseconds (default: 5 seconds)
  """
  @spec websocket_data_max_age_ms() :: non_neg_integer()
  def websocket_data_max_age_ms do
    seconds =
      case System.get_env("ORDER_SAFETY_WEBSOCKET_DATA_MAX_AGE_SECONDS") do
        nil ->
          :zen_cex
          |> Application.get_env(:order_safety, [])
          |> Keyword.get(:websocket_data_max_age_seconds, 5)

        env_value ->
          String.to_integer(env_value)
      end

    seconds * 1000
  end

  @doc """
  Gets the minimum notional value for an exchange.

  Can be configured per exchange via:
  - Application config: `config :zen_cex, :order_safety, exchanges: [binance: [min_notional: "15.00"]]`
  - Environment variable: `ORDER_SAFETY_BINANCE_MIN_NOTIONAL=15.00`

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  String representing the default minimum notional (e.g., "10.00")
  """
  @spec default_min_notional(atom()) :: String.t()
  def default_min_notional(exchange) do
    env_key = "ORDER_SAFETY_#{String.upcase(to_string(exchange))}_MIN_NOTIONAL"

    case System.get_env(env_key) do
      nil ->
        # Check application config
        exchange_config =
          :zen_cex
          |> Application.get_env(:order_safety, [])
          |> Keyword.get(:exchanges, [])
          |> Keyword.get(exchange, [])
          |> Keyword.get(:min_notional)

        exchange_config || default_min_notional_fallback(exchange)

      env_value ->
        env_value
    end
  end

  # Fallback values for each exchange
  defp default_min_notional_fallback(:binance), do: "10.00"
  defp default_min_notional_fallback(:bybit), do: "1.00"
  defp default_min_notional_fallback(:kraken), do: "10.00"
  defp default_min_notional_fallback(:deribit), do: "10.00"
  defp default_min_notional_fallback(_), do: "10.00"
end
