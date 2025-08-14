defmodule ZenCex.Health do
  @moduledoc """
  Health monitoring for exchange connections.

  Provides clock synchronization validation to ensure local time
  is in sync with exchange servers. This is critical for:
  - API authentication (signatures include timestamps)
  - Order timing accuracy
  - Rate limit window calculations
  """

  # 300ms drift triggers warning
  @default_warning_ms 300
  # 500ms drift is critical
  @default_critical_ms 500

  @doc """
  Checks time synchronization between server and local time.

  Returns:
  - `{:ok, %{drift_ms: integer}}` - drift within acceptable range
  - `{:warning, %{drift_ms: integer, threshold_ms: integer}}` - drift exceeds warning threshold
  - `{:critical, %{drift_ms: integer, threshold_ms: integer}}` - drift exceeds critical threshold

  ## Options
  - `:warning_ms` - Warning threshold in milliseconds (default: 300)
  - `:critical_ms` - Critical threshold in milliseconds (default: 500)
  """
  @spec check_time_sync(integer(), integer() | nil, keyword()) ::
          {:ok, map()} | {:warning, map()} | {:critical, map()}
  def check_time_sync(server_time_ms, local_time_ms \\ nil, opts \\ []) do
    start_time = System.monotonic_time()
    local_time_ms = local_time_ms || System.system_time(:millisecond)
    drift_ms = local_time_ms - server_time_ms

    warning_threshold = Keyword.get(opts, :warning_ms, @default_warning_ms)
    critical_threshold = Keyword.get(opts, :critical_ms, @default_critical_ms)

    abs_drift = abs(drift_ms)

    {status, result} =
      cond do
        abs_drift >= critical_threshold ->
          {:critical, %{drift_ms: drift_ms, threshold_ms: critical_threshold}}

        abs_drift >= warning_threshold ->
          {:warning, %{drift_ms: drift_ms, threshold_ms: warning_threshold}}

        true ->
          {:ok, %{drift_ms: drift_ms}}
      end

    # Emit telemetry event
    :telemetry.execute(
      [:zen_cex, :exchange, :health, :time_sync],
      %{
        drift_ms: abs_drift,
        duration: System.monotonic_time() - start_time
      },
      %{status: status}
    )

    {status, result}
  end

  @doc """
  Parses server time from exchange API response.

  Each exchange returns time in different formats:
  - Binance: `serverTime` field in milliseconds
  - Kraken: `unixtime` field in seconds
  - Deribit: `result` field in milliseconds
  """
  @spec parse_server_time(map(), atom()) :: {:ok, integer()} | {:error, atom()}
  def parse_server_time(response, :binance) do
    case response do
      %{"serverTime" => time} when is_integer(time) ->
        {:ok, time}

      _ ->
        {:error, :invalid_server_response}
    end
  end

  def parse_server_time(response, :kraken) do
    case response do
      %{"error" => [], "result" => %{"unixtime" => time}} when is_integer(time) ->
        # Convert seconds to milliseconds
        {:ok, time * 1000}

      %{"error" => [_ | _]} ->
        {:error, :invalid_server_response}

      _ ->
        {:error, :invalid_server_response}
    end
  end

  def parse_server_time(response, :deribit) do
    case response do
      %{"jsonrpc" => "2.0", "result" => time} when is_integer(time) ->
        {:ok, time}

      %{"error" => _} ->
        {:error, :invalid_server_response}

      _ ->
        {:error, :invalid_server_response}
    end
  end

  def parse_server_time(_response, _exchange) do
    {:error, :unknown_exchange}
  end

  @doc """
  Formats drift value for human-readable display.

  ## Examples
      iex> format_drift(50)
      "50ms"
      
      iex> format_drift(1500)
      "1.5s"
      
      iex> format_drift(-2300)
      "-2.3s"
  """
  @spec format_drift(integer()) :: String.t()
  def format_drift(drift_ms) when abs(drift_ms) < 1000 do
    "#{drift_ms}ms"
  end

  def format_drift(drift_ms) do
    seconds = drift_ms / 1000
    :erlang.float_to_binary(seconds, decimals: 1) <> "s"
  end

  @doc """
  Fetches current server time from an exchange.

  Makes an HTTP request to the exchange's time endpoint and parses
  the response to extract server time in milliseconds.
  """
  @spec get_server_time(atom()) :: {:ok, integer()} | {:error, term()}
  def get_server_time(exchange) when exchange in [:binance, :kraken, :deribit] do
    alias ZenCex.{Endpoints, HTTP}

    with {:ok, request} <- Endpoints.build_request(exchange, :server_time) do
      # Execute the prepared request
      # Req.request! returns just the response when successful
      response =
        try do
          {:ok, Req.request!(request)}
        rescue
          e ->
            {:error, Exception.message(e)}
        end

      case response do
        {:ok, %Req.Response{} = response} ->
          case HTTP.parse_response(response, :json) do
            {:ok, body} -> parse_server_time(body, exchange)
            error -> error
          end

        {:error, _} = error ->
          error
      end
    else
      {:error, _} = error -> error
    end
  end

  def get_server_time(_exchange) do
    {:error, :unknown_exchange}
  end

  @doc """
  Performs a complete synchronization check for an exchange.

  Fetches server time, compares with local time, and returns detailed
  sync status including drift metrics and health status.
  """
  @spec check_exchange_sync(atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def check_exchange_sync(exchange, opts \\ []) do
    start_time = System.monotonic_time()

    result =
      with {:ok, server_time} <- get_server_time(exchange) do
        local_time = System.system_time(:millisecond)

        {status, sync_info} = check_time_sync(server_time, local_time, opts)

        result = %{
          exchange: exchange,
          server_time: server_time,
          local_time: local_time,
          drift_ms: sync_info.drift_ms,
          drift_formatted: format_drift(sync_info.drift_ms),
          status: status
        }

        # Add threshold info if present
        result =
          case sync_info do
            %{threshold_ms: threshold} -> Map.put(result, :threshold_ms, threshold)
            _ -> result
          end

        {:ok, result}
      end

    # Emit telemetry event
    :telemetry.execute(
      [:zen_cex, :exchange, :health, :check],
      %{duration: System.monotonic_time() - start_time},
      %{
        exchange: exchange,
        success: match?({:ok, _}, result)
      }
    )

    result
  end

  @doc """
  Starts periodic synchronization checks for an exchange.

  Returns a timer reference that can be cancelled with `Process.cancel_timer/1`.

  ## Options
  - `:callback` - Function to call with sync results (fn result -> ... end)
  - `:warning_ms` - Warning threshold in milliseconds
  - `:critical_ms` - Critical threshold in milliseconds
  """
  @spec periodic_sync_check(atom(), non_neg_integer(), keyword()) ::
          {:ok, pid()}
  def periodic_sync_check(exchange, interval_ms, opts \\ []) do
    callback = Keyword.get(opts, :callback, &default_callback/1)
    parent = self()

    # Spawn a process to handle periodic checks
    pid =
      spawn(fn ->
        # Emit startup telemetry
        :telemetry.execute(
          [:zen_cex, :exchange, :health, :startup],
          %{interval_ms: interval_ms},
          %{exchange: exchange}
        )

        # Perform initial check
        result = check_exchange_sync(exchange, opts)
        callback.(result)

        # Handle periodic checks
        periodic_check_loop(exchange, interval_ms, opts, callback, parent)
      end)

    # Return a reference that can be used to stop the periodic checks
    {:ok, pid}
  end

  defp periodic_check_loop(exchange, interval_ms, opts, callback, parent) do
    receive do
      :stop ->
        :ok
    after
      interval_ms ->
        if Process.alive?(parent) do
          result = check_exchange_sync(exchange, opts)
          callback.(result)
          periodic_check_loop(exchange, interval_ms, opts, callback, parent)
        else
          :ok
        end
    end
  end

  defp default_callback({:ok, result}) do
    if result.status != :ok do
      IO.puts("[#{result.exchange}] Clock drift #{result.status}: #{result.drift_formatted}")
    end
  end

  defp default_callback({:error, reason}) do
    IO.puts("[Health Check] Error: #{inspect(reason)}")
  end

  @doc """
  Checks synchronization across multiple exchanges and detects outliers.

  Performs health checks for all specified exchanges and determines if any
  exchange has significantly different time drift compared to others.

  Returns:
  - `{:ok, results}` - All exchanges are in consensus
  - `{:warning, results}` - One or more exchanges show concerning drift
  - `{:critical, results}` - One or more exchanges show critical drift or consensus failure

  ## Options
  - `:outlier_threshold_ms` - Threshold for detecting outliers (default: 200ms)
  - `:warning_ms` - Warning threshold for individual exchanges (default: 300ms)
  - `:critical_ms` - Critical threshold for individual exchanges (default: 500ms)
  """
  @spec check_multi_exchange_consensus([atom()], keyword()) ::
          {:ok, map()} | {:warning, map()} | {:critical, map()}
  def check_multi_exchange_consensus(exchanges, opts \\ []) do
    start_time = System.monotonic_time()
    outlier_threshold = Keyword.get(opts, :outlier_threshold_ms, 200)

    # Perform checks for all exchanges concurrently
    tasks =
      Enum.map(exchanges, fn exchange ->
        Task.async(fn ->
          {exchange, check_exchange_sync(exchange, opts)}
        end)
      end)

    # Collect results with timeout
    results =
      tasks
      |> Task.yield_many(5000)
      |> Enum.map(fn {task, res} ->
        case res do
          {:ok, {exchange, result}} ->
            {exchange, result}

          _ ->
            Task.shutdown(task, :brutal_kill)
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Separate successful and failed checks
    {successful, failed} =
      Enum.split_with(results, fn {_exchange, result} ->
        match?({:ok, _}, result)
      end)

    successful_checks = Enum.map(successful, fn {exchange, {:ok, data}} -> {exchange, data} end)
    failed_exchanges = Enum.map(failed, fn {exchange, _} -> exchange end)

    # Calculate consensus metrics
    consensus_result = analyze_consensus(successful_checks, outlier_threshold)

    # Determine overall status
    overall_status = determine_overall_status(consensus_result, failed_exchanges)

    result =
      {overall_status,
       %{
         exchanges_checked: length(exchanges),
         successful_checks: length(successful_checks),
         failed_exchanges: failed_exchanges,
         consensus: consensus_result,
         individual_results: Map.new(results),
         timestamp: System.system_time(:millisecond)
       }}

    # Emit telemetry event
    :telemetry.execute(
      [:zen_cex, :exchange, :health, :consensus],
      %{
        duration: System.monotonic_time() - start_time,
        exchanges_checked: length(exchanges),
        successful_checks: length(successful_checks),
        outliers: length(consensus_result[:outliers] || [])
      },
      %{status: overall_status}
    )

    result
  end

  defp analyze_consensus([], _threshold), do: %{status: :no_data, outliers: []}

  defp analyze_consensus([_single], _threshold) do
    %{
      status: :insufficient_data,
      outliers: [],
      message: "Need at least 2 exchanges for consensus"
    }
  end

  defp analyze_consensus(checks, threshold) when length(checks) >= 2 do
    # Extract drift values
    drifts = Enum.map(checks, fn {exchange, data} -> {exchange, data.drift_ms} end)

    # Calculate median drift
    sorted_drifts = drifts |> Enum.map(&elem(&1, 1)) |> Enum.sort()
    median_drift = calculate_median(sorted_drifts)

    # Identify outliers
    outliers =
      drifts
      |> Enum.filter(fn {_exchange, drift} ->
        abs(drift - median_drift) > threshold
      end)
      |> Enum.map(&elem(&1, 0))

    %{
      status: if(outliers == [], do: :consensus, else: :drift_detected),
      median_drift_ms: median_drift,
      outliers: outliers,
      drift_range: Enum.min_max(sorted_drifts),
      individual_drifts: Map.new(drifts)
    }
  end

  defp calculate_median(sorted_list) when is_list(sorted_list) do
    len = length(sorted_list)
    mid = div(len, 2)

    if rem(len, 2) == 0 do
      # Even number of elements - average the two middle values
      [v1, v2] = Enum.slice(sorted_list, mid - 1, 2)
      div(v1 + v2, 2)
    else
      # Odd number of elements - take the middle value
      Enum.at(sorted_list, mid)
    end
  end

  defp determine_overall_status(consensus_result, failed_exchanges) do
    cond do
      # Too many failures
      length(failed_exchanges) > 1 ->
        :critical

      # Consensus failure with outliers
      consensus_result[:status] == :drift_detected and consensus_result[:outliers] != [] ->
        :warning

      # Any failed exchange
      failed_exchanges != [] ->
        :warning

      # All good
      true ->
        :ok
    end
  end

  @doc """
  Checks if a specific exchange is an outlier compared to others.

  Returns true if the exchange's drift differs significantly from the
  median drift of all exchanges.
  """
  @spec exchange_outlier?(atom(), [atom()], keyword()) :: boolean()
  def exchange_outlier?(exchange, all_exchanges, opts \\ []) do
    case check_multi_exchange_consensus(all_exchanges, opts) do
      {_status, %{consensus: %{outliers: outliers}}} ->
        exchange in outliers

      _ ->
        false
    end
  end
end
