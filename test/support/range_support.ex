defmodule SourcerorTest.RangeSupport do
  @moduledoc false

  def decorate(code, range) do
    code
    |> String.trim_trailing()
    |> Sourceror.patch_string([%Sourceror.Patch{range: range, change: &"«#{&1}»"}])
  end
end
