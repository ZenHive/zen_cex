defmodule ZenCex.Examples.CoreRateLimiterExample do
  @moduledoc """
  Example implementation showing how to use the Core.RateLimiter module
  for building exchange-specific rate limiters.

  This demonstrates a simple exchange with:
  - 100 requests per minute limit
  - Response header-based tracking
  - Status reporting
  """

  @behaviour ZenCex.Behaviors.RateLimiter

  alias ZenCex.Core.RateLimiter, as: Core

  @table_name __MODULE__.Table
  @limit_per_minute 100
  @seconds_per_minute 60

  @impl true
  @spec check_and_increment(String.t() | nil, non_neg_integer()) :: :ok
  def check_and_increment(_endpoint, weight \\ 1) do
    Core.init_table(@table_name)
    Core.check_and_increment(@table_name, :example, weight, @limit_per_minute)
  end

  @impl true
  @spec update_from_response(Req.Response.t()) :: :ok
  def update_from_response(%Req.Response{headers: headers}) do
    Core.init_table(@table_name)

    Core.update_from_headers(
      @table_name,
      :example,
      Map.new(headers),
      "x-ratelimit-used"
    )
  end

  @impl true
  @spec get_status(String.t() | nil) :: map()
  def get_status(_endpoint) do
    Core.init_table(@table_name)
    Core.get_status(@table_name, :example, @limit_per_minute, @seconds_per_minute)
  end

  @impl true
  @spec reset(String.t() | nil) :: :ok
  def reset(_endpoint) do
    Core.init_table(@table_name)
    Core.reset(@table_name, :example)
  end

  @impl true
  @spec get_limits() :: map()
  def get_limits do
    %{
      example: %{limit: @limit_per_minute, window: @seconds_per_minute}
    }
  end
end
