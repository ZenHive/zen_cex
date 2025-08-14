defmodule ZenCex.Auth.DeribitOAuth do
  @moduledoc """
  OAuth token management for Deribit API with caching.

  Manages OAuth2 client credentials flow with automatic refresh
  and token caching to avoid unnecessary token requests.
  """

  use GenServer
  require Logger

  # Refresh 120 seconds before expiry
  @refresh_buffer 120
  @table_name :deribit_oauth_cache
  # Check token expiry every 30 seconds
  @refresh_check_interval 30_000
  # Table for tracking in-flight token requests
  @inflight_table :deribit_oauth_inflight

  # Client API

  @doc """
  Starts the OAuth manager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a valid OAuth token, refreshing if necessary.

  Returns `{:ok, token}` or `{:error, reason}`.
  """
  @spec get_token(String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def get_token(client_id, client_secret) do
    ensure_started()
    start_time = System.monotonic_time()
    host = get_host()

    {result, source} =
      case get_cached_token(client_id, host) do
        {:ok, token} ->
          {{:ok, token}, :cache}

        :expired ->
          # Use single-flight protection to avoid concurrent refresh requests
          {refresh_token_single_flight(client_id, client_secret, host), :refresh}
      end

    duration = System.monotonic_time() - start_time
    status = if match?({:ok, _}, result), do: :ok, else: :error

    :telemetry.execute(
      [:zen_cex, :exchange, :auth, :oauth, :get_token],
      %{duration: duration},
      %{client_id: client_id, source: source, status: status}
    )

    result
  end

  @doc """
  Signs a request with OAuth authentication.
  """
  @spec sign_request(map(), String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def sign_request(request, client_id, client_secret) do
    case get_token(client_id, client_secret) do
      {:ok, token} ->
        headers = Map.get(request, :headers, [])
        signed_headers = [{"Authorization", "Bearer #{token}"} | headers]
        {:ok, Map.put(request, :headers, signed_headers)}

      error ->
        error
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for token cache
    :ets.new(@table_name, [:set, :public, :named_table])
    # Create ETS table for tracking in-flight requests
    :ets.new(@inflight_table, [:set, :public, :named_table])

    # Schedule periodic token refresh checks
    schedule_refresh_check()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_token_expiry, state) do
    # Check all cached tokens for upcoming expiry
    check_and_refresh_expiring_tokens()

    # Schedule next check
    schedule_refresh_check()

    {:noreply, state}
  end

  # Private Functions

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        # Start the GenServer if not running
        {:ok, _pid} = start_link()

      _pid ->
        :ok
    end
  end

  defp get_cached_token(client_id, host) do
    case :ets.lookup(@table_name, {:token, client_id, host}) do
      [{_, token, expiry}] ->
        if System.system_time(:second) < expiry do
          {:ok, token}
        else
          :expired
        end

      [] ->
        :expired
    end
  end

  defp refresh_token_single_flight(client_id, client_secret, host) do
    inflight_key = {:inflight, client_id, host}

    # Check if a refresh is already in progress
    case :ets.lookup(@inflight_table, inflight_key) do
      [{_, pid}] when is_pid(pid) ->
        # Another process is already refreshing, wait for it
        wait_for_inflight_refresh(pid, client_id, host)

      _ ->
        # Mark this refresh as in-flight
        :ets.insert(@inflight_table, {inflight_key, self()})

        try do
          result = refresh_token(client_id, client_secret, host)
          # Clean up inflight marker
          :ets.delete(@inflight_table, inflight_key)
          result
        rescue
          error ->
            # Clean up inflight marker on error
            :ets.delete(@inflight_table, inflight_key)
            reraise error, __STACKTRACE__
        end
    end
  end

  defp wait_for_inflight_refresh(pid, client_id, host, timeout \\ 5000) do
    # Monitor the process doing the refresh
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} ->
        # Process finished, try to get the token from cache
        case get_cached_token(client_id, host) do
          {:ok, token} -> {:ok, token}
          :expired -> {:error, :refresh_failed}
        end
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        {:error, :refresh_timeout}
    end
  end

  defp refresh_token(client_id, client_secret, host) do
    with {:ok, response} <- request_token(client_id, client_secret),
         {:ok, token} <- parse_token_response(response) do
      cache_token(client_id, token, host)
      {:ok, token.access_token}
    end
  end

  defp request_token(client_id, client_secret) do
    # Make a GET request with query params for Deribit OAuth
    url = get_auth_url()

    params = %{
      grant_type: "client_credentials",
      client_id: client_id,
      client_secret: client_secret
    }

    case Req.get(url, params: params) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, %{status: 200, body: Jason.decode!(body)}}

      {:ok, %{status: 200, body: body}} ->
        {:ok, %{status: 200, body: body}}

      {:ok, response} ->
        {:ok, %{status: response.status, body: response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_token_response(%{status: 200, body: body}) do
    case body do
      %{"result" => %{"access_token" => token, "expires_in" => expires_in}} ->
        {:ok,
         %{
           access_token: token,
           expires_in: expires_in,
           expiry: System.system_time(:second) + expires_in - @refresh_buffer
         }}

      %{"error" => error} ->
        {:error, {:auth_error, error}}

      _ ->
        {:error, :invalid_response}
    end
  end

  defp parse_token_response(%{status: status, body: body}) do
    {:error, {:http_error, status, body}}
  end

  defp cache_token(client_id, token, host) do
    :ets.insert(@table_name, {{:token, client_id, host}, token.access_token, token.expiry})
    Logger.debug("Cached OAuth token for #{client_id} on #{host}, expires at #{token.expiry}")
  end

  defp get_host do
    System.get_env("DERIBIT_HOST", "test.deribit.com")
  end

  defp get_auth_url do
    host = get_host()
    "https://#{host}/api/v2/public/auth"
  end

  @spec schedule_refresh_check() :: reference()
  defp schedule_refresh_check do
    Process.send_after(self(), :check_token_expiry, @refresh_check_interval)
  end

  @spec check_and_refresh_expiring_tokens() :: :ok
  defp check_and_refresh_expiring_tokens do
    # Get all cached tokens
    tokens = :ets.tab2list(@table_name)
    current_time = System.system_time(:second)

    Enum.each(tokens, fn entry ->
      handle_token_entry(entry, current_time)
    end)

    :ok
  end

  defp handle_token_entry({{:token, client_id, host}, _token, expiry}, current_time) do
    # Check if token needs refresh (within 150 seconds of expiry for safety)
    if current_time >= expiry - 150 do
      refresh_expiring_token(client_id, host)
    end
  end

  defp handle_token_entry({{:token, client_id}, _token, expiry}, current_time) do
    # Handle legacy cache entries (without host) for backward compatibility
    if current_time >= expiry - 150 do
      Logger.info("Found legacy token entry for #{client_id}, will migrate on refresh")
      # Delete the legacy entry
      :ets.delete(@table_name, {:token, client_id})
    end
  end

  defp handle_token_entry(_entry, _current_time), do: :ok

  defp refresh_expiring_token(client_id, host) do
    Logger.info("Proactively refreshing expiring token for client: #{client_id}")

    # Try to get credentials from environment
    client_secret = System.get_env("DERIBIT_CLIENT_SECRET")

    if client_secret do
      case refresh_token(client_id, client_secret, host) do
        {:ok, _token} ->
          Logger.info("Successfully refreshed token for client: #{client_id} on #{host}")

        {:error, reason} ->
          Logger.warning(
            "Failed to refresh token for client #{client_id} on #{host}: #{inspect(reason)}"
          )
      end
    else
      Logger.debug(
        "Cannot proactively refresh token for #{client_id} - secret not in environment"
      )
    end
  end
end
