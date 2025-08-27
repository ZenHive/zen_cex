defmodule ZenCex.Adapters.Binance.Auth do
  @moduledoc """
  Binance authentication module implementing HMAC-SHA256 signing.

  Supports all five Binance API types with identical authentication:
  - HMAC-SHA256 signature as LAST query parameter
  - X-MBX-APIKEY header with API key
  - Clock-synchronized timestamps
  """

  use ZenCex.Adapters.BaseAuth, exchange: :binance

  alias ZenCex.Adapters.Binance.ParameterBuilder
  alias ZenCex.Adapters.Binance.Signer

  require Logger

  @type api_type :: :spot | :margin | :usdm_futures | :coinm_futures | :portfolio

  @doc """
  Signs a request with the API type, API key, and secret.
  The API type can be passed either:
  - In the request's private data under :api_type
  - As the second parameter (for backward compatibility)
  """
  @spec sign_request_with_type(Req.Request.t(), api_type(), String.t(), String.t()) :: Req.Request.t()
  def sign_request_with_type(request, api_type, api_key, api_secret)
      when is_atom(api_type) and is_binary(api_key) and is_binary(api_secret) do
    # Extract params from request options
    all_params = request.options[:params] || %{}
    has_json_option = Map.has_key?(request.options, :json)
    body_params = request.options[:json] || %{}

    # Add API type to request private data
    request = Req.Request.put_private(request, :api_type, api_type)

    # Call the BaseAuth implementation
    sign_request(request, api_key, api_secret,
      all_params: all_params,
      has_json_option: has_json_option,
      body_params: body_params
    )
  end

  @impl true
  def sign_request(request, api_key, api_secret, opts) do
    api_type = get_in(request.private, [:api_type]) || :spot
    all_params = opts[:all_params] || %{}
    has_json_option = opts[:has_json_option] || false
    body_params = opts[:body_params] || %{}

    # Validate API type
    _base_url = base_url(api_type)

    # TODO: Remove debug logging once authentication is stable
    Logger.debug("Binance Auth: Starting to sign request for #{request.url}")

    # Add timing parameters
    params_with_timing = ParameterBuilder.ensure_timing_params(all_params, api_type)

    # Generate signature
    signature = Signer.create_signature(params_with_timing, api_secret)

    # Build authenticated request
    request
    |> Req.Request.put_header("x-mbx-apikey", api_key)
    |> build_authenticated_request(params_with_timing, signature, has_json_option, body_params)
  end

  # Builds the final authenticated request with signed URL
  @spec build_authenticated_request(
          Req.Request.t(),
          map(),
          String.t(),
          boolean(),
          map()
        ) :: Req.Request.t()
  defp build_authenticated_request(request, params_with_timing, signature, has_json_option, body_params) do
    request
    |> update_request_url(params_with_timing, signature)
    |> update_request_options(has_json_option, body_params)
  end

  # Updates the request URL with signed parameters
  @spec update_request_url(Req.Request.t(), map(), String.t()) :: Req.Request.t()
  defp update_request_url(request, params_with_timing, signature) do
    final_url = build_signed_url(request.url, params_with_timing, signature)
    Logger.debug("Binance Auth: Final URL: #{final_url}")
    %{request | url: URI.parse(final_url)}
  end

  # Updates the request options after signing
  @spec update_request_options(Req.Request.t(), boolean(), map()) :: Req.Request.t()
  defp update_request_options(request, has_json_option, body_params) do
    updated_options = clean_request_options(request.options, has_json_option, body_params)
    %{request | options: updated_options}
  end

  # Build the final URL with signed query string
  # Ensures proper parameter ordering as required by Binance API
  @spec build_signed_url(URI.t(), map(), String.t()) :: String.t()
  defp build_signed_url(url, params_with_timing, signature) do
    # Get existing query params (non-timing params like symbol, etc.)
    existing_params = Map.drop(params_with_timing, ["timestamp", "recvWindow"])

    # Build query string with proper ordering (delegate to ParameterBuilder)
    query_string = ParameterBuilder.build_ordered_query_string(existing_params, params_with_timing, signature)

    # Update the URL with the signed query string
    base_url = URI.to_string(%{url | query: nil})
    if query_string == "", do: base_url, else: "#{base_url}?#{query_string}"
  end

  # Clean request options after signing
  # Removes params (now in URL) and conditionally preserves json option
  @spec clean_request_options(map(), boolean(), map()) :: map()
  defp clean_request_options(options, has_json_option, body_params) do
    options
    # Always remove params - they're now in the URL
    |> Map.delete(:params)
    # Remove json first, then add back only if needed
    |> Map.delete(:json)
    |> then(fn opts ->
      # Only add json back if it was originally present AND has content
      if has_json_option and map_size(body_params) > 0 do
        Map.put(opts, :json, body_params)
      else
        opts
      end
    end)
  end

  @doc """
  Ensures timestamp and recvWindow parameters are present with appropriate values.

  If timestamp is not provided, generates a clock-synchronized timestamp.
  If recvWindow is not provided, uses the default value.
  Validates recvWindow doesn't exceed Binance limits.

  ## Parameters

    * `params` - Map of existing query parameters
    * `api_type` - The Binance API type (used for exchange-specific clock sync)

  ## Examples

      params = %{"symbol" => "BTCUSDT"}
      enhanced = Auth.ensure_timing_params(params, :spot)
      # Returns map with timestamp and recvWindow added
  """
  @spec ensure_timing_params(map(), api_type()) :: map()
  def ensure_timing_params(params, api_type) do
    ParameterBuilder.ensure_timing_params(params, api_type)
  end

  @doc """
  Generates HMAC-SHA256 signature for Binance API.

  Public function for backward compatibility and testing.
  Delegates to the Signer module for signature generation.

  ## Parameters

    * `params` - Map of query parameters (without signature)
    * `api_secret` - The Binance API secret

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "timestamp" => "1234567890"}
      iex> Auth.generate_signature(params, "secret")
      "..."  # 64-character hex string
  """
  @spec generate_signature(map(), String.t()) :: String.t()
  def generate_signature(params, api_secret) do
    Signer.create_signature(params, api_secret)
  end

  @doc """
  Returns the base URL for the given API type.

  ## Parameters

    * `api_type` - The Binance API type

  ## Examples

      iex> Auth.base_url(:spot)
      "https://api.binance.com"

      iex> Auth.base_url(:usdm_futures)
      "https://fapi.binance.com"
  """
  @spec base_url(api_type()) :: String.t()
  def base_url(:spot), do: "https://api.binance.com"
  def base_url(:margin), do: "https://api.binance.com"
  def base_url(:usdm_futures), do: "https://fapi.binance.com"
  def base_url(:coinm_futures), do: "https://dapi.binance.com"
  def base_url(:portfolio), do: "https://papi.binance.com"
end
