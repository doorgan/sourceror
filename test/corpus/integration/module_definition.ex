## empty module definition

defmodule Mod do
end

defmodule Mod.Child do
end

## module definition with atom literal

defmodule :mod do
end

## full module definition

defmodule Mod do
  @moduledoc """
  Example module
  """

  use UseMod

  @attribute 1

  @doc """
  Example function
  """
  @spec func(integer) :: integer
  def func(x) when is_integer(x) do
    priv(x) + priv(x)
  end

  defp priv(x), do: x * x
end