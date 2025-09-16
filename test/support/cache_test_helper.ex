defmodule ZenCex.CacheTestHelper do
  @moduledoc """
  Test helper for cache-related tests providing namespace isolation.

  This helper ensures tests don't interfere with each other by using
  unique namespaces for cache keys.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias ZenCex.Core.Cache

  @doc """
  Generates a unique test namespace for cache keys.

  ## Example

      namespace = CacheTestHelper.test_namespace()
      # => "test_12345_678"
  """
  @spec test_namespace() :: String.t()
  def test_namespace do
    "test_#{:erlang.unique_integer([:positive])}_#{:rand.uniform(10_000)}"
  end

  @doc """
  Creates a namespaced key for testing.

  ## Example

      key = CacheTestHelper.namespaced_key("my_key")
      # => "test_12345_678:my_key"

      key = CacheTestHelper.namespaced_key("my_key", "custom_namespace")
      # => "custom_namespace:my_key"
  """
  @spec namespaced_key(String.t(), String.t() | nil) :: String.t()
  def namespaced_key(key, namespace \\ nil) do
    ns = namespace || test_namespace()
    "#{ns}:#{key}"
  end

  @doc """
  Creates a setup function that provides a unique namespace.

  ## Example

      setup :with_cache_namespace

      test "my test", %{cache_namespace: namespace} do
        key = "\#{namespace}:my_key"
        # Use namespaced key in test
      end
  """
  def with_cache_namespace(_context \\ %{}) do
    namespace = test_namespace()

    on_exit(fn ->
      # Clean up all keys from this namespace when test completes
      pattern = "#{namespace}:*"
      Cache.clear_pattern(pattern)
    end)

    {:ok, cache_namespace: namespace}
  end

  @doc """
  Clears all cache entries for a given namespace.

  ## Example

      CacheTestHelper.clear_namespace("test_12345_678")
  """
  @spec clear_namespace(String.t()) :: {:ok, non_neg_integer()}
  def clear_namespace(namespace) do
    pattern = "#{namespace}:*"
    Cache.clear_pattern(pattern)
  end
end
