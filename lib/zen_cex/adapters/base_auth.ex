defmodule ZenCex.Adapters.BaseAuth do
  @moduledoc """
  Common authentication patterns for all exchange adapters.

  Provides shared authentication logic including credential resolution,
  validation, and request signing workflow that all adapters can use.

  ## Usage

      defmodule ZenCex.Adapters.MyExchange.Auth do
        use ZenCex.Adapters.BaseAuth, exchange: :my_exchange

        @impl true
        def sign_request(request, api_key, api_secret, opts) do
          # Exchange-specific signing logic
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
        if Application.get_env(:zen_cex, :debug_auth, false) do
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

  ## Parameters
    - `request` - The Req.Request to sign
    - `api_key` - The API key credential
    - `api_secret` - The API secret credential
    - `opts` - Keyword list with:
      - `:all_params` - Merged query and body parameters
      - `:has_json_option` - Whether request has JSON body
      - `:body_params` - JSON body parameters only

  ## Returns
    - Modified Req.Request with authentication applied
  """
  @callback sign_request(Req.Request.t(), binary(), binary(), sign_options()) :: Req.Request.t()
end
