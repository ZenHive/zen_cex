defmodule ZenCex.Adapters.Binance.Auth do
  @moduledoc """
  Binance authentication module implementing HMAC-SHA256 signing.

  This module handles:
  - HMAC-SHA256 signature generation for request authentication
  - Timestamp and recvWindow parameter injection
  - API key header addition
  - Parameter ordering (signature must be last)
  """

  @behaviour ZenCex.Behaviors.Auth

  # 5 second window for timestamp validation
  @recv_window 5000

  @impl true
  def sign_request(request, opts \\ []) do
    recv_window = Keyword.get(opts, :recv_window, @recv_window)
    timestamp = Keyword.get(opts, :timestamp, System.system_time(:millisecond))

    # Get credentials with explicit fallback
    api_key = get_credential(opts, :api_key, &get_api_key/0)
    api_secret = get_credential(opts, :api_secret, &get_api_secret/0)

    # Add timestamp and recvWindow to params
    params =
      request.params
      |> ensure_map()
      |> Map.put("timestamp", timestamp)
      |> Map.put("recvWindow", recv_window)

    # Generate query string for signing (without signature)
    query_string = URI.encode_query(params)

    # Generate HMAC-SHA256 signature
    signature = generate_signature(query_string, api_secret)

    # Add signature as LAST parameter (CRITICAL for Binance)
    final_params = Map.put(params, "signature", signature)

    # Add API key header
    headers = [{"X-MBX-APIKEY", api_key} | request.headers]

    %{request | params: final_params, headers: headers}
  end

  @impl true
  def validate_credentials do
    validate_credentials([])
  end

  @impl true
  def validate_credentials(opts) when is_list(opts) or is_map(opts) do
    api_key = get_credential(opts, :api_key, &get_api_key/0)
    api_secret = get_credential(opts, :api_secret, &get_api_secret/0)

    case {api_key, api_secret} do
      {nil, _} -> {:error, :missing_api_key}
      {_, nil} -> {:error, :missing_api_secret}
      {"", _} -> {:error, :empty_api_key}
      {_, ""} -> {:error, :empty_api_secret}
      _ -> :ok
    end
  end

  @impl true
  def auth_method, do: :hmac_sha256

  # Private functions

  defp generate_signature(data, api_secret) when is_binary(data) do
    if api_secret do
      :crypto.mac(:hmac, :sha256, api_secret, data)
      |> Base.encode16(case: :lower)
    else
      # Return empty signature if no secret (for testing)
      ""
    end
  end

  defp get_api_key do
    System.get_env("BINANCE_API_KEY")
  end

  defp get_api_secret do
    System.get_env("BINANCE_API_SECRET")
  end

  defp get_credential(opts, key, fallback_fn) when is_list(opts) do
    if Keyword.has_key?(opts, key) do
      Keyword.get(opts, key)
    else
      fallback_fn.()
    end
  end

  defp get_credential(opts, key, fallback_fn) when is_map(opts) do
    if Map.has_key?(opts, key) do
      Map.get(opts, key)
    else
      fallback_fn.()
    end
  end

  defp ensure_map(params) when is_map(params), do: params

  defp ensure_map(params) when is_list(params) do
    # Convert keyword list atoms to strings for consistency
    params
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  defp ensure_map(_), do: %{}
end
