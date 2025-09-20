defmodule ZenCex.Safety.OrderSafety.DecimalUtils do
  @moduledoc false

  @zero_balance "0"

  @doc """
  Parses a value into a Decimal, handling various input types.
  Returns a Decimal value, defaulting to 0 on parse failure.
  """
  @spec parse_decimal(any()) :: Decimal.t()
  def parse_decimal(value) when is_binary(value) do
    # Trim whitespace first
    trimmed = String.trim(value)

    # Check for special values that should return zero
    if trimmed in ["Infinity", "-Infinity", "NaN", ""] do
      Decimal.new(@zero_balance)
    else
      case Decimal.parse(trimmed) do
        {decimal, rest} ->
          # Only accept if the rest is empty (full parse)
          # This handles "123.456.789" case - it should return zero
          if rest == "" do
            decimal
          else
            Decimal.new(@zero_balance)
          end

        :error ->
          Decimal.new(@zero_balance)
      end
    end
  end

  def parse_decimal(value) when is_number(value) do
    value
    |> to_string()
    |> Decimal.new()
  end

  def parse_decimal(%Decimal{} = decimal), do: decimal

  def parse_decimal(_value) do
    Decimal.new(@zero_balance)
  end

  @doc """
  Safely parses a decimal and returns ok/error tuple.
  Used when explicit error handling is needed.
  """
  @spec safe_parse_decimal(any()) :: {:ok, Decimal.t()} | {:error, {:invalid_decimal, any()}}
  def safe_parse_decimal(str) when is_binary(str) do
    trimmed = String.trim(str)

    # Check for special values
    if trimmed in ["Infinity", "-Infinity", "NaN", ""] do
      {:error, {:invalid_decimal, str}}
    else
      case Decimal.parse(trimmed) do
        {decimal, rest} ->
          if rest == "" do
            {:ok, decimal}
          else
            {:error, {:invalid_decimal, str}}
          end

        :error ->
          {:error, {:invalid_decimal, str}}
      end
    end
  end

  def safe_parse_decimal(num) when is_number(num) do
    {:ok, Decimal.new(to_string(num))}
  end

  def safe_parse_decimal(%Decimal{} = decimal) do
    {:ok, decimal}
  end

  def safe_parse_decimal(value) do
    {:error, {:invalid_decimal, value}}
  end

  @doc """
  Extracts balance from various exchange balance formats.
  Handles Binance, Bybit, and other exchange formats.
  """
  @spec extract_available_balance(map(), String.t()) :: Decimal.t()
  def extract_available_balance(balances, asset) when is_map(balances) do
    case Map.get(balances, asset) do
      %{free: free_str} when is_binary(free_str) ->
        parse_decimal(free_str)

      %{available: available_str} when is_binary(available_str) ->
        parse_decimal(available_str)

      %{available_balance: available_str} when is_binary(available_str) ->
        parse_decimal(available_str)

      %{available_to_withdraw: available_str} when is_binary(available_str) ->
        parse_decimal(available_str)

      _ ->
        Decimal.new(@zero_balance)
    end
  end

  def extract_available_balance(_balances, _asset) do
    Decimal.new(@zero_balance)
  end
end
