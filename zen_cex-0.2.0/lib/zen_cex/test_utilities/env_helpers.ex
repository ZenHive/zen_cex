defmodule ZenCex.TestUtilities.EnvHelpers do
  @moduledoc """
  Helper macros for safely manipulating environment variables in tests.

  This module provides the `with_env` macro which allows tests to temporarily
  modify environment variables and automatically restore them after the test
  completes, even if the test fails.

  ## Usage

  Import this module in your test case:

      import ZenCex.TestUtilities.EnvHelpers

  Then use the macro in your tests:

      test "handles missing API key" do
        with_env [{"BINANCE_TESTNET_API_KEY", nil}] do
          assert {:error, :missing_credentials} = MyModule.authenticate()
        end
      end

      test "handles invalid credentials" do
        with_env [{"BINANCE_TESTNET_API_KEY", "invalid"}] do
          assert {:error, :invalid_credentials} = MyModule.authenticate()
        end
      end
  """

  @doc """
  Temporarily modifies environment variables for the duration of a code block.

  This macro:
  1. Saves the current values of the specified environment variables
  2. Sets the environment variables to the new values
  3. Executes the provided code block
  4. Restores the original environment variable values (even if the code fails)

  ## Parameters

  - `env_changes` - A list of tuples where each tuple is `{key, value}`:
    - `key` - The environment variable name (string)
    - `value` - The new value (string) or `nil` to delete the variable

  ## Examples

      # Set a single variable
      with_env [{"API_KEY", "test_key"}] do
        assert System.get_env("API_KEY") == "test_key"
      end

      # Set multiple variables
      with_env [{"API_KEY", "key"}, {"API_SECRET", "secret"}] do
        # Your test code here
      end

      # Delete a variable
      with_env [{"API_KEY", nil}] do
        assert System.get_env("API_KEY") == nil
      end

  ## Safety

  The macro ensures that environment variables are always restored to their
  original values, even if the code block raises an exception. This prevents
  test pollution and ensures tests remain isolated.
  """
  defmacro with_env(env_changes, do: block) do
    quote do
      # Save original values
      original_env =
        Enum.map(unquote(env_changes), fn {key, _value} ->
          {key, System.get_env(key)}
        end)

      try do
        # Set new values
        Enum.each(unquote(env_changes), fn
          {key, nil} -> System.delete_env(key)
          {key, value} -> System.put_env(key, value)
        end)

        # Execute the test code
        unquote(block)
      after
        # Restore original values
        Enum.each(original_env, fn
          {key, nil} -> System.delete_env(key)
          {key, value} -> System.put_env(key, value)
        end)
      end
    end
  end
end
