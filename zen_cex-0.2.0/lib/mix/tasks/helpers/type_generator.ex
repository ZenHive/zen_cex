defmodule Mix.Tasks.Helpers.TypeGenerator do
  @moduledoc """
  Generates Elixir type specifications from OpenAPI schemas.

  This module provides utilities for converting OpenAPI type definitions
  into Elixir @spec annotations for use in generated endpoint modules.

  ## Type Mapping

  OpenAPI types are mapped to Elixir types as follows:
  - `integer` → `integer()`
  - `number` → `float()`
  - `string` → `String.t()`
  - `boolean` → `boolean()`
  - `array` → `list(item_type())`
  - `object` → `%{key: type()}`
  - `enum` → `:atom | :atom | ...`

  ## Limitations

  Phase 1 implementation has the following limitations:
  - No `oneOf/anyOf/allOf` support (falls back to `term()`)
  - No discriminators
  - No custom type definitions (inline types only)
  - No validation (types are for Dialyzer only)
  """

  @doc """
  Extracts parameter types from an OpenAPI endpoint specification.

  Returns list of `{param_name_atom, type_string}` tuples.

  ## Examples

      iex> spec = %{"parameters" => [
      ...>   %{"name" => "symbol", "schema" => %{"type" => "string"}}
      ...> ]}
      iex> TypeGenerator.extract_param_types(spec, %{})
      [{:symbol, "String.t()"}]
  """
  @spec extract_param_types(map(), map()) :: [{atom(), String.t()}]
  def extract_param_types(endpoint_spec, components) do
    params = endpoint_spec["parameters"] || []

    Enum.map(params, fn param ->
      resolved = resolve_ref(param, components)
      name = resolved["name"]

      if name do
        schema = resolved["schema"] || %{}
        type = openapi_type_to_elixir(schema, components)
        {to_snake_case_atom(name), type}
      else
        # Fallback for missing name
        {:unknown_param, "term()"}
      end
    end)
  end

  @doc """
  Extracts response type from an OpenAPI endpoint specification.

  Looks for 200/201 success responses and generates type from schema.
  Returns type string like `"%{field: String.t()}"` or `"term()"` if unknown.

  ## Examples

      iex> spec = %{"responses" => %{"200" => %{
      ...>   "content" => %{"application/json" => %{
      ...>     "schema" => %{"type" => "object", "properties" => %{
      ...>       "serverTime" => %{"type" => "integer"}
      ...>     }}
      ...>   }}
      ...> }}}
      iex> TypeGenerator.extract_response_type(spec, %{})
      "%{server_time: integer()}"
  """
  @spec extract_response_type(map(), map()) :: String.t()
  def extract_response_type(endpoint_spec, components) do
    responses = endpoint_spec["responses"] || %{}
    success_response = responses["200"] || responses["201"]

    if success_response do
      schema = get_in(success_response, ["content", "application/json", "schema"])

      if schema do
        openapi_type_to_elixir(resolve_ref(schema, components), components)
      else
        "term()"
      end
    else
      "term()"
    end
  end

  @doc """
  Generates complete @spec annotation string for a function.

  Combines parameter types and response type into valid Elixir spec.

  ## Examples

      iex> TypeGenerator.generate_spec(:get_time, [], "%{server_time: integer()}")
      "@spec get_time(map(), keyword()) :: {:ok, %{server_time: integer()}} | {:error, term()}"
  """
  @spec generate_spec(atom(), [{atom(), String.t()}], String.t()) :: String.t()
  def generate_spec(operation_name, _param_types, response_type) do
    # Format the operation name properly (handle atoms with special characters)
    func_name_str = format_atom_for_spec(operation_name)

    # All generated functions take (params :: map(), opts :: keyword())
    "@spec #{func_name_str}(map(), keyword()) :: {:ok, #{response_type}} | {:error, term()}"
  end

  # Format an atom for use in a @spec annotation
  # Handles atoms with special characters that need quoting
  defp format_atom_for_spec(atom) when is_atom(atom) do
    atom_str = Atom.to_string(atom)

    # Check if the atom needs special quoting (contains special characters)
    if needs_quoting?(atom_str) do
      # Use inspect to get the proper quoted atom syntax
      inspect(atom)
    else
      atom_str
    end
  end

  # Check if an atom string needs quoting in specs
  # Atoms need quoting if they contain characters other than alphanumeric, underscore, @, or ?
  defp needs_quoting?(str) do
    not Regex.match?(~r/^[a-z_][a-zA-Z0-9_?!@]*$/, str)
  end

  @doc """
  Resolves a $ref reference to its actual schema definition.

  Handles both parameter refs and schema refs.

  ## Examples

      iex> components = %{"parameters" => %{"symbol" => %{"name" => "symbol", "schema" => %{"type" => "string"}}}}
      iex> TypeGenerator.resolve_ref(%{"$ref" => "#/components/parameters/symbol"}, components)
      %{"name" => "symbol", "schema" => %{"type" => "string"}}

      iex> TypeGenerator.resolve_ref(%{"type" => "string"}, %{})
      %{"type" => "string"}
  """
  @spec resolve_ref(map(), map()) :: map()
  def resolve_ref(%{"$ref" => ref_path}, components) when is_binary(ref_path) do
    # Navigate ref path like "#/components/parameters/symbol"
    # The path is "#/components/parameters/symbol", so we need to skip "#" and use the rest
    path_parts =
      ref_path
      |> String.split("/")
      |> Enum.reject(&(&1 == "#" || &1 == ""))

    # Build the full structure to navigate through
    full_spec = %{"components" => components}
    resolved = navigate_ref_path(path_parts, full_spec)

    # Recursively resolve if the result contains another $ref
    case resolved do
      %{"$ref" => _} -> resolve_ref(resolved, components)
      _ -> resolved
    end
  end

  def resolve_ref(schema, _components) when is_map(schema), do: schema

  # ============================================================================
  # Public Helpers (exposed for testing)
  # ============================================================================

  @doc """
  Converts an OpenAPI type schema to Elixir type string.

  This function is public for testing purposes.
  """
  @spec openapi_type_to_elixir(map(), map()) :: String.t()
  def openapi_type_to_elixir(schema, components) when is_map(schema) do
    cond do
      # Handle $ref (shouldn't happen if resolve_ref is called first, but safe fallback)
      Map.has_key?(schema, "$ref") ->
        openapi_type_to_elixir(resolve_ref(schema, components), components)

      # Handle enums (highest priority)
      Map.has_key?(schema, "enum") ->
        handle_enum(schema["enum"])

      # Handle oneOf/anyOf/allOf (Phase 2 - fallback to term())
      Map.has_key?(schema, "oneOf") or Map.has_key?(schema, "anyOf") or
          Map.has_key?(schema, "allOf") ->
        "term()"

      # Handle typed values
      schema["type"] == "integer" ->
        "integer()"

      schema["type"] == "number" ->
        "float()"

      schema["type"] == "string" ->
        handle_string_type(schema)

      schema["type"] == "boolean" ->
        "boolean()"

      schema["type"] == "array" ->
        type_array(schema, components)

      schema["type"] == "object" ->
        type_object(schema, components)

      # Unknown or missing type
      true ->
        "term()"
    end
  end

  def openapi_type_to_elixir(_, _), do: "term()"

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Handle string subtypes
  @spec handle_string_type(map()) :: String.t()
  defp handle_string_type(%{"enum" => values}), do: handle_enum(values)
  defp handle_string_type(_), do: "String.t()"

  # Handle enums - convert to union of atoms
  @spec handle_enum(list(String.t())) :: String.t()
  defp handle_enum(values) when is_list(values) do
    values
    |> Enum.map(&String.downcase/1)
    |> Enum.map_join(" | ", &":#{&1}")
  end

  # Handle array types
  @spec type_array(map(), map()) :: String.t()
  defp type_array(schema, components) do
    items_schema = schema["items"] || %{}
    item_type = openapi_type_to_elixir(items_schema, components)
    "list(#{item_type})"
  end

  # Handle object types
  @spec type_object(map(), map()) :: String.t()
  defp type_object(schema, components) do
    properties = schema["properties"] || %{}
    required_keys = schema["required"] || []

    if Enum.empty?(properties) do
      # Empty object or additionalProperties
      "map()"
    else
      # Build map with typed fields
      field_specs =
        Enum.map(properties, fn {key, value_schema} ->
          field_name = to_snake_case_atom(key)
          field_type = openapi_type_to_elixir(value_schema, components)

          if key in required_keys do
            "#{field_name}: #{field_type}"
          else
            # Use :atom syntax for optional keys in typespecs
            "optional(:#{field_name}) => #{field_type}"
          end
        end)

      "%{#{Enum.join(field_specs, ", ")}}"
    end
  end

  # Navigate ref path like "#/components/parameters/symbol"
  @spec navigate_ref_path(list(String.t()), map()) :: map()
  defp navigate_ref_path([], current), do: current

  defp navigate_ref_path([key | rest], current) when is_map(current) do
    next = Map.get(current, key, %{})
    navigate_ref_path(rest, next)
  end

  defp navigate_ref_path(_, _), do: %{}

  # Convert camelCase to snake_case atom
  @spec to_snake_case_atom(String.t()) :: atom()
  defp to_snake_case_atom(string) when is_binary(string) do
    string
    |> Macro.underscore()
    |> String.to_atom()
  end
end
