defmodule ZenCex.Adapters.Bybit.ParameterBuilder do
  @moduledoc """
  Bybit-specific parameter handling and query string construction.

  This module handles Bybit v5 API's specific parameter requirements,
  delegating common operations to Core.ParameterBuilder. It provides:
  - Automatic category injection based on operation prefixes
  - Timestamp and recv_window handling
  - Parameter ordering for signature generation
  - Query string vs JSON body formatting based on HTTP method

  All functions are pure with no side effects for reliable testing.
  """

  alias ZenCex.Core.ParameterBuilder, as: Core

  @default_recv_window "5000"
  @category_prefixes %{
    "spot_" => "spot",
    "linear_" => "linear",
    "inverse_" => "inverse",
    "option_" => "option"
  }

  @doc """
  Builds parameters for a Bybit API request.

  Handles Bybit-specific requirements including category injection,
  timestamp/recv_window addition, and proper formatting for GET/POST.

  ## Parameters

    * `params` - Map of request parameters
    * `operation` - The operation name (e.g., "spot_place_order", "linear_get_positions")
    * `opts` - Options including:
      * `:timestamp` - Request timestamp in milliseconds (auto-generated if not provided)
      * `:recv_window` - Receive window in milliseconds (default "5000")
      * `:method` - HTTP method (:get or :post), affects formatting

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "side" => "BUY"}
      iex> ParameterBuilder.build_params(params, "spot_place_order")
      %{
        "symbol" => "BTCUSDT",
        "side" => "BUY",
        "category" => "spot",
        "timestamp" => "1658385579423",
        "recv_window" => "5000"
      }

      iex> params = %{"symbol" => "BTCUSDT"}
      iex> ParameterBuilder.build_params(params, "linear_get_positions")
      %{
        "symbol" => "BTCUSDT",
        "category" => "linear",
        "timestamp" => "1658385579423",
        "recv_window" => "5000"
      }
  """
  @spec build_params(map(), String.t(), keyword()) :: map()
  def build_params(params, operation, opts \\ []) do
    timestamp = Keyword.get_lazy(opts, :timestamp, fn -> generate_timestamp() end)
    recv_window = Keyword.get(opts, :recv_window, @default_recv_window)

    params
    |> inject_category(operation)
    |> add_timing_params(timestamp, recv_window)
    |> Core.filter_optional_params()
    |> Core.normalize_param_values()
  end

  @doc """
  Builds a query string for GET requests with Bybit's ordering requirements.

  Parameters are sorted alphabetically as required by Bybit for signature generation.

  ## Parameters

    * `params` - Map of parameters to encode

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "category" => "spot"}
      iex> ParameterBuilder.build_query_string(params)
      "category=spot&symbol=BTCUSDT"
  """
  @spec build_query_string(map()) :: String.t()
  def build_query_string(params) do
    Core.build_query_string(params, sort: true)
  end

  @doc """
  Formats parameters for POST request body.

  POST requests require JSON body format for Bybit v5 API.

  ## Parameters

    * `params` - Map of parameters

  ## Returns

  JSON string representation of the parameters.

  ## Examples

      iex> params = %{"symbol" => "BTCUSDT", "side" => "BUY", "category" => "spot"}
      iex> ParameterBuilder.format_json_body(params)
      ~s({"category":"spot","side":"BUY","symbol":"BTCUSDT"})
  """
  @spec format_json_body(map()) :: String.t()
  def format_json_body(params) do
    Jason.encode!(params)
  end

  @doc """
  Extracts the category from an operation name prefix.

  ## Parameters

    * `operation` - The operation name (e.g., "spot_place_order")

  ## Returns

  The category string or nil if no matching prefix.

  ## Examples

      iex> ParameterBuilder.get_category_from_operation("spot_place_order")
      "spot"

      iex> ParameterBuilder.get_category_from_operation("linear_get_positions")
      "linear"

      iex> ParameterBuilder.get_category_from_operation("server_time")
      nil
  """
  @spec get_category_from_operation(String.t()) :: String.t() | nil
  def get_category_from_operation(operation) do
    Enum.find_value(@category_prefixes, fn {prefix, category} ->
      if String.starts_with?(operation, prefix), do: category
    end)
  end

  # Private helper functions

  @spec inject_category(map(), String.t()) :: map()
  defp inject_category(params, operation) do
    case get_category_from_operation(operation) do
      nil -> params
      category -> Map.put_new(params, "category", category)
    end
  end

  @spec add_timing_params(map(), String.t(), String.t()) :: map()
  defp add_timing_params(params, timestamp, recv_window) do
    params
    |> Map.put("timestamp", timestamp)
    |> Map.put("recv_window", recv_window)
  end

  @spec generate_timestamp() :: String.t()
  defp generate_timestamp do
    :millisecond |> System.system_time() |> Integer.to_string()
  end
end
