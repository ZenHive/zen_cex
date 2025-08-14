defmodule ZenCex.Auth do
  @moduledoc """
  Authentication module for centralized exchange REST APIs.

  Provides authentication methods for:
  - Binance: HMAC-SHA256 signatures
  - Kraken: HMAC-SHA512 with nonce (includes Content-Type header)
  - Deribit: OAuth2 client credentials flow

  ## Header Conventions

  This module uses standard HTTP header casing (Title-Case) for consistency:
  - `Authorization` for OAuth tokens
  - `Content-Type` for request content types
  - `API-Key`, `API-Sign` for Kraken
  - `X-MBX-APIKEY` for Binance (exchange-specific format)

  ## Environment Variables

  Each exchange requires specific environment variables:

  - **Binance**: `BINANCE_API_KEY`, `BINANCE_API_SECRET`
  - **Kraken**: `KRAKEN_API_KEY`, `KRAKEN_API_SECRET`
  - **Deribit**: `DERIBIT_CLIENT_ID`, `DERIBIT_CLIENT_SECRET`

  For Deribit OAuth, the module uses `DERIBIT_HOST` (defaults to "test.deribit.com").
  The OAuth token management includes:
  - Single-flight protection to avoid concurrent token refreshes
  - Token caching with automatic refresh 120 seconds before expiry
  - Proactive refresh using background GenServer (requires env variables)

  ## Telemetry Events

  This module emits the following telemetry events:

  * `[:zen_cex, :exchange, :auth, :sign_request, :start]` - Dispatched when request signing starts
    * Measurements: `%{system_time: integer()}`
    * Metadata: `%{exchange: atom()}`

  * `[:zen_cex, :exchange, :auth, :sign_request, :stop]` - Dispatched when request signing completes
    * Measurements: `%{duration: integer()}`
    * Metadata: `%{exchange: atom(), status: :ok | :error}`

  * `[:zen_cex, :exchange, :auth, :sign_request, :exception]` - Dispatched on signing errors
    * Measurements: `%{duration: integer()}`
    * Metadata: `%{exchange: atom(), kind: atom(), reason: term()}`
  """

  require Logger

  @doc """
  Generates HMAC-SHA256 signature for Binance API.

  ## Parameters
  - `secret`: API secret key
  - `message`: Message to sign (typically query string)
  - `format`: Output format (:hex or :base64)

  ## Examples
      iex> Auth.hmac_sha256("secret", "message", :hex)
      "8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b"
  """
  @spec hmac_sha256(String.t(), String.t(), :hex | :base64) :: String.t()
  def hmac_sha256(secret, message, format) do
    signature = :crypto.mac(:hmac, :sha256, secret, message)

    case format do
      :hex -> Base.encode16(signature, case: :lower)
      :base64 -> Base.encode64(signature)
    end
  end

  @doc """
  Generates monotonically increasing nonce for Kraken API.

  Uses microseconds since epoch with an atomic counter to ensure uniqueness
  even when called in rapid succession.

  ## Examples
      iex> nonce1 = Auth.kraken_nonce()
      iex> nonce2 = Auth.kraken_nonce()
      iex> String.to_integer(nonce2) > String.to_integer(nonce1)
      true
  """
  @spec kraken_nonce() :: String.t()
  def kraken_nonce do
    # Get microseconds since epoch
    microseconds = System.system_time(:microsecond)

    # Use an ETS counter to ensure uniqueness for rapid calls
    # Each process will check/create the table if needed
    table = ensure_nonce_table()

    # Use a global counter that always increments
    # This ensures absolutely unique values even across processes
    # The update_counter operation is atomic and works across processes
    global_counter =
      try do
        :ets.update_counter(table, :global_nonce_counter, {2, 1}, {:global_nonce_counter, 0})
      rescue
        ArgumentError ->
          # Table might have been deleted, recreate it
          ensure_nonce_table()
          :ets.update_counter(table, :global_nonce_counter, {2, 1}, {:global_nonce_counter, 0})
      end

    # Combine microseconds with counter to ensure uniqueness and monotonic increase
    # Format: microseconds + 6-digit counter (allows 1M requests before overflow)
    "#{microseconds}#{String.pad_leading(Integer.to_string(rem(global_counter, 1_000_000)), 6, "0")}"
  end

  @doc """
  Handles Deribit OAuth2 operations.

  ## Operations
  - `:request` - Generate OAuth token request
  - `{:calculate_expiry, expires_in}` - Calculate token expiry with buffer
  - `{:needs_refresh?, expiry_time}` - Check if token needs refresh
  - `{:format_header, token}` - Format authorization header

  ## Examples
      iex> {:ok, request} = Auth.deribit_oauth("client_id", "secret", :request)
      iex> request.grant_type
      "client_credentials"
  """
  @spec deribit_oauth(String.t(), String.t(), atom() | tuple()) ::
          {:ok, map()}
          | boolean()
          | integer()
          | float()
          | {String.t(), String.t()}
          | {:error, atom()}
  def deribit_oauth(client_id, client_secret, operation) do
    case operation do
      :request ->
        {:ok,
         %{
           grant_type: "client_credentials",
           client_id: client_id,
           client_secret: client_secret
         }}

      {:calculate_expiry, expires_in} ->
        # Add 120 second buffer before actual expiry
        System.system_time(:second) + expires_in - 120

      {:needs_refresh?, expiry_time} ->
        current_time = System.system_time(:second)
        # Refresh if we're within the buffer period (120s) of expiry
        current_time >= expiry_time - 120

      {:format_header, token} ->
        {"Authorization", "Bearer #{token}"}

      _ ->
        {:error, :invalid_operation}
    end
  end

  @doc """
  Validates timestamp is within acceptable window.

  ## Parameters
  - `timestamp`: Timestamp in milliseconds
  - `window`: Acceptable window in milliseconds (e.g., 5000 for 5 seconds)

  ## Examples
      iex> now = System.system_time(:millisecond)
      iex> Auth.validate_timestamp(now, 5000)
      :ok

      iex> old = System.system_time(:millisecond) - 10000
      iex> Auth.validate_timestamp(old, 5000)
      {:error, :timestamp_expired}
  """
  @spec validate_timestamp(integer(), integer()) :: :ok | {:error, atom()}
  def validate_timestamp(timestamp, window) do
    now = System.system_time(:millisecond)
    diff = now - timestamp

    cond do
      diff > window ->
        {:error, :timestamp_expired}

      diff < -window ->
        {:error, :timestamp_too_far}

      true ->
        :ok
    end
  end

  @doc """
  Adds Binance-required timestamp and receive window parameters.

  Binance requires a timestamp for all signed requests and optionally accepts
  a recvWindow parameter to specify how long the request is valid.

  ## Parameters
  - `params`: Existing parameters map
  - `opts`: Options
    - `:recv_window` - Time window in milliseconds (default: 5000)
    - `:timestamp` - Custom timestamp (default: current time)

  ## Examples
      iex> params = %{symbol: "BTCUSDT", side: "BUY"}
      iex> updated = Auth.add_binance_timestamp(params)
      iex> Map.has_key?(updated, "timestamp")
      true
      iex> Map.has_key?(updated, "recvWindow")
      true

      iex> custom = Auth.add_binance_timestamp(%{}, recv_window: 10000)
      iex> custom["recvWindow"]
      "10000"
  """
  @spec add_binance_timestamp(map(), keyword()) :: map()
  def add_binance_timestamp(params, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, System.system_time(:millisecond))
    recv_window = Keyword.get(opts, :recv_window, 5000)

    params
    |> Map.put("timestamp", to_string(timestamp))
    |> Map.put("recvWindow", to_string(recv_window))
  end

  @doc """
  Retrieves API keys for an exchange from environment variables.

  ## Parameters
  - `exchange`: Exchange atom (:binance, :kraken, :deribit)

  ## Returns
  - `{:ok, map()}` with keys for the exchange
  - `{:error, atom()}` if keys are missing or exchange unknown

  ## Examples
      iex> System.put_env("BINANCE_API_KEY", "key")
      iex> System.put_env("BINANCE_API_SECRET", "secret")
      iex> {:ok, keys} = Auth.get_api_keys(:binance)
      iex> keys.api_key
      "key"
  """
  @spec get_api_keys(atom()) :: {:ok, map()} | {:error, atom() | String.t()}
  def get_api_keys(exchange) do
    case exchange do
      :binance ->
        get_standard_keys("BINANCE")

      :kraken ->
        get_standard_keys("KRAKEN")

      :deribit ->
        get_oauth_keys("DERIBIT")

      _ ->
        {:error, :unknown_exchange}
    end
  end

  @doc """
  Signs a request according to exchange-specific requirements.

  ## Parameters
  - `exchange`: Exchange atom (:binance, :kraken, :deribit)
  - `request`: Request map with method, url, params/body, headers
  - `opts`: Additional options

  ## Returns
  - `{:ok, signed_request}` with added signatures/headers
  - `{:error, reason}` if signing fails

  ## Examples
      iex> request = %{method: :get, url: "https://api.binance.com/test", params: %{}}
      iex> {:ok, signed} = Auth.sign_request(:binance, request, [])
      iex> signed.params["signature"]
  """
  @spec sign_request(atom(), map(), keyword()) :: {:ok, map()} | {:error, atom() | String.t()}
  def sign_request(exchange, request, _opts) do
    metadata = %{exchange: exchange}
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:zen_cex, :exchange, :auth, :sign_request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    result =
      try do
        with {:ok, keys} <- get_api_keys(exchange) do
          case exchange do
            :binance ->
              sign_binance_request(request, keys)

            :kraken ->
              sign_kraken_request(request, keys)

            :deribit ->
              sign_deribit_request(request, keys)

            _ ->
              {:error, :unknown_exchange}
          end
        end
      rescue
        exception ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:zen_cex, :exchange, :auth, :sign_request, :exception],
            %{duration: duration},
            Map.merge(metadata, %{
              kind: :error,
              reason: exception,
              stacktrace: __STACKTRACE__
            })
          )

          reraise exception, __STACKTRACE__
      end

    duration = System.monotonic_time() - start_time
    status = if match?({:ok, _}, result), do: :ok, else: :error

    :telemetry.execute(
      [:zen_cex, :exchange, :auth, :sign_request, :stop],
      %{duration: duration},
      Map.merge(metadata, %{status: status})
    )

    result
  end

  # Private functions

  @spec ensure_nonce_table() :: atom()
  defp ensure_nonce_table do
    table_name = :kraken_nonce_table

    # Try to get the existing table or create it
    case :ets.info(table_name) do
      :undefined ->
        # Table doesn't exist, try to create it
        try do
          # Create as public so all processes can access it
          :ets.new(table_name, [:set, :public, :named_table, {:write_concurrency, true}])
        rescue
          ArgumentError ->
            # Another process created it in the meantime, that's fine
            :ok
        end

        table_name

      _info ->
        # Table exists and is accessible
        table_name
    end
  end

  @spec get_standard_keys(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  defp get_standard_keys(prefix) do
    api_key = System.get_env("#{prefix}_API_KEY")
    secret_key = System.get_env("#{prefix}_API_SECRET")

    cond do
      is_nil(api_key) ->
        {:error, "Missing environment variable: #{prefix}_API_KEY"}

      is_nil(secret_key) ->
        {:error, "Missing environment variable: #{prefix}_API_SECRET"}

      true ->
        {:ok, %{api_key: api_key, secret_key: secret_key}}
    end
  end

  @spec get_oauth_keys(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  defp get_oauth_keys(prefix) do
    client_id = System.get_env("#{prefix}_CLIENT_ID")
    client_secret = System.get_env("#{prefix}_CLIENT_SECRET")

    cond do
      is_nil(client_id) ->
        {:error, "Missing environment variable: #{prefix}_CLIENT_ID"}

      is_nil(client_secret) ->
        {:error, "Missing environment variable: #{prefix}_CLIENT_SECRET"}

      true ->
        {:ok, %{client_id: client_id, client_secret: client_secret}}
    end
  end

  @spec sign_binance_request(map(), map()) :: {:ok, map()}
  defp sign_binance_request(request, keys) do
    # Extract params from request (handle both map access and struct patterns)
    current_params =
      case request do
        %{params: params} when is_map(params) -> params
        %{"params" => params} when is_map(params) -> params
        _ -> %{}
      end

    # Add timestamp and recvWindow if not present
    params_with_timestamp =
      if Map.has_key?(current_params, "timestamp") do
        current_params
      else
        add_binance_timestamp(current_params, request[:binance_opts] || [])
      end

    # Build query string from params
    query_string =
      params_with_timestamp
      |> Enum.sort()
      |> Enum.map_join("&", fn {k, v} -> "#{k}=#{v}" end)

    # Generate signature
    signature = hmac_sha256(keys.secret_key, query_string, :hex)

    # Add signature to params
    signed_params = Map.put(params_with_timestamp, "signature", signature)

    # Add API key header (Binance uses uppercase for this header)
    headers = Map.get(request, :headers, [])
    signed_headers = [{"X-MBX-APIKEY", keys.api_key} | headers]

    {:ok, Map.merge(request, %{params: signed_params, headers: signed_headers})}
  end

  @spec sign_kraken_request(map(), map()) :: {:ok, map()}
  defp sign_kraken_request(request, keys) do
    # Generate nonce
    nonce = kraken_nonce()

    # Add nonce to body
    body = Map.put(request[:body] || %{}, "nonce", nonce)

    # Get API path from URL
    uri = URI.parse(request.url)
    api_path = uri.path

    # Create message for signature: nonce + post_data
    post_data = URI.encode_query(body)
    message = nonce <> post_data

    # Decode base64 secret (Kraken provides base64 encoded secrets)
    # IMPORTANT: Kraken's API documentation states that API secrets are base64-encoded.
    # However, some testing environments or third-party services might provide
    # non-base64 secrets. This code handles both cases gracefully:
    # - If the secret is valid base64, it decodes it (standard Kraken format)
    # - If it's not valid base64, it uses the raw string (for testing/compatibility)
    # This dual handling ensures compatibility with both production Kraken API
    # and various testing/sandbox environments.
    decoded_secret =
      case Base.decode64(keys.secret_key) do
        {:ok, decoded} -> decoded
        # Use as-is if not base64 (testing environments may use raw secrets)
        :error -> keys.secret_key
      end

    # SHA256 hash of nonce + post_data
    sha256_hash = :crypto.hash(:sha256, message)

    # HMAC-SHA512 of path + SHA256 hash
    hmac_message = api_path <> sha256_hash
    signature = :crypto.mac(:hmac, :sha512, decoded_secret, hmac_message)
    api_sign = Base.encode64(signature)

    # Add headers - Kraken expects Content-Type for private endpoints
    headers = Map.get(request, :headers, [])

    signed_headers = [
      {"API-Key", keys.api_key},
      {"API-Sign", api_sign},
      {"Content-Type", "application/x-www-form-urlencoded"}
      | headers
    ]

    {:ok, Map.merge(request, %{body: body, headers: signed_headers})}
  end

  @spec sign_deribit_request(map(), map()) :: {:ok, map()} | {:error, any()}
  defp sign_deribit_request(request, keys) do
    # Use the DeribitOAuth module for token management and signing
    alias ZenCex.Auth.DeribitOAuth

    DeribitOAuth.sign_request(request, keys.client_id, keys.client_secret)
  end
end
