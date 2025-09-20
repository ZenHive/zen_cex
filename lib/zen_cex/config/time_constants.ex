defmodule ZenCex.Config.TimeConstants do
  @moduledoc """
  Compile-time constants for time durations used throughout the application.

  All values are in milliseconds for consistency.
  """

  # Base time units in milliseconds
  @second_ms 1_000
  @minute_ms 60 * @second_ms
  @hour_ms 60 * @minute_ms
  @day_ms 24 * @hour_ms
  @week_ms 7 * @day_ms

  @doc "One second in milliseconds"
  @spec second_ms() :: pos_integer()
  def second_ms, do: @second_ms

  @doc "One minute in milliseconds"
  @spec minute_ms() :: pos_integer()
  def minute_ms, do: @minute_ms

  @doc "One hour in milliseconds"
  @spec hour_ms() :: pos_integer()
  def hour_ms, do: @hour_ms

  @doc "One day in milliseconds"
  @spec day_ms() :: pos_integer()
  def day_ms, do: @day_ms

  @doc "One week in milliseconds"
  @spec week_ms() :: pos_integer()
  def week_ms, do: @week_ms

  @doc """
  Convert seconds to milliseconds.

  ## Examples

      iex> TimeConstants.seconds(5)
      5000
  """
  @spec seconds(number()) :: number()
  def seconds(n) when is_number(n), do: n * @second_ms

  @doc """
  Convert minutes to milliseconds.

  ## Examples

      iex> TimeConstants.minutes(2)
      120000
  """
  @spec minutes(number()) :: number()
  def minutes(n) when is_number(n), do: n * @minute_ms

  @doc """
  Convert hours to milliseconds.

  ## Examples

      iex> TimeConstants.hours(1)
      3600000
  """
  @spec hours(number()) :: number()
  def hours(n) when is_number(n), do: n * @hour_ms

  @doc """
  Convert days to milliseconds.

  ## Examples

      iex> TimeConstants.days(1)
      86400000
  """
  @spec days(number()) :: number()
  def days(n) when is_number(n), do: n * @day_ms

  # Cache TTLs determined at compile time based on Mix.env()
  @cache_ttls_by_env %{
    prod: %{
      # 24 hours for symbol info
      symbol_info: @day_ms,
      # 24 hours for min notional
      min_notional: @day_ms,
      # 5 seconds for prices
      price: 5 * @second_ms,
      # 10 seconds for balances
      balance: 10 * @second_ms
    },
    dev: %{
      # 24 hours for symbol info
      symbol_info: @day_ms,
      # 24 hours for min notional
      min_notional: @day_ms,
      # 5 seconds for prices
      price: 5 * @second_ms,
      # 10 seconds for balances
      balance: 10 * @second_ms
    },
    test: %{
      # 5 minutes for test stability (symbol info doesn't change often)
      symbol_info: 5 * @minute_ms,
      # 5 minutes for test stability (min notionals are static)
      min_notional: 5 * @minute_ms,
      # 10 seconds for prices (more stable in tests)
      price: 10 * @second_ms,
      # 10 seconds for balances (more stable in tests)
      balance: 10 * @second_ms
    }
  }

  # Set cache TTLs at compile time
  @current_env Mix.env()
  @cache_ttls Map.get(@cache_ttls_by_env, @current_env, %{
                symbol_info: @hour_ms,
                min_notional: @hour_ms,
                price: 10 * @second_ms,
                balance: 30 * @second_ms
              })

  @doc """
  Get cache TTL configuration for the current environment.

  Returns a map with cache TTL values in milliseconds.
  """
  @spec cache_ttls() :: %{atom() => pos_integer()}
  def cache_ttls do
    @cache_ttls
  end

  @doc """
  Get rate limit window sizes for different exchanges.

  Returns a map with window sizes in milliseconds.
  """
  @spec rate_limit_windows() :: %{atom() => pos_integer()}
  def rate_limit_windows do
    %{
      # 1 minute windows
      binance: @minute_ms,
      # 5 second windows
      bybit: seconds(5),
      # 1 minute windows (when implemented)
      kraken: @minute_ms,
      # 1 minute windows (when implemented)
      deribit: @minute_ms
    }
  end

  @doc """
  Get cleanup intervals for various caches.

  Returns a map with cleanup intervals in milliseconds.
  """
  @spec cleanup_intervals() :: %{atom() => pos_integer()}
  def cleanup_intervals do
    %{
      # Clean every minute
      order_safety: @minute_ms,
      # Clean every 5 minutes
      rate_limiter: minutes(5),
      # Clean every hour
      clock_sync: hours(1),
      # Clean every 15 minutes
      debug_table: minutes(15)
    }
  end

  @doc """
  Get timeout values for different operations.

  Returns a map with timeout values in milliseconds.
  """
  @spec operation_timeouts() :: %{atom() => pos_integer()}
  def operation_timeouts do
    %{
      # 30 seconds for API requests
      api_request: seconds(30),
      # 10 seconds for order placement
      order_placement: seconds(10),
      # 5 seconds for balance queries
      balance_fetch: seconds(5),
      # 3 seconds for market data
      market_data: seconds(3),
      # 2 seconds for auth refresh
      auth_refresh: seconds(2)
    }
  end

  @doc """
  Get retry delay values for different scenarios.

  Returns a map with retry delays in milliseconds.
  """
  @spec retry_delays() :: %{atom() => pos_integer()}
  def retry_delays do
    %{
      # 100ms initial retry
      initial: 100,
      # 1 second after rate limit
      rate_limit: @second_ms,
      # 2 seconds after network error
      network_error: seconds(2),
      # 5 seconds after server error
      server_error: seconds(5),
      # Maximum 1 minute backoff
      max_backoff: minutes(1)
    }
  end
end
