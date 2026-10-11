defmodule Sourceror.Code.FunctionTest do
  use ExUnit.Case

  alias Sourceror.Code.Function

  describe "move_to_function_call_in_current_scope/4" do
    test "works on its own" do
      assert {:ok, zipper} =
               """
               x = 5
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Function.move_to_function_call_in_current_scope(:=, 2)

      assert Sourceror.to_string(zipper.node) == "x = 5"
    end

    test "works on erlang modules calls" do
      assert {:ok, zipper} =
               """
               hello
               :logger.add_handler(1, 2, 3)
               world
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Function.move_to_function_call_in_current_scope(
                 {:logger, :add_handler},
                 3
               )

      assert Sourceror.to_string(zipper.node) == ":logger.add_handler(1, 2, 3)"
    end

    test "works when composed inside of a block" do
      assert {:ok, zipper} =
               """
               def thing do
                x = 5

                other_code
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Function.move_to_def(:thing, 0)

      assert {:ok, zipper} =
               Function.move_to_function_call_in_current_scope(zipper, :=, 2)

      assert Sourceror.to_string(zipper.node) == "x = 5"
    end

    test "can be used to move multiple times" do
      assert {:ok, zipper} =
               """
               use Foo, [a: 1]
               use Bar, [a: 2]
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Function.move_to_function_call_in_current_scope(:use, 2)

      zipper = Sourceror.Zipper.right(zipper)

      assert {:ok, zipper} =
               Function.move_to_function_call_in_current_scope(zipper, :use, 2)

      assert Sourceror.to_string(zipper.node) == "use Bar, a: 2"
    end
  end

  test "argument_equals?/3" do
    zipper =
      "config :key, Test"
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    assert Function.argument_equals?(zipper, 0, :key) == true
    assert Function.argument_equals?(zipper, 0, Test) == false

    assert Function.argument_equals?(zipper, 1, :key) == false
    assert Function.argument_equals?(zipper, 1, Test) == true
  end

  describe "function?/3 with :any_named" do
    test "matches named function captures" do
      assert Function.function?(zipper("&foo/1"), :any_named, 1)
      assert Function.function?(zipper("&Foo.bar/2"), :any_named, 2)
      assert Function.function?(zipper("&Foo.bar(&1, &2)"), :any_named, 2)

      refute Function.function?(zipper("&Foo.bar/2"), :any_named, 1)
    end

    test "does not match anonymous functions" do
      refute Function.function?(zipper("fn x -> x end"), :any_named, 1)
    end
  end

  describe "function?/3 with :any" do
    test "matches named function captures" do
      assert Function.function?(zipper("&foo/1"), :any, 1)
      assert Function.function?(zipper("&Foo.bar/2"), :any)
    end

    test "falls back to anonymous functions" do
      assert Function.function?(zipper("fn x -> x end"), :any, 1)
      assert Function.function?(zipper("&(&1 + &2)"), :any, 2)
    end

    test "does not match non functions" do
      refute Function.function?(zipper("foo(1)"), :any)
    end
  end

  describe "function?/3 with piped remote calls" do
    test "only matches the expected arity" do
      assert Function.function?(zipper("&(&1 |> Foo.bar(2))"), :any_named, 2)
      refute Function.function?(zipper("&(&1 |> Foo.bar(2))"), :any_named, 3)
      refute Function.function?(zipper("&(&1 |> Foo.bar(2))"), :any_named, 5)
    end
  end

  defp zipper(code) do
    code
    |> Sourceror.parse_string!()
    |> Sourceror.Zipper.zip()
  end
end
