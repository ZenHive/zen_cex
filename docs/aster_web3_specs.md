# Aster V3 Web3 Integration Specification

This document contains numbered tasks for implementing Web3 authentication and Aster V3 API support in ZenCex.

## Status: PENDING

---

## 🔄 CONTINUATION PROMPT (Update at end of each session)

**Last Updated**: 2025-10-06 (Session 0)

**For next session, start with**:
```
Continue implementing Web3 support from docs/aster_web3_specs.md.

Current status: Not started. Specification created.
Next: Task 0 (Research and dependency selection).

Key points:
- Using Option A: ethers library (~0.6.7) for full Web3 support
- Web3 auth extends existing auth behavior pattern
- Optional dependencies (doesn't affect CEX-only users)
- Aster V3 API: ~6 endpoints with ECDSA signature authentication
- Foundation → Aster V3 → Testing → Generalization

Begin: "Starting Web3 integration from docs/aster_web3_specs.md - Task 0..."
```

**What to update at end of each session**:
1. Update "Last Updated" date and session number
2. Update "Current status" with completed tasks
3. Update "Next" with the next task number and name
4. If all tasks done, change Status to "COMPLETED"

---

## Overview

**Feature**: Web3 Authentication Support
**Primary Use Case**: Aster V3 API (DEX with wallet-based auth)
**Authentication Method**: ECDSA signatures (Keccak-256 + SECP256K1)

**Dependency Strategy**: **Option A - Full Web3 Library** ✅
- Library: `ethers` (~0.6.7) from ExWeb3
- Comprehensive Web3 toolkit with ABI encoding, wallet management, signing
- Battle-tested, maintained, proper Ethereum standards compliance
- ~15 additional dependencies (acceptable for full Web3 support)

**Architecture Principles**:
- **Optional**: Web3 features don't affect CEX-only users
- **Explicit credentials**: Wallet address + private key via `auth_credentials`
- **No global state**: Follows zen_cex library design (no Mix config, no ENV reading)
- **Library pattern**: NEVER reads ENV - calling code retrieves credentials and passes explicitly
- **Reusable pattern**: Foundation for future DEX integrations
- **Isolated**: Web3 auth is separate from HMAC auth (no mixing)

**CRITICAL: zen_cex is a LIBRARY, not an APPLICATION**
- ❌ Library code NEVER calls `System.get_env()` for credentials
- ✅ Credentials passed explicitly via `auth_credentials: %{wallet_address: ..., private_key: ...}`
- ✅ Calling application retrieves credentials (vault, database, user input)
- ✅ Enables multi-instance, multi-account, and flexible credential storage
- ✅ Tests can use ENV (test files only), but must pass explicitly to library

**Scope**:
- Aster V3 API (~6 endpoints for wallet-based trading)
- Generic Web3 authentication module (reusable for other DEXs)
- ABI encoding for signature payloads
- ECDSA signature generation (Keccak-256 hash + SECP256K1)
- Security best practices (private key handling)

---

## Task 0: Research and Dependency Analysis

[D:2/B:8 → Priority:4.0] 🎯

**Purpose**: Validate ethers library compatibility and understand Aster V3 requirements

**Actions**:

### 1. Explore ethers Library

Use Tidewave to test the ethers library:

```elixir
# Add to mix.exs temporarily for testing:
# {:ethers, "~> 0.6.7"}

# Then in Tidewave:
alias Ethers.Utils
alias Ethers.Signer

# Test wallet creation
{:ok, wallet} = Ethers.Signer.LocalSigner.new("0x<test_private_key>")

# Test address derivation
address = wallet.address

# Test Keccak hashing
data = "test data"
hash = Utils.keccak256(data)

# Test ABI encoding
Ethers.ABI.encode_function_call(
  %{function: "transfer", inputs: ["address", "uint256"]},
  ["0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", 1000]
)

# Test ECDSA signing
message_hash = Utils.keccak256("message")
{:ok, signature} = Ethers.Signer.sign_hash(wallet, message_hash)
```

### 2. Verify Aster V3 Signature Process

Test the complete Aster V3 signature generation:

```elixir
# Based on Aster V3 docs:
# 1. Convert params to JSON string
# 2. ABI encode: [json_string, user_address, signer_address, nonce]
# 3. Keccak hash the encoded data
# 4. ECDSA sign the hash

params = %{"symbol" => "BTCUSDT", "side" => "BUY"}
json_string = Jason.encode!(params)

user_address = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
signer_address = user_address
nonce = System.system_time(:microsecond)

# ABI encode parameters
encoded = Ethers.ABI.encode(
  ["string", "address", "address", "uint256"],
  [json_string, user_address, signer_address, nonce]
)

# Keccak hash
hash = Ethers.Utils.keccak256(encoded)

# Sign with private key
{:ok, wallet} = Ethers.Signer.LocalSigner.new("0x<private_key>")
{:ok, signature} = Ethers.Signer.sign_hash(wallet, hash)

IO.inspect(%{
  user: user_address,
  signer: signer_address,
  nonce: nonce,
  signature: signature
})
```

### 3. Test Against Aster V3 Testnet

If testnet available, verify signature with real API:

```elixir
# Make authenticated request to Aster V3
alias ZenCex.Core.HTTP

request = Req.new(
  url: "https://fapi.asterdex.com/fapi/v3/balance",
  method: :get,
  headers: [
    {"user", user_address},
    {"signer", signer_address},
    {"nonce", to_string(nonce)},
    {"signature", signature}
  ]
)

{:ok, response} = Req.request(request)
IO.inspect(response.body, label: "Aster V3 Response")
```

### 4. Document Findings

Create verification report:
- ✅/❌ ethers library works for signature generation
- ✅/❌ ABI encoding matches Aster V3 requirements
- ✅/❌ Signature format is accepted by Aster V3 API
- Example working code snippets
- Any gotchas or edge cases discovered

**Deliverables**:
- Confirmed ethers library compatibility
- Working Aster V3 signature generation code
- Understanding of any Aster-specific quirks
- Decision on whether to proceed with Option A

---

## Task 1: Add ethers Dependency and Foundation

[D:2/B:7 → Priority:3.5] 🎯

**Purpose**: Add ethers library and create base Web3 infrastructure

### 1.1: Update mix.exs

Add ethers as optional dependency:

```elixir
defp deps do
  [
    # ... existing deps ...

    # Web3 support (optional - only needed for DEX integrations)
    {:ethers, "~> 0.6.7", optional: true},

    # ... rest of deps ...
  ]
end
```

Update package description:
```elixir
defp description do
  """
  A comprehensive Elixir library for cryptocurrency exchange integrations with REST and WebSocket support.
  Provides unified API access to Binance, Bybit, and DEX platforms (Aster) with built-in rate limiting,
  clock sync, safety features, and Web3 authentication support.
  """
end
```

### 1.2: Update ZenCex.Behaviors.Auth

Add Web3 authentication method to the behavior:

```elixir
# In lib/zen_cex/behaviors/auth.ex

@doc """
Returns the authentication method used by this exchange.

## Returns
  - `:hmac_sha256` - For HMAC-SHA256 (Binance, Aster Standard API)
  - `:hmac_sha512` - For HMAC-SHA512 (Kraken)
  - `:oauth2` - For OAuth2 (Deribit)
  - `:api_key` - For simple API key auth
  - `:web3_ecdsa` - For Web3 wallet signatures (Aster V3, DEXs)
"""
@callback auth_method() ::
  :hmac_sha256 | :hmac_sha512 | :oauth2 | :api_key | :web3_ecdsa
```

### 1.3: Create Web3 Module Structure

Create base directory and modules:

```
lib/zen_cex/adapters/web3/
├── web3.ex                  # Main module with documentation
├── auth.ex                  # Core Web3 authentication
├── signer.ex                # ECDSA signing with ethers
├── abi_encoder.ex           # ABI encoding helpers
├── credential_validator.ex  # Wallet address/key validation
└── types.ex                 # Type definitions
```

