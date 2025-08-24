defmodule ZenCex.Core.Signer do
  @moduledoc """
  Common cryptographic utilities for exchange API authentication.

  This module provides reusable signing and encoding functions used across
  different exchange adapters. It supports multiple signing algorithms and
  encoding formats commonly used by cryptocurrency exchanges.

  ## Supported Algorithms

  - HMAC-SHA256 (Binance, Bybit)
  - HMAC-SHA512 (Kraken)
  - Base64 encoding/decoding (Kraken secrets)
  - Hex encoding (signature output)

  ## Usage

      # HMAC-SHA256 signature (Binance, Bybit)
      signature = Signer.hmac_sha256("payload", "secret")
      hex_signature = Signer.encode_hex(signature)

      # HMAC-SHA512 signature (Kraken)
      signature = Signer.hmac_sha512("payload", "secret")
      hex_signature = Signer.encode_hex(signature, case: :upper)

      # Base64 operations (Kraken secrets)
      decoded = Signer.decode_base64("encoded_secret")
  """

  @doc """
  Generates HMAC-SHA256 signature.

  Used by Binance, Bybit, and other exchanges requiring SHA256 signatures.

  ## Examples

      iex> Signer.hmac_sha256("message", "secret")
      <<...>>  # Binary signature
  """
  @spec hmac_sha256(String.t() | binary(), String.t() | binary()) :: binary()
  def hmac_sha256(payload, secret) when is_binary(payload) and is_binary(secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
  end

  @doc """
  Generates HMAC-SHA512 signature.

  Used by Kraken and other exchanges requiring SHA512 signatures.

  ## Examples

      iex> Signer.hmac_sha512("message", "secret")
      <<...>>  # Binary signature
  """
  @spec hmac_sha512(String.t() | binary(), String.t() | binary()) :: binary()
  def hmac_sha512(payload, secret) when is_binary(payload) and is_binary(secret) do
    :crypto.mac(:hmac, :sha512, secret, payload)
  end

  @doc """
  Encodes binary data as hexadecimal string.

  ## Options

  - `:case` - `:lower` (default) or `:upper` for hex case

  ## Examples

      iex> Signer.encode_hex(<<255, 0, 128>>)
      "ff0080"

      iex> Signer.encode_hex(<<255, 0, 128>>, case: :upper)
      "FF0080"
  """
  @spec encode_hex(binary(), keyword()) :: String.t()
  def encode_hex(data, opts \\ []) when is_binary(data) do
    case Keyword.get(opts, :case, :lower) do
      :lower -> Base.encode16(data, case: :lower)
      :upper -> Base.encode16(data, case: :upper)
    end
  end

  @doc """
  Decodes hexadecimal string to binary.

  Handles both uppercase and lowercase hex strings.

  ## Examples

      iex> Signer.decode_hex("ff0080")
      {:ok, <<255, 0, 128>>}

      iex> Signer.decode_hex("FF0080")
      {:ok, <<255, 0, 128>>}

      iex> Signer.decode_hex("invalid")
      {:error, :invalid_hex}
  """
  @spec decode_hex(String.t()) :: {:ok, binary()} | {:error, :invalid_hex}
  def decode_hex(hex_string) when is_binary(hex_string) do
    case Base.decode16(hex_string, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_hex}
    end
  end

  @doc """
  Encodes binary data as Base64 string.

  ## Examples

      iex> Signer.encode_base64(<<255, 0, 128>>)
      "/wCA"
  """
  @spec encode_base64(binary()) :: String.t()
  def encode_base64(data) when is_binary(data) do
    Base.encode64(data)
  end

  @doc """
  Decodes Base64 string to binary.

  Used for decoding exchange API secrets (e.g., Kraken).

  ## Examples

      iex> Signer.decode_base64("/wCA")
      {:ok, <<255, 0, 128>>}

      iex> Signer.decode_base64("invalid!")
      {:error, :invalid_base64}
  """
  @spec decode_base64(String.t()) :: {:ok, binary()} | {:error, :invalid_base64}
  def decode_base64(base64_string) when is_binary(base64_string) do
    case Base.decode64(base64_string) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid_base64}
    end
  end

  @doc """
  Generates a nonce based on current timestamp.

  ## Options

  - `:unit` - Time unit (`:millisecond`, `:microsecond`, `:nanosecond`)
  - `:offset` - Additional offset to add to timestamp (for uniqueness)

  ## Examples

      iex> nonce = Signer.generate_nonce()
      iex> is_integer(nonce) and nonce > 0
      true

      iex> nonce = Signer.generate_nonce(unit: :microsecond)
      iex> is_integer(nonce) and nonce > 1_000_000_000_000
      true
  """
  @spec generate_nonce(keyword()) :: integer()
  def generate_nonce(opts \\ []) do
    unit = Keyword.get(opts, :unit, :millisecond)
    offset = Keyword.get(opts, :offset, 0)

    System.os_time(unit) + offset
  end

  @doc """
  Generates a timestamp string in seconds.

  Some exchanges require timestamps as strings in seconds.

  ## Examples

      iex> timestamp = Signer.timestamp_seconds()
      iex> String.match?(timestamp, ~r/^\\d{10}$/)
      true
  """
  @spec timestamp_seconds() :: String.t()
  def timestamp_seconds do
    :second
    |> System.os_time()
    |> Integer.to_string()
  end

  @doc """
  Generates a timestamp string in milliseconds.

  Most exchanges require timestamps as strings in milliseconds.

  ## Examples

      iex> timestamp = Signer.timestamp_milliseconds()
      iex> String.match?(timestamp, ~r/^\\d{13}$/)
      true
  """
  @spec timestamp_milliseconds() :: String.t()
  def timestamp_milliseconds do
    :millisecond
    |> System.os_time()
    |> Integer.to_string()
  end

  @doc """
  Generates a timestamp string in microseconds.

  Used by exchanges requiring high-precision timestamps (e.g., Kraken).

  ## Examples

      iex> timestamp = Signer.timestamp_microseconds()
      iex> String.match?(timestamp, ~r/^\\d{16}$/)
      true
  """
  @spec timestamp_microseconds() :: String.t()
  def timestamp_microseconds do
    :microsecond
    |> System.os_time()
    |> Integer.to_string()
  end

  @doc """
  Creates a signed payload using specified algorithm.

  Convenience function that combines payload signing and encoding.

  ## Options

  - `:algorithm` - `:sha256` (default) or `:sha512`
  - `:encoding` - `:hex` (default) or `:base64`
  - `:case` - `:lower` (default) or `:upper` for hex encoding

  ## Examples

      # SHA256 with lowercase hex (Binance style)
      iex> Signer.sign_payload("data", "secret")
      "1b2c3d..."

      # SHA512 with uppercase hex (Kraken style)
      iex> Signer.sign_payload("data", "secret", algorithm: :sha512, case: :upper)
      "A1B2C3..."

      # SHA256 with base64 encoding
      iex> Signer.sign_payload("data", "secret", encoding: :base64)
      "GywD..."
  """
  @spec sign_payload(String.t() | binary(), String.t() | binary(), keyword()) :: String.t()
  def sign_payload(payload, secret, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :sha256)
    encoding = Keyword.get(opts, :encoding, :hex)

    signature =
      case algorithm do
        :sha256 -> hmac_sha256(payload, secret)
        :sha512 -> hmac_sha512(payload, secret)
      end

    case encoding do
      :hex -> encode_hex(signature, opts)
      :base64 -> encode_base64(signature)
    end
  end

  @doc """
  Verifies a signature against a payload.

  Used for webhook verification and response validation.

  ## Options

  - `:algorithm` - `:sha256` (default) or `:sha512`
  - `:encoding` - `:hex` (default) or `:base64`
  - `:case` - `:lower` (default) or `:upper` for hex encoding

  ## Examples

      iex> signature = Signer.sign_payload("data", "secret")
      iex> Signer.verify_signature("data", signature, "secret")
      true

      iex> Signer.verify_signature("data", "wrong_sig", "secret")
      false
  """
  @spec verify_signature(String.t() | binary(), String.t(), String.t() | binary(), keyword()) :: boolean()
  def verify_signature(payload, signature, secret, opts \\ []) do
    expected_signature = sign_payload(payload, secret, opts)

    # Constant-time comparison to prevent timing attacks
    byte_size(expected_signature) == byte_size(signature) and
      :crypto.hash_equals(expected_signature, signature)
  end
end
