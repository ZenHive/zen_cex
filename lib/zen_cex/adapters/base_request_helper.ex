defmodule ZenCex.Adapters.BaseRequestHelper do
  @moduledoc """
  Common request execution patterns for all exchange adapters.

  This module provides shared functionality for executing HTTP requests including:
  - Success status range checking
  - Request option building for GET/POST methods
  - Parameter handling for query strings and request bodies
  - Consistent error handling patterns

  ## Usage

      defmodule MyExchange.RequestHelper do
        use ZenCex.Adapters.BaseRequestHelper
        
        # Optionally override specific behaviors
        def build_request_options(config, params, opts) do
          # Custom logic here
          super(config, params, opts)
        end
      end
  """

  @doc """
  Makes a module use the BaseRequestHelper behavior.
  """
  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts \\ []) do
    quote do
      alias ZenCex.Core.HTTP

      require Logger

      @success_status_range 200..299
      # 30 seconds in milliseconds
      @default_timeout 30_000

      @doc """
      Executes an HTTP request with the given configuration.

      ## Parameters
      - config: Endpoint configuration map with :method, :path, :requires_auth, etc.
      - request_params: Parameters to send with the request
      - opts: Additional options like :timeout, :api_type
      - base_url: The base URL for the exchange
      - exchange: The exchange atom (e.g., :binance, :bybit)
      - operation_type: The operation being performed (for telemetry/logging)

      ## Returns
      - {:ok, response} for successful requests (2xx status codes)
      - {:error, {:http_error, status, body}} for HTTP errors (non-2xx status codes)
      - {:error, exception} for network or other exceptions
      """
      @spec execute_request(map(), map(), keyword(), String.t(), atom(), atom()) ::
              {:ok, any()} | {:error, term()}
      def execute_request(config, request_params, opts, base_url, exchange, operation_type) do
        api_type = Map.get(config, :api_type, Keyword.get(opts, :api_type, :spot))

        base_opts = build_base_options(config, opts, base_url, api_type)

        # Check if request_params is already structured with :params/:json keys
        # or if it's raw params that need to be processed
        request_opts =
          if Map.has_key?(request_params, :params) or Map.has_key?(request_params, :json) do
            # Already structured, merge directly
            base_opts
            |> maybe_add_option(:params, request_params[:params])
            |> maybe_add_option(:json, request_params[:json])
          else
            # Raw params, process through build_request_options
            build_request_options(config, request_params, base_opts)
          end

        # Build and execute request using Req
        # Remove api_type from request_opts as it's not a valid Req option
        {api_type_value, clean_opts} = Map.pop(request_opts, :api_type)

        request =
          exchange
          |> HTTP.base_request(operation_type)
          |> Req.merge(Map.to_list(clean_opts))
          |> Req.merge(opts)
          |> then(fn req ->
            if api_type_value do
              Req.Request.put_private(req, :api_type, api_type_value)
            else
              req
            end
          end)

        # Execute request and handle response
        case Req.request(request) do
          {:ok, %Req.Response{status: status, body: body}} when status in @success_status_range ->
            {:ok, body}

          {:ok, %Req.Response{status: status, body: body} = response} ->
            Logger.warning("Request failed with status #{status}: #{inspect(body)}")
            # Return HTTP error tuple with status and body for consistent error handling
            {:error, {:http_error, status, body}}

          {:error, exception} ->
            Logger.error("Request failed with error: #{inspect(exception)}")
            {:error, exception}
        end
      end

      @doc """
      Builds the base options map for the request.

      ## Override
      Adapters may override this to add exchange-specific options.
      """
      @spec build_base_options(map(), keyword(), String.t(), atom()) :: map()
      def build_base_options(config, opts, base_url, api_type) do
        %{
          method: config.method,
          url: base_url <> config.path,
          receive_timeout: Keyword.get(opts, :timeout, config[:timeout] || @default_timeout),
          skip_auth: not Map.get(config, :requires_auth, false),
          # Exchanges typically don't want automatic retries
          retry: false,
          # api_type will be added to private fields, not as a Req option
          api_type: api_type
        }
      end

      @doc """
      Builds request options including query params or body based on method.

      ## Override
      Adapters may override this to handle exchange-specific parameter requirements.
      """
      @spec build_request_options(map(), map(), map()) :: map()
      def build_request_options(%{method: :get} = _config, params, base_opts) when map_size(params) > 0 do
        Map.put(base_opts, :params, params)
      end

      def build_request_options(%{method: :get}, _params, base_opts) do
        base_opts
      end

      def build_request_options(%{method: method} = _config, params, base_opts)
          when method in [:post, :put, :delete] and map_size(params) > 0 do
        base_opts
        |> maybe_add_option(:params, extract_query_params(params))
        |> maybe_add_option(:json, extract_body_params(params))
      end

      def build_request_options(%{method: method}, _params, base_opts) when method in [:post, :put, :delete] do
        base_opts
      end

      # Helper functions

      defp maybe_add_option(opts, _key, nil), do: opts
      defp maybe_add_option(opts, _key, empty) when empty == %{}, do: opts
      defp maybe_add_option(opts, key, value), do: Map.put(opts, key, value)

      defp extract_query_params(params) when is_map(params) do
        # Override this in specific adapters if needed
        # Default: all params go to query string
        params
      end

      defp extract_body_params(params) when is_map(params) do
        # Override this in specific adapters if needed
        # Default: no body params
        %{}
      end

      # NOTE: format_error_message functions removed - we now return raw responses
      # for consistent error handling per library philosophy

      # Allow adapters to override these if needed
      defoverridable execute_request: 6,
                     build_base_options: 4,
                     build_request_options: 3
    end
  end
end
