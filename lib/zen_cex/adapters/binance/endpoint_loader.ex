defmodule ZenCex.Adapters.Binance.EndpointLoader do
  @moduledoc """
  Macro for loading generated endpoints from external files.

  This module eliminates duplicated endpoint loading code across Binance modules
  by providing a reusable macro that handles:
  - Loading generated endpoints at compile time
  - Parsing files safely as Elixir AST
  - Marking files as external resources for recompilation
  - Applying optional transformations to endpoints
  """

  @doc """
  Load generated endpoints from an external file at compile time.

  This macro:
  1. Marks the file as an external resource for automatic recompilation
  2. Loads and parses the file safely at compile time
  3. Applies an optional transformation function to customize endpoints

  ## Parameters

  - `filename` - The name of the file in the same directory as the calling module
  - `transform_fn` - Optional function to transform each endpoint (default: nil)

  ## Usage

  ```elixir
  defmodule MyModule do
    require ZenCex.Adapters.Binance.EndpointLoader
    alias ZenCex.Adapters.Binance.EndpointLoader
    
    # Simple loading without customization
    EndpointLoader.load_endpoints("generated_endpoints.ex")
    
    # With customization function
    EndpointLoader.load_endpoints("generated_endpoints.ex", fn endpoint ->
      case endpoint.operation do
        :get_account -> 
          %{endpoint | operation: :get_balances}
        op when op in [:place_order, :modify_order] ->
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
      alias ZenCex.Adapters.Binance.Parser

      # Mark as external resource so recompilation happens when the file changes
      @external_resource Path.join([__DIR__, unquote(filename)])

      # Load the endpoints file at compile time and convert to AST
      # This is safer than Code.eval_file as it doesn't execute arbitrary code
      @generated_endpoints (
                             path = Path.join([__DIR__, unquote(filename)])
                             {:ok, content} = File.read(path)
                             # Parse as Elixir code to get the AST
                             {:ok, ast} = Code.string_to_quoted(content)
                             # The file contains a list literal, evaluate it in a restricted context
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
end
