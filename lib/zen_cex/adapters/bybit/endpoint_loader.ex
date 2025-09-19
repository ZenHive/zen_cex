defmodule ZenCex.Adapters.Bybit.EndpointLoader do
  @moduledoc """
  Macro for loading generated endpoints from external files for Bybit.

  This module eliminates duplicated endpoint loading code across Bybit modules
  by providing a reusable macro that handles:
  - Loading generated endpoints at compile time
  - Parsing files safely as Elixir AST
  - Marking files as external resources for recompilation
  - Applying optional transformations to endpoints
  - Category parameter injection for unified API endpoints
  """

  @doc """
  Load generated endpoints from an external file at compile time.

  This macro:
  1. Marks the file as an external resource for automatic recompilation
  2. Loads and parses the file safely at compile time
  3. Applies an optional transformation function to customize endpoints
  4. Supports category parameter injection for Bybit's unified API

  ## Parameters

  - `filename` - The name of the file in the same directory as the calling module
  - `transform_fn` - Optional function to transform each endpoint (default: nil)

  ## Usage

  ```elixir
  defmodule MyModule do
    require ZenCex.Adapters.Bybit.EndpointLoader
    alias ZenCex.Adapters.Bybit.EndpointLoader

    # Simple loading without customization
    EndpointLoader.load_endpoints("generated_endpoints.ex")

    # With customization function for category injection
    EndpointLoader.load_endpoints("generated_endpoints.ex", fn endpoint ->
      case endpoint.operation do
        :place_order ->
          %{endpoint | max_retries: 0, retry_on: []}
        _ ->
          endpoint
      end
    end)
  end
  ```

  The macro creates two module attributes:
  - `@generated_endpoints` - The raw loaded endpoints
  - `@endpoints` - The transformed endpoints (or same as generated if no transform)
  """
  defmacro load_endpoints(filename, transform_fn \\ nil) do
    quote do
      alias ZenCex.Adapters.Bybit.Parser

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
                             # Parser is required because generated files reference &Parser.function_name/1
                             # for response_parser and error_mapping callbacks in endpoint definitions
                             {result, _} = Code.eval_quoted(ast, [Parser: Parser], __ENV__)
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
  Create a category parameter injection function for Bybit unified API endpoints.

  This helper creates transformation functions that inject the `category` parameter
  into endpoint parameters, useful for creating category-specific convenience functions.

  ## Parameters

  - `category` - The category value to inject ("spot", "linear", "inverse", "option")

  ## Returns

  A function that can be used as a transform_fn in `load_endpoints/2`

  ## Usage

  ```elixir
  # Create spot-specific endpoints with category pre-filled
  EndpointLoader.load_endpoints(
    "generated_endpoints.ex",
    EndpointLoader.inject_category("spot")
  )
  ```
  """
  @spec inject_category(String.t()) :: (map() -> map())
  def inject_category(category) when is_binary(category) do
    fn endpoint ->
      # Add the category to the endpoint's default parameters
      update_in(endpoint, [:params], fn
        nil ->
          %{"category" => category}

        params when is_map(params) ->
          Map.put(params, "category", category)

        params ->
          # Log a warning for unexpected param types to help with debugging
          require Logger

          Logger.warning(
            "Bybit endpoint has non-map params that cannot be injected with category. " <>
              "Endpoint: #{inspect(endpoint[:path])}, Params type: #{inspect(params.__struct__ || :unknown)}"
          )

          params
      end)
    end
  end
end