**File**: `lib/zen_cex/adapters/web3/web3.ex`

```elixir
defmodule ZenCex.Adapters.Web3 do
  @moduledoc """
  Web3 authentication support for DEX integrations.

  This module provides Ethereum-compatible Web3 authentication using
  ECDSA signatures (Keccak-256 + SECP256K1) for decentralized exchanges
  that require wallet-based authentication instead of traditional API keys.

  ## Authentication Flow

  1. **ABI Encode**: Encode request parameters using Ethereum ABI standards
  2. **Keccak Hash**: Generate Keccak-256 hash of encoded data
  3. **ECDSA Sign**: Sign hash with private key using SECP256K1 curve
  4. **Add Headers**: Attach wallet address, nonce, and signature to request

  ## Supported DEX Platforms

  - Aster V3 API (perpetual futures with Web3 auth)

  ## Dependencies

  Requires the optional `ethers` dependency:

      # In mix.exs
      {:ethers, "~> 0.6.7", optional: true}

  ## Security Considerations

  - **Never log private keys** - sanitized in all logging/debug output
  - **Secure storage** - use environment variables or secure vaults
  - **Testnet first** - always test with testnet credentials
  - **Minimal funds** - keep minimal funds in wallets used for API access

  ## Usage Example

      # Load credentials securely
      wallet_address = System.get_env("WEB3_WALLET_ADDRESS")
      private_key = System.get_env("WEB3_PRIVATE_KEY")

      # Make authenticated request
      AsterV3.Futures.get_balance(%{},
        auth_credentials: %{
          wallet_address: wallet_address,
          private_key: private_key,
          testnet: true
        }
      )
  """

  @doc """
  Check if Web3 support is available (ethers dependency installed).
  """
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Ethers)
  end

  @doc """
  Returns error message if Web3 support is not available.
  """
  @spec require_web3!() :: :ok | no_return()
  def require_web3! do
    unless available?() do
      raise """
      Web3 support requires the ethers library.

      Add to your mix.exs:
        {:ethers, "~> 0.6.7"}

      Then run:
        mix deps.get
      """
    end

    :ok
  end
end
```

**Verification**:
- `mix deps.get` succeeds
- `mix compile` succeeds (with optional dep warning if not installed)
- Modules are accessible in IEx
- `Web3.available?()` returns true if ethers installed

---

## Task 2: Implement Core Web3 Authentication

[D:4/B:8 → Priority:2.0] 🚀

**Purpose**: Create reusable Web3 authentication module

### 2.1: Types Module

**File**: `lib/zen_cex/adapters/web3/types.ex`

```elixir
defmodule ZenCex.Adapters.Web3.Types do
  @moduledoc """
  Type definitions for Web3 authentication.
  """

  @typedoc "Ethereum wallet address (0x-prefixed hex string)"
  @type address :: String.t()

  @typedoc "Private key (0x-prefixed hex string)"
  @type private_key :: String.t()

  @typedoc "ECDSA signature (0x-prefixed hex string)"
  @type signature :: String.t()

  @typedoc "Web3 credentials for authentication"
  @type credentials :: %{
    wallet_address: address(),
    private_key: private_key(),
    optional(:testnet) => boolean()
  }

  @typedoc "Signature payload data"
  @type payload :: %{
    data: binary(),
    hash: binary(),
    types: [String.t()],
    values: [term()]
  }
end
```

### 2.2: Credential Validator

**File**: `lib/zen_cex/adapters/web3/credential_validator.ex`

```elixir
defmodule ZenCex.Adapters.Web3.CredentialValidator do
  @moduledoc """
  Validates Web3 credentials (wallet addresses and private keys).
  """

  alias ZenCex.Adapters.Web3.Types

  @doc """
  Validates Web3 credentials.

  Checks:
  - Wallet address is valid Ethereum address (0x + 40 hex chars)
  - Private key is valid (0x + 64 hex chars)
  - Address matches private key (optional verification)

  ## Examples

      validate_credentials(%{
        wallet_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
        private_key: "0x<64_hex_chars>"
      })
      #=> :ok
  """
  @spec validate_credentials(Types.credentials()) ::
    :ok | {:error, term()}
  def validate_credentials(credentials) do
    with :ok <- validate_wallet_address(credentials.wallet_address),
         :ok <- validate_private_key(credentials.private_key),
         :ok <- validate_address_match(credentials) do
      :ok
    end
  end

  @doc """
  Validates Ethereum address format.

  Accepts:
  - 0x-prefixed hex string with 40 hex characters
  - Mixed case (checksummed) addresses
  """
  @spec validate_wallet_address(Types.address()) ::
    :ok | {:error, term()}
  def validate_wallet_address(address) when is_binary(address) do
    case Regex.match?(~r/^0x[a-fA-F0-9]{40}$/, address) do
      true -> :ok
      false -> {:error, {:invalid_address, "Expected 0x + 40 hex chars"}}
    end
  end

  @doc """
  Validates private key format.

  Expects 0x-prefixed 64 hex character string.
  """
  @spec validate_private_key(Types.private_key()) ::
    :ok | {:error, term()}
  def validate_private_key(key) when is_binary(key) do
    case Regex.match?(~r/^0x[a-fA-F0-9]{64}$/, key) do
      true -> :ok
      false -> {:error, {:invalid_private_key, "Expected 0x + 64 hex chars"}}
    end
  end

  @doc """
  Verifies that wallet address matches the private key.

  Uses ethers to derive address from private key and compare.
  """
  @spec validate_address_match(Types.credentials()) ::
    :ok | {:error, term()}
  def validate_address_match(%{wallet_address: address, private_key: key}) do
    ZenCex.Adapters.Web3.require_web3!()

    case Ethers.Signer.LocalSigner.new(key) do
      {:ok, wallet} ->
        derived_address = String.downcase(wallet.address)
        expected_address = String.downcase(address)

        if derived_address == expected_address do
          :ok
        else
          {:error, {:address_mismatch,
            "Address #{address} doesn't match private key (derives to #{wallet.address})"}}
        end

      {:error, reason} ->
        {:error, {:invalid_private_key, reason}}
    end
  end

  @doc """
  Sanitizes credentials for logging (removes private key).
  """
  @spec sanitize_for_logging(Types.credentials()) :: map()
  def sanitize_for_logging(credentials) do
    credentials
    |> Map.delete(:private_key)
    |> Map.put(:private_key, "<REDACTED>")
  end
end
```

### 2.3: ABI Encoder

**File**: `lib/zen_cex/adapters/web3/abi_encoder.ex`

```elixir
defmodule ZenCex.Adapters.Web3.ABIEncoder do
  @moduledoc """
  ABI encoding utilities for Web3 authentication.

  Uses ethers library for Ethereum ABI standard encoding.
  """

  alias ZenCex.Adapters.Web3.Types

  require Logger

  @doc """
  Encodes parameters using Ethereum ABI standards.

  ## Parameters

    * `types` - List of Solidity types (e.g., ["string", "address", "uint256"])
    * `values` - List of values matching the types

  ## Examples

      encode(
        ["string", "address", "uint256"],
        ["hello", "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", 12345]
      )
      #=> {:ok, <<binary_encoded_data>>}
  """
  @spec encode([String.t()], [term()]) :: {:ok, binary()} | {:error, term()}
  def encode(types, values) when is_list(types) and is_list(values) do
    ZenCex.Adapters.Web3.require_web3!()

    if length(types) != length(values) do
      {:error, {:abi_encoding_error, "Types and values length mismatch"}}
    else
      try do
        encoded = Ethers.ABI.encode(types, values)
        {:ok, encoded}
      rescue
        error ->
          Logger.error("ABI encoding failed: #{inspect(error)}")
          {:error, {:abi_encoding_error, Exception.message(error)}}
      end
    end
  end

  @doc """
  Encodes parameters for Aster V3 signature payload.

  Standard Aster V3 format:
  - types: ["string", "address", "address", "uint256"]
  - values: [json_params, user_address, signer_address, nonce]
  """
  @spec encode_aster_v3_payload(
    json_string :: String.t(),
    user_address :: Types.address(),
    signer_address :: Types.address(),
    nonce :: non_neg_integer()
  ) :: {:ok, binary()} | {:error, term()}
  def encode_aster_v3_payload(json_string, user_address, signer_address, nonce) do
    encode(
      ["string", "address", "address", "uint256"],
      [json_string, user_address, signer_address, nonce]
    )
  end
end
```

