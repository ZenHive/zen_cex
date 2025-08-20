defmodule ZenCex.Adapters.Binance.PortfolioMargin do
  @moduledoc """
  Portfolio Margin trading endpoints for Binance.

  Portfolio Margin provides unified margin across multiple trading products:
  - USDT-M Futures (UM)
  - COIN-M Futures (CM)
  - Margin trading

  Features:
  - Cross-collateralization between different product types
  - Single account balance for multiple trading products
  - Unified position and order management
  - Enhanced capital efficiency

  These endpoints use the /papi/ path prefix and have a higher rate limit
  of 3,000 requests per minute compared to regular futures.
  """

  use ZenCex.EndpointRegistry, adapter: ZenCex.Adapters.Binance.Endpoints

  alias ZenCex.Adapters.Binance.Parser

  require Logger

  # Import generated endpoints from Postman collection
  # This is loaded at compile time as a module attribute for safety
  # Mark as external resource so recompilation happens when the file changes
  @external_resource "lib/zen_cex/adapters/binance/generated_portfolio_endpoints.ex"

  # Load the endpoints file at compile time and convert to AST
  @generated_endpoints (
                         path = Path.join([__DIR__, "generated_portfolio_endpoints.ex"])
                         {:ok, content} = File.read(path)
                         # Parse as Elixir code to get the AST
                         {:ok, ast} = Code.string_to_quoted(content)
                         # The file contains a list literal, evaluate it in a restricted context
                         {result, _} = Code.eval_quoted(ast, [Parser: Parser], __ENV__)
                         result
                       )

  # Use endpoints directly without renaming to maintain simplicity
  # This ensures generated tests match actual function names
  @endpoints @generated_endpoints

  # Custom operations that require special handling
  @doc """
  Get unified account information across all product types.

  Returns consolidated account data including UM, CM, and Margin positions
  with cross-collateralization details.
  """
  @spec get_unified_account(map()) :: {:ok, map()} | {:error, term()}
  def get_unified_account(params \\ %{}) do
    get_unified_account(params, [])
  end

  @spec get_unified_account(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_unified_account(params, opts) do
    # Use the primary account endpoint which provides unified view
    account_information(params, opts)
  end

  @doc """
  Place a unified order that can span multiple product types.

  This allows placing orders that can use collateral from different
  trading products within the portfolio margin system.
  """
  @spec place_unified_order(map()) :: {:ok, map()} | {:error, term()}
  def place_unified_order(params) do
    place_unified_order(params, [])
  end

  @spec place_unified_order(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def place_unified_order(params, opts) do
    # Determine which product type based on symbol or explicit parameter
    product_type = determine_product_type(params)

    case product_type do
      :um_futures -> new_um_order(params, opts)
      :cm_futures -> new_cm_order(params, opts)
      :margin -> new_margin_order(params, opts)
      _ -> {:error, {:invalid_product_type, product_type}}
    end
  end

  @doc """
  Get all positions across UM, CM, and Margin products.

  Returns a unified view of all positions with cross-margin calculations.
  """
  @spec get_all_positions(map()) :: {:ok, map()} | {:error, term()}
  def get_all_positions(params \\ %{}) do
    get_all_positions(params, [])
  end

  @spec get_all_positions(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_all_positions(params, opts) do
    with {:ok, um_positions} <- query_um_position_information(params, opts),
         {:ok, cm_positions} <- query_cm_position_information(params, opts) do
      # TODO: For now, combine UM and CM positions
      # In the future, add margin positions when endpoint is available
      combined_positions = %{
        um_futures: um_positions,
        cm_futures: cm_positions
      }

      {:ok, combined_positions}
    end
  end

  # Helper function to determine product type from order parameters
  defp determine_product_type(%{symbol: symbol}) when is_binary(symbol) do
    cond do
      String.ends_with?(symbol, "USDT") -> :um_futures
      String.contains?(symbol, "USD_") -> :cm_futures
      true -> :margin
    end
  end

  defp determine_product_type(%{product_type: type}) do
    case type do
      "UM" -> :um_futures
      "CM" -> :cm_futures
      "MARGIN" -> :margin
      _ -> :unknown
    end
  end

  defp determine_product_type(_), do: :unknown
end
