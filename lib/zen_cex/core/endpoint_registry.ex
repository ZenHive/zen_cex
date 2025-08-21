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

  alias ZenCex.Core.HTTP

  @default_timeout 30_000
  @default_retries 0

  @doc """
  Sets up the endpoint registry for a module.

  ## Options

    * `:adapter` - The adapter module to use for request execution
    * `:debug` - When true, prints generated AST during compilation

  ## Examples

      use ZenCex.EndpointRegistry, adapter: MyAdapter
      use ZenCex.EndpointRegistry, debug: true
      use ZenCex.EndpointRegistry, :debug  # Shorthand for debug: true
  """
  @spec __using__(keyword() | :debug | any()) :: Macro.t()
  defmacro __using__(opts) do
    # Handle all patterns in a single macro definition
    {adapter, debug} =
      case opts do
        :debug ->
          {nil, true}

        opts when is_list(opts) ->
          {Keyword.get(opts, :adapter), Keyword.get(opts, :debug, false)}

        _ ->
          {nil, false}
      end

    quote do
      alias ZenCex.Core.HTTP

      require Logger

      @before_compile unquote(__MODULE__)
      @endpoint_registry_adapter unquote(adapter)
      @endpoint_registry_debug unquote(debug)

      Module.register_attribute(__MODULE__, :endpoints, accumulate: false)

      # Import needed for generated functions
    end
  end

  @doc """
  Generates endpoint functions before compilation.

  This macro is called automatically by Elixir's compilation process
  and generates all the endpoint functions based on the @endpoints attribute.
  """
  @spec __before_compile__(Macro.Env.t()) :: Macro.t()
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

  @doc false
  @spec validate_endpoints!(list() | any(), module()) :: :ok
  defp validate_endpoints!(endpoints, module) when is_list(endpoints) do
    Enum.each(endpoints, fn endpoint ->
      validate_endpoint!(endpoint, module)
    end)
  end

  defp validate_endpoints!(_, module) do
    raise CompileError,
      description: "#{module}: @endpoints must be a list of endpoint specifications"
  end

  @spec validate_endpoint!(map() | any(), module()) :: :ok | no_return()
  defp validate_endpoint!(endpoint, module) when is_map(endpoint) do
    validate_required_keys(endpoint, module)
    validate_http_method(endpoint, module)
    validate_parser_functions(endpoint, module)
    validate_retry_configuration(endpoint, module)
    validate_order_operations(endpoint, module)
    :ok
  end

  defp validate_endpoint!(_, module) do
    raise CompileError,
      description: "#{module}: Each endpoint must be a map"
  end

  # Extract validation helpers to reduce complexity
  defp validate_required_keys(endpoint, module) do
    required_keys = [:operation, :method, :path, :response_parser, :error_mapping]

    Enum.each(required_keys, fn key ->
      if !Map.has_key?(endpoint, key) do
        raise CompileError,
          description: "#{module}: Endpoint #{inspect(endpoint[:operation])} missing required key: #{key}"
      end
    end)
  end

  defp validate_http_method(endpoint, module) do
    valid_methods = [:get, :post, :put, :delete, :patch]

    if endpoint.method not in valid_methods do
      raise CompileError,
        description: "#{module}: Invalid HTTP method #{inspect(endpoint.method)} for #{endpoint.operation}"
    end
  end

  defp validate_parser_functions(endpoint, module) do
    validate_parser_function(endpoint.response_parser, "response_parser", module)
    validate_parser_function(endpoint.error_mapping, "error_mapping", module)
  end

  defp validate_parser_function(parser, name, module) do
    if !parser do
      raise CompileError,
        description: "#{module}: #{name} must be provided"
    end

    if !valid_function_ref?(parser) do
      raise CompileError,
        description: "#{module}: #{name} must be a function reference with arity 1 (e.g., &Module.function/1)"
    end
  end

  defp valid_function_ref?(parser) do
    match?({:&, _, _}, parser) or match?({:fn, _, _}, parser) or is_function(parser, 1)
  end

  defp validate_retry_configuration(endpoint, module) do
    if Map.has_key?(endpoint, :retry_on) and not is_list(endpoint.retry_on) do
      raise CompileError,
        description: "#{module}: retry_on must be a list of error atoms"
    end
  end

  defp validate_order_operations(endpoint, module) do
    order_operations = [:place_order, :place_limit_order, :place_market_order]

    if endpoint.operation in order_operations do
      max_retries = Map.get(endpoint, :max_retries, 0)

      if max_retries > 0 do
        raise CompileError,
          description: "#{module}: Order placement operations MUST NOT have retries (found max_retries: #{max_retries})"
      end
    end
  end

  @spec generate_endpoint_functions(list(map()), module() | nil, module()) :: Macro.t()
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

  @spec generate_lookup_functions(list(map())) :: list(Macro.t())
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

  @spec generate_operation_function(map(), module() | nil, module()) :: list(Macro.t())
  defp generate_operation_function(endpoint, adapter, module) do
    config = extract_endpoint_config(endpoint)

    [
      generate_main_function(config),
      generate_opts_function(config, adapter),
      generate_helper_functions(module)
    ]
    |> List.flatten()
    |> Enum.filter(&(&1 != nil))
  end

  @spec extract_endpoint_config(map()) :: map()
  defp extract_endpoint_config(endpoint) do
    %{
      operation: endpoint.operation,
      method: endpoint.method,
      path: endpoint.path,
      requires_auth: Map.get(endpoint, :requires_auth, true),
      response_parser: endpoint.response_parser,
      error_mapping: endpoint.error_mapping,
      retry_on: Map.get(endpoint, :retry_on, []),
      max_retries: Map.get(endpoint, :max_retries, @default_retries),
      timeout: Map.get(endpoint, :timeout, @default_timeout),
      weight: Map.get(endpoint, :weight, 1),
      params_transformer: Map.get(endpoint, :params_transformer),
      api_type: Map.get(endpoint, :api_type),
      doc: Map.get(endpoint, :doc, "Executes the #{endpoint.operation} operation")
    }
  end

  @spec generate_main_function(map()) :: Macro.t()
  defp generate_main_function(config) do
    func_name = config.operation
    doc = config.doc

    quote do
      @doc unquote(doc)
      @spec unquote(func_name)(map()) ::
              {:ok, term()} | {:error, term()}
      def unquote(func_name)(params \\ %{}) do
        unquote(func_name)(params, [])
      end
    end
  end

  @spec generate_opts_function(map(), module() | nil) :: Macro.t()
  defp generate_opts_function(config, adapter) do
    func_name = config.operation

    quote do
      @spec unquote(func_name)(map(), keyword()) ::
              {:ok, term()} | {:error, term()}
      def unquote(func_name)(params, opts) do
        endpoint_config =
          build_endpoint_config(
            unquote(Macro.escape(config)),
            opts
          )

        final_params =
          transform_params(
            params,
            unquote(Macro.escape(config.params_transformer))
          )

        execute_with_telemetry(
          endpoint_config,
          final_params,
          opts,
          unquote(adapter),
          unquote(Macro.escape(config.response_parser)),
          unquote(Macro.escape(config.error_mapping))
        )
      end
    end
  end

  @spec generate_helper_functions(module()) :: list(Macro.t())
  defp generate_helper_functions(_module) do
    # Always generate helper functions - they use defp so won't conflict
    # The Elixir compiler will handle duplicate private function definitions
    [
      generate_config_builder(),
      generate_params_transformer(),
      generate_telemetry_executor(),
      generate_request_executor()
    ]
  end

  @spec generate_config_builder() :: Macro.t()
  defp generate_config_builder do
    quote do
      defp build_endpoint_config(base_config, opts) do
        config = %{
          operation: base_config.operation,
          method: base_config.method,
          path: base_config.path,
          requires_auth: base_config.requires_auth,
          weight: base_config.weight,
          timeout: Keyword.get(opts, :timeout, base_config.timeout),
          max_retries: Keyword.get(opts, :max_retries, base_config.max_retries),
          retry_on: base_config.retry_on,
          response_parser: base_config.response_parser,
          error_mapping: base_config.error_mapping
        }

        if base_config[:api_type] do
          Map.put(config, :api_type, base_config.api_type)
        else
          config
        end
      end
    end
  end

  @spec generate_params_transformer() :: Macro.t()
  defp generate_params_transformer do
    quote do
      defp transform_params(params, nil), do: params
      defp transform_params(params, transformer), do: transformer.(params)
    end
  end

  @spec generate_telemetry_executor() :: Macro.t()
  defp generate_telemetry_executor do
    quote do
      defp execute_with_telemetry(config, params, opts, adapter, response_parser, error_mapping) do
        start_time = System.monotonic_time()

        start_metadata = %{
          exchange: adapter.__exchange__(),
          operation: config.operation,
          endpoint: config.path
        }

        :telemetry.execute(
          [:zen_cex, :endpoint, :start],
          %{system_time: System.system_time()},
          start_metadata
        )

        result =
          execute_and_parse(
            config,
            params,
            opts,
            adapter,
            response_parser,
            error_mapping
          )

        emit_telemetry_result(result, start_time, start_metadata)
        result
      end

      defp execute_and_parse(config, params, opts, adapter, response_parser, error_mapping) do
        case execute_endpoint_request(config, params, opts, adapter) do
          {:ok, response} ->
            response_parser.(response)

          {:error, %Req.Response{status: status, body: body}} when status >= 400 ->
            error_mapping.(body)

          {:error, reason} ->
            {:error, reason}
        end
      end

      defp emit_telemetry_result(result, start_time, start_metadata) do
        duration = System.monotonic_time() - start_time

        {event_name, metadata} =
          case result do
            {:ok, _} ->
              {[:zen_cex, :endpoint, :success], Map.put(start_metadata, :status, :ok)}

            {:error, reason} ->
              {[:zen_cex, :endpoint, :error], Map.merge(start_metadata, %{status: :error, reason: reason})}
          end

        :telemetry.execute(event_name, %{duration: duration}, metadata)
      end
    end
  end

  @spec generate_request_executor() :: Macro.t()
  defp generate_request_executor do
    quote do
      unquote(generate_main_executor())
      unquote(generate_request_builders())
      unquote(generate_retry_handlers())
    end
  end

  # Generate the main execution pipeline
  defp generate_main_executor do
    quote do
      defp execute_endpoint_request(config, params, opts, adapter) do
        case build_request(config, params, adapter) do
          {:error, _} = error ->
            # Return error early if request building failed (e.g., no testnet URL)
            error

          request ->
            request
            |> merge_user_options(opts)
            |> apply_retry_logic(config)
            |> execute_request()
        end
      end

      defp execute_request(request) do
        case Req.request(request) do
          {:ok, %Req.Response{status: status} = response} when status in 200..299 ->
            {:ok, response.body}

          {:ok, response} ->
            {:error, response}

          {:error, _} = error ->
            error
        end
      end
    end
  end

  # Generate request building functions
  defp generate_request_builders do
    quote do
      unquote(generate_request_pipeline())
      unquote(generate_url_helpers())
      unquote(generate_request_configuration())
      unquote(generate_operation_mapping())
    end
  end

  # Generate the main request building pipeline
  defp generate_request_pipeline do
    quote do
      defp build_request(config, params, adapter) do
        case determine_base_url(config, adapter) do
          {:error, _} = error ->
            # Return error early if base URL is not available (e.g., no testnet for portfolio)
            error

          base_url ->
            operation_type = map_to_operation_type(config)

            adapter.__exchange__()
            |> HTTP.base_request(operation_type)
            |> configure_request(config, params, base_url)
            |> add_request_metadata(config)
        end
      end

      defp merge_user_options(request, opts) do
        Req.merge(request, opts)
      end
    end
  end

  # Generate URL determination helpers
  defp generate_url_helpers do
    quote do
      defp determine_base_url(config, adapter) do
        if supports_multi_api?(config, adapter) do
          adapter.base_url(adapter.current_env(), config.api_type)
        else
          adapter.base_url()
        end
      end

      defp supports_multi_api?(config, adapter) do
        Map.has_key?(config, :api_type) and function_exported?(adapter, :base_url, 2)
      end
    end
  end

  # Generate request configuration functions
  defp generate_request_configuration do
    quote do
      defp configure_request(request, config, params, base_url) do
        {request_params, request_json} = build_request_data(config.method, params)

        Req.merge(request,
          method: config.method,
          url: base_url <> config.path,
          params: request_params,
          json: request_json,
          receive_timeout: config.timeout,
          skip_auth: not config.requires_auth,
          retry: false
        )
      end

      defp build_request_data(:get, params), do: {params, nil}
      defp build_request_data(_, params), do: {nil, params}

      defp add_request_metadata(request, config) do
        request
        |> Req.Request.put_private(:rate_limit_weight, config.weight)
        |> Req.Request.put_private(:endpoint_config, config)
        |> Req.Request.put_private(:endpoint_operation, config.operation)
      end
    end
  end

  # Generate operation type mapping
  defp generate_operation_mapping do
    quote do
      defp map_to_operation_type(%{operation: operation}) do
        case operation do
          op when op in [:place_order, :cancel_order] -> :trading
          :get_server_time -> :health
          _ -> :standard
        end
      end
    end
  end

  # Generate retry handling functions
  defp generate_retry_handlers do
    quote do
      unquote(generate_retry_logic())
      unquote(generate_retry_helpers())
    end
  end

  # Generate retry application logic
  defp generate_retry_logic do
    quote do
      defp apply_retry_logic(request, config) do
        if should_enable_retry?(config) do
          enable_retry(request, config)
        else
          request
        end
      end

      defp should_enable_retry?(config) do
        config.max_retries > 0 and length(config.retry_on) > 0
      end

      defp enable_retry(request, config) do
        Req.Request.prepend_error_steps(request,
          endpoint_retry: &handle_retry(&1, config)
        )
      end
    end
  end

  # Generate retry decision helpers
  defp generate_retry_helpers do
    quote do
      unquote(generate_retry_handler())
      unquote(generate_exception_classifier())
    end
  end

  # Generate the main retry handling logic
  defp generate_retry_handler do
    quote do
      defp handle_retry({request, exception}, config) do
        if should_retry_exception?(exception, config.retry_on) do
          {request, exception}
        else
          {Req.Request.halt(request, exception), exception}
        end
      end

      defp should_retry_exception?(exception, retry_on) do
        exception
        |> classify_exception()
        |> should_retry_error_type?(retry_on)
      end

      defp should_retry_error_type?(error_type, retry_on) do
        error_type in retry_on
      end
    end
  end

  # Generate exception classification functions
  defp generate_exception_classifier do
    quote do
      defp classify_exception(%Req.Response{status: 429}), do: :rate_limited
      defp classify_exception(%Req.Response{status: status}) when status in [503, 504], do: :timeout
      defp classify_exception(%Mint.TransportError{}), do: :timeout
      defp classify_exception(_), do: :other
    end
  end

  @spec print_debug_output(Macro.t(), module()) :: :ok
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