### 2.4: Web3 Signer

**File**: `lib/zen_cex/adapters/web3/signer.ex`

```elixir
defmodule ZenCex.Adapters.Web3.Signer do
  @moduledoc """
  ECDSA signature generation for Web3 authentication.

  Uses ethers library for Keccak-256 hashing and SECP256K1 signing.
  """

  alias ZenCex.Adapters.Web3.Types

  require Logger

  @doc """
  Generates ECDSA signature for given data.

  Process:
  1. Keccak-256 hash the data
  2. Sign hash with private key (SECP256K1)
  3. Return signature as 0x-prefixed hex string

  ## Examples

      sign("some data", "0x<private_key>")
      #=> {:ok, "0x<signature>"}
  """
  @spec sign(binary(), Types.private_key()) ::
    {:ok, Types.signature()} | {:error, term()}
  def sign(data, private_key) when is_binary(data) and is_binary(private_key) do
    ZenCex.Adapters.Web3.require_web3!()

    with {:ok, wallet} <- create_wallet(private_key),
         {:ok, hash} <- hash_data(data),
         {:ok, signature} <- sign_hash(wallet, hash) do
      {:ok, signature}
    end
  end

  @doc """
  Creates wallet from private key.
  """
  @spec create_wallet(Types.private_key()) ::
    {:ok, Ethers.Signer.LocalSigner.t()} | {:error, term()}
  defp create_wallet(private_key) do
    case Ethers.Signer.LocalSigner.new(private_key) do
      {:ok, wallet} ->
        {:ok, wallet}

      {:error, reason} ->
        Logger.error("Failed to create wallet: #{inspect(reason)}")
        {:error, {:wallet_creation_failed, reason}}
    end
  end

  @doc """
  Generates Keccak-256 hash of data.
  """
  @spec hash_data(binary()) :: {:ok, binary()} | {:error, term()}
  defp hash_data(data) do
    try do
      hash = Ethers.Utils.keccak256(data)
      {:ok, hash}
    rescue
      error ->
        Logger.error("Keccak hashing failed: #{inspect(error)}")
        {:error, {:hashing_failed, Exception.message(error)}}
    end
  end

  @doc """
  Signs hash with wallet's private key.
  """
  @spec sign_hash(Ethers.Signer.LocalSigner.t(), binary()) ::
    {:ok, Types.signature()} | {:error, term()}
  defp sign_hash(wallet, hash) do
    case Ethers.Signer.sign_hash(wallet, hash) do
      {:ok, signature} ->
        {:ok, signature}

      {:error, reason} ->
        Logger.error("Signature generation failed: #{inspect(reason)}")
        {:error, {:signing_failed, reason}}
    end
  end
end
```

**Verification**:
- All modules compile without errors
- Type specs pass dialyzer
- Can create wallet from private key
- Can generate valid ECDSA signatures
- ABI encoding works for standard types

---

## Task 3: Implement Web3 Auth Module

[D:3/B:7 → Priority:2.33] 🚀

**Purpose**: Create main Web3 Auth module that integrates with Core.HTTP

**File**: `lib/zen_cex/adapters/web3/auth.ex`

```elixir
defmodule ZenCex.Adapters.Web3.Auth do
  @moduledoc """
  Web3 authentication implementation for DEX integrations.

  Implements the `ZenCex.Behaviors.Auth` behavior for Web3-based
  authentication using ECDSA signatures.

  ## Authentication Flow

  1. Extract request parameters
  2. Generate nonce (timestamp in microseconds)
  3. ABI encode payload (params + addresses + nonce)
  4. Keccak-256 hash the encoded data
  5. ECDSA sign the hash
  6. Add authentication headers to request

  ## Usage

  This module is typically used indirectly through DEX adapters
  (like Aster V3), but can be used directly:

      request = Req.new(url: "https://api.dex.com/endpoint")

      credentials = %{
        wallet_address: "0x...",
        private_key: "0x...",
        payload_builder: &build_custom_payload/3
      }

      authenticated_request = Web3.Auth.sign_request(
        request,
        credentials
      )
  """

  @behaviour ZenCex.Behaviors.Auth

  alias ZenCex.Adapters.Web3.{
    ABIEncoder,
    Signer,
    CredentialValidator,
    Types
  }

  require Logger

  @impl true
  def auth_method, do: :web3_ecdsa

  @impl true
  def sign_request(request, credentials) when is_map(credentials) do
    with :ok <- CredentialValidator.validate_credentials(credentials),
         {:ok, auth_data} <- generate_auth_data(request, credentials),
         authenticated <- add_auth_headers(request, auth_data) do
      authenticated
    else
      {:error, reason} ->
        Logger.error("Web3 auth failed: #{inspect(reason)}")
        # Return original request on error (will fail at API level)
        request
    end
  end

  @impl true
  def validate_credentials(credentials \\ %{}) when is_map(credentials) do
    CredentialValidator.validate_credentials(credentials)
  end

  @doc """
  Generates authentication data (signature, nonce, etc.).

  Delegates to the payload builder function if provided,
  otherwise uses standard ABI encoding.
  """
  @spec generate_auth_data(Req.Request.t(), Types.credentials()) ::
    {:ok, map()} | {:error, term()}
  def generate_auth_data(request, credentials) do
    nonce = generate_nonce()
    params = extract_params(request)

    payload_builder = Map.get(credentials, :payload_builder, &default_payload_builder/3)

    with {:ok, payload} <- payload_builder.(params, credentials, nonce),
         {:ok, signature} <- Signer.sign(payload, credentials.private_key) do
      {:ok, %{
        user: credentials.wallet_address,
        signer: credentials.wallet_address,
        nonce: nonce,
        signature: signature
      }}
    end
  end

  @doc """
  Default payload builder using standard ABI encoding.

  Can be overridden by passing custom :payload_builder in credentials.
  """
  @spec default_payload_builder(map(), Types.credentials(), non_neg_integer()) ::
    {:ok, binary()} | {:error, term()}
  def default_payload_builder(params, credentials, nonce) do
    json_string = Jason.encode!(params)

    ABIEncoder.encode_aster_v3_payload(
      json_string,
      credentials.wallet_address,
      credentials.wallet_address,
      nonce
    )
  end

  @doc """
  Generates nonce (current timestamp in microseconds).
  """
  @spec generate_nonce() :: non_neg_integer()
  def generate_nonce do
    System.system_time(:microsecond)
  end

  @doc """
  Extracts parameters from request.
  """
  @spec extract_params(Req.Request.t()) :: map()
  def extract_params(request) do
    # Merge query params and body params
    query_params = request.options[:params] || %{}
    body_params = request.options[:json] || %{}

    Map.merge(query_params, body_params)
  end

  @doc """
  Adds Web3 authentication headers to request.
  """
  @spec add_auth_headers(Req.Request.t(), map()) :: Req.Request.t()
  def add_auth_headers(request, auth_data) do
    request
    |> Req.Request.put_header("user", auth_data.user)
    |> Req.Request.put_header("signer", auth_data.signer)
    |> Req.Request.put_header("nonce", to_string(auth_data.nonce))
    |> Req.Request.put_header("signature", auth_data.signature)
  end
end
```

**Verification**:
- Implements `ZenCex.Behaviors.Auth` correctly
- Generates valid signatures
- Adds proper headers to requests
- Handles errors gracefully
- Private keys never logged

---

## Task 4: Create Aster V3 Adapter

[D:4/B:7 → Priority:1.75] 🚀

**Purpose**: Implement Aster V3 API support using Web3 authentication

