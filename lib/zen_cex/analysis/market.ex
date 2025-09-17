defmodule ZenCex.Analysis.Market do
  @moduledoc """
  Advanced market data analysis including funding rate calculations and cross-exchange comparisons.

  This module provides functions for:
  - Calculating annualized funding rates (APR)
  - Comparing funding rates across exchanges
  - Identifying arbitrage opportunities
  - Analyzing funding rate trends

  All calculations support both single-exchange and multi-exchange operations.
  """

  alias ZenCex.Adapters.Binance
  alias ZenCex.Adapters.Bybit
  alias ZenCex.Core.Cache

  require Logger

  # Cache duration for market data that changes frequently
  @cache_ttl_seconds 60

  # Minimum rate delta (0.05%) to consider as arbitrage opportunity
  # Below this threshold, fees would likely eliminate profit
  @arbitrage_threshold "0.0005"

  # Minimum rate change (0.001%) to detect trend direction
  # Filters out noise in funding rate fluctuations
  @trend_threshold "0.00001"

  # Standard funding interval for perpetual futures (8 hours)
  @default_funding_interval_hours 8

  # Maximum concurrent API calls to avoid overwhelming exchanges
  @max_api_concurrency 5

  # API call timeout (10 seconds) to prevent hanging requests
  @api_timeout_ms 10_000

  # Number of funding periods per day (funding typically happens every 8 hours)
  @funding_periods_per_day 3

  # Days per year for annualized calculations
  @days_per_year 365

  @typedoc "Exchange identifier"
  @type exchange :: :binance | :bybit | atom()

  @typedoc "Configuration map for exchange API access"
  @type config :: %{
          required(:api_key) => String.t(),
          required(:api_secret) => String.t(),
          optional(:testnet) => boolean(),
          optional(:account_type) => atom()
        }

  @typedoc "Funding rate APR calculation result"
  @type apr_result :: %{
          hourly: Decimal.t(),
          daily: Decimal.t(),
          annual: Decimal.t()
        }

  @typedoc "Funding rate comparison result"
  @type comparison_result :: %{
          String.t() => map()
        }

  @doc """
  Calculates annualized funding rates for a symbol from one or multiple exchanges.

  ## Parameters
    - exchange_or_exchanges: Single exchange atom or list of exchange atoms
    - symbol: Trading pair symbol (e.g., "BTCUSDT")
    - config_or_configs: Single config map or list of configs (matching exchanges)

  ## Returns
    - Single exchange: `{:ok, apr_result}`
    - Multiple exchanges: `{:ok, %{exchange => apr_result}}`
    - Error: `{:error, reason}`

  ## Examples

      # Single exchange
      calculate_funding_apr(:binance, "BTCUSDT", config)
      # => {:ok, %{hourly: 0.01, daily: 0.72, annual: 262.8}}

      # Multiple exchanges
      calculate_funding_apr([:binance, :bybit], "BTCUSDT", [binance_config, bybit_config])
      # => {:ok, %{binance: %{...}, bybit: %{...}}}
  """
  @spec calculate_funding_apr(exchange | [exchange], String.t(), config | [config]) ::
          {:ok, apr_result | %{exchange => apr_result}} | {:error, term()}
  def calculate_funding_apr(exchange, symbol, config) when is_atom(exchange) do
    cache_key = build_cache_key("funding_apr", exchange, symbol)

    case Cache.get(cache_key) do
      {:ok, cached_result} ->
        {:ok, cached_result}

      {:error, _reason} ->
        with {:ok, funding_data} <- fetch_funding_rate(exchange, symbol, config),
             {:ok, calculated} <- calculate_apr_from_data(funding_data) do
          Cache.put(cache_key, calculated, @cache_ttl_seconds)
          {:ok, calculated}
        end
    end
  end

  def calculate_funding_apr(exchanges, symbol, configs) when is_list(exchanges) do
    results =
      exchanges
      |> Enum.zip(configs)
      |> Task.async_stream(
        fn {exchange, config} ->
          {exchange, calculate_funding_apr(exchange, symbol, config)}
        end,
        max_concurrency: @max_api_concurrency,
        timeout: @api_timeout_ms,
        on_timeout: :kill_task
      )
      |> Enum.reduce(%{}, fn
        {:ok, {exchange, {:ok, apr}}}, acc ->
          Map.put(acc, exchange, apr)

        {:ok, {exchange, {:error, reason}}}, acc ->
          Logger.debug("Failed to calculate APR for #{exchange}: #{inspect(reason)}")
          acc

        {:exit, reason}, acc ->
          Logger.warning("Task failed when calculating APR: #{inspect(reason)}")
          acc
      end)

    if map_size(results) > 0 do
      {:ok, results}
    else
      {:error, :all_exchanges_failed}
    end
  end

  @doc """
  Compares funding rates across multiple exchanges for arbitrage opportunities.

  ## Parameters
    - exchanges: List of exchange atoms or exchange-config tuples
    - symbols: List of trading pair symbols to compare

  ## Returns
    - `{:ok, comparison_result}` with rate comparisons and arbitrage flags
    - `{:error, reason}` on failure

  ## Examples

      compare_funding_rates([{:binance, config1}, {:bybit, config2}], ["BTCUSDT", "ETHUSDT"])
      # => {:ok, %{
      #       "BTCUSDT" => %{
      #         binance: 0.01,
      #         bybit: 0.008,
      #         delta: 0.002,
      #         arbitrage_opportunity: true
      #       }
      #     }}
  """
  @spec compare_funding_rates([{exchange, config}] | [exchange], [String.t()]) ::
          {:ok, comparison_result} | {:error, term()}
  def compare_funding_rates(exchanges_with_configs, symbols) when is_list(symbols) do
    cache_key = build_comparison_cache_key(exchanges_with_configs, symbols)

    case Cache.get(cache_key) do
      {:ok, cached_result} ->
        {:ok, cached_result}

      {:error, _reason} ->
        with {:ok, comparison} <- fetch_and_compare_rates(exchanges_with_configs, symbols) do
          Cache.put(cache_key, comparison, @cache_ttl_seconds)
          {:ok, comparison}
        end
    end
  end

  @doc """
  Identifies funding arbitrage opportunities based on rate differentials.

  ## Parameters
    - exchanges_with_configs: List of exchange-config tuples
    - opts: Options including:
      - :min_delta - Minimum rate delta to consider (default: 0.001)
      - :symbols - Symbols to analyze (default: ["BTCUSDT", "ETHUSDT"])

  ## Returns
    List of arbitrage opportunities sorted by annual APR delta

  ## Examples

      find_arbitrage_opportunities(exchanges, min_delta: 0.002)
      # => {:ok, [
      #       %{
      #         symbol: "BTCUSDT",
      #         long_exchange: :bybit,
      #         short_exchange: :binance,
      #         delta: 0.003,
      #         annual_apr_delta: 10.95
      #       }
      #     ]}
  """
  @spec find_arbitrage_opportunities([{exchange, config}], keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def find_arbitrage_opportunities(exchanges_with_configs, opts \\ []) do
    min_delta = ensure_decimal(Keyword.get(opts, :min_delta, Decimal.new("0.001")))
    symbols = Keyword.get(opts, :symbols, ["BTCUSDT", "ETHUSDT"])

    with {:ok, comparison} <- compare_funding_rates(exchanges_with_configs, symbols) do
      opportunities =
        comparison
        |> Enum.filter(fn {_symbol, data} ->
          delta = ensure_decimal(Map.get(data, :delta, Decimal.new(0)))

          Map.get(data, :arbitrage_opportunity, false) and
            Decimal.compare(Decimal.abs(delta), min_delta) != :lt
        end)
        |> Enum.map(fn {symbol, data} ->
          build_arbitrage_opportunity(symbol, data)
        end)
        |> Enum.sort_by(& &1.annual_apr_delta, :desc)

      {:ok, opportunities}
    end
  end

  @doc """
  Gets historical funding rate trends for analysis.

  ## Parameters
    - exchange: Exchange atom
    - symbol: Trading pair symbol
    - config: Exchange configuration
    - opts: Options including:
      - :hours - Number of hours of history (default: 24)
      - :limit - Number of data points (default: hours * 3)

  ## Returns
    Trend analysis including average, min, max rates and trend direction

  ## Examples

      get_funding_trend(:binance, "BTCUSDT", config, hours: 24)
      # => {:ok, %{
      #       avg_rate: 0.01,
      #       max_rate: 0.03,
      #       min_rate: -0.01,
      #       trend: :increasing,
      #       volatility: 0.04,
      #       data_points: 72
      #     }}
  """
  @spec get_funding_trend(exchange, String.t(), config, keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_funding_trend(exchange, symbol, config, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    # Calculate limit based on funding interval (typically 8 hours)
    # Default to 3 data points per day (one per 8-hour funding period)
    funding_interval_hours = Keyword.get(opts, :funding_interval_hours, 8)
    # +1 to ensure we have enough data
    default_limit = div(hours, funding_interval_hours) + 1
    limit = Keyword.get(opts, :limit, default_limit)
    cache_key = build_cache_key("funding_trend", exchange, "#{symbol}:#{hours}h")

    case Cache.get(cache_key) do
      {:ok, cached_result} ->
        {:ok, cached_result}

      {:error, _reason} ->
        with {:ok, history} <- fetch_funding_history(exchange, symbol, config, limit),
             {:ok, trend_data} <- analyze_funding_trend(history) do
          # Include the history in the result
          result = Map.put(trend_data, :history, history)
          Cache.put(cache_key, result, @cache_ttl_seconds)
          {:ok, result}
        end
    end
  end

  # Internal functions (exposed for testing)

  @doc false
  def calculate_apr_from_data(funding_data) when is_map(funding_data) do
    rate = ensure_decimal(Map.get(funding_data, :rate, 0))
    interval_hours = Map.get(funding_data, :interval_hours, @default_funding_interval_hours)
    interval_hours_dec = Decimal.new(interval_hours)

    # Funding rate is typically every 8 hours (3 times per day)
    funding_per_day = Decimal.div(Decimal.new(24), interval_hours_dec)

    hourly_rate = Decimal.div(rate, interval_hours_dec)
    daily_rate = Decimal.mult(rate, funding_per_day)
    annual_rate = Decimal.mult(daily_rate, Decimal.new(@days_per_year))

    # Convert to percentage and round
    hundred = Decimal.new(100)

    {:ok,
     %{
       hourly: Decimal.round(Decimal.mult(hourly_rate, hundred), 4),
       daily: Decimal.round(Decimal.mult(daily_rate, hundred), 4),
       annual: Decimal.round(Decimal.mult(annual_rate, hundred), 2)
     }}
  end

  @doc false
  def calculate_apr_from_data(_), do: {:error, :invalid_funding_data}

  @doc false
  def analyze_rate_differences(rates) when map_size(rates) < 2 do
    %{
      insufficient_data: true,
      arbitrage_opportunity: false
    }
  end

  @doc false
  def analyze_rate_differences(rates) do
    # Convert all rates to Decimals
    decimal_rates = Map.new(rates, fn {k, v} -> {k, ensure_decimal(v)} end)
    rate_values = Map.values(decimal_rates)

    max_rate = Enum.max_by(rate_values, &Decimal.to_float/1)
    min_rate = Enum.min_by(rate_values, &Decimal.to_float/1)
    delta = Decimal.sub(max_rate, min_rate)

    # Find which exchanges have max and min rates
    {max_exchange, _} = Enum.find(decimal_rates, fn {_, r} -> Decimal.equal?(r, max_rate) end)
    {min_exchange, _} = Enum.find(decimal_rates, fn {_, r} -> Decimal.equal?(r, min_rate) end)

    base_data =
      Map.merge(decimal_rates, %{
        delta: Decimal.round(delta, 6),
        max_exchange: max_exchange,
        min_exchange: min_exchange,
        # Using configured arbitrage threshold
        arbitrage_opportunity: Decimal.compare(Decimal.abs(delta), Decimal.new(@arbitrage_threshold)) == :gt
      })

    # Add APR delta if arbitrage opportunity exists
    if base_data.arbitrage_opportunity do
      # delta * funding_periods_per_day * days_per_year * 100
      annual_apr_delta =
        delta
        |> Decimal.mult(Decimal.new(@funding_periods_per_day))
        |> Decimal.mult(Decimal.new(@days_per_year))
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(2)

      Map.put(base_data, :annual_apr_delta, annual_apr_delta)
    else
      base_data
    end
  end

  @doc false
  def build_arbitrage_opportunity(symbol, data) do
    %{
      symbol: symbol,
      # Long on exchange with lower funding
      long_exchange: data.min_exchange,
      # Short on exchange with higher funding
      short_exchange: data.max_exchange,
      delta: data.delta,
      annual_apr_delta: Map.get(data, :annual_apr_delta, Decimal.new(0)),
      rates: Map.take(data, [:binance, :bybit, :deribit])
    }
  end

  @doc false
  def analyze_funding_trend(history) when is_list(history) and length(history) > 0 do
    rates =
      Enum.map(history, fn h ->
        ensure_decimal(Map.get(h, :rate, Decimal.new(0)))
      end)

    sum = Enum.reduce(rates, Decimal.new(0), &Decimal.add/2)
    count = Decimal.new(length(rates))
    avg_rate = Decimal.div(sum, count)

    max_rate = Enum.max_by(rates, &Decimal.to_float/1)
    min_rate = Enum.min_by(rates, &Decimal.to_float/1)

    # Calculate trend (simple linear regression slope)
    trend = calculate_trend_direction(rates)

    {:ok,
     %{
       avg_rate: Decimal.round(avg_rate, 6),
       max_rate: Decimal.round(max_rate, 6),
       min_rate: Decimal.round(min_rate, 6),
       trend: trend,
       volatility: Decimal.round(Decimal.sub(max_rate, min_rate), 6),
       data_points: length(rates)
     }}
  end

  @doc false
  def analyze_funding_trend(_), do: {:error, :insufficient_data}

  # Private functions

  defp fetch_funding_rate(:binance, symbol, config) do
    account_type = Map.get(config, :account_type, :futures_usdm)

    case account_type do
      :futures_usdm ->
        case Binance.MarketData.usdm_get_funding_rate(%{symbol: symbol}) do
          {:ok, data} when is_list(data) ->
            # When returning a list (with limit param), take the most recent
            {:ok, normalize_funding_data(List.first(data), :binance)}

          {:ok, data} ->
            # Single object response
            {:ok, normalize_funding_data(data, :binance)}

          error ->
            error
        end

      :futures_coinm ->
        case Binance.MarketData.coinm_get_funding_rate(%{symbol: symbol}) do
          {:ok, data} when is_list(data) ->
            # When returning a list (with limit param), take the most recent
            {:ok, normalize_funding_data(List.first(data), :binance)}

          {:ok, data} ->
            # Single object response
            {:ok, normalize_funding_data(data, :binance)}

          error ->
            error
        end

      _ ->
        {:error, {:unsupported_account_type, account_type}}
    end
  end

  defp fetch_funding_rate(:bybit, symbol, config) do
    account_type = Map.get(config, :account_type, :linear)

    # Bybit includes funding rate in the ticker data
    # We need to use the correct category based on account type
    category =
      case account_type do
        :linear -> "linear"
        :inverse -> "inverse"
        # Default to linear for futures
        _ -> "linear"
      end

    case Bybit.MarketData.get_tickers(%{category: category, symbol: symbol}) do
      {:ok, %{"list" => [ticker | _]}} ->
        {:ok, normalize_funding_data(ticker, :bybit)}

      {:ok, %{"list" => []}} ->
        {:error, {:symbol_not_found, symbol}}

      error ->
        error
    end
  end

  defp fetch_funding_rate(exchange, _symbol, _config) do
    # TODO: Add support for additional exchanges - Kraken (futures), Deribit (perpetuals), OKX (perpetuals)
    {:error, {:unsupported_exchange, exchange}}
  end

  defp fetch_funding_history(:binance, symbol, config, limit) do
    account_type = Map.get(config, :account_type, :futures_usdm)

    case account_type do
      :futures_usdm ->
        # Use the same funding rate endpoint with limit parameter
        case Binance.MarketData.usdm_get_funding_rate(%{symbol: symbol, limit: limit}) do
          {:ok, data} when is_list(data) ->
            {:ok, Enum.map(data, &normalize_funding_data(&1, :binance))}

          {:ok, data} ->
            # Single item, wrap in list
            {:ok, [normalize_funding_data(data, :binance)]}

          error ->
            error
        end

      :futures_coinm ->
        case Binance.MarketData.coinm_get_funding_rate(%{symbol: symbol, limit: limit}) do
          {:ok, data} when is_list(data) ->
            {:ok, Enum.map(data, &normalize_funding_data(&1, :binance))}

          {:ok, data} ->
            # Single item, wrap in list
            {:ok, [normalize_funding_data(data, :binance)]}

          error ->
            error
        end

      _ ->
        {:error, {:unsupported_account_type, account_type}}
    end
  end

  defp fetch_funding_history(:bybit, symbol, config, limit) do
    account_type = Map.get(config, :account_type, :linear)

    # Map account type to Bybit category
    category =
      case account_type do
        :linear -> "linear"
        :inverse -> "inverse"
        # Default to linear for futures
        _ -> "linear"
      end

    case Bybit.MarketData.get_funding_history(%{category: category, symbol: symbol, limit: limit}) do
      {:ok, %{"list" => data}} when is_list(data) ->
        {:ok, Enum.map(data, &normalize_funding_data(&1, :bybit_history))}

      error ->
        error
    end
  end

  defp fetch_funding_history(exchange, _symbol, _config, _limit) do
    # TODO: Add historical funding rate support for additional exchanges - Kraken, Deribit, OKX
    {:error, {:unsupported_exchange, exchange}}
  end

  defp normalize_funding_data(data, :binance) when is_map(data) do
    %{
      rate: parse_decimal(Map.get(data, "lastFundingRate") || Map.get(data, "fundingRate")),
      interval_hours: 8,
      time: parse_timestamp(Map.get(data, "fundingTime") || Map.get(data, "time"))
    }
  end

  defp normalize_funding_data(data, :bybit) when is_map(data) do
    # Current funding rate from ticker endpoint
    %{
      rate: parse_decimal(Map.get(data, "fundingRate")),
      interval_hours: 8,
      time: parse_timestamp(Map.get(data, "nextFundingTime"))
    }
  end

  defp normalize_funding_data(data, :bybit_history) when is_map(data) do
    # Historical funding rate from funding history endpoint
    %{
      rate: parse_decimal(Map.get(data, "fundingRate")),
      interval_hours: 8,
      time: parse_timestamp(Map.get(data, "fundingRateTimestamp"))
    }
  end

  defp normalize_funding_data(data, _exchange), do: data

  defp parse_decimal(nil), do: Decimal.new(0)
  defp parse_decimal(%Decimal{} = value), do: value
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> Decimal.new(0)
    end
  end

  # Helper to ensure a value is a Decimal
  defp ensure_decimal(%Decimal{} = value), do: value
  defp ensure_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp ensure_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp ensure_decimal(value) when is_binary(value), do: parse_decimal(value)
  defp ensure_decimal(_), do: Decimal.new(0)

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(value) when is_binary(value), do: value

  defp parse_timestamp(value) when is_integer(value) do
    # Assuming millisecond timestamp
    value
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp fetch_and_compare_rates(exchanges_with_configs, symbols) do
    comparison =
      Map.new(symbols, fn symbol ->
        rates = fetch_rates_for_symbol(exchanges_with_configs, symbol)
        {symbol, analyze_rate_differences(rates)}
      end)

    {:ok, comparison}
  rescue
    e in [ArgumentError, KeyError, RuntimeError] ->
      Logger.error("Error comparing funding rates: #{Exception.message(e)}")
      {:error, :comparison_failed}

    e ->
      Logger.error("Unexpected error comparing funding rates: #{inspect(e)}")
      {:error, :unexpected_error}
  end

  defp fetch_rates_for_symbol(exchanges_with_configs, symbol) do
    exchanges_with_configs
    |> Task.async_stream(
      fn
        {exchange, config} ->
          {exchange, fetch_funding_rate(exchange, symbol, config)}

        exchange when is_atom(exchange) ->
          # TODO: For backward compatibility - would need config from central configuration management
          {exchange, {:error, :config_required}}
      end,
      max_concurrency: @max_api_concurrency,
      timeout: @api_timeout_ms,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {exchange, {:ok, funding_data}}}, acc ->
        Map.put(acc, exchange, ensure_decimal(Map.get(funding_data, :rate, Decimal.new(0))))

      {:ok, {exchange, {:error, reason}}}, acc ->
        Logger.debug("Failed to fetch funding rate from #{exchange}: #{inspect(reason)}")
        acc

      {:exit, :timeout}, acc ->
        Logger.warning("API call timeout when fetching funding rates")
        acc

      {:exit, reason}, acc ->
        Logger.warning("Task failed when fetching funding rates: #{inspect(reason)}")
        acc
    end)
  end

  defp calculate_trend_direction(rates) when length(rates) < 2, do: :flat

  defp calculate_trend_direction(rates) do
    # Simple trend detection: compare first half average with second half
    mid = div(length(rates), 2)
    {first_half, second_half} = Enum.split(rates, mid)

    first_sum = Enum.reduce(first_half, Decimal.new(0), &Decimal.add/2)
    first_count = Decimal.new(length(first_half))
    first_avg = Decimal.div(first_sum, first_count)

    second_sum = Enum.reduce(second_half, Decimal.new(0), &Decimal.add/2)
    second_count = Decimal.new(length(second_half))
    second_avg = Decimal.div(second_sum, second_count)

    diff = Decimal.sub(second_avg, first_avg)

    threshold = Decimal.new(@trend_threshold)

    cond do
      Decimal.compare(diff, threshold) == :gt -> :increasing
      Decimal.compare(diff, Decimal.negate(threshold)) == :lt -> :decreasing
      true -> :flat
    end
  end

  defp build_cache_key(type, exchange, symbol) do
    "#{type}:#{exchange}:#{symbol}"
  end

  defp build_comparison_cache_key(exchanges_with_configs, symbols) do
    exchanges =
      exchanges_with_configs
      |> Enum.map(fn
        {exchange, _config} -> exchange
        exchange -> exchange
      end)
      |> Enum.sort()
      |> Enum.join(",")

    symbols_str = symbols |> Enum.sort() |> Enum.join(",")
    "funding_comparison:#{exchanges}:#{symbols_str}"
  end
end
