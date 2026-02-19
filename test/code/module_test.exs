defmodule Sourceror.Code.ModuleTest do
  use ExUnit.Case

  test "move_to_attribute_definition" do
    mod_zipper =
      ~s"""
      defmodule MyApp.Foo do
        @doc "My app module doc"
        @foo_key Application.compile_env!(:my_app, :key)
      end
      """
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert {:ok, zipper} = Sourceror.Code.Module.move_to_attribute_definition(mod_zipper, :doc)
    assert Sourceror.to_string(zipper.node) == ~s|@doc "My app module doc"|

    assert {:ok, zipper} =
             Sourceror.Code.Module.move_to_attribute_definition(mod_zipper, :foo_key)

    assert Sourceror.to_string(zipper.node) ==
             "@foo_key Application.compile_env!(:my_app, :key)"
  end
end