### 4.1: Module Structure

Create Aster V3 modules:

```
lib/zen_cex/adapters/aster_v3/
├── aster_v3.ex          # Main module (constants, URLs)
├── auth.ex              # Aster-specific Web3 auth
├── endpoints.ex         # V3 endpoint definitions
├── parser.ex            # Response parsing
├── futures.ex           # Main trading interface
└── rate_limiter.ex      # Rate limiting
```

### 4.2: Main Module

**File**: `lib/zen_cex/adapters/aster_v3/aster_v3.ex`

```elixir
defmodule ZenCex.Adapters.AsterV3 do
  @moduledoc """
  Aster V3 API adapter with Web3 authentication.

  The V3 API uses Ethereum wallet signatures instead of API key/secret.
  This is suitable for DeFi wallets and decentralized trading.

  ## Base URLs

  - REST: https://fapi.asterdex.com
  - WebSocket: wss://fstream.asterdex.com (same as Standard API)

  ## Authentication

  Uses Web3 ECDSA signatures with the following process:
  1. ABI encode request params + wallet addresses + nonce
  2. Keccak-256 hash the encoded data
  3. ECDSA sign the hash with private key
  4. Send signature in request headers

  ## Credentials Format

      %{
        wallet_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
        private_key: "0x<64_hex_chars>",
        testnet: true  # optional
      }

  ## Example Usage

      alias ZenCex.Adapters.AsterV3.Futures

      # Load from environment (production)
      credentials = %{
        wallet_address: System.get_env("WEB3_WALLET_ADDRESS"),
        private_key: System.get_env("WEB3_PRIVATE_KEY"),
        testnet: false
      }

      # Get account balance
      {:ok, balance} = Futures.get_balance(%{},
        auth_credentials: credentials
      )

  ## Security Notes

  - Never commit private keys to version control
  - Use environment variables or secure vaults
  - Test with testnet first
  - Keep minimal funds in API wallets
  - Monitor for unauthorized transactions

  ## Differences from Standard API

  | Aspect | Standard API | V3 API |
  |--------|-------------|--------|
  | Auth | HMAC-SHA256 | Web3 ECDSA |
  | Credentials | API Key + Secret | Wallet + Private Key |
  | Endpoints | ~40 endpoints | ~6 endpoints |
  | Use Case | Bots, servers | Wallets, DeFi |
  """

  @base_url "https://fapi.asterdex.com"
  @ws_url "wss://fstream.asterdex.com"

  @doc "Returns the base REST URL for Aster V3 API"
  @spec base_url() :: String.t()
  def base_url, do: @base_url

  @doc "Returns the WebSocket URL for Aster V3 API"
  @spec websocket_url() :: String.t()
  def websocket_url, do: @ws_url

  @doc "Check if Web3 support is available"
  @spec web3_available?() :: boolean()
  def web3_available? do
    ZenCex.Adapters.Web3.available?()
  end
end
```

### 4.3: Aster V3 Authentication

**File**: `lib/zen_cex/adapters/aster_v3/auth.ex`

```elixir
defmodule ZenCex.Adapters.AsterV3.Auth do
  @moduledoc """
  Aster V3-specific Web3 authentication.

  Delegates to ZenCex.Adapters.Web3.Auth with Aster-specific
  payload building.
  """

  @behaviour ZenCex.Behaviors.Auth

  alias ZenCex.Adapters.Web3
  alias ZenCex.Adapters.Web3.ABIEncoder

  @impl true
  def auth_method, do: :web3_ecdsa

  @impl true
  def sign_request(request, credentials) when is_map(credentials) do
    # Add Aster V3-specific payload builder
    credentials_with_builder = Map.put(
      credentials,
      :payload_builder,
      &build_aster_v3_payload/3
    )

    Web3.Auth.sign_request(request, credentials_with_builder)
  end

  @impl true
  def validate_credentials(credentials \\ %{}) do
    Web3.Auth.validate_credentials(credentials)
  end

  @doc """
  Builds Aster V3-specific signature payload.

  Format: ABI encode [json_string, user, signer, nonce]
  Types: ["string", "address", "address", "uint256"]
  """
  @spec build_aster_v3_payload(map(), map(), non_neg_integer()) ::
    {:ok, binary()} | {:error, term()}
  def build_aster_v3_payload(params, credentials, nonce) do
    # Sort params by key for consistency
    sorted_params = Enum.sort(params)
    json_string = Jason.encode!(sorted_params)

    ABIEncoder.encode_aster_v3_payload(
      json_string,
      credentials.wallet_address,
      credentials.wallet_address,
      nonce
    )
  end
end
```

### 4.4: Endpoints Module

**File**: `lib/zen_cex/adapters/aster_v3/endpoints.ex`

```elixir
defmodule ZenCex.Adapters.AsterV3.Endpoints do
  @moduledoc """
  Aster V3 API endpoint definitions.

  V3 API has limited endpoints (~6) focused on wallet-based operations.
  """

  alias ZenCex.Adapters.AsterV3.{Auth, Parser}
  alias ZenCex.Core.HTTP

  @base_url "https://fapi.asterdex.com"

  # Helper to make authenticated requests
  defp request(method, path, params, opts) do
    endpoint_config = %{
      method: method,
      path: path,
      base_url: @base_url
    }

    HTTP.request(endpoint_config, params, opts)
    |> Parser.parse_response()
  end

  # ==================== ACCOUNT ====================

  @doc "Get futures account balance (V3 with Web3 auth)"
  def get_balance(params \\ %{}, opts) do
    request(:get, "/fapi/v3/balance", params, opts)
  end

  # ==================== TRADING ====================

  @doc "Transfer between futures and spot wallet (V3 with Web3 auth)"
  def transfer_wallet(params, opts) do
    request(:post, "/fapi/v3/asset/wallet/transfer", params, opts)
  end

  # ==================== REGISTRY FUNCTIONS ====================

  def auth, do: Auth
  def base_url, do: @base_url

  def list_operations do
    [:get_balance, :transfer_wallet]
  end
end
```

### 4.5: Futures Module

**File**: `lib/zen_cex/adapters/aster_v3/futures.ex`

```elixir
defmodule ZenCex.Adapters.AsterV3.Futures do
  @moduledoc """
  Aster V3 perpetual futures trading interface.

  Uses Web3 authentication with Ethereum wallet signatures.
  """

  alias ZenCex.Adapters.AsterV3.Endpoints

  @doc """
  Get futures account balance.

  ## Parameters

    * `params` - Empty map (no parameters)
    * `opts` - Options with :auth_credentials containing:
      - :wallet_address - Ethereum wallet address
      - :private_key - Private key for signing
      - :testnet - (optional) true for testnet

  ## Examples

      credentials = %{
        wallet_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
        private_key: "0x...",
        testnet: true
      }

      {:ok, balance} = get_balance(%{}, auth_credentials: credentials)
  """
  @spec get_balance(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_balance(params \\ %{}, opts) do
    Endpoints.get_balance(params, opts)
  end

  @doc """
  Transfer between futures and spot wallet.

  ## Parameters

    * `params` - Transfer parameters:
      - :asset - Asset to transfer (e.g., "USDT")
      - :amount - Amount to transfer
      - :type - Transfer type (1: spot to futures, 2: futures to spot)
    * `opts` - Options with :auth_credentials

  ## Examples

      transfer_wallet(
        %{asset: "USDT", amount: "100", type: 1},
        auth_credentials: credentials
      )
  """
  @spec transfer_wallet(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def transfer_wallet(params, opts) do
    Endpoints.transfer_wallet(params, opts)
  end
end
```

### 4.6: Parser Module

**File**: `lib/zen_cex/adapters/aster_v3/parser.ex`

