defmodule ZenCex.ParserMacros do
  @moduledoc """
  Common macros for parser modules to reduce duplication.

  Provides macros for safe decimal conversion and field extraction patterns
  that are commonly used across exchange parsers.
  """

  @doc """
  Safely converts a value to a Decimal, with fallback to "0".

  This macro handles:
  - nil values → Decimal.new("0")
  - empty strings → Decimal.new("0")
  - binary strings → parses to Decimal
  - numbers → converts to Decimal
  - invalid/unparseable values → Decimal.new("0")

  ## Options
  - `:default` - The default value to use instead of "0" (optional)
  - `:basis_points` - Whether to treat integer values as basis points (optional)

  ## Examples

      import ZenCex.ParserMacros

      # Simple usage
      amount = safe_decimal_field(response["amount"])

      # With custom default
      price = safe_decimal_field(response["price"], default: "1")

      # With basis points conversion (10 bps = 0.001)
      commission = safe_decimal_field(response["commission"], basis_points: true)
  """
  defmacro safe_decimal_field(value, opts \\ []) do
    default = Keyword.get(opts, :default, "0")
    basis_points = Keyword.get(opts, :basis_points, false)

    quote do
      ZenCex.ParserMacros.convert_to_decimal(
        unquote(value),
        unquote(default),
        unquote(basis_points)
      )
    end
  end

  @doc """
  Converts a value to Decimal with various input handling.

  This is the runtime function called by the safe_decimal_field macro.
  It handles nil, empty strings, binary strings, numbers, and basis points.
  """
  @spec convert_to_decimal(any(), String.t(), boolean()) :: Decimal.t()
  def convert_to_decimal(nil, default, _basis_points), do: Decimal.new(default)
  def convert_to_decimal("", default, _basis_points), do: Decimal.new(default)

  def convert_to_decimal(value, _default, true) when is_integer(value) do
    # Convert basis points to decimal: 10 bps = 10/10000 = 0.001
    value
    |> Decimal.new()
    |> Decimal.div(Decimal.new("10000"))
  end

  def convert_to_decimal(value, default, _basis_points) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> Decimal.new(default)
    end
  end

  def convert_to_decimal(value, _default, _basis_points) when is_number(value) do
    Decimal.new(to_string(value))
  end

  def convert_to_decimal(_value, default, _basis_points), do: Decimal.new(default)

  @doc """
  Extracts a field from a map with fallback field names and optional transformation.

  This macro helps with APIs that use different field names for the same data.

  ## Parameters
  - `source` - The map to extract from
  - `fields` - List of field names to try (in order)
  - `transform` - Optional transformation (:string, :decimal, :integer, or custom function)

  ## Examples

      import ZenCex.ParserMacros

      # Try multiple field names
      order_id = extract_field(response, ["orderId", "id"], :string)

      # With decimal conversion
      quantity = extract_field(response, ["origQty", "quantity"], :decimal)

      # With custom transformation
      timestamp = extract_field(response, ["transactTime", "time"], &DateTime.from_unix!/1)
  """
  defmacro extract_field(source, fields, transform \\ :identity) do
    quote do
      ZenCex.ParserMacros.extract_and_transform(
        unquote(source),
        unquote(fields),
        unquote(transform)
      )
    end
  end

  @doc """
  Runtime function for field extraction and transformation.
  """
  @spec extract_and_transform(map(), list(String.t()), atom() | function()) :: any()
  def extract_and_transform(source, fields, transform) when is_map(source) do
    value = Enum.find_value(fields, fn field -> Map.get(source, field) end)

    case transform do
      :identity -> value
      :string -> to_string(value || "")
      :decimal -> convert_to_decimal(value, "0", false)
      :integer -> to_integer(value)
      transform_fn when is_function(transform_fn, 1) -> transform_fn.(value)
      _ -> value
    end
  end

  def extract_and_transform(_source, _fields, _transform), do: nil

  defp to_integer(nil), do: 0
  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_integer(value) when is_float(value), do: round(value)
  defp to_integer(_), do: 0
end
