defmodule SourcerorTest.Utils.TypedstructTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Utils.TypedStruct

  import Sourceror.Utils.TypedStruct

  describe "typedstruct/1" do
    test "generates the correct code" do
      quoted =
        Macro.expand_once(
          quote do
            typedstruct do
              field :a, String.t(), default: "a"
              field :b, boolean()
              field :c, integer, enforced?: true
            end
          end,
          __ENV__
        )

      assert {:__block__, _, [typespec, enforced_keys, struct_def]} = quoted

      assert {:@, _,
              [
                {:type, _,
                 [
                   {:"::", _,
                    [
                      {:t, _, _},
                      {:%, _, [{:__MODULE__, _, _}, {:%{}, _, fields}]}
                    ]}
                 ]}
              ]} = typespec

      assert [
               a:
                 {:|, _,
                  [
                    {{:., _, [{:__aliases__, _, [:String]}, :t]}, _, _},
                    nil
                  ]},
               b:
                 {:|, _,
                  [
                    {:boolean, _, _},
                    nil
                  ]},
               c: {:integer, _, _}
             ] = fields

      assert {:@, _, [{:enforce_keys, _, [[:c]]}]} = enforced_keys

      assert {:defstruct, _,
              [
                [
                  a: "a",
                  b: nil,
                  c: nil
                ]
              ]} = struct_def
    end

    test "handles single field" do
      quoted =
        Macro.expand_once(
          quote do
            typedstruct do
              field :a, integer()
            end
          end,
          __ENV__
        )

      assert {:__block__, _, [specs | _]} = quoted

      assert {:@, _,
              [
                {:type, _,
                 [
                   {:"::", _,
                    [
                      {:t, _, _},
                      {:%, _,
                       [
                         {:__MODULE__, _, _},
                         {:%{}, _,
                          [
                            a: {:|, _, [{:integer, _, _}, nil]}
                          ]}
                       ]}
                    ]}
                 ]}
              ]} = specs
    end
  end
end
