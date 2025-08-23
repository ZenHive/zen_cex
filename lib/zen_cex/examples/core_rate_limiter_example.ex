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

  @impl true
  def check_and_increment(endpoint, weight \\ 1) do
    Core.init_table(@table_name)
    Core.check_and_increment(@table_name, endpoint, weight, @limit_per_minute)
  end

  @impl true
  def update_from_response(%Req.Response{headers: headers}) do
    Core.init_table(@table_name)

    Core.update_from_headers(
      @table_name,
      Map.new(headers),
      &parse_header/1,
      "x-ratelimit-used"
    )
  end

  @impl true
  def get_status(_endpoint) do
    Core.init_table(@table_name)
    Core.get_status(@table_name, "example", @limit_per_minute, :minute)
  end

  @impl true
  def reset(_endpoint) do
    Core.init_table(@table_name)
    Core.reset(@table_name, "example")
  end

  @impl true
  def get_limits do
    %{
      example: %{limit: @limit_per_minute, window: 60}
    }
  end

  defp parse_header(value) when is_binary(value), do: String.to_integer(value)
  defp parse_header([value | _]), do: parse_header(value)
  defp parse_header(value) when is_integer(value), do: value
end
