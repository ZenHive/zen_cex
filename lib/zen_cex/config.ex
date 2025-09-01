defmodule ZenCex.Config do
  @moduledoc """
  Configuration helpers for ZenCex library.

  Provides a consistent interface for checking testnet/production
  environments across different exchanges.

  ## Environment Variables

  Each exchange uses its own environment variable for testnet detection:
  - `BINANCE_TESTNET=true` - Use Binance testnet
  - `KRAKEN_TESTNET=true` - Use Kraken testnet
  - `DERIBIT_TESTNET=true` - Use Deribit testnet

  ## Examples

      iex> ZenCex.Config.testnet?(:binance)
      false

      iex> System.put_env("BINANCE_TESTNET", "true")
      iex> ZenCex.Config.testnet?(:binance)
      true

      iex> ZenCex.Config.environment(:binance)
      :test
  """

  @type exchange :: :binance | :kraken | :deribit
  @type environment :: :test | :prod

  @doc """
  Checks if an exchange is configured to use testnet.

  Returns true if the exchange's testnet environment variable is set to "true".

  ## Examples

      iex> ZenCex.Config.testnet?(:binance)
      false

      iex> System.put_env("BINANCE_TESTNET", "true")
      iex> ZenCex.Config.testnet?(:binance)
      true
  """
  @spec testnet?(exchange()) :: boolean()
  def testnet?(:binance) do
    System.get_env("BINANCE_TESTNET") == "true"
  end

  def testnet?(:kraken) do
    System.get_env("KRAKEN_TESTNET") == "true"
  end

  def testnet?(:deribit) do
    System.get_env("DERIBIT_TESTNET") == "true"
  end

  @doc """
  Returns the current environment for an exchange.

  Returns `:test` if testnet is enabled, `:prod` otherwise.

  ## Examples

      iex> ZenCex.Config.environment(:binance)
      :prod

      iex> System.put_env("BINANCE_TESTNET", "true")
      iex> ZenCex.Config.environment(:binance)
      :test
  """
  @spec environment(exchange()) :: environment()
  def environment(exchange) do
    if testnet?(exchange), do: :test, else: :prod
  end

  @doc """
  Returns the base URL for an exchange based on its current environment.

  ## Examples

      iex> ZenCex.Config.base_url(:binance)
      "https://api.binance.com"

      iex> System.put_env("BINANCE_TESTNET", "true")
      iex> ZenCex.Config.base_url(:binance)
      "https://testnet.binance.vision"
  """
  @spec base_url(exchange()) :: String.t()
  def base_url(:binance) do
    if testnet?(:binance) do
      "https://testnet.binance.vision"
    else
      "https://api.binance.com"
    end
  end

  def base_url(:kraken) do
    # Kraken uses same base URL but different endpoints for testnet
    "https://api.kraken.com"
  end

  def base_url(:deribit) do
    if testnet?(:deribit) do
      "https://test.deribit.com"
    else
      "https://www.deribit.com"
    end
  end

  @doc """
  Returns API credentials for an exchange.

  Automatically selects testnet or production credentials based on environment.

  ## Examples

      iex> ZenCex.Config.credentials(:binance)
      %{api_key: nil, api_secret: nil}

      iex> System.put_env("BINANCE_API_KEY", "key123")
      iex> System.put_env("BINANCE_API_SECRET", "secret456")
      iex> ZenCex.Config.credentials(:binance)
      %{api_key: "key123", api_secret: "secret456"}
  """
  @spec credentials(exchange()) :: %{api_key: String.t() | nil, api_secret: String.t() | nil}
  def credentials(:binance) do
    if testnet?(:binance) do
      %{
        api_key: System.get_env("BINANCE_TESTNET_API_KEY"),
        api_secret: System.get_env("BINANCE_TESTNET_API_SECRET")
      }
    else
      %{
        api_key: System.get_env("BINANCE_API_KEY"),
        api_secret: System.get_env("BINANCE_API_SECRET")
      }
    end
  end

  def credentials(:kraken) do
    if testnet?(:kraken) do
      %{
        api_key: System.get_env("KRAKEN_TESTNET_API_KEY"),
        api_secret: System.get_env("KRAKEN_TESTNET_API_SECRET")
      }
    else
      %{
        api_key: System.get_env("KRAKEN_API_KEY"),
        api_secret: System.get_env("KRAKEN_API_SECRET")
      }
    end
  end

  def credentials(:deribit) do
    if testnet?(:deribit) do
      %{
        api_key: System.get_env("DERIBIT_TESTNET_CLIENT_ID"),
        api_secret: System.get_env("DERIBIT_TESTNET_CLIENT_SECRET")
      }
    else
      %{
        api_key: System.get_env("DERIBIT_CLIENT_ID"),
        api_secret: System.get_env("DERIBIT_CLIENT_SECRET")
      }
    end
  end

  @doc """
  Validates that required credentials are present for an exchange.

  Returns `:ok` if both api_key and api_secret are present,
  otherwise returns an error tuple.

  ## Examples

      iex> ZenCex.Config.validate_credentials(:binance)
      {:error, :missing_api_key}

      iex> System.put_env("BINANCE_API_KEY", "key123")
      iex> System.put_env("BINANCE_API_SECRET", "secret456")
      iex> ZenCex.Config.validate_credentials(:binance)
      :ok
  """
  @spec validate_credentials(exchange()) :: :ok | {:error, :missing_api_key | :missing_api_secret}
  def validate_credentials(exchange) do
    creds = credentials(exchange)

    cond do
      is_nil(creds.api_key) -> {:error, :missing_api_key}
      is_nil(creds.api_secret) -> {:error, :missing_api_secret}
      true -> :ok
    end
  end

  @doc """
  Clears cached environment values (useful for testing).

  This clears any cached values in :persistent_term storage.
  Should only be used in tests or when environment variables change.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    # Clear Binance cached environment
    :persistent_term.erase({ZenCex.Adapters.Binance.Endpoints, :current_env})
    :ok
  rescue
    # Key doesn't exist, that's fine
    ArgumentError -> :ok
  end
end
