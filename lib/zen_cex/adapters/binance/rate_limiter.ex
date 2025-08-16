defmodule ZenCex.Adapters.Binance.RateLimiter do
  @moduledoc """
  Rate limiting implementation for Binance exchange.

  Binance has separate rate limits for spot (1200/min) and futures (2400/min) APIs.
  Uses atomic ETS operations for lock-free concurrent access with true sliding window.
  """

  @behaviour ZenCex.Behaviors.RateLimiter

  @spot_limit 1200
  @futures_limit 2400
  @window_seconds 60
  @spot_table :binance_spot_limits
  @futures_table :binance_futures_limits

  @doc """
  Starts the rate limiter and creates ETS tables.
  Should be called from the application supervisor.
  """
  def start_link(_opts \\ []) do
    # Create ETS tables if they don't exist
    unless :ets.whereis(@spot_table) != :undefined do
      :ets.new(@spot_table, [:named_table, :public, {:read_concurrency, true}])
    end

    unless :ets.whereis(@futures_table) != :undefined do
      :ets.new(@futures_table, [:named_table, :public, {:read_concurrency, true}])
    end

    :ignore
  end

  @impl true
  def check_and_increment(endpoint, weight \\ 1) do
    table = get_table(endpoint)
    limit = get_limit(endpoint)
    now = System.system_time(:second)

    # Clean up old windows (older than 70 seconds for safety)
    cleanup_old_windows(table, now - @window_seconds - 10)

    # Get current usage in the sliding window
    current_usage = calculate_window_usage(table, now)

    if current_usage + weight > limit do
      {:error, :rate_limited}
    else
      # Atomic increment for current second
      :ets.update_counter(table, now, {2, weight}, {now, 0})
      :ok
    end
  end

  @impl true
  def update_from_response(response) do
    # Extract rate limit headers from Binance response
    # Req already emits telemetry events we can subscribe to if needed
    # For now, just parse the headers if we want to track server-reported weights

    headers = Map.new(response.headers)

    case headers["x-mbx-used-weight-1m"] do
      nil ->
        :ok

      [weight_str | _] when is_binary(weight_str) ->
        # Header is a list (common with HTTP clients)
        # Just acknowledge we got it - Req's telemetry handles the rest
        _weight = String.to_integer(weight_str)
        :ok

      weight_str when is_binary(weight_str) ->
        # Header is a string
        _weight = String.to_integer(weight_str)
        :ok

      _ ->
        :ok
    end
  end

  @impl true
  def get_status(endpoint) do
    table = get_table(endpoint || "/api/v3/ticker")
    limit = get_limit(endpoint || "/api/v3/ticker")
    now = System.system_time(:second)

    used = calculate_window_usage(table, now)

    %{
      used: used,
      limit: limit,
      window: @window_seconds,
      reset_at: now + @window_seconds,
      remaining: max(0, limit - used)
    }
  end

  @impl true
  def reset(endpoint) do
    if endpoint do
      table = get_table(endpoint)
      :ets.delete_all_objects(table)
    else
      # Reset both tables
      :ets.delete_all_objects(@spot_table)
      :ets.delete_all_objects(@futures_table)
    end

    :ok
  end

  @impl true
  def get_limits() do
    %{
      spot: %{
        limit: @spot_limit,
        window: @window_seconds,
        endpoints: ["api.binance.com", "/api", "/sapi"]
      },
      futures: %{
        limit: @futures_limit,
        window: @window_seconds,
        endpoints: ["fapi.binance.com", "/fapi", "/dapi"]
      }
    }
  end

  # Private functions

  defp get_table("/fapi" <> _), do: @futures_table
  defp get_table("/dapi" <> _), do: @futures_table
  defp get_table(_), do: @spot_table

  defp get_limit("/fapi" <> _), do: @futures_limit
  defp get_limit("/dapi" <> _), do: @futures_limit
  defp get_limit(_), do: @spot_limit

  defp calculate_window_usage(table, now) do
    # Sum all requests in the last 60 seconds
    cutoff = now - @window_seconds

    :ets.select(table, [
      {{:"$1", :"$2"}, [{:>, :"$1", cutoff}], [:"$2"]}
    ])
    |> Enum.sum()
  end

  defp cleanup_old_windows(table, cutoff) do
    :ets.select_delete(table, [
      {{:"$1", :"$2"}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  @doc """
  Initialize ETS tables for testing or manual setup.
  """
  def init_tables do
    unless :ets.whereis(@spot_table) != :undefined do
      :ets.new(@spot_table, [:named_table, :public, {:read_concurrency, true}])
    end

    unless :ets.whereis(@futures_table) != :undefined do
      :ets.new(@futures_table, [:named_table, :public, {:read_concurrency, true}])
    end

    :ok
  end

  @doc """
  Clean up ETS tables (mainly for testing).
  """
  def cleanup_tables do
    try do
      :ets.delete(@spot_table)
    rescue
      _ -> :ok
    end

    try do
      :ets.delete(@futures_table)
    rescue
      _ -> :ok
    end

    :ok
  end
end
