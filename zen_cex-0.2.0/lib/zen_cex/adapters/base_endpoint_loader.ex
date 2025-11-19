defmodule ZenCex.Adapters.BaseEndpointLoader do
  @moduledoc """
  Unified macro for loading generated endpoints from external files.

  This module provides a reusable macro that all exchange adapters can use to
  load endpoint definitions at compile time. It handles:
  - Loading generated endpoints at compile time
  - Parsing files safely as Elixir AST
  - Marking files as external resources for recompilation
  - Applying optional transformations to endpoints
  - Configurable parser module binding

  ## Usage

  ```elixir
  defmodule ZenCex.Adapters.MyExchange.Spot do
    require ZenCex.Adapters.BaseEndpointLoader
    alias ZenCex.Adapters.BaseEndpointLoader

    # Simple loading without customization
    BaseEndpointLoader.load_endpoints("generated_endpoints.ex",
      parser_module: MyExchange.Parser
    )

    # With customization function
    BaseEndpointLoader.load_endpoints("generated_endpoints.ex",
      parser_module: MyExchange.Parser,
      transform_fn: fn endpoint ->
        case endpoint.operation do
          :place_order ->
            %{endpoint | max_retries: 0, retry_on: []}
          _ ->
            endpoint
        end
      end
    )
  end
  ```

  ## Options

  - `:parser_module` (required) - The parser module to bind in the evaluation context
  - `:transform_fn` (optional) - Function to transform each endpoint after loading

  ## Generated Attributes

  The macro creates two module attributes:
  - `@generated_endpoints` - The raw loaded endpoints from the file
  - `@endpoints` - The transformed endpoints (or same as generated if no transform)

  ## File Format

  The loaded file should contain a list of endpoint maps. The file is evaluated
  with the specified parser module in scope, allowing references like `&Parser.parse_response/1`.
  """

  @doc """
  Load generated endpoints from an external file at compile time.

  This macro:
  1. Marks the file as an external resource for automatic recompilation
  2. Loads and parses the file safely at compile time
  3. Evaluates the AST with the specified parser module in binding
  4. Applies an optional transformation function to customize endpoints

  ## Parameters

  - `filename` - The name of the file in the same directory as the calling module
  - `opts` - Keyword list of options:
    - `:parser_module` (required) - Parser module to bind for evaluation
    - `:transform_fn` (optional) - Function to transform each endpoint

  ## Examples

      # Basic usage
      BaseEndpointLoader.load_endpoints("generated_endpoints.ex",
        parser_module: Binance.Parser
      )

      # With transformation
      BaseEndpointLoader.load_endpoints("generated_endpoints.ex",
        parser_module: Bybit.Parser,
        transform_fn: fn endpoint ->
          %{endpoint | category: "spot"}
        end
      )
  """
  defmacro load_endpoints(filename, opts) do
    parser_module = Keyword.fetch!(opts, :parser_module)
    transform_fn = Keyword.get(opts, :transform_fn)

    quote do
      # Mark as external resource so recompilation happens when the file changes
      @external_resource Path.join([__DIR__, unquote(filename)])

      # Load the endpoints file at compile time and convert to AST
      # This is safer than Code.eval_file as it doesn't execute arbitrary code
      @generated_endpoints (
                             path = Path.join([__DIR__, unquote(filename)])
                             {:ok, content} = File.read(path)
                             # Parse as Elixir code to get the AST
                             {:ok, ast} = Code.string_to_quoted(content)
                             # Evaluate the AST with Parser binding
                             # Parser is required because generated files may reference
                             # &Parser.function_name/1 for response_parser and error_mapping
                             # callbacks in endpoint definitions
                             parser_alias = unquote(parser_module)
                             {result, _} = Code.eval_quoted(ast, [Parser: parser_alias], __ENV__)
                             result
                           )

      # Apply customizations to generated endpoints if transform function provided
      @endpoints (
                   transform = unquote(transform_fn)

                   if transform do
                     Enum.map(@generated_endpoints, transform)
                   else
                     @generated_endpoints
                   end
                 )
    end
  end

  @doc """
  Create a category parameter injection function for unified API endpoints.

  This helper creates transformation functions that inject a `category` parameter
  into endpoint parameters. Useful for exchanges like Bybit where the unified API
  requires a category parameter for most endpoints.

  ## Parameters

  - `category` - The category value to inject (e.g., "spot", "linear", "inverse", "option")

  ## Returns

  A function that can be used as the `:transform_fn` option in `load_endpoints/2`

  ## Example

      # Create a transform function for spot category
      spot_transform = BaseEndpointLoader.category_injector("spot")

      # Use it when loading endpoints
      BaseEndpointLoader.load_endpoints("generated_endpoints.ex",
        parser_module: Bybit.Parser,
        transform_fn: spot_transform
      )
  """
  @spec category_injector(String.t()) :: (map() -> map())
  def category_injector(category) when is_binary(category) do
    fn endpoint ->
      Map.update(endpoint, :params, %{category: category}, fn params ->
        Map.put(params, :category, category)
      end)
    end
  end
end
