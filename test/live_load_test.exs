defmodule LiveLoadTest do
  use ExUnit.Case

  doctest LiveLoad

  test "Code.loaded?" do
    assert Code.loaded?(LiveLoad)
  end
end
