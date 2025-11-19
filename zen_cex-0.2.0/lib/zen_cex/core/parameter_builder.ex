defmodule ZenCex.Core.ParameterBuilder do
  @moduledoc """
  Core parameter handling and query string construction for exchange API requests.

  This module provides reusable parameter management patterns that are common
  across different exchanges:
  - Query string construction with proper URL encoding
  - Parameter filtering and validation
  - Alphabetical sorting for signature consistency
  - Optional parameter handling

  Exchange-specific parameter ordering and timing requirements are handled
  by individual exchange adapters that delegate common operations to this module.

  All functions are pure with no side effects for reliable testing.
  """

  @doc """
  Builds a query string from parameters with proper URL encoding.

  Takes a map of parameters and constructs a URL-encoded query string.
  Parameters are sorted alphabetically by key for consistent ordering.

  ## Parameters

    * `params` - Map of parameters to encode

  ## Options

    * `:sort` - Whether to sort parameters alphabetically (default: `true`)
    * `:exclude_keys` - List of keys to exclude from the query string (default: `[]`)

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "side" => "BUY"}
      iex> ParameterBuilder.build_query_string(params)
      "side=BUY&symbol=BTCUSDT"

      iex> params = %{"symbol" => "BTCUSDT", "timestamp" => "1234567890"}
      iex> ParameterBuilder.build_query_string(params, exclude_keys: ["timestamp"])
      "symbol=BTCUSDT"

  ## Notes

  This function provides consistent URL encoding and parameter ordering
  that works across different exchanges. Exchange-specific ordering rules
  should be implemented in the exchange adapters.
  """
  @spec build_query_string(map(), keyword()) :: String.t()
  def build_query_string(params, opts \\ []) do
    sort? = Keyword.get(opts, :sort, true)
    exclude_keys = Keyword.get(opts, :exclude_keys, [])

    filtered_params = Map.drop(params, exclude_keys)

    param_pairs =
      if sort? do
        filtered_params
        |> Enum.sort()
        |> Enum.map(&encode_param_pair/1)
      else
        Enum.map(filtered_params, &encode_param_pair/1)
      end

    Enum.join(param_pairs, "&")
  end

  @doc """
  Filters out nil and empty string values from parameters.

  Removes parameters with `nil` values or empty strings, which is a common
  requirement across exchanges for optional parameters.

  ## Parameters

    * `params` - Map of parameters to filter

  ## Options

    * `:remove_empty_strings` - Whether to remove empty strings (default: `true`)

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "type" => nil, "side" => ""}
      iex> ParameterBuilder.filter_optional_params(params)
      %{"symbol" => "BTCUSDT"}

      iex> params = %{"symbol" => "BTCUSDT", "side" => ""}
      iex> ParameterBuilder.filter_optional_params(params, remove_empty_strings: false)
      %{"symbol" => "BTCUSDT", "side" => ""}
  """
  @spec filter_optional_params(map(), keyword()) :: map()
  def filter_optional_params(params, opts \\ []) do
    remove_empty_strings? = Keyword.get(opts, :remove_empty_strings, true)

    Enum.reduce(params, %{}, fn {key, value}, acc ->
      cond do
        is_nil(value) ->
          # Always remove nil values
          acc

        remove_empty_strings? and value === "" ->
          # Remove empty strings if option is enabled
          acc

        true ->
          # Keep the parameter
          Map.put(acc, key, value)
      end
    end)
  end

  @doc """
  Validates that required parameters are present and non-nil.

  Checks that all required parameters exist in the parameter map and have
  non-nil values.

  ## Parameters

    * `params` - Map of parameters to validate
    * `required_keys` - List of keys that must be present

  ## Returns

    * `:ok` if all required parameters are present
    * `{:error, {:missing_required_param, key}}` if a required parameter is missing

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "side" => "BUY"}
      iex> ParameterBuilder.validate_required_params(params, ["symbol", "side"])
      :ok

      iex> params = %{"symbol" => "BTCUSDT"}
      iex> ParameterBuilder.validate_required_params(params, ["symbol", "side"])
      {:error, {:missing_required_param, "side"}}

      iex> params = %{"symbol" => "BTCUSDT", "side" => nil}
      iex> ParameterBuilder.validate_required_params(params, ["symbol", "side"])
      {:error, {:missing_required_param, "side"}}
  """
  @spec validate_required_params(map(), [String.t()]) :: :ok | {:error, {:missing_required_param, String.t()}}
  def validate_required_params(params, required_keys) do
    case find_missing_param(params, required_keys) do
      nil -> :ok
      missing_key -> {:error, {:missing_required_param, missing_key}}
    end
  end

  @doc """
  Normalizes parameter values to strings for consistent API formatting.

  Converts various parameter types to their string representations as expected
  by most exchange APIs.

  ## Parameters

    * `params` - Map of parameters to normalize

  ## Examples

      iex> params = %{"quantity" => 1.5, "price" => Decimal.new("10.50"), "test" => true}
      iex> ParameterBuilder.normalize_param_values(params)
      %{"quantity" => "1.5", "price" => "10.50", "test" => "true"}

      iex> params = %{"timestamp" => 1640995200000}
      iex> ParameterBuilder.normalize_param_values(params)
      %{"timestamp" => "1640995200000"}
  """
  @spec normalize_param_values(map()) :: map()
  def normalize_param_values(params) do
    Map.new(params, fn {key, value} ->
      {key, normalize_value(value)}
    end)
  end

  @doc """
  Merges parameters with defaults, giving priority to existing values.

  Takes a map of default values and merges them with existing parameters,
  where existing parameters take precedence over defaults.

  ## Parameters

    * `params` - Map of existing parameters
    * `defaults` - Map of default parameter values

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT"}
      iex> defaults = %{"symbol" => "ETHUSDT", "type" => "LIMIT", "timeInForce" => "GTC"}
      iex> ParameterBuilder.merge_with_defaults(params, defaults)
      %{"symbol" => "BTCUSDT", "type" => "LIMIT", "timeInForce" => "GTC"}
  """
  @spec merge_with_defaults(map(), map()) :: map()
  def merge_with_defaults(params, defaults) do
    Map.merge(defaults, params)
  end

  @doc """
  Splits parameters into multiple groups based on key prefixes or patterns.

  Useful for separating different types of parameters (e.g., timing parameters,
  query parameters, body parameters).

  ## Parameters

    * `params` - Map of parameters to split
    * `groups` - Keyword list where keys are group names and values are lists of parameter keys

  ## Returns

  Map where keys are group names and values are parameter maps for that group.

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "timestamp" => "123", "recvWindow" => "5000"}
      iex> groups = [timing: ["timestamp", "recvWindow"], trading: ["symbol", "side"]]
      iex> ParameterBuilder.split_params_by_groups(params, groups)
      %{
        timing: %{"timestamp" => "123", "recvWindow" => "5000"},
        trading: %{"symbol" => "BTCUSDT"}
      }
  """
  @spec split_params_by_groups(map(), keyword()) :: %{atom() => map()}
  def split_params_by_groups(params, groups) do
    Map.new(groups, fn {group_name, keys} ->
      group_params = Map.take(params, keys)
      {group_name, group_params}
    end)
  end

  # Private helper functions

  @spec encode_param_pair({String.t(), term()}) :: String.t()
  defp encode_param_pair({key, value}) do
    encoded_value = value |> to_string() |> URI.encode_www_form()
    "#{key}=#{encoded_value}"
  end

  @spec find_missing_param(map(), [String.t()]) :: String.t() | nil
  defp find_missing_param(params, required_keys) do
    Enum.find(required_keys, fn key ->
      case Map.get(params, key) do
        nil -> true
        _ -> false
      end
    end)
  end

  @spec normalize_value(term()) :: String.t()
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_value(value) when is_float(value), do: Float.to_string(value)
  defp normalize_value(value) when is_boolean(value), do: Atom.to_string(value)
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)

  # Handle Decimal values (common for financial amounts)
  defp normalize_value(%{__struct__: Decimal} = value) do
    Decimal.to_string(value, :normal)
  end

  # Fallback for other types
  defp normalize_value(value), do: to_string(value)
end
