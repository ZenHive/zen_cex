defmodule ZenCex.Core.Supervisor do
  @moduledoc """
  OTP supervisor for managing adapter processes and shared resources.

  Supervises:
  - Rate limit ETS table managers
  - Health monitoring processes
  - Dynamic adapter processes
  """

  use Supervisor

  @doc """
  Starts the Core supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Rate limit table manager - manages ETS tables for rate limiting
      {ZenCex.Core.RateLimitManager, []},

      # Health monitor - monitors adapter health status
      {ZenCex.Core.HealthMonitor, []},

      # Dynamic supervisor for adapter processes
      {DynamicSupervisor, name: ZenCex.AdapterSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Starts an adapter process under supervision.

  ## Examples

      iex> ZenCex.Core.Supervisor.start_adapter(:binance, [])
      {:ok, pid}
  """
  def start_adapter(exchange, opts \\ []) do
    adapter = ZenCex.Core.Registry.get_adapter!(exchange)

    child_spec = %{
      id: {adapter, exchange},
      start: {adapter, :start_link, [opts]},
      restart: :transient
    }

    DynamicSupervisor.start_child(ZenCex.AdapterSupervisor, child_spec)
  end

  @doc """
  Stops an adapter process.

  ## Examples

      iex> ZenCex.Core.Supervisor.stop_adapter(pid)
      :ok
  """
  def stop_adapter(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(ZenCex.AdapterSupervisor, pid)
  end

  @doc """
  Lists all running adapter processes.

  ## Examples

      iex> ZenCex.Core.Supervisor.list_adapters()
      [%{id: {ZenCex.Adapters.Binance, :binance}, pid: #PID<0.123.0>}]
  """
  def list_adapters do
    DynamicSupervisor.which_children(ZenCex.AdapterSupervisor)
    |> Enum.map(fn {id, pid, _type, _modules} ->
      %{id: id, pid: pid}
    end)
  end

  @doc """
  Restarts an adapter process.

  ## Examples

      iex> ZenCex.Core.Supervisor.restart_adapter(pid)
      {:ok, new_pid}
  """
  def restart_adapter(pid) when is_pid(pid) do
    # Find the adapter info before stopping
    case find_adapter_info(pid) do
      {:ok, {_adapter, exchange}} ->
        :ok = stop_adapter(pid)
        start_adapter(exchange, [])

      :error ->
        {:error, :adapter_not_found}
    end
  end

  defp find_adapter_info(pid) do
    DynamicSupervisor.which_children(ZenCex.AdapterSupervisor)
    |> Enum.find(fn {_id, child_pid, _type, _modules} -> child_pid == pid end)
    |> case do
      {{adapter, exchange}, ^pid, _type, _modules} ->
        {:ok, {adapter, exchange}}

      _ ->
        :error
    end
  end
end

defmodule ZenCex.Core.RateLimitManager do
  @moduledoc """
  Manages ETS tables for rate limiting across exchanges.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create ETS tables for each exchange
    tables = create_rate_limit_tables()

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{tables: tables}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries(state.tables)
    schedule_cleanup()
    {:noreply, state}
  end

  defp create_rate_limit_tables do
    %{
      binance_spot:
        :ets.new(:binance_spot_limits, [:named_table, :public, {:read_concurrency, true}]),
      binance_futures:
        :ets.new(:binance_futures_limits, [:named_table, :public, {:read_concurrency, true}]),
      kraken: :ets.new(:kraken_limits, [:named_table, :public, {:read_concurrency, true}]),
      deribit: :ets.new(:deribit_limits, [:named_table, :public, {:read_concurrency, true}])
    }
  end

  defp schedule_cleanup do
    # Every 60 seconds
    Process.send_after(self(), :cleanup, 60_000)
  end

  defp cleanup_expired_entries(tables) do
    now = System.system_time(:second)
    # Clean entries older than 2 minutes
    cutoff = now - 120

    Enum.each(tables, fn {_name, table} ->
      :ets.select_delete(table, [
        {{:"$1", :"$2"}, [{:<, :"$1", cutoff}], [true]}
      ])
    end)
  end
end

defmodule ZenCex.Core.HealthMonitor do
  @moduledoc """
  Monitors health status of adapter processes and shared resources.
  """

  use GenServer
  require Logger

  defstruct adapters: %{}, last_check: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule periodic health checks
    schedule_health_check()

    {:ok, %__MODULE__{}}
  end

  @doc """
  Reports health status for an adapter.
  """
  def report_health(exchange, status) do
    GenServer.cast(__MODULE__, {:report_health, exchange, status})
  end

  @doc """
  Gets current health status for all adapters.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end

  @impl true
  def handle_cast({:report_health, exchange, status}, state) do
    adapters =
      Map.put(state.adapters, exchange, %{
        status: status,
        timestamp: System.system_time(:second)
      })

    {:noreply, %{state | adapters: adapters}}
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    {:reply, state.adapters, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Check adapter processes
    adapters = ZenCex.Core.Supervisor.list_adapters()

    Enum.each(adapters, fn %{id: {_adapter, exchange}, pid: pid} ->
      if Process.alive?(pid) do
        report_health(exchange, :healthy)
      else
        Logger.warning("Adapter #{exchange} process is not alive")
        report_health(exchange, :unhealthy)
      end
    end)

    schedule_health_check()
    {:noreply, %{state | last_check: System.system_time(:second)}}
  end

  defp schedule_health_check do
    # Every 30 seconds
    Process.send_after(self(), :health_check, 30_000)
  end
end
