defmodule ZenCex.Safety.ClockSync do
  @moduledoc """
  Clock synchronization module for accurate exchange API timestamps.

  This module synchronizes local system time with exchange servers to ensure
  accurate authentication timestamps. It maintains clock offsets in ETS tables
  and provides automatic periodic synchronization.

  ## Features

  - Proactive NTP-style sync with all exchanges on startup
  - Periodic sync every 5 minutes to maintain accuracy
  - Sub-millisecond offset calculation and application
  - Automatic fallback to cached offsets on sync failure
  - Warning alerts for clock skew >1000ms
  - Exchange-specific offset tracking

  ## Implementation

  Uses ETS tables for atomic offset storage and high-performance lookups.
  Each exchange offset is stored as `{exchange, server_time_offset_ms}`.
  Server time is queried via exchange-specific time endpoints.

  ## Usage

      # Get current timestamp with exchange offset applied
      timestamp_ms = ClockSync.now_with_offset(:binance)
      
      # For specific Binance API types
      timestamp_ms = ClockSync.now_with_offset(:binance, :usdm_futures)
      timestamp_ms = ClockSync.now_with_offset(:binance, :coinm_futures)

      # Force manual sync with specific exchange
      ClockSync.sync_exchange(:kraken)
      
      # Sync specific Binance API type
      ClockSync.sync_exchange(:binance, :usdm_futures)

      # Get current offset for debugging
      offset_ms = ClockSync.get_offset(:deribit)
      offset_ms = ClockSync.get_offset(:binance, :usdm_futures)
  """

  use GenServer

  alias ZenCex.Core.HTTP
  alias ZenCex.Core.Registry

  require Logger

  @table_name :clock_offsets
  # Sync every 5 minutes
  @sync_interval_ms 5 * 60 * 1000
  # Warn if skew is > 1 second
  @max_skew_warning_ms 1000
  # Request timeout for time sync requests
  @sync_timeout_ms 5000
  # GenServer call timeout buffer in milliseconds
  @genserver_timeout_buffer_ms 1000
  # Maximum exchanges multiplier for parallel sync
  @max_exchanges_multiplier 3

  # Client API

  @doc """
  Starts the ClockSync GenServer and performs initial synchronization.

  ## Options
  - `:name` - The name to register the process under (default: `__MODULE__`)
  - `:sync_interval` - Sync interval in ms (default: 300,000 = 5 minutes)

  ## Examples

      {:ok, _pid} = ClockSync.start_link()
      {:ok, _pid} = ClockSync.start_link(sync_interval: 60_000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current system time with exchange-specific offset applied.

  ## Parameters
  - `exchange` - The exchange atom (e.g., `:binance`)

  ## Returns
  Current timestamp in milliseconds adjusted for exchange clock offset.

  ## Examples

      timestamp = ClockSync.now_with_offset(:binance)
      # Returns: 1640995200000 (adjusted for any clock drift)
  """
  @spec now_with_offset(atom()) :: integer()
  @spec now_with_offset(atom(), atom() | nil) :: integer()
  def now_with_offset(exchange, api_type \\ nil) do
    offset = get_offset(exchange, api_type)
    System.system_time(:millisecond) + offset
  end

  @doc """
  Gets the current clock offset for a specific exchange.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  Offset in milliseconds (positive = server ahead, negative = server behind).
  Returns 0 if no offset has been calculated.

  ## Examples

      offset = ClockSync.get_offset(:binance)
      # Returns: 150 (server is 150ms ahead of local time)
  """
  @spec get_offset(atom()) :: integer()
  @spec get_offset(atom(), atom() | nil) :: integer()
  def get_offset(exchange, api_type \\ nil) do
    key = make_key(exchange, api_type)

    case :ets.lookup(@table_name, key) do
      [{^key, offset}] -> offset
      [] -> 0
    end
  end

  @doc """
  Forces synchronization with a specific exchange.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  - `{:ok, offset_ms}` - Synchronization successful
  - `{:error, reason}` - Synchronization failed

  ## Examples

      {:ok, offset} = ClockSync.sync_exchange(:binance)
      # Returns: {:ok, 150}
  """
  @spec sync_exchange(atom()) :: {:ok, integer()} | {:error, term()}
  @spec sync_exchange(atom(), atom() | nil) :: {:ok, integer()} | {:error, term()}
  def sync_exchange(exchange, api_type \\ nil) do
    GenServer.call(__MODULE__, {:sync_exchange, exchange, api_type}, @sync_timeout_ms + @genserver_timeout_buffer_ms)
  end

  @doc """
  Forces synchronization with all registered exchanges.

  ## Returns
  Map of results keyed by exchange atom.

  ## Examples

      results = ClockSync.sync_all_exchanges()
      # Returns: %{binance: {:ok, 150}, kraken: {:ok, -75}, deribit: {:error, :timeout}}
  """
  @spec sync_all_exchanges() :: %{atom() => {:ok, integer()} | {:error, term()}}
  def sync_all_exchanges do
    GenServer.call(
      __MODULE__,
      :sync_all_exchanges,
      @sync_timeout_ms * @max_exchanges_multiplier + @genserver_timeout_buffer_ms
    )
  end

  @doc """
  Gets clock sync statistics for monitoring and debugging.

  ## Returns
  Map with sync statistics including:
  - `:exchanges` - List of tracked exchanges
  - `:last_sync_time` - Last successful sync timestamp
  - `:sync_interval_ms` - Current sync interval
  - `:offsets` - Current offsets for all exchanges

  ## Examples

      stats = ClockSync.get_stats()
      # Returns: %{exchanges: [:binance, :kraken], last_sync_time: 1640995200000, ...}
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Ensures time sync has been performed for an exchange.

  If no offset exists, performs synchronization immediately.
  Used to guarantee time accuracy before critical operations.

  ## Parameters
  - `exchange` - The exchange atom

  ## Returns
  - `{:ok, offset_ms}` - Time sync verified or completed
  - `{:error, reason}` - Failed to sync

  ## Examples

      {:ok, offset} = ClockSync.ensure_time_sync(:binance)
  """
  @spec ensure_time_sync(atom()) :: {:ok, integer()} | {:error, term()}
  def ensure_time_sync(exchange) do
    case :ets.lookup(@table_name, exchange) do
      [{^exchange, offset}] ->
        {:ok, offset}

      [] ->
        sync_exchange(exchange)
    end
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    # Create ETS table if it doesn't exist
    if !table_exists?() do
      :ets.new(@table_name, [
        :named_table,
        :public,
        :set,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])
    end

    sync_interval = Keyword.get(opts, :sync_interval, @sync_interval_ms)

    # Perform initial sync with all exchanges
    # Send message to self to avoid blocking init
    send(self(), :initial_sync)

    # Schedule periodic sync
    schedule_sync(sync_interval)

    {:ok, %{sync_interval: sync_interval, last_sync_time: nil}}
  end

  @impl true
  def handle_info(:initial_sync, state) do
    case sync_all_exchanges_internal() do
      results when map_size(results) > 0 ->
        Logger.info("ClockSync: Initial synchronization completed for #{map_size(results)} exchanges")

        emit_telemetry(:initial_sync_complete, %{exchange_count: map_size(results)})

      _empty ->
        Logger.warning("ClockSync: No exchanges found for initial synchronization")
    end

    {:noreply, %{state | last_sync_time: System.system_time(:millisecond)}}
  end

  @impl true
  def handle_info(:periodic_sync, state) do
    results = sync_all_exchanges_internal()

    successful_count =
      Enum.count(results, fn {_exchange, result} ->
        match?({:ok, _}, result)
      end)

    Logger.debug("ClockSync: Periodic sync completed for #{successful_count}/#{map_size(results)} exchanges")

    emit_telemetry(:periodic_sync_complete, %{
      total_exchanges: map_size(results),
      successful_count: successful_count
    })

    schedule_sync(state.sync_interval)
    {:noreply, %{state | last_sync_time: System.system_time(:millisecond)}}
  end

  @impl true
  def handle_call({:sync_exchange, exchange, api_type}, _from, state) do
    result = sync_exchange_internal(exchange, api_type)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:sync_all_exchanges, _from, state) do
    results = sync_all_exchanges_internal()
    {:reply, results, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    exchanges = Registry.list_exchanges()

    offsets =
      Map.new(exchanges, fn exchange -> {exchange, get_offset(exchange)} end)

    stats = %{
      exchanges: exchanges,
      last_sync_time: state.last_sync_time,
      sync_interval_ms: state.sync_interval,
      offsets: offsets
    }

    {:reply, stats, state}
  end

  # Private functions

  defp sync_all_exchanges_internal do
    exchanges = Registry.list_exchanges()

    # Build list of {exchange, api_type} tuples to sync
    sync_targets =
      Enum.flat_map(exchanges, fn exchange ->
        case exchange do
          :binance ->
            # Sync all Binance API types
            [
              # Default/spot
              {:binance, nil},
              {:binance, :usdm_futures},
              {:binance, :coinm_futures},
              {:binance, :portfolio}
            ]

          other ->
            # Other exchanges just sync once
            [{other, nil}]
        end
      end)

    # Sync all targets concurrently
    tasks =
      Enum.map(sync_targets, fn {exchange, api_type} ->
        Task.async(fn ->
          key = make_key(exchange, api_type)
          {key, sync_exchange_internal(exchange, api_type)}
        end)
      end)

    # Collect results with timeout
    results =
      tasks
      |> Task.await_many(@sync_timeout_ms)
      |> Map.new()

    results
  end

  defp sync_exchange_internal(exchange, api_type) do
    case fetch_server_time(exchange, api_type) do
      {:ok, server_time_ms} ->
        local_time_ms = System.system_time(:millisecond)
        offset_ms = server_time_ms - local_time_ms

        # Check for significant skew and warn
        if abs(offset_ms) > @max_skew_warning_ms do
          Logger.warning(
            "ClockSync: Large time skew detected for #{exchange}: #{offset_ms}ms " <>
              "(local: #{local_time_ms}, server: #{server_time_ms})"
          )

          emit_telemetry(:large_skew_detected, %{
            exchange: exchange,
            offset_ms: offset_ms,
            local_time_ms: local_time_ms,
            server_time_ms: server_time_ms
          })
        end

        # Store the offset
        key = make_key(exchange, api_type)
        :ets.insert(@table_name, {key, offset_ms})

        Logger.debug("ClockSync: Synchronized #{exchange} with offset #{offset_ms}ms")

        emit_telemetry(:sync_success, %{
          exchange: exchange,
          offset_ms: offset_ms
        })

        {:ok, offset_ms}

      {:error, reason} ->
        Logger.warning("ClockSync: Failed to sync #{exchange}: #{inspect(reason)}")

        emit_telemetry(:sync_failure, %{
          exchange: exchange,
          reason: reason
        })

        {:error, reason}
    end
  end

  defp fetch_server_time(exchange, api_type) do
    case get_time_endpoint_url(exchange, api_type) do
      {:ok, url} ->
        request =
          exchange
          |> HTTP.health_check_request()
          |> Req.merge(url: url, receive_timeout: @sync_timeout_ms)

        case Req.request(request) do
          {:ok, %{status: 200, body: body}} ->
            parse_server_time(exchange, body)

          {:ok, %{status: status}} ->
            {:error, {:http_error, status}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_time_endpoint_url(:binance, api_type), do: get_binance_time_url(api_type)
  defp get_time_endpoint_url(:bybit, _), do: get_bybit_time_url()
  defp get_time_endpoint_url(:kraken, _), do: {:ok, "https://api.kraken.com/0/public/Time"}

  defp get_time_endpoint_url(:deribit, _) do
    # TODO: Use test/prod host from config - should use Deribit adapter's base_url method
    {:ok, "https://test.deribit.com/api/v2/public/get_time"}
  end

  defp get_time_endpoint_url(unknown, _), do: {:error, {:unsupported_exchange, unknown}}

  defp get_bybit_time_url do
    if Application.get_env(:zen_cex, :use_testnet, false) do
      {:ok, "https://api-testnet.bybit.com/v5/market/time"}
    else
      {:ok, "https://api.bybit.com/v5/market/time"}
    end
  end

  defp get_binance_time_url(api_type) do
    case api_type do
      nil -> {:ok, "https://api.binance.com/api/v3/time"}
      :spot -> {:ok, "https://api.binance.com/api/v3/time"}
      :margin -> {:ok, "https://api.binance.com/api/v3/time"}
      :usdm_futures -> {:ok, get_futures_time_url("fapi")}
      :coinm_futures -> {:ok, get_futures_time_url("dapi")}
      :portfolio -> {:ok, get_portfolio_time_url()}
      _ -> {:ok, "https://api.binance.com/api/v3/time"}
    end
  end

  defp get_futures_time_url(api_prefix) do
    if Application.get_env(:zen_cex, :use_testnet, false) do
      "https://testnet.binancefuture.com/#{api_prefix}/v1/time"
    else
      "https://#{api_prefix}.binance.com/#{api_prefix}/v1/time"
    end
  end

  defp get_portfolio_time_url do
    if Application.get_env(:zen_cex, :use_testnet, false) do
      "https://testnet.binance.vision/papi/v1/time"
    else
      "https://papi.binance.com/papi/v1/time"
    end
  end

  defp parse_server_time(exchange, body) do
    case exchange do
      :binance -> parse_binance_time(body)
      :bybit -> parse_bybit_time(body)
      :kraken -> parse_kraken_time(body)
      :deribit -> parse_deribit_time(body)
      _unknown -> {:error, {:unsupported_exchange, exchange}}
    end
  end

  defp parse_binance_time(body) when is_map(body) do
    # Binance returns: {"serverTime": 1640995200000}
    # Note: Req automatically decodes JSON, so body is already a map
    case body do
      %{"serverTime" => server_time} when is_integer(server_time) ->
        {:ok, server_time}

      data ->
        {:error, {:invalid_response, data}}
    end
  end

  defp parse_binance_time(body) when is_binary(body) do
    # Fallback for string body (shouldn't happen with Req, but kept for compatibility)
    case Jason.decode(body) do
      {:ok, decoded} -> parse_binance_time(decoded)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_bybit_time(body) when is_map(body) do
    # Bybit V5 API returns: {"retCode": 0, "retMsg": "OK",
    # "result": {"timeSecond": "1234567890", "timeNano": "1234567890123456789"},
    # "time": 1234567890123}
    # The "time" field at root level is server time in milliseconds
    # The "result.timeSecond" is server time in seconds (as string)
    # The "result.timeNano" is server time in nanoseconds (as string)
    case body do
      # V5 API format with time field at root level (milliseconds)
      %{"time" => server_time} when is_integer(server_time) ->
        {:ok, server_time}

      # V5 API format with result containing timeSecond (seconds as string)
      %{"result" => %{"timeSecond" => time_str}} when is_binary(time_str) ->
        case Integer.parse(time_str) do
          {seconds, ""} -> {:ok, seconds * 1000}
          _ -> {:error, {:invalid_time_format, time_str}}
        end

      # Error response
      %{"retCode" => code} when code != 0 ->
        {:error, {:bybit_error, body["retMsg"] || "Unknown error"}}

      data ->
        {:error, {:invalid_response, data}}
    end
  end

  defp parse_bybit_time(body) when is_binary(body) do
    # Fallback for string body (shouldn't happen with Req, but kept for compatibility)
    case Jason.decode(body) do
      {:ok, decoded} -> parse_bybit_time(decoded)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_kraken_time(body) when is_map(body) do
    # Kraken returns: {"error": [], "result": {"unixtime": 1640995200, "rfc1123": "..."}}
    # Note: Req automatically decodes JSON, so body is already a map
    case body do
      %{"result" => %{"unixtime" => unix_time}} when is_integer(unix_time) ->
        # Convert seconds to milliseconds
        {:ok, unix_time * 1000}

      %{"error" => [error | _]} ->
        {:error, {:kraken_error, error}}

      data ->
        {:error, {:invalid_response, data}}
    end
  end

  defp parse_kraken_time(body) when is_binary(body) do
    # Fallback for string body (shouldn't happen with Req, but kept for compatibility)
    case Jason.decode(body) do
      {:ok, decoded} -> parse_kraken_time(decoded)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  defp parse_deribit_time(body) when is_map(body) do
    # Deribit returns: {"jsonrpc": "2.0", "result": {"server_time": 1640995200000}, ...}
    # Note: Req automatically decodes JSON, so body is already a map
    case body do
      %{"result" => %{"server_time" => server_time}} when is_integer(server_time) ->
        {:ok, server_time}

      %{"error" => error} ->
        {:error, {:deribit_error, error}}

      data ->
        {:error, {:invalid_response, data}}
    end
  end

  defp parse_deribit_time(body) when is_binary(body) do
    # Fallback for string body (shouldn't happen with Req, but kept for compatibility)
    case Jason.decode(body) do
      {:ok, decoded} -> parse_deribit_time(decoded)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  # Helper to create ETS table key for exchange/api_type combination
  defp make_key(exchange, nil), do: exchange
  defp make_key(exchange, api_type), do: {exchange, api_type}

  defp table_exists? do
    case :ets.whereis(@table_name) do
      :undefined -> false
      _ -> true
    end
  end

  defp schedule_sync(interval) do
    Process.send_after(self(), :periodic_sync, interval)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:zen_cex, :clock_sync, event],
      %{timestamp: System.system_time(:millisecond)},
      metadata
    )
  end
end