```elixir
defmodule ZenCex.Adapters.AsterV3.Parser do
  @moduledoc """
  Response parser for Aster V3 API.

  V3 responses likely have same format as Standard API,
  but this module allows for V3-specific parsing if needed.
  """

  use ZenCex.Adapters.BaseParser

  @doc """
  Parses generic Aster V3 response.

  Falls back to standard Binance-compatible parsing.
  """
  def parse_response({:ok, %{status: 200, body: body}}) when is_map(body) do
    normalized = normalize_keys(body)
    {:ok, normalized}
  end

  def parse_response({:ok, %{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  def parse_response({:error, reason}) do
    {:error, reason}
  end
end
```

**Verification**:
- All modules compile
- Can create authenticated requests
- Web3 signature headers are added
- Endpoint functions are accessible
- Parser handles responses correctly

---

## Task 5: Integration Tests

[D:3/B:7 → Priority:2.33] 🚀

**Purpose**: Create comprehensive tests for Web3 functionality

### 5.1: Web3 Auth Tests

**File**: `test/zen_cex/adapters/web3/auth_test.exs`

```elixir
defmodule ZenCex.Adapters.Web3.AuthTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Web3.Auth

  describe "auth_method/0" do
    test "returns :web3_ecdsa" do
      assert Auth.auth_method() == :web3_ecdsa
    end
  end

  describe "generate_nonce/0" do
    test "generates timestamp in microseconds" do
      nonce = Auth.generate_nonce()
      assert is_integer(nonce)
      assert nonce > 0

      # Should be recent (within last second)
      now = System.system_time(:microsecond)
      assert_in_delta nonce, now, 1_000_000
    end
  end

  describe "extract_params/1" do
    test "extracts query params from request" do
      request = Req.new(url: "https://example.com", params: %{symbol: "BTCUSDT"})
      params = Auth.extract_params(request)

      assert params == %{symbol: "BTCUSDT"}
    end

    test "merges query and body params" do
      request = Req.new(
        url: "https://example.com",
        params: %{symbol: "BTCUSDT"},
        json: %{side: "BUY", quantity: "1"}
      )

      params = Auth.extract_params(request)

      assert params == %{symbol: "BTCUSDT", side: "BUY", quantity: "1"}
    end
  end
end
```

### 5.2: Credential Validator Tests

**File**: `test/zen_cex/adapters/web3/credential_validator_test.exs`

```elixir
defmodule ZenCex.Adapters.Web3.CredentialValidatorTest do
  use ExUnit.Case, async: true

  alias ZenCex.Adapters.Web3.CredentialValidator

  describe "validate_wallet_address/1" do
    test "accepts valid Ethereum address" do
      assert :ok = CredentialValidator.validate_wallet_address(
        "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
      )
    end

    test "rejects address without 0x prefix" do
      assert {:error, {:invalid_address, _}} =
        CredentialValidator.validate_wallet_address(
          "742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
        )
    end

    test "rejects address with wrong length" do
      assert {:error, {:invalid_address, _}} =
        CredentialValidator.validate_wallet_address("0x123")
    end

    test "rejects address with invalid characters" do
      assert {:error, {:invalid_address, _}} =
        CredentialValidator.validate_wallet_address(
          "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEZ"
        )
    end
  end

  describe "validate_private_key/1" do
    test "accepts valid private key" do
      # 64 hex chars after 0x
      key = "0x" <> String.duplicate("a", 64)
      assert :ok = CredentialValidator.validate_private_key(key)
    end

    test "rejects key without 0x prefix" do
      key = String.duplicate("a", 64)
      assert {:error, {:invalid_private_key, _}} =
        CredentialValidator.validate_private_key(key)
    end

    test "rejects key with wrong length" do
      assert {:error, {:invalid_private_key, _}} =
        CredentialValidator.validate_private_key("0x123")
    end
  end

  describe "sanitize_for_logging/1" do
    test "removes private key" do
      credentials = %{
        wallet_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
        private_key: "0x" <> String.duplicate("a", 64)
      }

      sanitized = CredentialValidator.sanitize_for_logging(credentials)

      assert sanitized.wallet_address == credentials.wallet_address
      assert sanitized.private_key == "<REDACTED>"
    end
  end
end
```

### 5.3: Aster V3 Integration Tests

**File**: `test/zen_cex/adapters/aster_v3/integration_test.exs`

```elixir
defmodule ZenCex.Adapters.AsterV3.IntegrationTest do
  use ExUnit.Case

  @moduletag :aster_v3
  @moduletag :integration
  @moduletag :web3

  alias ZenCex.Adapters.AsterV3.Futures

  setup do
    # Skip if Web3 not available
    unless ZenCex.Adapters.Web3.available?() do
      :skip
    else
      # ENV reading is OK in TEST code (not library code)
      wallet = System.get_env("ASTER_V3_WALLET_ADDRESS")
      key = System.get_env("ASTER_V3_PRIVATE_KEY")

      if wallet && key do
        # Test passes credentials explicitly to library
        credentials = %{
          wallet_address: wallet,
          private_key: key,
          testnet: true
        }

        {:ok, credentials: credentials}
      else
        :skip
      end
    end
  end

  describe "get_balance/2" do
    @tag :authenticated
    test "retrieves account balance", %{credentials: credentials} do
      case Futures.get_balance(%{}, auth_credentials: credentials) do
        {:ok, balance} ->
          assert is_map(balance)
          # May have various structures depending on V3 response

        {:error, reason} ->
          # Document the error for debugging
          flunk("Expected successful balance retrieval, got: #{inspect(reason)}")
      end
    end
  end
end
```

**Verification**:
- Unit tests pass
- Integration tests pass (if credentials available)
- Web3 signatures are valid
- Private keys never appear in logs

---

## Task 6: Documentation and Examples

[D:2/B:6 → Priority:3.0] 🎯

**Purpose**: Document Web3 functionality for users

### 6.1: Update README.md

Add Web3 section:

```markdown
## Web3 Support (DEX Integrations)

zen_cex supports Web3-based authentication for decentralized exchanges.

### Installation

Web3 features require the optional `ethers` dependency:

\`\`\`elixir
# In mix.exs
def deps do
  [
    {:zen_cex, "~> 0.1.0"},
    {:ethers, "~> 0.6.7"}  # Optional - only needed for DEX integrations
  ]
end
\`\`\`

### Supported DEX Platforms

- ✅ **Aster V3** - Perpetual futures with Web3 wallet authentication

### Usage Example

\`\`\`elixir
alias ZenCex.Adapters.AsterV3.Futures

# Credentials passed explicitly (NEVER from ENV in library code)
# Application code retrieves from database, vault, or user input
credentials = %{
  wallet_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  private_key: wallet_private_key,  # From your secure source
  testnet: true
}

# Get account balance
{:ok, balance} = Futures.get_balance(%{}, auth_credentials: credentials)

# Transfer between wallets
Futures.transfer_wallet(
  %{asset: "USDT", amount: "100", type: 1},
  auth_credentials: credentials
)
\`\`\`

### Security Best Practices

- ⚠️ **Never commit private keys** to version control
- ✅ **Library takes credentials explicitly** - calling code handles secure retrieval
- ✅ Use secure vaults (HashiCorp Vault, AWS Secrets, database encryption)
- ✅ Test with testnet first
- ✅ Keep minimal funds in API wallets
- ✅ Monitor for unauthorized transactions
- ✅ Rotate keys regularly
```

### 6.2: Create WEB3.md Guide

**File**: `docs/WEB3.md`

