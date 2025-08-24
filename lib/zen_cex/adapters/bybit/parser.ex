defmodule ZenCex.Adapters.Bybit.Parser do
  @moduledoc """
  Response parser for Bybit V5 API.

  Handles Bybit's unified response structure with retCode/retMsg/result format.
  Leverages Core.ResponseParser for common parsing patterns while handling
  Bybit-specific response formats and error codes.

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

  ## Error Codes
  - 10001-10999: Authentication/signature errors
  - 11000-11999: Order-related errors
  - 12000-12999: Position-related errors
  - 20000-29999: Business logic errors
  - 30000-39999: API-specific errors
  - 110000+: System and rate limit errors
  """

  alias ZenCex.Core.ResponseParser

  require Logger

  # Bybit-specific error code mappings
  @error_code_atoms %{
    # Authentication errors (10xxx)
    10_001 => :invalid_request_params,
    10_002 => :invalid_api_key,
    10_003 => :invalid_signature,
    10_004 => :signature_not_valid,
    10_005 => :permission_denied,
    10_006 => :rate_limited,
    10_007 => :api_key_expired,
    10_008 => :invalid_recv_window,
    10_009 => :invalid_timestamp,
    10_010 => :ip_not_whitelisted,

    # Order errors (110xxx)
    110_001 => :order_not_found,
    110_003 => :order_already_canceled,
    110_004 => :insufficient_balance,
    110_005 => :invalid_order_qty,
    110_007 => :invalid_order_price,
    110_012 => :invalid_symbol,
    110_013 => :invalid_order_type,
    110_014 => :invalid_order_side,
    110_017 => :duplicate_order_id,
    110_025 => :position_not_found,
    110_043 => :order_would_trigger_immediately,

    # System errors (10000+)
    10_016 => :server_error,
    10_018 => :too_many_requests,
    10_027 => :timestamp_out_of_range,
    20_001 => :order_not_exists,
    30_024 => :account_not_unified,

    # Rate limit specific
    130_006 => :rate_limit_exceeded,
    140_003 => :request_frequency_exceeded
  }

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

  defp handle_bybit_response(%{"retCode" => code, "retMsg" => msg}, _status, _response) when is_integer(code) do
    error_atom = Map.get(@error_code_atoms, code)

    if error_atom do
      {:error, error_atom}
    else
      # Unknown error code - use standardized error message parsing
      case ResponseParser.standardize_error_message(msg) do
        {:exchange_error, _} -> {:error, {code, msg}}
        atom -> {:error, atom}
      end
    end
  end

  defp handle_bybit_response(%{"retCode" => code, "retMsg" => msg}, _status, _response) do
    # Non-integer retCode (shouldn't happen but handle gracefully)
    Logger.warning("Bybit returned non-integer retCode: #{inspect(code)}")
    {:error, {code, msg}}
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
end
