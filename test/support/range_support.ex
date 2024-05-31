defmodule SourcerorTest.RangeSupport do
  @moduledoc false

  def decorate(code, range) do
    code
    |> Sourceror.patch_string([%Sourceror.Patch{range: range, change: &"«#{&1}»"}])
    |> String.trim_trailing()
  end
end