```markdown
# Web3 Authentication Guide

This guide explains Web3-based authentication in zen_cex for DEX integrations.

## What is Web3 Authentication?

Web3 authentication uses Ethereum wallet signatures instead of traditional API keys:

- **Traditional (CEX)**: API Key + API Secret → HMAC-SHA256 signature
- **Web3 (DEX)**: Wallet Address + Private Key → ECDSA signature

## When to Use Web3 Auth

Use Web3 authentication when:
- Trading on decentralized exchanges (DEXs)
- Platform requires Ethereum wallet signatures
- You want trustless, non-custodial trading
- DeFi wallet integration is needed

Use traditional auth (HMAC) when:
- Trading on centralized exchanges (Binance, Bybit)
- API keys are available
- Simpler integration is preferred

## How It Works

### 1. Signature Generation Process

\`\`\`
Request Parameters
    ↓
Convert to JSON
    ↓
ABI Encode [json, user_address, signer_address, nonce]
    ↓
Keccak-256 Hash
    ↓
ECDSA Sign with Private Key
    ↓
Add to Request Headers
\`\`\`

### 2. Code Example

\`\`\`elixir
# Step 1: Prepare credentials
credentials = %{
  wallet_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
  private_key: "0x<64_hex_chars>",
  testnet: true
}

# Step 2: Make authenticated request
{:ok, response} = AsterV3.Futures.get_balance(%{},
  auth_credentials: credentials
)

# Behind the scenes:
# 1. Params extracted: {}
# 2. Nonce generated: 1696896000000000
# 3. ABI encoded: [...binary data...]
# 4. Keccak hash: 0xabc123...
# 5. ECDSA signature: 0xdef456...
# 6. Headers added:
#    - user: 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb
#    - signer: 0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb
#    - nonce: 1696896000000000
#    - signature: 0xdef456...
\`\`\`

## Security Considerations

### Private Key Management

**❌ NEVER DO THIS:**
\`\`\`elixir
# Hard-coded private key in library code
credentials = %{
  wallet_address: "0x...",
  private_key: "0x1234..."  # DANGER!
}

# Reading ENV in library code (zen_cex is a LIBRARY, not an app)
credentials = %{
  wallet_address: System.get_env("WEB3_WALLET_ADDRESS"),
  private_key: System.get_env("WEB3_PRIVATE_KEY")
}
\`\`\`

**✅ CORRECT APPROACH:**
\`\`\`elixir
# APPLICATION CODE (not library) retrieves credentials
# Option 1: From secure vault
{:ok, wallet_address} = Vault.read("secret/web3/address")
{:ok, private_key} = Vault.read("secret/web3/private_key")

credentials = %{
  wallet_address: wallet_address,
  private_key: private_key
}

# Option 2: From database (encrypted at rest)
{:ok, wallet_config} = MyApp.Repo.get_wallet_config(user_id)

credentials = %{
  wallet_address: wallet_config.address,
  private_key: decrypt_private_key(wallet_config.encrypted_key)
}

# Option 3: From user input (web form, CLI arg)
credentials = %{
  wallet_address: wallet_address_from_user,
  private_key: private_key_from_user
}

# Then pass to library explicitly
AsterV3.Futures.get_balance(%{}, auth_credentials: credentials)
\`\`\`

### Best Practices

1. **Separate Wallets**: Use different wallets for:
   - Trading (hot wallet, minimal funds)
   - Storage (cold wallet, main funds)
   - Testing (testnet wallet)

2. **Monitor Activity**:
   \`\`\`elixir
   # Check transactions regularly
   Etherscan.get_transactions(wallet_address)

   # Set up alerts for unauthorized activity
   \`\`\`

3. **Rotate Keys**: Change private keys periodically

4. **Testnet First**: Always test on testnet before production

## Troubleshooting

### "Invalid signature" Error

**Cause**: Signature doesn't match expected format

**Solutions**:
1. Verify wallet address matches private key
2. Check nonce is recent (within 5 minutes)
3. Ensure params are sorted correctly
4. Verify ABI encoding matches platform requirements

### "Insufficient funds" Error

**Cause**: Wallet doesn't have enough balance

**Solutions**:
1. Check wallet balance on blockchain explorer
2. Transfer funds to wallet
3. Ensure using correct network (mainnet vs testnet)

### "ethers not available" Error

**Cause**: ethers dependency not installed

**Solution**:
\`\`\`bash
# Add to mix.exs
{:ethers, "~> 0.6.7"}

# Install
mix deps.get
\`\`\`

## Advanced Usage

### Custom Payload Builder

For DEXs with different signature formats:

\`\`\`elixir
defmodule MyCustomAuth do
  def custom_payload_builder(params, credentials, nonce) do
    # Custom ABI encoding logic
    data = custom_encode(params, credentials.wallet_address, nonce)
    {:ok, data}
  end
end

# Use custom builder
credentials = %{
  wallet_address: "0x...",
  private_key: "0x...",
  payload_builder: &MyCustomAuth.custom_payload_builder/3
}
\`\`\`

### Monitoring Gas Costs

\`\`\`elixir
# Web3 auth doesn't consume gas (off-chain signing)
# But monitor on-chain transactions:

{:ok, tx} = Ethers.get_transaction(tx_hash)
gas_used = tx["gasUsed"]
gas_price = tx["gasPrice"]
cost_wei = gas_used * gas_price
cost_eth = Decimal.div(cost_wei, Decimal.new("1000000000000000000"))
\`\`\`

## Resources

- [Ethers Library Documentation](https://hex.pm/packages/ethers)
- [Ethereum ABI Encoding](https://docs.soliditylang.org/en/latest/abi-spec.html)
- [ECDSA Signatures](https://en.wikipedia.org/wiki/Elliptic_Curve_Digital_Signature_Algorithm)
- [Aster V3 API Docs](https://github.com/asterdex/api-docs)
```

### 6.3: Create Example Module

**File**: `lib/examples/aster_v3_trading.ex`

```elixir
defmodule ZenCex.Examples.AsterV3Trading do
  @moduledoc """
  Example usage of Aster V3 API with Web3 authentication.

  Demonstrates wallet-based trading on Aster DEX.
  """

  alias ZenCex.Adapters.AsterV3.Futures

  @doc """
  Get account balance with Web3 auth.

  Credentials must be provided by the calling application.

  ## Example

      # Application retrieves credentials from secure source
      credentials = MyApp.get_web3_credentials()

      # Pass to library function
      iex> AsterV3Trading.get_balance(credentials)
      {:ok, %{balances: [...]}}
  """
  def get_balance(credentials) do
    Futures.get_balance(%{}, auth_credentials: credentials)
  end

  @doc """
  Transfer USDT from spot to futures wallet.

  ## Example

      credentials = MyApp.get_web3_credentials()

      iex> AsterV3Trading.transfer_to_futures("100", credentials)
      {:ok, %{tranId: "12345"}}
  """
  def transfer_to_futures(amount, credentials) do

    Futures.transfer_wallet(
      %{
        asset: "USDT",
        amount: amount,
        type: 1  # 1 = spot to futures
      },
      auth_credentials: credentials
    )
  end

  @doc """
  Transfer USDT from futures to spot wallet.
  """
  def transfer_to_spot(amount, credentials) do

    Futures.transfer_wallet(
      %{
        asset: "USDT",
        amount: amount,
        type: 2  # 2 = futures to spot
      },
      auth_credentials: credentials
    )
  end
end
```

**Verification**:
- README.md updated with Web3 section
- WEB3.md guide is comprehensive
- Examples are clear and working
- Security best practices documented

---

## Task 7: Generalization and Cleanup

[D:3/B:6 → Priority:2.0] 🚀

**Purpose**: Make Web3 auth reusable for future DEX integrations

### 7.1: Create BaseWeb3Auth Behavior

**File**: `lib/zen_cex/adapters/base_web3_auth.ex`

