defmodule ZenCex.EndpointRegistry do
  @moduledoc """
  Macro for generating exchange endpoint functions from declarative specifications.

  Eliminates boilerplate for standard CRUD operations while allowing hand-written
  implementations for complex operations. Provides compile-time validation,
  type-safe function generation, and automatic documentation.

  ## Usage

  ```elixir
  defmodule MyExchange.Endpoints do
    use ZenCex.EndpointRegistry
    
    @endpoints [
      %{
        operation: :get_balances,
        method: :get,
        path: "/api/v3/account",
        requires_auth: true,
        response_parser: &Parser.parse_balances/1,
        error_mapping: &Parser.parse_error/1,
        retry_on: [:rate_limited, :timeout],
        max_retries: 2,
        weight: 10
      }
    ]
  end
  ```

  This generates:
  - `get_balances/1` and `get_balances/2` functions
  - Proper @spec annotations with error types
  - Documentation from the spec
  - Retry and rate limit handling

  ## Debug Mode

  Use `{:debug, opts}` to see generated code:

  ```elixir
  use ZenCex.EndpointRegistry, :debug
  ```
  """

  @default_timeout 30_000
  @default_retries 0

  defmacro __using__(opts) when is_list(opts) do
    adapter = Keyword.get(opts, :adapter)
    debug = Keyword.get(opts, :debug, false)

    quote do
      @before_compile unquote(__MODULE__)
      @endpoint_registry_adapter unquote(adapter)
      @endpoint_registry_debug unquote(debug)

      Module.register_attribute(__MODULE__, :endpoints, accumulate: false)

      # Import needed for generated functions
      alias ZenCex.Core.HTTP
      require Logger
    end
  end

  defmacro __using__(:debug) do
    quote do
      use unquote(__MODULE__), debug: true
    end
  end

  defmacro __using__(_opts) do
    quote do
      use unquote(__MODULE__), []
    end
  end

  defmacro __before_compile__(env) do
    endpoints = Module.get_attribute(env.module, :endpoints, [])
    adapter = Module.get_attribute(env.module, :endpoint_registry_adapter)
    debug = Module.get_attribute(env.module, :endpoint_registry_debug, false)

    # Validate endpoints at compile time
    validate_endpoints!(endpoints, env.module)

    # Generate AST for all endpoint functions
    ast = generate_endpoint_functions(endpoints, adapter, env.module)

    # Print debug output if requested
    if debug do
      print_debug_output(ast, env.module)
    end

    ast
  end

  defp validate_endpoints!(endpoints, module) when is_list(endpoints) do
    Enum.each(endpoints, fn endpoint ->
      validate_endpoint!(endpoint, module)
    end)
  end

  defp validate_endpoints!(_, module) do
    raise CompileError,
      description: "#{module}: @endpoints must be a list of endpoint specifications"
  end

  defp validate_endpoint!(endpoint, module) when is_map(endpoint) do
    required_keys = [:operation, :method, :path, :response_parser, :error_mapping]

    Enum.each(required_keys, fn key ->
      unless Map.has_key?(endpoint, key) do
        raise CompileError,
          description:
            "#{module}: Endpoint #{inspect(endpoint[:operation])} missing required key: #{key}"
      end
    end)

    # Validate method
    unless endpoint.method in [:get, :post, :put, :delete, :patch] do
      raise CompileError,
        description:
          "#{module}: Invalid HTTP method #{inspect(endpoint.method)} for #{endpoint.operation}"
    end

    # Validate parsers are function references
    unless is_function(endpoint.response_parser, 1) do
      raise CompileError,
        description: "#{module}: response_parser must be a function reference with arity 1"
    end

    unless is_function(endpoint.error_mapping, 1) do
      raise CompileError,
        description: "#{module}: error_mapping must be a function reference with arity 1"
    end

    # Validate retry configuration
    if Map.has_key?(endpoint, :retry_on) and not is_list(endpoint.retry_on) do
      raise CompileError,
        description: "#{module}: retry_on must be a list of error atoms"
    end

    # Critical: Never retry order placement
    if endpoint.operation in [:place_order, :place_limit_order, :place_market_order] do
      max_retries = Map.get(endpoint, :max_retries, 0)

      if max_retries > 0 do
        raise CompileError,
          description:
            "#{module}: Order placement operations MUST NOT have retries (found max_retries: #{max_retries})"
      end
    end
  end

  defp validate_endpoint!(_, module) do
    raise CompileError,
      description: "#{module}: Each endpoint must be a map"
  end

  defp generate_endpoint_functions(endpoints, adapter, module) do
    # Generate lookup functions
    lookup_functions = generate_lookup_functions(endpoints)

    # Generate endpoint operation functions
    operation_functions =
      endpoints
      |> Enum.map(&generate_operation_function(&1, adapter, module))
      |> List.flatten()

    # Combine all generated code
    quote do
      unquote_splicing(lookup_functions)
      unquote_splicing(operation_functions)
    end
  end

  defp generate_lookup_functions(endpoints) do
    # Generate pattern matching functions for each endpoint
    endpoint_clauses =
      Enum.map(endpoints, fn endpoint ->
        operation = endpoint.operation
        # We can include function references now since we're using module function captures
        # not anonymous functions

        quote do
          def get_endpoint(unquote(operation)) do
            unquote(Macro.escape(endpoint))
          end
        end
      end)

    # Add a catch-all clause that returns nil
    catch_all =
      quote do
        def get_endpoint(_), do: nil
      end

    # Generate all_endpoints function
    all_endpoints_function =
      quote do
        @doc """
        Returns all configured endpoints.
        """
        @spec all_endpoints() :: [map()]
        def all_endpoints do
          unquote(Macro.escape(endpoints))
        end
      end

    # Generate get_weight function
    weight_function =
      quote do
        @doc """
        Returns the rate limit weight for an operation.
        """
        @spec get_weight(atom()) :: integer()
        def get_weight(operation) do
          case get_endpoint(operation) do
            nil -> 1
            endpoint -> Map.get(endpoint, :weight, 1)
          end
        end
      end

    [
      quote do
        @doc """
        Returns the endpoint configuration for the given operation.

        ## Examples

            iex> get_endpoint(:get_balances)
            %{operation: :get_balances, path: "/api/v3/account", ...}
        """
        @spec get_endpoint(atom()) :: map() | nil
      end
    ] ++ endpoint_clauses ++ [catch_all, all_endpoints_function, weight_function]
  end

  defp generate_operation_function(endpoint, adapter, module) do
    operation = endpoint.operation
    method = endpoint.method
    path = endpoint.path
    requires_auth = Map.get(endpoint, :requires_auth, true)
    response_parser = endpoint.response_parser
    error_mapping = endpoint.error_mapping
    retry_on = Map.get(endpoint, :retry_on, [])
    max_retries = Map.get(endpoint, :max_retries, @default_retries)
    timeout = Map.get(endpoint, :timeout, @default_timeout)
    weight = Map.get(endpoint, :weight, 1)
    params_transformer = Map.get(endpoint, :params_transformer)
    api_type = Map.get(endpoint, :api_type)
    doc = Map.get(endpoint, :doc, "Executes the #{operation} operation")

    # Generate the function name
    func_name = operation

    # Generate the main function and its /2 variant
    [
      # Main function with default opts
      quote do
        @doc unquote(doc)
        @spec unquote(func_name)(map()) ::
                {:ok, term()} | {:error, term()}
        def unquote(func_name)(params \\ %{}) do
          unquote(func_name)(params, [])
        end
      end,

      # Function with opts
      quote do
        @spec unquote(func_name)(map(), keyword()) ::
                {:ok, term()} | {:error, term()}
        def unquote(func_name)(params, opts) do
          endpoint_config = %{
            operation: unquote(operation),
            method: unquote(method),
            path: unquote(path),
            requires_auth: unquote(requires_auth),
            weight: unquote(weight),
            timeout: Keyword.get(opts, :timeout, unquote(timeout)),
            max_retries: Keyword.get(opts, :max_retries, unquote(max_retries)),
            retry_on: unquote(retry_on)
          }

          # Add api_type if present
          endpoint_config =
            unquote(
              if api_type do
                quote do
                  Map.put(endpoint_config, :api_type, unquote(api_type))
                end
              else
                quote do
                  endpoint_config
                end
              end
            )

          # Transform params if transformer provided
          final_params =
            unquote(
              if params_transformer do
                quote do
                  unquote(params_transformer).(params)
                end
              else
                quote do
                  params
                end
              end
            )

          # Start telemetry span
          start_time = System.monotonic_time()

          start_metadata = %{
            exchange: unquote(adapter).__exchange__(),
            operation: unquote(operation),
            endpoint: unquote(path)
          }

          :telemetry.execute(
            [:zen_cex, :endpoint, :start],
            %{system_time: System.system_time()},
            start_metadata
          )

          # Execute the request
          result =
            case execute_endpoint_request(endpoint_config, final_params, unquote(adapter)) do
              {:ok, response} ->
                # Parse the response
                unquote(response_parser).(response)

              {:error, %Req.Response{status: status, body: body}} when status >= 400 ->
                # Map exchange-specific errors
                unquote(error_mapping).(body)

              {:error, reason} ->
                # Pass through other errors
                {:error, reason}
            end

          # End telemetry span
          duration = System.monotonic_time() - start_time

          {event_name, metadata} =
            case result do
              {:ok, _} ->
                {[:zen_cex, :endpoint, :success], Map.put(start_metadata, :status, :ok)}

              {:error, reason} ->
                {[:zen_cex, :endpoint, :error],
                 Map.merge(start_metadata, %{status: :error, reason: reason})}
            end

          :telemetry.execute(
            event_name,
            %{duration: duration},
            metadata
          )

          result
        end
      end,

      # Private helper for request execution (shared by all generated functions)
      # Using Module.defines_function?/3 for more reliable detection
      if not function_exported?(module, :execute_endpoint_request, 3) and
           not Module.defines?(module, {:execute_endpoint_request, 3}, :defp) do
        quote do
          defp execute_endpoint_request(config, params, adapter) do
            # Build the request
            request = build_request(config, params, adapter)

            # Add retry logic based on config
            request =
              if config.max_retries > 0 and length(config.retry_on) > 0 do
                Req.Request.prepend_error_steps(request,
                  endpoint_retry: &handle_retry(&1, config)
                )
              else
                request
              end

            # Execute the request
            case Req.request(request) do
              {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
                {:ok, response.body}

              {:ok, response} ->
                {:error, response}

              {:error, _} = error ->
                error
            end
          end

          defp build_request(config, params, adapter) do
            # Determine operation type from config
            operation_type = map_to_operation_type(config)

            # Determine base URL based on api_type if present
            base_url =
              if Map.has_key?(config, :api_type) and function_exported?(adapter, :base_url, 2) do
                adapter.base_url(adapter.current_env(), config.api_type)
              else
                adapter.base_url()
              end

            # Use Core.HTTP to create the base request with all middleware
            ZenCex.Core.HTTP.base_request(adapter.__exchange__(), operation_type)
            |> Req.merge(
              method: config.method,
              url: base_url <> config.path,
              params: if(config.method == :get, do: params, else: nil),
              json: if(config.method != :get, do: params, else: nil),
              receive_timeout: config.timeout,
              # Control auth based on endpoint config
              skip_auth: not config.requires_auth,
              # We handle retry at the endpoint level
              retry: false
            )
            # Store endpoint metadata for rate limiting and telemetry
            |> Req.Request.put_private(:rate_limit_weight, config.weight)
            |> Req.Request.put_private(:endpoint_config, config)
            |> Req.Request.put_private(:endpoint_operation, config.operation)
          end

          defp map_to_operation_type(config) do
            # Map endpoint operations to Core.HTTP operation types
            case config.operation do
              op when op in [:place_order, :cancel_order] -> :trading
              op when op in [:get_ticker] -> :market
              op when op in [:get_server_time] -> :health
              _ -> :standard
            end
          end

          # These functions are no longer needed - Core.HTTP handles auth and rate limiting

          defp handle_retry({request, exception}, config) do
            # Check if we should retry this error
            should_retry =
              case exception do
                %Req.Response{status: 429} -> :rate_limited in config.retry_on
                %Req.Response{status: 503} -> :timeout in config.retry_on
                %Req.Response{status: 504} -> :timeout in config.retry_on
                %Mint.TransportError{} -> :timeout in config.retry_on
                _ -> false
              end

            if should_retry do
              # Let Req's retry mechanism handle it
              {request, exception}
            else
              # Don't retry - use halt/2 with exception
              {Req.Request.halt(request, exception), exception}
            end
          end
        end
      else
        []
      end
    ]
  end

  defp print_debug_output(ast, module) do
    code =
      ast
      |> Macro.to_string()
      |> Code.format_string!()
      |> IO.iodata_to_binary()

    IO.puts("""

    ========================================
    Generated code for #{module}:
    ========================================
    #{code}
    ========================================
    """)
  end
end
