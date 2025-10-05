defmodule ZenCex.Analysis.Basis do
  @moduledoc """
  Basis trading analysis for spot vs futures spread calculations.

  This module provides functions for:
  - Calculating spot-perpetual basis spreads
  - Analyzing term structure across futures expiries
  - Identifying contango/backwardation market conditions
  - Computing annualized basis returns

  All calculations use Decimal for precision and support both
  single-symbol and multi-symbol analysis.

  ## Supported Expiry Date Formats

  The module handles multiple date formats used by different exchanges:

  - **Binance**: `YYMMDD` format (e.g., "250926" for Sept 26, 2025)
  - **Bybit DD-MMM-YY**: Dash-separated format (e.g., "26-DEC-25")
  - **Bybit DDMMMYY**: Compact format (e.g., "03OCT25")
  - **ISO**: Standard format `YYYY-MM-DD` (for future compatibility)

  Symbol formats like "BTCUSDT-03OCT25" are automatically parsed to extract
  the date component.
  """

  alias ZenCex.Adapters.Binance
  alias ZenCex.Adapters.Bybit
  alias ZenCex.Core.Cache

  require Logger

  # Cache key prefix for all basis-related cache entries
  @cache_prefix "zen_cex:basis"

  # Cache duration for market data - short TTL for rapidly changing prices
  @price_cache_ttl_seconds 5

  # Cache duration for term structure - longer TTL for less volatile term structure
  @term_cache_ttl_seconds 60

  # Days per year for annualized calculations (standard financial year)
  @days_per_year 365

  # Funding periods per day - most exchanges use 8-hour funding periods (3x daily)
  # This can be overridden via Application.get_env(:zen_cex, :funding_periods_per_day, 3)
  @default_funding_periods_per_day 3

  # Maximum concurrent API calls to avoid rate limiting
  @max_api_concurrency 5

  # API call timeout - 10 seconds for external API calls
  @api_timeout_ms 10_000

  @typedoc "Exchange identifier"
  @type exchange :: :binance | :bybit | atom()

  @typedoc "Configuration map for exchange API access"
  @type config :: %{
          required(:api_key) => String.t(),
          required(:api_secret) => String.t(),
          optional(:testnet) => boolean()
        }

  @typedoc "Basis spread calculation result"
  @type basis_spread :: %{
          spot_price: Decimal.t(),
          perp_price: Decimal.t(),
          spread: Decimal.t(),
          spread_pct: Decimal.t(),
          annualized_return: Decimal.t(),
          funding_rate: Decimal.t(),
          funding_apr: Decimal.t(),
          market_condition: :contango | :backwardation | :neutral
        }

  @typedoc "Term structure data point"
  @type term_point :: %{
          expiry: String.t(),
          days_to_expiry: integer(),
          price: Decimal.t(),
          basis: Decimal.t(),
          basis_pct: Decimal.t(),
          annualized_return: Decimal.t()
        }

  @doc """
  Calculates the basis spread between spot and perpetual futures.

  ## Parameters
    - exchange: Exchange atom (:binance or :bybit)
    - symbol: Trading pair symbol (e.g., "BTCUSDT")
    - config: Exchange configuration map

  ## Returns
    - `{:ok, basis_spread}` with spread calculations
    - `{:error, reason}` on failure

  ## Examples

      get_basis_spread(:binance, "BTCUSDT", config)
      # => {:ok, %{
      #       spot_price: #Decimal<45000.00>,
      #       perp_price: #Decimal<45100.00>,
      #       spread: #Decimal<100.00>,
      #       spread_pct: #Decimal<0.22>,
      #       annualized_return: #Decimal<80.30>,
      #       funding_rate: #Decimal<0.01>,
      #       funding_apr: #Decimal<10.95>,
      #       market_condition: :contango
      #     }}
  """
  @spec get_basis_spread(exchange, String.t(), config) ::
          {:ok, basis_spread} | {:error, term()}
  def get_basis_spread(exchange, symbol, config) do
    cache_key = build_cache_key("basis_spread", exchange, symbol)
    start_time = System.monotonic_time()

    result =
      case Cache.get(cache_key) do
        {:ok, cached_result} ->
          emit_telemetry(:cache_hit, %{exchange: exchange, symbol: symbol}, start_time)
          {:ok, cached_result}

        {:error, _reason} ->
          with {:ok, spot_price} <- fetch_spot_price(exchange, symbol, config),
               {:ok, perp_price} <- fetch_perp_price(exchange, symbol, config),
               {:ok, funding_rate} <- fetch_funding_rate(exchange, symbol, config),
               {:ok, calculated} <- calculate_basis_spread(spot_price, perp_price, funding_rate) do
            Cache.put(cache_key, calculated, @price_cache_ttl_seconds)

            # Emit telemetry with spread data
            emit_telemetry(
              :spread_calculated,
              %{
                exchange: exchange,
                symbol: symbol,
                spread_pct: Decimal.to_float(calculated.spread_pct),
                market_condition: calculated.market_condition
              },
              start_time
            )

            {:ok, calculated}
          else
            error ->
              emit_telemetry(:spread_error, %{exchange: exchange, symbol: symbol, error: error}, start_time)
              error
          end
      end

    result
  end

  @doc """
  Gets the term structure across all futures expiries for a base asset.

  ## Parameters
    - exchange: Exchange atom (:binance or :bybit)
    - base_asset: Base asset symbol (e.g., "BTC", "ETH")
    - config: Exchange configuration map

  ## Returns
    - `{:ok, [term_point]}` sorted by days to expiry
    - `{:error, reason}` on failure

  ## Examples

      get_term_structure(:binance, "BTC", config)
      # => {:ok, [
      #       %{
      #         expiry: "240329",
      #         days_to_expiry: 7,
      #         price: #Decimal<45500.00>,
      #         basis: #Decimal<500.00>,
      #         basis_pct: #Decimal<1.11>,
      #         annualized_return: #Decimal<57.82>
      #       },
      #       %{
      #         expiry: "240628",
      #         days_to_expiry: 98,
      #         price: #Decimal<46000.00>,
      #         basis: #Decimal<1000.00>,
      #         basis_pct: #Decimal<2.22>,
      #         annualized_return: #Decimal<8.27>
      #       }
      #     ]}
  """
  @spec get_term_structure(exchange, String.t(), config) ::
          {:ok, [term_point]} | {:error, term()}
  def get_term_structure(exchange, base_asset, config) do
    cache_key = build_cache_key("term_structure", exchange, base_asset)
    start_time = System.monotonic_time()

    result =
      case Cache.get(cache_key) do
        {:ok, cached_result} ->
          emit_telemetry(:cache_hit, %{exchange: exchange, base_asset: base_asset}, start_time)
          {:ok, cached_result}

        {:error, _reason} ->
          with {:ok, spot_price} <- fetch_spot_price_for_base(exchange, base_asset, config),
               {:ok, futures_data} <- fetch_futures_contracts(exchange, base_asset, config),
               {:ok, term_structure} <- calculate_term_structure(spot_price, futures_data) do
            Cache.put(cache_key, term_structure, @term_cache_ttl_seconds)

            # Emit telemetry with term structure data
            emit_telemetry(
              :term_structure_calculated,
              %{
                exchange: exchange,
                base_asset: base_asset,
                contract_count: length(term_structure)
              },
              start_time
            )

            {:ok, term_structure}
          else
            error ->
              emit_telemetry(
                :term_structure_error,
                %{
                  exchange: exchange,
                  base_asset: base_asset,
                  error: error
                },
                start_time
              )

              error
          end
      end

    result
  end

  @doc """
  Compares basis spreads across multiple exchanges for arbitrage opportunities.

  ## Parameters
    - exchanges_with_configs: List of {exchange, config} tuples
    - symbols: List of trading pair symbols

  ## Returns
    - `{:ok, comparison_map}` with basis comparisons
    - `{:error, reason}` on failure

  ## Examples

      compare_basis_spreads([{:binance, config1}, {:bybit, config2}], ["BTCUSDT"])
      # => {:ok, %{
      #       "BTCUSDT" => %{
      #         binance: %{spread_pct: 0.22, market_condition: :contango},
      #         bybit: %{spread_pct: -0.15, market_condition: :backwardation},
      #         arbitrage_opportunity: true,
      #         best_long_spot: :bybit,
      #         best_short_perp: :binance
      #       }
      #     }}
  """
  @spec compare_basis_spreads([{exchange, config}], [String.t()]) ::
          {:ok, map()} | {:error, term()}
  def compare_basis_spreads(exchanges_with_configs, symbols) do
    results =
      Map.new(symbols, fn symbol ->
        spreads = fetch_spreads_for_symbol(exchanges_with_configs, symbol)
        {symbol, analyze_basis_arbitrage(spreads)}
      end)

    {:ok, results}
  end

  # Internal functions (exposed for testing)

  @doc false
  @spec calculate_basis_spread(Decimal.t(), Decimal.t(), Decimal.t()) :: {:ok, basis_spread}
  def calculate_basis_spread(spot_price, perp_price, funding_rate \\ Decimal.new(0)) do
    spread = Decimal.sub(perp_price, spot_price)

    # Calculate spread percentage (basis / spot * 100)
    # Handle division by zero
    spread_pct =
      if Decimal.compare(spot_price, Decimal.new(0)) == :eq do
        Decimal.new(0)
      else
        spread
        |> Decimal.div(spot_price)
        |> Decimal.mult(Decimal.new(100))
        |> Decimal.round(2)
      end

    # Calculate funding APR (funding rate * 3 * 365 for 8-hour funding)
    # Most exchanges use 8-hour funding periods (3 times per day)
    funding_periods = Application.get_env(:zen_cex, :funding_periods_per_day, @default_funding_periods_per_day)

    funding_apr =
      funding_rate
      |> Decimal.mult(Decimal.new(funding_periods))
      |> Decimal.mult(Decimal.new(@days_per_year))
      # Convert to percentage
      |> Decimal.mult(Decimal.new(100))
      |> Decimal.round(2)

    # Annualized return combines basis spread and funding rate
    # If in contango (perp > spot), you pay funding but capture basis
    # If in backwardation (perp < spot), you receive funding and capture basis
    if_result =
      if Decimal.compare(spread_pct, Decimal.new(0)) == :gt do
        # Contango: basis gain minus funding cost
        spread_pct |> Decimal.mult(Decimal.new(@days_per_year)) |> Decimal.sub(funding_apr)
      else
        # Backwardation: basis gain plus funding income
        spread_pct |> Decimal.abs() |> Decimal.mult(Decimal.new(@days_per_year)) |> Decimal.add(funding_apr)
      end

    annualized_return = Decimal.round(if_result, 2)

    # Determine market condition
    market_condition =
      cond do
        Decimal.compare(spread_pct, Decimal.new("0.1")) == :gt -> :contango
        Decimal.compare(spread_pct, Decimal.new("-0.1")) == :lt -> :backwardation
        true -> :neutral
      end

    {:ok,
     %{
       spot_price: Decimal.round(spot_price, 2),
       perp_price: Decimal.round(perp_price, 2),
       spread: Decimal.round(spread, 2),
       spread_pct: spread_pct,
       annualized_return: annualized_return,
       funding_rate: funding_rate |> Decimal.mult(Decimal.new(100)) |> Decimal.round(4),
       funding_apr: funding_apr,
       market_condition: market_condition
     }}
  end

  @doc false
  @spec calculate_term_structure(Decimal.t(), list(map())) :: {:ok, [term_point]} | {:error, term()}
  def calculate_term_structure(spot_price, futures_data) when is_list(futures_data) do
    now = DateTime.utc_now()

    term_points =
      futures_data
      |> Enum.map(fn contract ->
        days_to_expiry = calculate_days_to_expiry(contract.expiry, now)
        basis = Decimal.sub(contract.price, spot_price)

        basis_pct =
          basis
          |> Decimal.div(spot_price)
          |> Decimal.mult(Decimal.new(100))
          |> Decimal.round(2)

        # Annualized return = (basis_pct / days_to_expiry) * 365
        annualized_return =
          if days_to_expiry > 0 do
            basis_pct
            |> Decimal.div(Decimal.new(days_to_expiry))
            |> Decimal.mult(Decimal.new(@days_per_year))
            |> Decimal.round(2)
          else
            Decimal.new(0)
          end

        %{
          expiry: contract.expiry,
          days_to_expiry: days_to_expiry,
          price: Decimal.round(contract.price, 2),
          basis: Decimal.round(basis, 2),
          basis_pct: basis_pct,
          annualized_return: annualized_return
        }
      end)
      |> Enum.sort_by(& &1.days_to_expiry)

    {:ok, term_points}
  end

  def calculate_term_structure(_spot_price, _futures_data) do
    {:error, {:invalid_futures_data, "Expected list of futures contracts"}}
  end

  @doc false
  @spec analyze_basis_arbitrage(map()) :: map()
  def analyze_basis_arbitrage(spreads) when map_size(spreads) < 2 do
    Map.merge(spreads, %{
      arbitrage_opportunity: false,
      insufficient_data: true
    })
  end

  @doc false
  def analyze_basis_arbitrage(spreads) do
    # Find exchange with highest and lowest spread percentages
    sorted_by_spread =
      Enum.sort_by(spreads, fn {_exchange, data} ->
        Decimal.to_float(data.spread_pct)
      end)

    {min_exchange, min_data} = List.first(sorted_by_spread)
    {max_exchange, max_data} = List.last(sorted_by_spread)

    spread_diff =
      max_data.spread_pct
      |> Decimal.sub(min_data.spread_pct)
      |> Decimal.abs()

    # Arbitrage opportunity if spread difference > 0.5%
    arbitrage_opportunity = Decimal.compare(spread_diff, Decimal.new("0.5")) == :gt

    result =
      Map.merge(spreads, %{
        arbitrage_opportunity: arbitrage_opportunity,
        spread_difference: Decimal.round(spread_diff, 2)
      })

    if arbitrage_opportunity do
      Map.merge(result, %{
        # Long spot on exchange with lower basis (cheaper spot relative to futures)
        best_long_spot: min_exchange,
        # Short perp on exchange with higher basis (more expensive futures)
        best_short_perp: max_exchange,
        potential_profit_pct: spread_diff
      })
    else
      result
    end
  end

  @doc false
  @spec parse_expiry_date(String.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def parse_expiry_date(expiry_string) when is_binary(expiry_string) do
    cond do
      # Binance format: "YYMMDD" (e.g., "250926")
      String.length(expiry_string) == 6 and String.match?(expiry_string, ~r/^\d{6}$/) ->
        parse_binance_format(expiry_string)

      # Bybit format: "DD-MMM-YY" (e.g., "26-DEC-25")
      String.match?(expiry_string, ~r/^\d{1,2}-[A-Z]{3}-\d{2}$/) ->
        parse_bybit_dashed_format(expiry_string)

      # Bybit format: "SYMBOL-DDMMMYY" or just "DDMMMYY" (e.g., "BTCUSDT-03OCT25" or "03OCT25")
      String.match?(expiry_string, ~r/(^|-)\d{2}[A-Z]{3}\d{2}$/) ->
        parse_bybit_compact_format(expiry_string)

      # ISO format: "YYYY-MM-DD" (standard date format for future compatibility)
      String.match?(expiry_string, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        parse_iso_format(expiry_string)

      true ->
        {:error, {:unsupported_expiry_format, "Cannot parse expiry: #{expiry_string}"}}
    end
  end

  # Parse Binance YYMMDD format
  defp parse_binance_format(expiry_string) do
    year = "20" <> String.slice(expiry_string, 0, 2)
    month = String.slice(expiry_string, 2, 2)
    day = String.slice(expiry_string, 4, 2)
    parse_date_components(year, month, day)
  end

  # Parse Bybit DD-MMM-YY format
  defp parse_bybit_dashed_format(expiry_string) do
    [day, month_abbr, year] = String.split(expiry_string, "-")
    month = month_number_from_abbr(month_abbr)
    year = "20" <> year
    parse_date_components(year, month, day)
  end

  # Parse Bybit compact DDMMMYY format (with optional symbol prefix)
  defp parse_bybit_compact_format(expiry_string) do
    date_part =
      if String.contains?(expiry_string, "-") do
        expiry_string |> String.split("-") |> List.last()
      else
        expiry_string
      end

    day = String.slice(date_part, 0, 2)
    month_abbr = String.slice(date_part, 2, 3)
    year = "20" <> String.slice(date_part, 5, 2)
    month = month_number_from_abbr(month_abbr)
    parse_date_components(year, month, day)
  end

  # Parse ISO YYYY-MM-DD format
  defp parse_iso_format(expiry_string) do
    case Date.from_iso8601(expiry_string) do
      {:ok, date} ->
        # Convert to DateTime at UTC midnight
        {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}

      {:error, _} ->
        {:error, {:invalid_iso_format, "Expected YYYY-MM-DD format, got: #{expiry_string}"}}
    end
  end

  defp parse_date_components(year, month, day) when is_binary(year) and is_binary(month) and is_binary(day) do
    with {year_int, ""} <- Integer.parse(year),
         {month_int, ""} <- Integer.parse(month),
         {day_int, ""} <- Integer.parse(day),
         {:ok, date} <- Date.new(year_int, month_int, day_int) do
      {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}
    else
      _ -> {:error, {:invalid_date_format, "Cannot parse date components: #{year}/#{month}/#{day}"}}
    end
  end

  @month_map %{
    "JAN" => "01",
    "FEB" => "02",
    "MAR" => "03",
    "APR" => "04",
    "MAY" => "05",
    "JUN" => "06",
    "JUL" => "07",
    "AUG" => "08",
    "SEP" => "09",
    "OCT" => "10",
    "NOV" => "11",
    "DEC" => "12"
  }

  defp month_number_from_abbr(abbr) do
    Map.get(@month_map, abbr, "00")
  end

  @doc false
  @spec calculate_days_to_expiry(String.t(), DateTime.t()) :: non_neg_integer()
  def calculate_days_to_expiry(expiry_string, now) do
    # Parse expiry string - supports multiple formats
    case parse_expiry_date(expiry_string) do
      {:ok, expiry_date} ->
        # Never return negative days
        max(0, DateTime.diff(expiry_date, now, :day))

      _ ->
        0
    end
  end

  defp fetch_spot_price(:binance, symbol, _config) do
    case Binance.MarketData.get_ticker_price(%{symbol: symbol}) do
      {:ok, %{"price" => price}} ->
        {:ok, parse_decimal(price)}

      error ->
        error
    end
  end

  defp fetch_spot_price(:bybit, symbol, _config) do
    case Bybit.MarketData.get_tickers(%{category: "spot", symbol: symbol}) do
      {:ok, %{list: [%{last_price: price} | _]}} ->
        {:ok, parse_decimal(price)}

      {:ok, %{list: []}} ->
        {:error, {:symbol_not_found, symbol}}

      error ->
        error
    end
  end

  defp fetch_spot_price(exchange, _symbol, _config) do
    {:error, {:unsupported_exchange, exchange}}
  end

  defp fetch_perp_price(:binance, symbol, config) do
    account_type = Map.get(config, :account_type, :futures_usdm)

    case account_type do
      :futures_usdm ->
        case Binance.MarketData.usdm_get_ticker_price(%{symbol: symbol}) do
          {:ok, %{"price" => price}} ->
            {:ok, parse_decimal(price)}

          error ->
            error
        end

      :futures_coinm ->
        case Binance.MarketData.coinm_get_ticker_price(%{symbol: symbol}) do
          {:ok, %{"price" => price}} ->
            {:ok, parse_decimal(price)}

          error ->
            error
        end

      _ ->
        {:error, {:unsupported_account_type, account_type}}
    end
  end

  defp fetch_perp_price(:bybit, symbol, config) do
    account_type = Map.get(config, :account_type, :linear)

    category =
      case account_type do
        :linear -> "linear"
        :inverse -> "inverse"
        _ -> "linear"
      end

    case Bybit.MarketData.get_tickers(%{category: category, symbol: symbol}) do
      {:ok, %{list: [%{last_price: price} | _]}} ->
        {:ok, parse_decimal(price)}

      {:ok, %{list: []}} ->
        {:error, {:symbol_not_found, symbol}}

      error ->
        error
    end
  end

  defp fetch_perp_price(exchange, _symbol, _config) do
    {:error, {:unsupported_exchange, exchange}}
  end

  defp fetch_funding_rate(:binance, symbol, _config) do
    case Binance.MarketData.usdm_get_mark_price(%{symbol: symbol}) do
      {:ok, %{"lastFundingRate" => rate}} when is_binary(rate) ->
        {:ok, parse_decimal(rate)}

      {:ok, _} ->
        # If no funding rate available, default to 0
        {:ok, Decimal.new(0)}

      error ->
        error
    end
  end

  defp fetch_funding_rate(:bybit, symbol, _config) do
    case Bybit.MarketData.get_tickers(%{category: "linear", symbol: symbol}) do
      {:ok, %{list: [%{funding_rate: rate} | _]}} when is_binary(rate) ->
        {:ok, parse_decimal(rate)}

      {:ok, %{list: [_]}} ->
        # If no funding rate available, default to 0
        {:ok, Decimal.new(0)}

      {:ok, %{list: []}} ->
        {:error, {:symbol_not_found, symbol}}

      error ->
        error
    end
  end

  defp fetch_funding_rate(_exchange, _symbol, _config) do
    # Default to 0 if exchange not supported
    {:ok, Decimal.new(0)}
  end

  defp fetch_spot_price_for_base(exchange, base_asset, config) do
    # Construct the common spot symbol (most bases trade against USDT)
    symbol = base_asset <> "USDT"
    fetch_spot_price(exchange, symbol, config)
  end

  defp fetch_futures_contracts(:binance, base_asset, _config) do
    with {:ok, symbols} <- fetch_binance_exchange_info(),
         {:ok, filtered} <- filter_binance_delivery_futures(symbols, base_asset),
         {:ok, with_prices} <- fetch_binance_futures_prices(filtered) do
      if length(with_prices) > 0 do
        {:ok, with_prices}
      else
        {:error, {:no_futures_contracts_found, "No delivery futures found for #{base_asset}"}}
      end
    end
  end

  defp fetch_futures_contracts(:bybit, base_asset, _config) do
    # Bybit delivery futures support
    with {:ok, instruments} <- fetch_bybit_instruments(),
         {:ok, filtered} <- filter_bybit_delivery_futures(instruments, base_asset),
         {:ok, with_prices} <- fetch_bybit_futures_prices(filtered) do
      if length(with_prices) > 0 do
        {:ok, with_prices}
      else
        {:error, {:no_futures_contracts_found, "No delivery futures found for #{base_asset} on Bybit"}}
      end
    end
  end

  defp fetch_futures_contracts(exchange, _base_asset, _config) do
    {:error, {:unsupported_exchange, "Futures contracts not implemented for #{exchange}"}}
  end

  defp fetch_binance_exchange_info do
    case Binance.MarketData.usdm_get_exchange_info() do
      {:ok, %{"symbols" => symbols}} ->
        {:ok, symbols}

      {:error, reason} ->
        {:error, {:exchange_info_fetch_failed, reason}}

      _ ->
        {:error, {:unexpected_exchange_info_format, "Expected 'symbols' key in Binance exchange info"}}
    end
  end

  defp filter_binance_delivery_futures(symbols, base_asset) do
    filtered =
      Enum.filter(symbols, fn symbol ->
        Map.get(symbol, "baseAsset", "") == base_asset &&
          Map.get(symbol, "status", "") == "TRADING" &&
          Map.get(symbol, "contractType", "") in ["CURRENT_QUARTER", "NEXT_QUARTER"]
      end)

    {:ok, filtered}
  end

  defp fetch_binance_futures_prices(contracts) do
    with_prices =
      contracts
      |> Enum.map(fn contract ->
        symbol = Map.get(contract, "symbol", "")
        delivery_date = Map.get(contract, "deliveryDate", 0)

        # Extract expiry from symbol (e.g., "BTCUSDT_250926" -> "250926")
        expiry =
          case String.split(symbol, "_") do
            [_, date_part] -> date_part
            _ -> ""
          end

        # Fetch current price for this contract
        case Binance.MarketData.usdm_get_ticker_price(%{symbol: symbol}) do
          {:ok, %{"price" => price}} ->
            %{
              symbol: symbol,
              expiry: expiry,
              delivery_date: delivery_date,
              price: parse_decimal(price)
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, with_prices}
  end

  defp fetch_bybit_instruments do
    case Bybit.MarketData.get_instruments_info(%{category: "linear"}) do
      {:ok, %{list: instruments}} ->
        {:ok, instruments}

      {:error, reason} ->
        {:error, {:instruments_fetch_failed, reason}}

      _ ->
        {:error, {:unexpected_instruments_format, "Expected 'list' key in Bybit instruments response"}}
    end
  end

  defp filter_bybit_delivery_futures(instruments, base_asset) do
    # Bybit uses formats like "BTC-26DEC25" or "BTCUSDT-03OCT25"
    filtered =
      Enum.filter(instruments, fn inst ->
        symbol = Map.get(inst, "symbol", "")
        base_coin = Map.get(inst, "baseCoin", "")
        status = Map.get(inst, "status", "")
        contract_type = Map.get(inst, "contractType", "")
        # Check if it's a delivery future (not perpetual) for our base asset
        base_coin == base_asset &&
          status == "Trading" &&
          contract_type == "LinearFutures" &&
          (String.contains?(symbol, "-") and not String.ends_with?(symbol, "PERP"))
      end)

    {:ok, filtered}
  end

  defp fetch_bybit_futures_prices(contracts) do
    with_prices =
      contracts
      |> Enum.map(fn contract ->
        symbol = Map.get(contract, "symbol", "")
        delivery_time = Map.get(contract, "deliveryTime", "0")

        # Extract expiry from symbol (e.g., "BTC-26DEC25" -> "26-DEC-25")
        expiry =
          case String.split(symbol, "-") do
            [_, date_part] -> date_part
            _ -> ""
          end

        # Fetch current price for this contract
        case Bybit.MarketData.get_tickers(%{category: "linear", symbol: symbol}) do
          {:ok, %{list: [%{last_price: price} | _]}} ->
            %{
              symbol: symbol,
              expiry: expiry,
              delivery_date: String.to_integer(delivery_time),
              price: parse_decimal(price)
            }

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, with_prices}
  end

  # These internal functions were moved to the public section above as @doc false

  defp fetch_spreads_for_symbol(exchanges_with_configs, symbol) do
    exchanges_with_configs
    |> Task.async_stream(
      fn {exchange, config} ->
        {exchange, get_basis_spread(exchange, symbol, config)}
      end,
      max_concurrency: @max_api_concurrency,
      timeout: @api_timeout_ms,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {exchange, {:ok, spread}}}, acc ->
        Map.put(acc, exchange, spread)

      {:ok, {exchange, {:error, reason}}}, acc ->
        Logger.debug("Failed to fetch basis spread from #{exchange}: #{inspect(reason)}")
        acc

      {:exit, reason}, acc ->
        Logger.warning("Task failed when fetching basis spreads: #{inspect(reason)}")
        acc
    end)
  end

  # This function was moved to the public section above

  defp parse_decimal(nil), do: Decimal.new(0)
  defp parse_decimal(%Decimal{} = value), do: value
  defp parse_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp parse_decimal(value) when is_integer(value), do: Decimal.new(value)

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> Decimal.new(0)
    end
  end

  defp build_cache_key(type, exchange, identifier) do
    "#{@cache_prefix}:#{type}:#{exchange}:#{identifier}"
  end

  defp emit_telemetry(event, metadata, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:zen_cex, :basis, event],
      %{duration: duration},
      metadata
    )
  end
end