```elixir
defmodule ZenCex.Adapters.BaseWeb3Auth do
  @moduledoc """
  Base behavior for Web3-based authentication adapters.

  Provides common patterns for DEX integrations that use
  Ethereum wallet signatures.

  ## Usage

  Implement this behavior for each DEX platform:

      defmodule MyDex.Auth do
        use ZenCex.Adapters.BaseWeb3Auth

        @impl true
        def build_signature_payload(params, credentials, nonce) do
          # DEX-specific ABI encoding
        end
      end
  """

  @doc """
  Builds the signature payload for the specific DEX.

  Different DEX platforms may have different payload structures.
  """
  @callback build_signature_payload(
    params :: map(),
    credentials :: map(),
    nonce :: non_neg_integer()
  ) :: {:ok, binary()} | {:error, term()}

  @doc """
  Optional: Custom header names for authentication.

  Some DEXs may use different header names than the standard
  user/signer/nonce/signature format.
  """
  @callback auth_header_names() :: %{
    user: String.t(),
    signer: String.t(),
    nonce: String.t(),
    signature: String.t()
  }

  @optional_callbacks auth_header_names: 0

  defmacro __using__(_opts) do
    quote do
      @behaviour ZenCex.Adapters.BaseWeb3Auth
      @behaviour ZenCex.Behaviors.Auth

      alias ZenCex.Adapters.Web3

      @impl ZenCex.Behaviors.Auth
      def auth_method, do: :web3_ecdsa

      @impl ZenCex.Behaviors.Auth
      def sign_request(request, credentials) do
        credentials_with_builder = Map.put(
          credentials,
          :payload_builder,
          &build_signature_payload/3
        )

        Web3.Auth.sign_request(request, credentials_with_builder)
      end

      @impl ZenCex.Behaviors.Auth
      def validate_credentials(credentials \\ %{}) do
        Web3.Auth.validate_credentials(credentials)
      end

      # Default header names (can be overridden)
      def auth_header_names do
        %{
          user: "user",
          signer: "signer",
          nonce: "nonce",
          signature: "signature"
        }
      end

      defoverridable auth_header_names: 0
    end
  end
end
```

### 7.2: Update Aster V3 to Use BaseWeb3Auth

Simplify `lib/zen_cex/adapters/aster_v3/auth.ex`:

```elixir
defmodule ZenCex.Adapters.AsterV3.Auth do
  @moduledoc """
  Aster V3-specific Web3 authentication.
  """

  use ZenCex.Adapters.BaseWeb3Auth

  alias ZenCex.Adapters.Web3.ABIEncoder

  @impl true
  def build_signature_payload(params, credentials, nonce) do
    # Sort params by key for consistency
    sorted_params = Enum.sort(params)
    json_string = Jason.encode!(sorted_params)

    ABIEncoder.encode_aster_v3_payload(
      json_string,
      credentials.wallet_address,
      credentials.wallet_address,
      nonce
    )
  end
end
```

### 7.3: Update CLAUDE.md

Add Web3 section to project guidance:

```markdown
## Web3 Integration (DEX Support)

### When to Use Web3 Auth

- Decentralized exchanges (Aster V3, etc.)
- Platforms requiring Ethereum wallet signatures
- Trustless, non-custodial trading

### Implementation Pattern

1. **Use BaseWeb3Auth**: All Web3 adapters should use `ZenCex.Adapters.BaseWeb3Auth`
2. **Implement payload builder**: Define DEX-specific ABI encoding
3. **Test with real wallet**: Use testnet wallet for development
4. **Security first**: Never log private keys, always sanitize

### Example Structure

\`\`\`elixir
defmodule ZenCex.Adapters.NewDex.Auth do
  use ZenCex.Adapters.BaseWeb3Auth

  @impl true
  def build_signature_payload(params, credentials, nonce) do
    # DEX-specific ABI encoding
  end
end
\`\`\`

### Security Requirements

- ✅ Private keys never logged (use CredentialValidator.sanitize_for_logging/1)
- ✅ Credentials passed explicitly (never from global config)
- ✅ Testnet flag in credentials
- ✅ Comprehensive tests with sanitized test keys
```

### 7.4: Add Telemetry Events

Update Web3.Auth to emit telemetry:

```elixir
# In lib/zen_cex/adapters/web3/auth.ex

defp generate_auth_data(request, credentials) do
  start_time = System.monotonic_time()

  result = # ... existing logic ...

  duration = System.monotonic_time() - start_time

  :telemetry.execute(
    [:zen_cex, :web3, :auth, :sign],
    %{duration: duration},
    %{
      wallet: credentials.wallet_address,
      testnet: Map.get(credentials, :testnet, false)
    }
  )

  result
end
```

**Verification**:
- BaseWeb3Auth behavior works correctly
- Aster V3 Auth is simplified
- Telemetry events fire
- Documentation is complete
- Pattern is reusable for future DEXs

---

## Task 8: Security Hardening

[D:2/B:8 → Priority:4.0] 🎯

**Purpose**: Ensure Web3 implementation is production-ready and secure

### 8.1: Private Key Sanitization

Ensure private keys never appear in logs:

```elixir
# In lib/zen_cex/adapters/web3/auth.ex

defp sanitize_error({:error, reason}, credentials) do
  # Remove sensitive data from error messages
  sanitized_creds = CredentialValidator.sanitize_for_logging(credentials)

  {:error, %{
    reason: reason,
    credentials: sanitized_creds
  }}
end

# Update all Logger.error calls to sanitize
Logger.error("Web3 auth failed",
  credentials: CredentialValidator.sanitize_for_logging(credentials),
  error: inspect(reason)
)
```

### 8.2: Add Wallet Address Checksum Validation

Use ethers to validate checksummed addresses:

```elixir
# In lib/zen_cex/adapters/web3/credential_validator.ex

@doc """
Validates Ethereum address checksum.

Ensures address uses proper EIP-55 checksum encoding.
"""
@spec validate_checksum(Types.address()) :: :ok | {:error, term()}
def validate_checksum(address) do
  ZenCex.Adapters.Web3.require_web3!()

  case Ethers.Utils.is_address?(address) do
    true ->
      # Check if checksummed correctly
      checksummed = Ethers.Utils.to_checksum_address(address)

      if checksummed == address do
        :ok
      else
        {:warning, {:checksum_mismatch,
          "Address should be checksummed as: #{checksummed}"}}
      end

    false ->
      {:error, {:invalid_address, "Not a valid Ethereum address"}}
  end
end
```

### 8.3: Rate Limiting for Signature Generation

Prevent abuse of signature generation:

```elixir
# In lib/zen_cex/adapters/web3/signer.ex

@max_signatures_per_minute 60

defp check_rate_limit(wallet_address) do
  # Use ETS to track signature generation rate
  table = :web3_signature_rate_limit
  key = {:signatures, wallet_address, current_minute()}

  case :ets.update_counter(table, key, {2, 1}, {key, 0}) do
    count when count > @max_signatures_per_minute ->
      {:error, :rate_limit_exceeded}

    _ ->
      :ok
  end
end

defp current_minute do
  div(System.system_time(:second), 60)
end
```

### 8.4: Security Documentation

**File**: `docs/SECURITY_WEB3.md`

```markdown
# Web3 Security Guidelines

## Private Key Management

### Storage

**Production** (Application responsibility, NOT library):
- ✅ HashiCorp Vault
- ✅ AWS Secrets Manager
- ✅ Azure Key Vault
- ✅ Google Cloud Secret Manager
- ✅ Database with encrypted fields
- ✅ User input (for DeFi wallet integrations)

**Development/Testing**:
- ✅ ENV variables in tests ONLY (System.get_env in test files)
- ✅ Local encrypted keystore
- ❌ NEVER read ENV in library code
- ❌ NEVER hard-code in source code
- ❌ NEVER commit to version control

**zen_cex Library Pattern**:
- Library NEVER reads credentials from ENV
- Calling code (application/tests) retrieves credentials
- Credentials passed explicitly via `auth_credentials` option
- Enables multi-instance, multi-account, and flexible storage

### Access Control

1. **Principle of Least Privilege**:
   - Only services that need Web3 auth should have access
   - Use separate keys for different environments
   - Rotate keys regularly (every 90 days minimum)

2. **Monitoring**:
   - Log all wallet transactions
   - Alert on unexpected activity
   - Track balance changes
   - Monitor gas usage (for on-chain tx)

### Key Rotation

\`\`\`elixir
# 1. Generate new wallet
{:ok, new_wallet} = Ethers.Signer.LocalSigner.generate()

# 2. Update credentials in vault
Vault.write("secret/web3/private_key", new_wallet.private_key)

# 3. Transfer funds to new wallet (if needed)
# 4. Update monitoring/alerts
# 5. Revoke old credentials after grace period
\`\`\`

## Common Security Mistakes

### ❌ Logging Private Keys

\`\`\`elixir
# BAD
Logger.info("Credentials: #{inspect(credentials)}")

# GOOD
Logger.info("Credentials: #{inspect(CredentialValidator.sanitize_for_logging(credentials))}")
\`\`\`

### ❌ Error Messages with Sensitive Data

\`\`\`elixir
# BAD
raise "Failed to sign with key: #{private_key}"

# GOOD
raise "Failed to sign (key: #{String.slice(private_key, 0..5)}...)"
\`\`\`

### ❌ Shared Wallets

\`\`\`elixir
# BAD - Same wallet for all environments
production_wallet = testnet_wallet

# GOOD - Separate wallets
production_wallet = load_from_vault("prod/web3/key")
testnet_wallet = load_from_vault("testnet/web3/key")
\`\`\`

## Incident Response

If private key is compromised:

1. **Immediate**: Transfer all funds to safe wallet
2. **Within 1 hour**: Rotate key in all systems
3. **Within 24 hours**: Full security audit
4. **Post-mortem**: Document and improve processes

## Compliance

- PCI-DSS: Not applicable (crypto, not credit cards)
- GDPR: Wallet addresses may be personal data (anonymize in logs)
- SOC 2: Implement access controls and audit logging
```

