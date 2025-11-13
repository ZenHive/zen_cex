defmodule ZenCex.Adapters.Deribit.RateLimiter do
  @moduledoc """
  Rate limiter for Deribit API requests using token bucket algorithm.

  Wraps `ZenWebsocket.RateLimiter` with Deribit-specific configuration.

  ## Deribit Rate Limits

  Deribit uses a credit-based rate limiting system with 100 credits per second.
  Different request types consume different amounts of credits:

  - Public methods: 1 credit
  - Private `get_*` methods: 5 credits
  - Private `set_*` methods: 10 credits
  - Trading methods (`buy`, `sell`): 15 credits

  See: https://docs.deribit.com/#rate-limits

  ## Usage

      # Initialize rate limiter
      {:ok, :deribit_limiter} = RateLimiter.init()

      # Check if request can proceed
      case RateLimiter.check_rate_limit(%{"method" => "private/buy"}) do
        :ok -> # Request allowed
        {:error, :rate_limited} -> # Wait and retry
        {:error, :queue_full} -> # System overload
      end

      # Check current status
      {:ok, %{tokens: 85, queue_size: 0}} = RateLimiter.get_status()

      # Reset (testing only)
      :ok = RateLimiter.reset()
  """

  alias ZenWebsocket.RateLimiter

  @limiter_name :deribit_limiter

  @bucket_capacity 100
  @refill_rate 100
  @refill_interval_ms 1000

  @doc """
  Initializes Deribit rate limiter with 100-credit bucket.

  ## Configuration

  - Bucket capacity: 100 credits
  - Refill rate: 100 credits per second
  - Cost function: `ZenWebsocket.RateLimiter.deribit_cost/1`

  Returns `{:ok, :deribit_limiter}` on success.

  ## Examples

      iex> {:ok, :deribit_limiter} = RateLimiter.init()
      {:ok, :deribit_limiter}
  """
  @spec init() :: {:ok, atom()} | {:error, term()}
  def init do
    config = %{
      tokens: @bucket_capacity,
      refill_rate: @refill_rate,
      refill_interval: @refill_interval_ms,
      request_cost: &RateLimiter.deribit_cost/1
    }

    RateLimiter.init(@limiter_name, config)
  end

  @doc """
  Checks if request can proceed under rate limits.

  Consumes credits based on request method:
  - Public methods: 1 credit
  - Private `get_*`: 5 credits
  - Private `set_*`: 10 credits
  - Trading (`buy`/`sell`): 15 credits

  Returns `:ok` if credits available, `{:error, :rate_limited}` if request
  queued, or `{:error, :queue_full}` if queue is full (100+ pending requests).

  ## Parameters

  - `request` - Map with `"method"` key (e.g., `%{"method" => "private/buy"}`)

  ## Examples

      iex> {:ok, :deribit_limiter} = RateLimiter.init()
      iex> RateLimiter.check_rate_limit(%{"method" => "public/ticker"})
      :ok
      iex> {:ok, %{tokens: tokens}} = RateLimiter.get_status()
      iex> tokens
      99

      iex> # After exhausting credits
      iex> RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      {:error, :rate_limited}
      iex> {:ok, %{queue_size: queue}} = RateLimiter.get_status()
      iex> queue
      1
  """
  @spec check_rate_limit(map()) :: :ok | {:error, :rate_limited | :queue_full}
  def check_rate_limit(request) when is_map(request) do
    RateLimiter.consume(@limiter_name, request)
  end

  @doc """
  Returns current rate limiter status.

  ## Return Value

  Returns `{:ok, status}` where `status` contains:
  - `:tokens` - Credits currently available (0-100)
  - `:queue_size` - Number of queued requests waiting for credits

  ## Examples

      iex> RateLimiter.init()
      iex> RateLimiter.get_status()
      {:ok, %{tokens: 100, queue_size: 0}}

      iex> RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      iex> RateLimiter.get_status()
      {:ok, %{tokens: 85, queue_size: 0}}
  """
  @spec get_status() :: {:ok, %{tokens: non_neg_integer(), queue_size: non_neg_integer()}}
  def get_status do
    RateLimiter.status(@limiter_name)
  end

  @doc """
  Resets rate limiter to initial state.

  **Testing only** - Destroys and recreates the ETS table with fresh state.

  ## Examples

      iex> RateLimiter.init()
      iex> RateLimiter.check_rate_limit(%{"method" => "private/buy"})
      iex> RateLimiter.reset()
      :ok
      iex> RateLimiter.get_status()
      {:ok, %{tokens: 100, queue_size: 0}}
  """
  @spec reset() :: :ok
  def reset do
    if :ets.whereis(@limiter_name) != :undefined do
      :ets.delete(@limiter_name)
    end

    {:ok, _} = init()
    :ok
  end
end
