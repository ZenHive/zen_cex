defmodule ZenCex.Adapters.BaseParser do
  @moduledoc """
  Common parsing patterns for all exchange adapters.

  Provides shared parsing logic for common response formats and
  data normalization across exchanges.

  ## Error Handling Philosophy: Pure Pass-Through

  **CRITICAL**: This library follows pure Elixir/Erlang error handling philosophy:

  ### Always Pass Raw Errors Through Unchanged

  Exchange APIs return diverse, unpredictable error formats. We CANNOT and SHOULD NOT
  attempt to standardize them because:

  1. **Incompleteness**: We can never cover all error codes from all exchanges
  2. **Loss of Context**: Wrapping errors loses original messages, codes, and metadata
  3. **Maintenance Burden**: New errors are added, old ones change - leaky abstraction
  4. **User Needs**: Users handle exchange-specific errors anyway for edge cases

  ### What To Do Instead

  ```elixir
  # ❌ BAD: Error standardization/mapping
  def parse_response(%{"code" => 10001}) do
    {:error, :invalid_api_key}  # Lost original message and context!
  end

  def parse_response(%{"code" => code}) do
    {:error, map_error_code(code)}  # Incomplete - can't cover all codes
  end

  # ✅ GOOD: Pass raw errors through
  def parse_response(%{"code" => code} = response) when code != 0 do
    {:error, response}  # Preserve everything!
  end

  def parse_response(%{"retCode" => code, "retMsg" => msg} = response) when code != 0 do
    {:error, response}  # Keep original structure
  end
  ```

  ### Documentation Over Code

  Instead of error mapping in code, document common patterns in your adapter's moduledoc:

  ```elixir
  @moduledoc \"\"\"
  Bybit Parser

  ## Common Error Codes (Reference Only)
  - 10001: Invalid API key
  - 110004: Insufficient balance
  - 130006: Rate limit exceeded

  All errors are returned as `{:error, raw_response}` with the original
  exchange response preserved.
  \"\"\"
  ```

  ### Benefits of Pass-Through

  - **Simplicity**: No error mapping code to maintain
  - **Completeness**: All errors automatically handled
  - **Debugging**: Original error messages preserved
  - **Flexibility**: Users can handle errors their way
  - **Future-proof**: New errors work automatically

  ## Data Normalization

  This module provides helpers for normalizing SUCCESS responses (balances, positions, etc.)
  where standardization adds value. Errors should NEVER be normalized.
  """

  defmacro __using__(_opts) do
    quote do
      alias ZenCex.Core.ResponseParser

      require Logger

      @doc """
      Parses a generic response (map or list).
      """
      @spec parse_generic(any()) :: {:ok, any()} | {:error, term()}
      def parse_generic(response) when is_map(response) or is_list(response) do
        {:ok, response}
      end

      def parse_generic(response), do: {:ok, response}

      @doc """
      Parses server time from various response formats.
      """
      @spec parse_server_time(map()) :: {:ok, map()} | {:error, :invalid_format}
      def parse_server_time(%{"serverTime" => time} = _response) when is_integer(time) do
        {:ok, %{server_time: time}}
      end

      def parse_server_time(%{"time" => time} = _response) when is_integer(time) do
        {:ok, %{server_time: time}}
      end

      def parse_server_time(%{"timestamp" => time} = _response) when is_integer(time) do
        {:ok, %{server_time: time}}
      end

      def parse_server_time(_), do: {:error, :invalid_format}

      @doc """
      Parses HTML error responses.
      """
      @spec parse_html_error(String.t(), integer()) :: {:error, term()}
      defdelegate parse_html_error(html, status), to: ResponseParser

      @doc """
      Logs error responses for debugging.

      Note: This is for internal debugging only. The error response should still
      be passed through unchanged to the caller.
      """
      @spec log_error_response(any(), atom()) :: :ok
      def log_error_response(response, exchange) do
        Logger.warning("#{exchange} API error response",
          response: inspect(response, limit: :infinity),
          exchange: exchange
        )
      end

      @doc """
      Parses balance responses into a common format.
      """
      @spec parse_balances(list()) :: {:ok, list(map())} | {:error, term()}
      def parse_balances(balances) when is_list(balances) do
        normalized = Enum.map(balances, &normalize_balance/1)
        {:ok, normalized}
      end

      def parse_balances(_), do: {:error, :invalid_balance_format}

      # Private helpers

      @spec normalize_balance(map()) :: map()
      defp normalize_balance(balance) do
        %{
          asset: get_asset_name(balance),
          free: parse_decimal(get_free_amount(balance)),
          locked: parse_decimal(get_locked_amount(balance)),
          total: parse_decimal(get_total_amount(balance))
        }
      end

      @spec get_asset_name(map()) :: String.t() | nil
      defp get_asset_name(%{"asset" => asset}), do: asset
      defp get_asset_name(%{"coin" => coin}), do: coin
      defp get_asset_name(%{"currency" => currency}), do: currency
      defp get_asset_name(_), do: nil

      @spec get_free_amount(map()) :: String.t() | number() | nil
      defp get_free_amount(%{"free" => amount}), do: amount
      defp get_free_amount(%{"available" => amount}), do: amount
      defp get_free_amount(%{"availableBalance" => amount}), do: amount
      defp get_free_amount(_), do: "0"

      @spec get_locked_amount(map()) :: String.t() | number() | nil
      defp get_locked_amount(%{"locked" => amount}), do: amount
      defp get_locked_amount(%{"frozen" => amount}), do: amount
      defp get_locked_amount(%{"lockedBalance" => amount}), do: amount
      defp get_locked_amount(_), do: "0"

      @spec get_total_amount(map()) :: String.t()
      defp get_total_amount(%{"total" => amount}) do
        amount |> Decimal.new() |> Decimal.to_string()
      end

      defp get_total_amount(%{"balance" => amount}) do
        amount |> Decimal.new() |> Decimal.to_string()
      end

      defp get_total_amount(%{"walletBalance" => amount}) do
        amount |> Decimal.new() |> Decimal.to_string()
      end

      defp get_total_amount(balance) do
        # Calculate total only if no total field exists
        free_value = get_free_amount(balance)
        locked_value = get_locked_amount(balance)

        free_value
        |> parse_decimal()
        |> Decimal.add(parse_decimal(locked_value))
        |> Decimal.to_string()
      end

      @spec parse_decimal(nil | String.t() | number()) :: Decimal.t()
      defp parse_decimal(nil), do: Decimal.new(0)
      defp parse_decimal(value) when is_binary(value), do: Decimal.new(value)
      defp parse_decimal(value) when is_number(value), do: Decimal.new(value)
      defp parse_decimal(_), do: Decimal.new(0)

      # Allow adapters to override these if needed
      defoverridable parse_generic: 1,
                     parse_server_time: 1,
                     parse_balances: 1
    end
  end
end
