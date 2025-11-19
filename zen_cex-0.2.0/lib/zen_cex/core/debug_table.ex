defmodule ZenCex.Core.DebugTable do
  @moduledoc """
  Manages the ETS table for debug mode storage.

  This GenServer ensures the debug ETS table is properly initialized
  and cleaned up as part of the application supervision tree.
  """

  use GenServer

  @table_name :zen_cex_debug
  # 1 minute
  @cleanup_interval_ms 60_000
  @max_stored_requests 100

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create the ETS table owned by this process
    :ets.new(@table_name, [:ordered_set, :public, :named_table])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_old_entries do
    size = :ets.info(@table_name, :size)

    if size > @max_stored_requests do
      # Remove oldest entries
      to_remove = size - @max_stored_requests

      @table_name
      |> :ets.first()
      |> remove_entries(to_remove)
    end
  end

  defp remove_entries(:"$end_of_table", _count), do: :ok
  defp remove_entries(_key, 0), do: :ok

  defp remove_entries(key, count) do
    next_key = :ets.next(@table_name, key)
    :ets.delete(@table_name, key)
    remove_entries(next_key, count - 1)
  end
end
