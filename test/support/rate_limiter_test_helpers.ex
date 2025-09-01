defmodule ZenCex.RateLimiterTestHelpers do
  @moduledoc """
  Test helpers for rate limiter tests.

  Provides utilities for cleaning up ETS tables and resetting state
  between tests to prevent pollution.
  """

  @doc """
  Resets all rate limiter tables for the Binance adapter.

  This function:
  1. Directly cleans up ETS table objects to avoid table creation conflicts
  2. Uses the core rate limiter reset on existing tables only
  3. Handles all API types: spot, sapi, usdm_futures, coinm_futures, portfolio
  """
  @spec reset_all_binance_rate_limiter_tables() :: :ok
  def reset_all_binance_rate_limiter_tables do
    alias ZenCex.Adapters.Binance.RateLimiter
    alias ZenCex.Core.RateLimiter, as: Core

    # Clean up all existing tables directly
    api_types = [:spot, :sapi, :usdm_futures, :coinm_futures, :portfolio]

    Enum.each(api_types, fn api_type ->
      table_name = String.to_atom("#{RateLimiter}.Table.#{api_type}")

      case :ets.whereis(table_name) do
        :undefined ->
          :ok

        _tid ->
          # Reset using core rate limiter directly to avoid get_or_create issues
          Core.reset(table_name, :all)
      end
    end)

    :ok
  end

  @doc """
  Gets the actual table name for a given Binance API type.

  Useful for debugging and advanced test scenarios.
  """
  @spec get_binance_rate_limiter_table_name(atom()) :: atom()
  def get_binance_rate_limiter_table_name(api_type) do
    alias ZenCex.Adapters.Binance.RateLimiter

    String.to_atom("#{RateLimiter}.Table.#{api_type}")
  end

  @doc """
  Lists all existing Binance rate limiter tables.

  Returns a list of {api_type, table_name, exists?} tuples.
  """
  @spec list_binance_rate_limiter_tables() :: [{atom(), atom(), boolean()}]
  def list_binance_rate_limiter_tables do
    api_types = [:spot, :sapi, :usdm_futures, :coinm_futures, :portfolio]

    Enum.map(api_types, fn api_type ->
      table_name = get_binance_rate_limiter_table_name(api_type)
      exists = :ets.whereis(table_name) != :undefined
      {api_type, table_name, exists}
    end)
  end

  @doc """
  Deletes all Binance rate limiter ETS tables completely.

  This is more aggressive than reset - it deletes the tables entirely.
  Use with caution as it may cause issues if tests are running concurrently.
  """
  @spec delete_all_binance_rate_limiter_tables() :: :ok
  def delete_all_binance_rate_limiter_tables do
    api_types = [:spot, :sapi, :usdm_futures, :coinm_futures, :portfolio]

    Enum.each(api_types, fn api_type ->
      table_name = get_binance_rate_limiter_table_name(api_type)

      case :ets.whereis(table_name) do
        :undefined -> :ok
        tid -> :ets.delete(tid)
      end
    end)

    :ok
  end
end
