defmodule ZenCexTest do
  use ExUnit.Case

  doctest ZenCex

  test "module has correct documentation" do
    assert ZenCex.__info__(:module) == ZenCex
  end
end