**Verification**:
- Private keys never logged
- Checksummed addresses validated
- Rate limiting prevents abuse
- Security documentation comprehensive

---

## Task 9: Final Integration and Testing

[D:3/B:7 → Priority:2.33] 🚀

**Purpose**: Complete integration and verify all features work together

### 9.1: Core Registry Integration

Update `lib/zen_cex/core/registry.ex`:

```elixir
defp init_registry do
  %{
    # ... existing CEX mappings ...

    # DEX with Web3 auth
    {:aster_v3, :futures} => ZenCex.Adapters.AsterV3.Futures
  }
end
```

### 9.2: Update Application

Ensure Web3 doesn't break existing functionality:

```elixir
# In lib/zen_cex/application.ex

def start(_type, _args) do
  children = [
    # ... existing children ...

    # Only start Web3 rate limiter if ethers available
    if Code.ensure_loaded?(Ethers) do
      {Task, fn -> init_web3_rate_limiter() end}
    end
  ] |> Enum.reject(&is_nil/1)

  # ... rest of start logic ...
end

defp init_web3_rate_limiter do
  :ets.new(:web3_signature_rate_limit,
    [:set, :public, :named_table, write_concurrency: true])
end
```

### 9.3: Comprehensive Integration Test Suite

**File**: `test/zen_cex/web3_integration_test.exs`

```elixir
defmodule ZenCex.Web3IntegrationTest do
  use ExUnit.Case

  @moduletag :web3
  @moduletag :integration

  alias ZenCex.Adapters.{AsterV3, Web3}

  setup_all do
    unless Web3.available?() do
      {:skip, "ethers not installed"}
    else
      :ok
    end
  end

  describe "Web3 availability" do
    test "Web3 module reports availability correctly" do
      assert Web3.available?() == true
    end
  end

  describe "End-to-end Web3 auth flow" do
    test "can generate valid signature" do
      # Use test wallet
      credentials = %{
        wallet_address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb",
        private_key: generate_test_private_key(),
        testnet: true
      }

      # Create request
      request = Req.new(
        url: "https://fapi.asterdex.com/fapi/v3/balance",
        params: %{symbol: "BTCUSDT"}
      )

      # Sign request
      signed = AsterV3.Auth.sign_request(request, credentials)

      # Verify headers added
      headers = Map.new(signed.headers)
      assert headers["user"] == credentials.wallet_address
      assert headers["signer"] == credentials.wallet_address
      assert headers["nonce"]
      assert headers["signature"]
      assert String.starts_with?(headers["signature"], "0x")
    end
  end

  defp generate_test_private_key do
    # Generate random test key
    {:ok, wallet} = Ethers.Signer.LocalSigner.generate()
    wallet.private_key
  end
end
```

### 9.4: Quality Checks

Run full test suite:

```bash
# Install ethers for testing
mix deps.get

# Run all tests
mix test

# Run Web3-specific tests
mix test --only web3

# Check code quality
mix format
mix credo
mix dialyzer
mix doctor

# Check test coverage
mix coveralls
```

### 9.5: Performance Testing

**File**: `test/zen_cex/web3_performance_test.exs`

```elixir
defmodule ZenCex.Web3PerformanceTest do
  use ExUnit.Case

  @moduletag :performance
  @moduletag :web3

  alias ZenCex.Adapters.Web3.Signer

  test "signature generation performance" do
    private_key = generate_test_key()
    data = "test message"

    # Measure time for 100 signatures
    {time_us, _} = :timer.tc(fn ->
      for _ <- 1..100 do
        {:ok, _sig} = Signer.sign(data, private_key)
      end
    end)

    avg_time_ms = time_us / 100 / 1000

    # Should complete in reasonable time (< 10ms per signature)
    assert avg_time_ms < 10,
      "Average signature time: #{avg_time_ms}ms (expected < 10ms)"
  end

  defp generate_test_key do
    {:ok, wallet} = Ethers.Signer.LocalSigner.generate()
    wallet.private_key
  end
end
```

**Verification**:
- All tests pass (unit + integration)
- No dialyzer warnings
- Credo score maintained
- Test coverage > 80%
- Performance is acceptable
- No breaking changes to existing CEX functionality

---

## Notes

### Dependency Management

**ethers (~0.6.7) Dependencies**:
- ex_keccak (~0.7.5) - Keccak-256 hashing
- ex_secp256k1 (~0.7.2) - ECDSA signing
- ex_abi (~0.6.0) - ABI encoding/decoding
- jason - JSON encoding (already in zen_cex)
- Additional deps: ~15 total

**Installation Size**: ~2-3 MB additional

**Optional Flag**: Users who don't need Web3 can skip ethers installation

### Web3 vs Traditional Auth Comparison

| Aspect | HMAC (CEX) | Web3 (DEX) |
|--------|------------|------------|
| **Credentials** | API Key + Secret | Wallet + Private Key |
| **Signature** | HMAC-SHA256 | Keccak-256 + ECDSA |
| **Algorithm** | Symmetric | Asymmetric |
| **Use Case** | Trading bots, servers | Wallets, DeFi frontends |
| **Complexity** | Low | Medium |
| **Dependencies** | None (built-in crypto) | ethers library |
| **Testnet** | Separate API keys | Same wallet (different network) |

### Future DEX Integrations

Pattern is reusable for:
- GMX (decentralized perpetuals)
- dYdX (StarkEx-based perpetuals)
- Vertex Protocol (Arbitrum-based)
- Any DEX with Web3 authentication

Each requires:
1. Create adapter using `BaseWeb3Auth`
2. Implement `build_signature_payload/3`
3. Add endpoint definitions
4. Test with testnet

### Performance Considerations

- **Signature generation**: ~5-10ms per request (acceptable for trading)
- **Memory usage**: Minimal (ethers is lightweight)
- **Concurrent requests**: No issues (stateless signing)
- **Rate limiting**: Built-in signature rate limiting

### Monitoring and Observability

Telemetry events emitted:
- `[:zen_cex, :web3, :auth, :sign]` - Signature generation
- `[:zen_cex, :web3, :auth, :error]` - Authentication errors
- `[:zen_cex, :web3, :signer, :rate_limit]` - Rate limit hits

Use for:
- Performance monitoring
- Error tracking
- Security auditing
- Usage analytics

---

## Session Notes (Append after each session)

### Session 0: 2025-10-06

**Completed**:
- Created specification document
- Researched ethers library
- Documented Aster V3 API requirements
- Defined task breakdown

**Findings**:
- ethers library is mature and well-maintained
- Aster V3 uses standard Ethereum signature format
- ABI encoding matches Solidity standards
- Pattern is reusable for other DEXs

**Next session**: Task 0 (Research and test ethers library with Tidewave)

---

_Add new session notes above this line_
