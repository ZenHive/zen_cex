defmodule ZenCex.Adapters.BaseAuth do
  @moduledoc """
  Common authentication patterns for all exchange adapters.

  Provides shared authentication logic including credential resolution,
  validation, and request signing workflow that all adapters can use.

  ## Credential Resolution Standard

  **CRITICAL**: ALL exchange adapters MUST use `ZenCex.Core.Auth.get_credentials/2`
  for credential resolution. This provides:
  - Consistent priority: request private data → environment variables
  - Automatic testnet/production credential switching
  - Proper credential validation
  - Memory-safe credential handling

  **Never use `System.get_env/1` directly** - it bypasses the standard credential
  resolution flow and breaks per-request credential support.

  ## Usage Pattern

      defmodule ZenCex.Adapters.MyExchange.Auth do
        use ZenCex.Adapters.BaseAuth, exchange: :my_exchange

        @impl true
        def sign_request(request, api_key, api_secret, opts) do
          # Extract parameters from opts
          all_params = opts[:all_params]        # Merged query + body params
          has_json_option = opts[:has_json_option]  # true if request has JSON body
          body_params = opts[:body_params]      # JSON body parameters only

          # Exchange-specific signing logic
          timestamp = System.system_time(:millisecond)
          params_with_timestamp = Map.put(all_params, "timestamp", timestamp)

          signature = create_hmac_signature(params_with_timestamp, api_secret)

          request
          |> Req.Request.put_header("X-API-KEY", api_key)
          |> add_signature_to_url(params_with_timestamp, signature)
        end
      end

  ## Credential Resolution Example

      # The apply_auth/1 function automatically resolves credentials using Core.Auth:
      def apply_auth(request) do
        case CoreAuth.get_credentials(request, :my_exchange) do
          {api_key, api_secret} when is_binary(api_key) and is_binary(api_secret) ->
            # Credentials found - proceed with signing
            sign_request(request, api_key, api_secret, ...)

          _ ->
            # No valid credentials - pass request through unchanged
            request
        end
      end
  """

  defmacro __using__(opts) do
    exchange = Keyword.fetch!(opts, :exchange)

    quote do
      @behaviour ZenCex.Adapters.BaseAuth

      alias ZenCex.Core.Auth, as: CoreAuth

      require Logger

      @doc """
      Applies authentication to a request if valid credentials are available.

      This function implements the standard authentication flow:
      1. Check if request needs authentication (has :auth_required in private)
      2. Validate credentials exist for the exchange
      3. Extract and sign the request with exchange-specific logic
      4. Return the authenticated request
      """
      @spec apply_auth(Req.Request.t()) :: Req.Request.t()
      def apply_auth(%Req.Request{} = request) do
        exchange = unquote(exchange)

        # Check if auth is required for this request
        auth_required = get_in(request.private, [:auth_required])

        if auth_required == false do
          request
        else
          case CoreAuth.get_credentials(request, exchange) do
            {api_key, api_secret} when is_binary(api_key) and is_binary(api_secret) ->
              # Log credential status for debugging
              log_credential_status(exchange, api_key, api_secret)

              # Extract common request parameters
              {all_params, has_json_option, body_params} = extract_request_params(request)

              # Delegate to exchange-specific signing
              sign_request(request, api_key, api_secret,
                all_params: all_params,
                has_json_option: has_json_option,
                body_params: body_params
              )

            _ ->
              # No valid credentials, pass through unchanged
              request
          end
        end
      end

      @doc false
      @spec extract_request_params(Req.Request.t()) :: {map(), boolean(), map()}
      defp extract_request_params(request) do
        has_json_option = Map.has_key?(request.options, :json)
        query_params = request.options[:params] || %{}
        body_params = request.options[:json] || %{}

        # Merge all params for signature generation
        all_params = Map.merge(body_params, query_params)

        {all_params, has_json_option, body_params}
      end

      @doc false
      @spec log_credential_status(atom(), String.t(), String.t()) :: :ok
      defp log_credential_status(exchange, api_key, api_secret) do
        if System.get_env("ZEN_CEX_DEBUG_AUTH") in ["true", "TRUE", "1"] do
          key_preview = String.slice(api_key, 0..7) <> "..."
          # api_secret is always a binary at this point
          secret_preview = "***"
          Logger.debug("#{exchange} auth: key=#{key_preview}, secret=#{secret_preview}")
        end
      end

      @doc false
      @spec auth_required?(Req.Request.t()) :: boolean()
      defp auth_required?(request) do
        get_in(request.private, [:auth_required]) != false
      end

      # Allow adapters to override these helpers if needed
      defoverridable extract_request_params: 1, log_credential_status: 3, auth_required?: 1
    end
  end

  @type sign_options :: [
          all_params: map(),
          has_json_option: boolean(),
          body_params: map()
        ]

  @doc """
  Callback for exchange-specific request signing logic.

  Implement this callback to add exchange-specific authentication to requests.
  The callback receives pre-extracted request parameters and credentials, and
  should return the modified request with authentication applied.

  ## Parameters
    - `request` - The Req.Request struct to sign
    - `api_key` - The API key credential (guaranteed to be a non-empty binary)
    - `api_secret` - The API secret credential (guaranteed to be a non-empty binary)
    - `opts` - Keyword list with pre-extracted request data:
      - `:all_params` - Map of ALL parameters (query params merged with body params)
        Used for signature generation when the exchange signs both query and body.
      - `:has_json_option` - Boolean indicating if the request has a JSON body.
        Use this to determine if params should go in URL (false) or body (true).
      - `:body_params` - Map of ONLY the JSON body parameters (empty map if no JSON body).
        Use when the exchange requires separate handling of body vs query params.

  ## Returns
    - Modified `Req.Request.t()` with authentication headers, signed URL, or signed body

  ## Implementation Notes

  Common patterns for using the opts:
  - **HMAC signature of all params**: Use `all_params` to generate signature
  - **Separate query and body**: Use `body_params` vs query params from request.url
  - **Conditional param placement**: Use `has_json_option` to decide URL vs body

  The request params are already extracted by `extract_request_params/1` which you
  can call directly if you need to customize the extraction logic.

  ## Example Implementation

      @impl true
      def sign_request(request, api_key, api_secret, opts) do
        all_params = opts[:all_params]
        has_json_option = opts[:has_json_option]

        # Add timestamp for signature
        timestamp = System.system_time(:millisecond)
        params_with_timestamp = Map.put(all_params, "timestamp", timestamp)

        # Generate HMAC-SHA256 signature
        signature = :crypto.mac(:hmac, :sha256, api_secret, encode_params(params_with_timestamp))
                    |> Base.encode16(case: :lower)

        # Build signed URL
        query_string = encode_params(params_with_timestamp) <> "&signature=" <> signature

        request
        |> Req.Request.put_header("x-api-key", api_key)
        |> update_request_url(query_string)
      end
  """
  @callback sign_request(Req.Request.t(), binary(), binary(), sign_options()) :: Req.Request.t()
end
