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

  @doc """
  Normalizes string keys to atom keys with snake_case conversion.

  Safe for exchange responses because field names are controlled by the exchange,
  not user input. Uses String.to_atom/1 since we know the field vocabulary is bounded.

  ## Examples

      iex> normalize_keys(%{"orderId" => "123", "clientOrderId" => "abc"})
      %{order_id: "123", client_order_id: "abc"}

      iex> normalize_keys([%{"symbol" => "BTCUSDT"}])
      [%{symbol: "BTCUSDT"}]

      iex> normalize_keys(%{"nested" => %{"timeSecond" => "123"}})
      %{nested: %{time_second: "123"}}

      iex> normalize_keys("string")
      "string"

      iex> normalize_keys(nil)
      nil
  """
  @spec normalize_keys(map() | list() | term()) :: map() | list() | term()
  def normalize_keys(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      normalized_key =
        key
        |> to_string()
        |> Macro.underscore()
        |> String.to_atom()

      normalized_value = normalize_keys(value)
      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  def normalize_keys(data) when is_list(data) do
    Enum.map(data, &normalize_keys/1)
  end

  def normalize_keys(data), do: data

  @doc """
  Safely decodes JSON string to Elixir term.

  Returns {:ok, decoded} on success or {:error, :invalid_json} on failure.

  ## Examples

      iex> decode_json_body(~s({"key": "value"}))
      {:ok, %{"key" => "value"}}

      iex> decode_json_body("not json")
      {:error, :invalid_json}

      iex> decode_json_body("")
      {:error, :invalid_json}
  """
  @spec decode_json_body(binary()) :: {:ok, term()} | {:error, :invalid_json}
  def decode_json_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Normalizes string enum value to lowercase atom.

  Safe for exchange API enums (controlled vocabulary).

  ## Examples

      iex> normalize_enum_value("BUY")
      :buy

      iex> normalize_enum_value("PARTIALLY_FILLED")
      :partially_filled

      iex> normalize_enum_value(nil)
      nil

      iex> normalize_enum_value(:buy)
      :buy
  """
  @spec normalize_enum_value(String.t() | atom() | nil) :: atom() | nil
  def normalize_enum_value(value) when is_binary(value) do
    value |> String.downcase() |> String.to_atom()
  end

  def normalize_enum_value(nil), do: nil
  def normalize_enum_value(value) when is_atom(value), do: value
end
