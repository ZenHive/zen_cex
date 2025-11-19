defmodule ZenCex.Behaviors.RateLimiter do
  @moduledoc """
  Behavior defining the rate limiting contract for exchange adapters.

  Each exchange has different rate limiting rules and this behavior
  provides a consistent interface for checking and tracking API usage.
  """

  @doc """
  Checks if a request can be made and increments the counter if allowed.

  ## Parameters
    - endpoint: The API endpoint being called
    - weight: The weight/cost of this request (default: 1)

  ## Returns
    - `:ok` if the request can proceed
    - `{:error, :rate_limited}` if rate limit would be exceeded
    - `{:error, {:rate_limited, retry_after_ms}}` with retry time

  ## Notes
    - Must be atomic to handle concurrent requests
    - Should clean up old tracking data automatically
  """
  @callback check_and_increment(String.t(), integer()) :: :ok | {:error, term()}

  @doc """
  Updates rate limit tracking based on response headers.

  ## Parameters
    - response: The HTTP response containing rate limit headers

  ## Returns
    - `:ok` after updating internal tracking

  ## Notes
    - Binance: Uses x-mbx-used-weight-1m header
    - Kraken: Uses ratelimit headers
    - Deribit: Uses x-ratelimit headers
  """
  @callback update_from_response(Req.Response.t()) :: :ok

  @doc """
  Returns the current rate limit status.

  ## Parameters
    - endpoint: Optional endpoint to check specific limits

  ## Returns
    - Map with keys:
      - `:used` - Current usage count
      - `:limit` - Maximum allowed
      - `:window` - Time window in seconds
      - `:reset_at` - Unix timestamp of next reset
  """
  @callback get_status(String.t() | nil) :: map()

  @doc """
  Resets rate limit tracking for testing or manual intervention.

  ## Parameters
    - endpoint: Optional endpoint to reset, or nil for all

  ## Returns
    - `:ok` after resetting
  """
  @callback reset(String.t() | nil) :: :ok

  @doc """
  Returns the rate limit configuration for this exchange.

  ## Returns
    - Map with exchange-specific limits and windows
  """
  @callback get_limits() :: map()

  @optional_callbacks update_from_response: 1, reset: 1
end
