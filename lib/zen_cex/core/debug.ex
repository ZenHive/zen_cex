defmodule ZenCex.Core.Debug do
  @moduledoc """
  Debug utilities for ZenCex, including curl command export for failed requests.

  This module provides debugging capabilities that are only available in development
  and test environments. The primary feature is the ability to export failed HTTP
  requests as curl commands for easy reproduction and debugging.

  ## Configuration

  Debug mode can be enabled via configuration:

      config :zen_cex, :debug,
        enabled: true,
        export_curl: true,
        log_level: :debug

  ## Usage

  When debug mode is enabled and a request fails, the curl command will be:
  - Logged to the console
  - Stored in ETS for retrieval
  - Emitted via telemetry events

  ## Examples

      # Enable debug mode at runtime
      ZenCex.Core.Debug.enable()

      # Get the last failed request as curl
      {:ok, curl_command} = ZenCex.Core.Debug.get_last_curl()

      # Get all recent failed requests
      commands = ZenCex.Core.Debug.get_recent_curls(10)

  """

  require Logger

  @ets_table :zen_cex_debug

  @doc """
  Checks if debug mode is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    :zen_cex
    |> Application.get_env(:debug, [])
    |> Keyword.get(:enabled, false)
  end

  @doc """
  Checks if curl export is available and enabled.
  """
  @spec curl_export_enabled?() :: boolean()
  def curl_export_enabled? do
    enabled?() &&
      Code.ensure_loaded?(CurlReq) &&
      :zen_cex
      |> Application.get_env(:debug, [])
      |> Keyword.get(:export_curl, true)
  end

  @doc """
  Enables debug mode at runtime.
  """
  @spec enable() :: :ok
  def enable do
    Application.put_env(
      :zen_cex,
      :debug,
      Keyword.put(
        Application.get_env(:zen_cex, :debug, []),
        :enabled,
        true
      )
    )

    Logger.info("[ZenCex.Debug] Debug mode enabled")
    :ok
  end

  @doc """
  Disables debug mode at runtime.
  """
  @spec disable() :: :ok
  def disable do
    Application.put_env(
      :zen_cex,
      :debug,
      Keyword.put(
        Application.get_env(:zen_cex, :debug, []),
        :enabled,
        false
      )
    )

    Logger.info("[ZenCex.Debug] Debug mode disabled")
    :ok
  end

  @doc """
  Captures a failed request and exports it as a curl command if debug mode is enabled.

  This function is called automatically by the HTTP client when a request fails.
  """
  @spec capture_request(Req.Request.t(), term()) :: :ok
  def capture_request(%Req.Request{} = request, error) do
    if curl_export_enabled?() do
      # export_to_curl always returns {:ok, _} due to fallback
      {:ok, curl_command} = export_to_curl(request)
      store_curl_command(request, curl_command, error)
      log_curl_command(request, curl_command, error)
      emit_telemetry(request, curl_command, error)
      :ok
    else
      :ok
    end
  end

  @doc """
  Exports a Req.Request to a curl command string.
  """
  @spec export_to_curl(Req.Request.t()) :: {:ok, String.t()} | {:error, term()}
  def export_to_curl(%Req.Request{} = request) do
    if Code.ensure_loaded?(CurlReq) do
      try do
        curl_command = CurlReq.to_curl(request)
        {:ok, curl_command}
      rescue
        _e ->
          # Fallback to manual construction on error
          build_curl_manually(request)
      end
    else
      build_curl_manually(request)
    end
  end

  @doc """
  Gets the last failed request as a curl command.
  """
  @spec get_last_curl() :: {:ok, String.t()} | {:error, :not_found}
  def get_last_curl do
    case :ets.last(@ets_table) do
      :"$end_of_table" ->
        {:error, :not_found}

      key ->
        case :ets.lookup(@ets_table, key) do
          [{_key, _request, curl_command, _error, _timestamp}] -> {:ok, curl_command}
          [] -> {:error, :not_found}
        end
    end
  end

  @doc """
  Gets recent failed requests as curl commands.
  """
  @spec get_recent_curls(non_neg_integer()) :: [String.t()]
  def get_recent_curls(limit \\ 10) do
    @ets_table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, _, _, _, _} -> key end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_key, _request, curl_command, _error, _timestamp} -> curl_command end)
  end

  @doc """
  Clears all stored debug data.
  """
  @spec clear() :: :ok
  def clear do
    if :ets.whereis(@ets_table) != :undefined do
      :ets.delete_all_objects(@ets_table)
    end

    :ok
  end

  @doc """
  Gets debug statistics.
  """
  @spec stats() :: map()
  def stats do
    requests =
      if :ets.whereis(@ets_table) == :undefined do
        []
      else
        :ets.tab2list(@ets_table)
      end

    %{
      total_captured: length(requests),
      debug_enabled: enabled?(),
      curl_export_enabled: curl_export_enabled?(),
      curl_req_available: Code.ensure_loaded?(CurlReq),
      recent_errors:
        requests
        |> Enum.take(5)
        |> Enum.map(fn {_key, _request, _curl, error, timestamp} ->
          %{error: inspect(error), timestamp: timestamp}
        end)
    }
  end

  # Private functions

  defp store_curl_command(request, curl_command, error) do
    # Table is managed by DebugTable GenServer
    if :ets.whereis(@ets_table) == :undefined do
      # Table not available, skip storing
      :ok
    else
      timestamp = System.system_time(:microsecond)
      key = {timestamp, request.url}

      :ets.insert(@ets_table, {key, request, curl_command, error, timestamp})

      # Cleanup is now handled by DebugTable GenServer
      :ok
    end
  end

  defp log_curl_command(request, curl_command, error) do
    Logger.warning("""
    [ZenCex.Debug] Request failed: #{inspect(error)}

    Exchange: #{request.private[:exchange] || "unknown"}
    Operation: #{request.private[:zen_cex_operation] || "unknown"}
    URL: #{request.url}

    Reproduce with curl:
    #{curl_command}
    """)
  end

  defp emit_telemetry(request, curl_command, error) do
    :telemetry.execute(
      [:zen_cex, :debug, :curl_export],
      %{count: 1},
      %{
        request: request,
        curl_command: curl_command,
        error: error,
        exchange: request.private[:exchange],
        operation: request.private[:zen_cex_operation]
      }
    )
  end

  defp build_curl_manually(%Req.Request{} = request) do
    # Fallback manual curl construction if curl_req is not available
    headers =
      Enum.map_join(request.headers, " ", fn {key, value} -> "-H '#{key}: #{value}'" end)

    method = String.upcase(to_string(request.method))

    body =
      case request.body do
        nil -> ""
        "" -> ""
        body when is_binary(body) -> " -d '#{body}'"
        body -> " -d '#{Jason.encode!(body)}'"
      end

    curl = "curl -X #{method} #{headers}#{body} '#{request.url}'"

    {:ok, curl}
  end
end
