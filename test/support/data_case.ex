defmodule ZenCex.DataCase do
  @moduledoc """
  This module defines the setup for tests.

  You may define functions here to be used as helpers in your tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import ZenCex.DataCase
    end
  end

  setup _tags do
    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.
  """
  def errors_on(changeset) do
    Enum.reduce(changeset.errors, %{}, fn {field, {message, opts}}, acc ->
      full_message = build_error_message(message, opts)
      Map.update(acc, field, [full_message], &[full_message | &1])
    end)
  end

  defp build_error_message(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
