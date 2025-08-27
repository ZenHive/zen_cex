defmodule ZenCex.Adapters.BaseParser do
  @moduledoc """
  Common parsing patterns for all exchange adapters.

  Provides shared parsing logic for common response formats,
  error handling, and data normalization across exchanges.
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
      """
      @spec log_error_response(any(), atom()) :: :ok
      def log_error_response(response, exchange) do
        Logger.warning("#{exchange} API error response",
          response: inspect(response, limit: :infinity),
          exchange: exchange
        )
      end

      @doc """
      Standardizes common error messages across exchanges.
      """
      @spec standardize_error(String.t() | map()) :: atom() | String.t()
      def standardize_error(message) when is_binary(message) do
        ResponseParser.standardize_error_message(message)
      end

      def standardize_error(%{"msg" => msg}), do: standardize_error(msg)
      def standardize_error(%{"message" => msg}), do: standardize_error(msg)
      def standardize_error(%{"error" => msg}), do: standardize_error(msg)
      def standardize_error(_), do: :unknown_error

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

      defp normalize_balance(balance) do
        %{
          asset: get_asset_name(balance),
          free: parse_decimal(get_free_amount(balance)),
          locked: parse_decimal(get_locked_amount(balance)),
          total: parse_decimal(get_total_amount(balance))
        }
      end

      defp get_asset_name(%{"asset" => asset}), do: asset
      defp get_asset_name(%{"coin" => coin}), do: coin
      defp get_asset_name(%{"currency" => currency}), do: currency
      defp get_asset_name(_), do: nil

      defp get_free_amount(%{"free" => amount}), do: amount
      defp get_free_amount(%{"available" => amount}), do: amount
      defp get_free_amount(%{"availableBalance" => amount}), do: amount
      defp get_free_amount(_), do: "0"

      defp get_locked_amount(%{"locked" => amount}), do: amount
      defp get_locked_amount(%{"frozen" => amount}), do: amount
      defp get_locked_amount(%{"lockedBalance" => amount}), do: amount
      defp get_locked_amount(_), do: "0"

      defp get_total_amount(%{"total" => amount}), do: amount
      defp get_total_amount(%{"balance" => amount}), do: amount
      defp get_total_amount(%{"walletBalance" => amount}), do: amount

      defp get_total_amount(balance) do
        free = parse_decimal(get_free_amount(balance))
        locked = parse_decimal(get_locked_amount(balance))
        free |> Decimal.add(locked) |> Decimal.to_string()
      end

      defp parse_decimal(nil), do: Decimal.new(0)
      defp parse_decimal(value) when is_binary(value), do: Decimal.new(value)
      defp parse_decimal(value) when is_number(value), do: Decimal.new(value)
      defp parse_decimal(_), do: Decimal.new(0)

      # Allow adapters to override these if needed
      defoverridable parse_generic: 1,
                     parse_server_time: 1,
                     parse_balances: 1,
                     standardize_error: 1
    end
  end
end
