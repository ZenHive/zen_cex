defmodule ZenCex.Examples.CredentialManagement do
  @moduledoc """
  Authentication and credential management patterns for ZenCex.

  **CRITICAL**: The ZenCex library NEVER reads environment variables for credentials.
  All credentials must be passed explicitly via the `auth_credentials` option.

  This module demonstrates:
  - Passing credentials explicitly (the PRIMARY pattern)
  - How calling code can read ENV and pass to library
  - Managing multiple accounts/subaccounts
  - Implementing credential rotation on errors

  ## Library Design Philosophy

  ZenCex is a LIBRARY, not an APPLICATION. It does not read environment variables
  directly because:
  - Multiple apps using zen_cex would have namespace collisions
  - Can't connect to testnet + prod simultaneously
  - Can't use different API keys for different subaccounts
  - Forces a specific config pattern (ENV vars)
  - Creates hidden global state
  - Makes testing complex

  Instead, calling code (your application, tests, scripts, IEx helpers) reads
  credentials from wherever they're stored (ENV, vault, database) and passes
  them explicitly to each API call.

  ## Usage

      # PRIMARY PATTERN: Pass credentials explicitly
      {:ok, balances} = ZenCex.Examples.CredentialManagement.use_explicit_credentials(
        "your_api_key",
        "your_api_secret"
      )

      # CALLING CODE reads ENV, then passes to library
      {:ok, balances} = ZenCex.Examples.CredentialManagement.use_credentials_from_env()

      # Multi-account management
      accounts = [
        %{api_key: "account1_key", api_secret: "account1_secret"},
        %{api_key: "account2_key", api_secret: "account2_secret"}
      ]
      {:ok, results} = ZenCex.Examples.CredentialManagement.manage_multiple_accounts(accounts)

      # Credential rotation on auth errors
      {:ok, order} = ZenCex.Examples.CredentialManagement.rotate_credentials_on_error(
        %{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: "0.001"},
        &get_credentials_from_vault/0
      )

  ## Security Best Practices

  ⚠️ **NEVER commit API keys to version control!**

  - Store API keys in environment variables or secure vault systems
  - Use read-only API keys when write access is not needed
  - Restrict API key permissions to only required operations
  - Enable IP whitelisting on exchange APIs when possible
  - Rotate credentials regularly
  - Monitor API key usage for suspicious activity
  - Use testnet credentials for development and testing
  """

  alias ZenCex.Adapters.Binance.Spot

  @doc """
  Pass credentials explicitly to API calls (PRIMARY PATTERN).

  This is the recommended approach for library usage. Credentials are passed
  directly via the `auth_credentials` option, which can be a keyword list or map.

  The library accepts credentials ONLY through this option - it never reads
  environment variables.

  ## Examples

      # Using keyword list format
      {:ok, balances} = ZenCex.Examples.CredentialManagement.use_explicit_credentials(
        "your_api_key",
        "your_api_secret"
      )

      # The function passes credentials like this:
      Spot.get_balances(%{}, [
        auth_credentials: %{
          api_key: "your_api_key",
          api_secret: "your_api_secret",
          testnet: true  # Optional, defaults to false
        }
      ])

  ## Parameters

  - `api_key` - Binance API key
  - `api_secret` - Binance API secret
  - `opts` - Additional options (keyword list or map)
    - `:testnet` - Use testnet (default: `true` for safety)

  ## Returns

  - `{:ok, balances}` - List of account balances with atom keys
  - `{:error, reason}` - Failed to fetch (invalid credentials, API error, etc.)
  """
  @spec use_explicit_credentials(String.t(), String.t(), keyword() | map()) ::
          {:ok, list(map())} | {:error, term()}
  def use_explicit_credentials(api_key, api_secret, opts \\ []) do
    # Extract testnet flag from opts (default to true for safety)
    testnet = Keyword.get(opts, :testnet, true)

    # Build auth_credentials - can use keyword list or map format
    # Both are equivalent - the library accepts either
    opts_with_auth = [
      auth_credentials: %{
        api_key: api_key,
        api_secret: api_secret,
        testnet: testnet
      }
    ]

    # Call API with explicit credentials
    Spot.get_balances(%{}, opts_with_auth)
  end

  @doc """
  Calling code reads environment variables, then passes to library.

  **IMPORTANT**: This demonstrates that reading ENV is the CALLING CODE's
  responsibility, not the library's. The library only accepts credentials
  via the `auth_credentials` option.

  This pattern is useful for:
  - Simple applications with single account
  - Development and testing
  - When ENV vars are your primary credential storage

  ## Examples

      # In your application code:
      api_key = System.get_env("BINANCE_TESTNET_API_KEY")
      api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

      {:ok, balances} = Spot.get_balances(%{}, [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: true
        }
      ])

  ## Returns

  - `{:ok, balances}` - Account balances
  - `{:error, reason}` - Failed (missing ENV vars, invalid credentials, API error)
  """
  @spec use_credentials_from_env() :: {:ok, list(map())} | {:error, term()}
  def use_credentials_from_env do
    # CALLING CODE reads environment variables
    api_key = System.get_env("BINANCE_TESTNET_API_KEY")
    api_secret = System.get_env("BINANCE_TESTNET_API_SECRET")

    # Validate credentials exist
    if is_nil(api_key) or is_nil(api_secret) do
      {:error, :missing_credentials}
    else
      # CALLING CODE passes credentials to library
      opts = [
        auth_credentials: %{
          api_key: api_key,
          api_secret: api_secret,
          testnet: true
        }
      ]

      Spot.get_balances(%{}, opts)
    end
  end

  @doc """
  Manage multiple accounts by passing different credentials to each request.

  This demonstrates one of the key benefits of explicit credential passing:
  you can easily manage multiple accounts, subaccounts, or API keys without
  any global configuration.

  Useful for:
  - Multi-account portfolio management
  - Subaccount risk isolation
  - Aggregating balances across accounts
  - Testing with different API keys

  ## Examples

      accounts = [
        %{api_key: "account1_key", api_secret: "account1_secret"},
        %{api_key: "account2_key", api_secret: "account2_secret"}
      ]
      {:ok, results} = ZenCex.Examples.CredentialManagement.manage_multiple_accounts(accounts)

      # Results contain balances for each account
      Enum.each(results, fn {creds, balances} ->
        IO.inspect(creds.api_key, label: "Account")
        IO.inspect(balances, label: "Balances")
      end)

  ## Parameters

  - `account_credentials_list` - List of credential maps
    - Each map must have `:api_key` and `:api_secret`
    - Optional `:testnet` key (defaults to `true`)

  ## Returns

  - `{:ok, [{credentials, balances}, ...]}` - List of {credentials, balances} tuples
  - `{:error, {credentials, reason}}` - First account that failed with its credentials
  """
  @spec manage_multiple_accounts(list(map())) ::
          {:ok, list({map(), list(map())})} | {:error, {map(), term()}}
  def manage_multiple_accounts(account_credentials_list) do
    results =
      Enum.reduce_while(account_credentials_list, [], fn creds, acc ->
        # Add testnet flag if not present (default to true for safety)
        creds_with_testnet = Map.put_new(creds, :testnet, true)

        # Pass credentials explicitly for this account
        opts = [auth_credentials: creds_with_testnet]

        case Spot.get_balances(%{}, opts) do
          {:ok, balances} ->
            {:cont, [{creds_with_testnet, balances} | acc]}

          {:error, reason} ->
            {:halt, {:error, {creds_with_testnet, reason}}}
        end
      end)

    case results do
      {:error, _} = error -> error
      list -> {:ok, Enum.reverse(list)}
    end
  end

  @doc """
  Implement credential rotation with automatic retry on authorization errors.

  This pattern demonstrates:
  - Detecting authorization failures
  - Triggering credential rotation
  - Retrying with fresh credentials
  - Integration with credential management systems (vaults, databases, etc.)

  The `get_credentials_fn` should return a map with `:api_key`, `:api_secret`,
  and optionally `:testnet` keys. On auth errors, the function is called again
  to fetch fresh credentials.

  ## Examples

      # Define a function that fetches credentials from your vault
      get_creds = fn ->
        %{
          api_key: fetch_from_vault("binance_api_key"),
          api_secret: fetch_from_vault("binance_api_secret"),
          testnet: true
        }
      end

      # Place order with automatic credential rotation on auth errors
      {:ok, order} = ZenCex.Examples.CredentialManagement.rotate_credentials_on_error(
        %{symbol: "BTCUSDT", side: "BUY", type: "MARKET", quantity: "0.001"},
        get_creds
      )

  ## Parameters

  - `params` - Order parameters (symbol, side, type, quantity, etc.)
  - `get_credentials_fn` - Zero-arity function that returns credentials map

  ## Returns

  - `{:ok, order}` - Order placed successfully (possibly after rotation)
  - `{:error, reason}` - Failed even after rotation attempt
  """
  @spec rotate_credentials_on_error(map(), (-> map())) ::
          {:ok, map()} | {:error, term()}
  def rotate_credentials_on_error(params, get_credentials_fn) do
    # Get initial credentials from the provided function
    creds = get_credentials_fn.()
    opts = [auth_credentials: creds]

    case Spot.place_order(params, opts) do
      # Success - return result
      {:ok, _} = success ->
        success

      # Authorization error - rotate and retry
      {:error, reason} when reason in [:unauthorized, :invalid_api_key] ->
        # Get fresh credentials (simulates rotation)
        new_creds = get_credentials_fn.()
        new_opts = [auth_credentials: new_creds]

        # Retry with new credentials
        Spot.place_order(params, new_opts)

      # Other errors - return as-is (don't retry)
      {:error, _} = error ->
        error
    end
  end
end
