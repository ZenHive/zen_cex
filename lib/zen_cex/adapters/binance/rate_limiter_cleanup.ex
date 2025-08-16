defmodule ZenCex.Adapters.Binance.RateLimiterCleanup do
  @moduledoc """
  GenServer that handles periodic cleanup of old rate limit entries.

  Runs every 60 seconds to remove entries older than the rate limit window.
  """

  use GenServer
  require Logger

  alias ZenCex.Adapters.Binance.RateLimiter

  @cleanup_interval_ms :timer.seconds(60)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule first cleanup
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:perform_cleanup, state) do
    # Perform the cleanup
    RateLimiter.perform_cleanup()

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :perform_cleanup, @cleanup_interval_ms)
  end
end
