defmodule ZenCex.Adapters.Bybit.Parser do
  @moduledoc """
  Response parser for Bybit V5 API.

  Handles Bybit's unified response structure with retCode/retMsg/result format.
  Follows pure Elixir error pass-through philosophy - all errors are returned
  as `{:error, raw_response}` with original exchange data preserved.

  ## Response Structure
  All Bybit V5 API responses follow this structure:
  ```json
  {
    "retCode": 0,        // 0 = success, non-zero = error
    "retMsg": "OK",      // Human-readable message
    "result": {...},     // Response data (null on error)
    "retExtInfo": {},    // Extended info (usually empty)
    "time": 1672211736359 // Server timestamp (ms)
  }
  ```

  ## Error Handling

  All errors are returned unchanged as `{:error, raw_response}` where `raw_response`
  is the complete Bybit response map including `retCode`, `retMsg`, and any other fields.

  ## Common Error Codes (Reference Only)

  These are documented for reference - the actual errors are passed through unchanged:

  - **10001-10999**: Authentication/signature errors
    - 10001: Invalid request params
    - 10002: Invalid API key
    - 10003: Invalid signature
    - 10006: Rate limited
  - **110000-119999**: Order-related errors
    - 110001: Order not found
    - 110004: Insufficient balance
    - 110012: Invalid symbol
  - **130000+**: System errors
    - 130006: Rate limit exceeded
  """

  alias ZenCex.Core.ResponseParser

  require Logger

  @doc """
  Parses a Bybit API response into a standardized format.

  Returns `{:ok, result}` for successful responses or `{:error, reason}` for errors.

  ## Examples

      iex> parse(%{status: 200, body: ~s({"retCode":0,"retMsg":"OK","result":{"symbol":"BTCUSDT"}})})
      {:ok, %{"symbol" => "BTCUSDT"}}

      iex> parse(%{status: 200, body: ~s({"retCode":10006,"retMsg":"Too many visits!"})})
      {:error, :rate_limited}
  """
  @spec parse(map()) :: {:ok, term()} | {:error, term()}
  def parse(%{status: status, body: body} = response) when is_binary(body) do
    case ResponseParser.parse_json_body(body) do
      {:ok, parsed} ->
        handle_bybit_response(parsed, status, response)

      {:error, :invalid_json} ->
        ResponseParser.parse_html_error(body, status)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Handle case where Req has already decoded the JSON to a map
  def parse(%{status: status, body: body} = response) when is_map(body) do
    handle_bybit_response(body, status, response)
  end

  # Handle direct map response (from successful requests)
  def parse(%{"retCode" => _} = body) do
    # This is a direct Bybit response body
    handle_bybit_response(body, 200, %{})
  end

  def parse(%{status: status}) do
    # No body or non-binary body
    {:error, ResponseParser.map_http_status_to_error(status)}
  end

  def parse(_), do: {:error, :invalid_response}

  @doc """
  Extracts rate limit information from Bybit response headers and body.

  Bybit includes rate limit info in the response body's retExtInfo field
  and sometimes in headers.
  """
  @spec extract_rate_limits(map()) :: map()
  def extract_rate_limits(%{headers: headers, body: body}) when is_list(headers) do
    header_limits = ResponseParser.extract_rate_limit_info(headers)

    body_limits =
      case ResponseParser.parse_json_body(body) do
        {:ok, %{"retExtInfo" => ext_info}} when is_map(ext_info) ->
          parse_ext_info_limits(ext_info)

        _ ->
          %{}
      end

    Map.merge(header_limits, body_limits)
  end

  def extract_rate_limits(_), do: %{}

  # Private functions

  defp handle_bybit_response(%{"retCode" => 0, "result" => result}, _status, _response) do
    {:ok, result}
  end

  defp handle_bybit_response(%{"retCode" => 0} = data, _status, _response) do
    # Success but no result field (some endpoints return data at root level)
    {:ok, Map.drop(data, ["retCode", "retMsg", "time", "retExtInfo"])}
  end

  defp handle_bybit_response(%{"retCode" => code} = response, _status, _response) when is_integer(code) and code != 0 do
    # Pass through raw error response unchanged - preserve all original context
    {:error, response}
  end

  defp handle_bybit_response(%{"retCode" => code} = response, _status, _response) do
    # Non-integer retCode or other error format - pass through unchanged
    Logger.warning("Bybit returned unexpected retCode format: #{inspect(code)}")
    {:error, response}
  end

  defp handle_bybit_response(data, status, _response) when is_map(data) do
    # Response doesn't have expected Bybit structure
    Logger.debug("Bybit response missing retCode/retMsg structure: #{inspect(data)}")
    ResponseParser.normalize_response(%{status: status, body: Jason.encode!(data)})
  end

  defp handle_bybit_response(_, status, _response) do
    {:error, ResponseParser.map_http_status_to_error(status)}
  end

  defp parse_ext_info_limits(ext_info) do
    Enum.reduce(ext_info, %{}, fn
      {"rateLimit", value}, acc when is_integer(value) ->
        Map.put(acc, :rate_limit, value)

      {"rateLimitApi", value}, acc when is_binary(value) ->
        Map.put(acc, :rate_limit_api, value)

      {"rateLimitStatus", value}, acc when is_binary(value) ->
        Map.put(acc, :rate_limit_status, value)

      _, acc ->
        acc
    end)
  end

  # Specialized parsers for common endpoints

  @doc """
  Parses unified trading API responses.
  This is an alias for the main parse/1 function used by generated endpoints.
  """
  @spec parse_unified_response(map() | binary()) :: {:ok, term()} | {:error, term()}
  def parse_unified_response(response), do: parse(response)

  @doc """
  Parses server time response body directly.

  ## Examples

      iex> parse_server_time(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"timeSecond" => "1672211736", "timeNano" => "1672211736359000000"}})
      {:ok, %{"timeSecond" => "1672211736", "timeNano" => "1672211736359000000"}}
  """
  @spec parse_server_time(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_server_time(body) when is_map(body) do
    # Body is already decoded by Req
    handle_bybit_response(body, 200, %{})
  end

  def parse_server_time(body) when is_binary(body) do
    # If still a string, decode it first
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses error response body directly.
  """
  @spec parse_error(map() | binary()) :: {:error, term()}
  def parse_error(%{"retCode" => _} = body) do
    # Direct Bybit response body
    case handle_bybit_response(body, 400, %{}) do
      {:ok, _} -> {:error, :unexpected_success}
      error -> error
    end
  end

  def parse_error(body) when is_map(body) do
    # For errors, we expect a Bybit error structure
    case handle_bybit_response(body, 400, %{}) do
      {:ok, _} -> {:error, :unexpected_success}
      error -> error
    end
  end

  def parse_error(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_error(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses announcements response body directly.

  ## Examples

      iex> parse_announcements(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"list" => [...]}})
      {:ok, %{"list" => [...]}}
  """
  @spec parse_announcements(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_announcements(body) when is_map(body) do
    # Body is already decoded by Req
    handle_bybit_response(body, 200, %{})
  end

  def parse_announcements(body) when is_binary(body) do
    # If still a string, decode it first
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses wallet balance response.
  """
  @spec parse_wallet_balance(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_wallet_balance(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_wallet_balance(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses order response (place, cancel, get).
  """
  @spec parse_order(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_order(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_order(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses multiple orders response.
  """
  @spec parse_orders(map() | binary()) :: {:ok, list()} | {:error, term()}
  def parse_orders(body) when is_map(body) do
    case handle_bybit_response(body, 200, %{}) do
      {:ok, result} when is_map(result) ->
        # Extract list from result (handle both direct list and nested structure)
        orders = Map.get(result, "list", result)
        {:ok, orders}

      {:ok, result} when is_list(result) ->
        {:ok, result}

      error ->
        error
    end
  end

  def parse_orders(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_orders(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses batch cancel response.
  """
  @spec parse_batch_cancel(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_batch_cancel(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_batch_cancel(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses positions response.
  """
  @spec parse_positions(map() | binary()) :: {:ok, list()} | {:error, term()}
  def parse_positions(body) when is_map(body) do
    case handle_bybit_response(body, 200, %{}) do
      {:ok, result} when is_map(result) ->
        # Extract list from result
        positions = Map.get(result, "list", [])
        {:ok, positions}

      {:ok, result} when is_list(result) ->
        {:ok, result}

      error ->
        error
    end
  end

  def parse_positions(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_positions(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses trades/executions response.
  """
  @spec parse_trades(map() | binary()) :: {:ok, list()} | {:error, term()}
  def parse_trades(body) when is_map(body) do
    case handle_bybit_response(body, 200, %{}) do
      {:ok, result} when is_map(result) ->
        # Extract list from result
        trades = Map.get(result, "list", [])
        {:ok, trades}

      {:ok, result} when is_list(result) ->
        {:ok, result}

      error ->
        error
    end
  end

  def parse_trades(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_trades(decoded)
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses generic response (for operations that don't need special handling).
  """
  @spec parse_generic(map() | binary()) :: {:ok, map()} | {:error, term()}
  def parse_generic(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_generic(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc """
  Parses market data API responses.

  Market data responses can be:
  - Simple result for single items (ticker, instrument info)
  - List-based result for collections (klines, trades, order book)
  - Paginated results with nextPageCursor

  ## Examples

      iex> parse_market_data_response(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"list" => [...]}})
      {:ok, %{"list" => [...]}}

      iex> parse_market_data_response(%{"retCode" => 0, "retMsg" => "OK", "result" => %{"symbol" => "BTCUSDT"}})
      {:ok, %{"symbol" => "BTCUSDT"}}
  """
  @spec parse_market_data_response(map() | binary()) :: {:ok, term()} | {:error, term()}
  def parse_market_data_response(body) when is_map(body) do
    handle_bybit_response(body, 200, %{})
  end

  def parse_market_data_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> handle_bybit_response(decoded, 200, %{})
      {:error, _} -> {:error, :invalid_json}
    end
  end
end
