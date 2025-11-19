defmodule ZenCex.Examples.DebugTroubleshooting do
  @moduledoc """
  Debug mode and troubleshooting utilities for ZenCex API issues.

  The Debug module helps troubleshoot API integration issues by capturing
  failed requests and exporting them as curl commands. This is invaluable
  for debugging authentication issues, parameter problems, or unexpected
  API responses.

  ## Features

  - **Curl Export**: Failed requests are automatically exported as curl commands
  - **Debug Statistics**: Track total failures, error patterns, and debug state
  - **Runtime Control**: Enable/disable debug mode at runtime
  - **ETS Storage**: Failed requests stored in ETS for quick retrieval

  ## Workflow

  1. Enable debug mode
  2. Execute API calls that may fail
  3. Get curl commands for failed requests
  4. Run curl in terminal to see exact API response
  5. Fix issues based on actual API behavior
  6. Clear debug data and disable when done

  ## Usage

      # Enable debug mode
      ZenCex.Examples.DebugTroubleshooting.enable_debug_mode()

      # Make a request that fails
      {:error, _} = ZenCex.Examples.DebugTroubleshooting.debug_failed_request(%{
        symbol: "BTCUSDT",
        side: "BUY",
        type: "INVALID"  # This will fail
      })

      # Get the curl command to reproduce
      {:ok, curl} = ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()
      IO.puts(curl)
      # Copy and run in terminal to see exact API response

      # Get debug statistics
      stats = ZenCex.Examples.DebugTroubleshooting.get_debug_stats()
      IO.inspect(stats)

      # Disable when done
      ZenCex.Examples.DebugTroubleshooting.disable_debug_mode()

  ## Debug Statistics

  The stats map includes:
  - `total_captured` - Number of failed requests captured
  - `debug_enabled` - Whether debug mode is currently enabled
  - `curl_export_enabled` - Whether curl export is available
  - `curl_req_available` - Whether CurlReq library is loaded
  - `recent_errors` - List of recent error details with timestamps

  ## Security Notes

  ⚠️ **NEVER enable debug mode in production!**

  Debug mode logs request details including:
  - API endpoints and parameters
  - Signatures (not secrets, but still sensitive)
  - Error messages

  Always:
  - Use debug mode only in development/test environments
  - Clear debug data before sharing logs
  - Be careful with curl commands containing sensitive data
  - Disable debug mode when troubleshooting is complete
  """

  alias ZenCex.Adapters.Binance.Spot
  alias ZenCex.Core.Debug

  @doc """
  Enable debug mode to capture failed requests.

  When enabled, all failed API requests are:
  - Automatically exported as curl commands
  - Stored in ETS for retrieval
  - Logged with detailed error information
  - Emitted via telemetry events

  This is a runtime operation that doesn't require application restart.

  ## Examples

      iex> ZenCex.Examples.DebugTroubleshooting.enable_debug_mode()
      :ok

      # Now all failed requests will be captured
      # Check logs for "[ZenCex.Debug] Debug mode enabled"

  ## Returns

  - `:ok` - Debug mode successfully enabled
  """
  @spec enable_debug_mode() :: :ok
  def enable_debug_mode do
    Debug.enable()
  end

  @doc """
  Disable debug mode to stop capturing failed requests.

  This clears the debug configuration but does NOT clear stored data.
  Use `Debug.clear/0` to remove captured requests from ETS.

  ## Examples

      iex> ZenCex.Examples.DebugTroubleshooting.disable_debug_mode()
      :ok

      # Check logs for "[ZenCex.Debug] Debug mode disabled"

  ## Returns

  - `:ok` - Debug mode successfully disabled
  """
  @spec disable_debug_mode() :: :ok
  def disable_debug_mode do
    Debug.disable()
  end

  @doc """
  Get the last failed request as a curl command.

  This retrieves the most recent failed request from ETS storage.
  The curl command includes all headers, parameters, and signatures
  exactly as they were sent to the API.

  ## Examples

      iex> ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()
      {:ok, "curl -X POST -H 'X-MBX-APIKEY: ...' 'https://testnet.binance.vision/api/v3/order?...'"}

      # When no failures captured:
      iex> ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()
      {:error, :not_found}

  ## Usage

      {:ok, curl} = ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()
      IO.puts(curl)
      # Copy the curl command and run in terminal to see exact API response

  ## Returns

  - `{:ok, curl_command}` - Curl command string for the last failed request
  - `{:error, :not_found}` - No failed requests captured yet
  """
  @spec get_last_curl_command() :: {:ok, String.t()} | {:error, :not_found}
  def get_last_curl_command do
    Debug.get_last_curl()
  end

  @doc """
  Get debug statistics and captured request information.

  Returns a map with debug state, counts, and recent errors. Useful for
  monitoring debug activity and understanding failure patterns.

  ## Examples

      iex> stats = ZenCex.Examples.DebugTroubleshooting.get_debug_stats()
      iex> IO.inspect(stats)
      %{
        total_captured: 3,
        debug_enabled: true,
        curl_export_enabled: true,
        curl_req_available: true,
        recent_errors: [
          %{error: "{:invalid_params, ...}", timestamp: 1704470400000000},
          ...
        ]
      }

  ## Returns

  - `%{total_captured: integer(), ...}` - Debug statistics map

  Map keys:
  - `total_captured` - Total number of failed requests captured
  - `debug_enabled` - Whether debug mode is currently enabled
  - `curl_export_enabled` - Whether curl export functionality is active
  - `curl_req_available` - Whether CurlReq library is available
  - `recent_errors` - List of up to 5 most recent errors with details
  """
  @spec get_debug_stats() :: map()
  def get_debug_stats do
    Debug.stats()
  end

  @doc """
  Make a failing API request to demonstrate debug capture.

  This function intentionally sends invalid parameters to trigger an API
  error, which gets captured by the debug system. This is useful for:
  - Testing debug functionality
  - Understanding error formats
  - Generating curl commands for specific scenarios

  The function requires testnet credentials via environment variables:
  - `BINANCE_TESTNET_API_KEY`
  - `BINANCE_TESTNET_API_SECRET`

  ## Examples

      # Enable debug first
      iex> ZenCex.Examples.DebugTroubleshooting.enable_debug_mode()
      :ok

      # Make a failing request
      iex> ZenCex.Examples.DebugTroubleshooting.debug_failed_request(%{
      ...>   symbol: "BTCUSDT",
      ...>   side: "BUY",
      ...>   type: "INVALID"
      ...> })
      {:error, _reason}

      # Now get the curl command
      iex> {:ok, curl} = ZenCex.Examples.DebugTroubleshooting.get_last_curl_command()
      {:ok, "curl -X POST ..."}

  ## Parameters

  - `params` - Map with order parameters (will be made invalid to trigger error)
    - `:symbol` - Trading pair (e.g., "BTCUSDT")
    - `:side` - Order side (e.g., "BUY", "SELL")
    - `:type` - Order type (e.g., "MARKET", "LIMIT") - will be made invalid

  ## Returns

  - `{:error, reason}` - Always fails (intentionally) to trigger debug capture
  - `{:error, :missing_credentials}` - Testnet credentials not configured
  """
  @spec debug_failed_request(map()) :: {:error, term()}
  def debug_failed_request(params) do
    # Get testnet credentials from environment
    api_key = System.get_env("BINANCE_TESTNET_API_KEY")
    api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

    if is_nil(api_key) or is_nil(api_secret) do
      {:error, :missing_credentials}
    else
      # Make the params invalid to guarantee failure
      invalid_params =
        params
        |> Map.put(:type, "INVALID_TYPE")
        |> Map.put(:timeInForce, "INVALID_TIF")

      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: true
        }
      ]

      # This will fail and be captured by debug system
      Spot.place_order(invalid_params, opts)
    end
  end
end
