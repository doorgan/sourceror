defmodule Sourceror.Code.CommonTest do
  alias Sourceror.Code.Common
  alias Sourceror.Zipper
  use ExUnit.Case
  require Sourceror.Code.Function
  import ExUnit.CaptureLog
  doctest Sourceror.Code.Common

  describe "move_to_last/2" do
    test "no matching nodes returns :error" do
      assert :error =
               """
               foo = 1
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Sourceror.Code.Common.move_to_last(&match?({:=, _, [{:bar, _, _}, _]}, &1.node))
    end

    test "move to the last matching node" do
      assert {:ok, zipper} =
               """
               foo = 1
               bar = 1
               foo = 2
               bar = 2
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Sourceror.Code.Common.move_to_last(&match?({:=, _, [{:foo, _, _}, _]}, &1.node))

      assert Sourceror.to_string(zipper.node) == "foo = 2"
    end
  end

  describe "topmost/1" do
    test "escapes subtrees using `within`" do
      """
      [
        [1, 2, 3],
        [4, 5, 6]
      ]
      """
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()
      |> Sourceror.Zipper.down()
      |> Sourceror.Zipper.down()
      |> Sourceror.Code.Common.within(fn zipper ->
        send(self(), {:zipper, Sourceror.Zipper.topmost(zipper)})

        {:ok, zipper}
      end)

      assert_received {:zipper, zipper}

      assert Sourceror.to_string(zipper.node) ==
               String.trim_trailing("""
               [
                 [1, 2, 3],
                 [4, 5, 6]
               ]
               """)
    end
  end

  describe "move_to_cursor_match_in_scope/1" do
    test "escapes subtrees using `within`" do
      pattern = """
      if config_env() == :prod do
        __cursor__()
      end
      """

      assert {:ok, zipper} =
               """
               foo = 10

               bar = 12

               if config_env() == :prod do
                 12
               end
               """
               |> Sourceror.parse_string!()
               |> Sourceror.Zipper.zip()
               |> Sourceror.Code.Common.move_to_cursor_match_in_scope(pattern)

      assert Sourceror.to_string(zipper.node) == "12"
    end
  end

  describe "add_code" do
    test "warns on deprecated placement argument" do
      zipper =
        """
        foo = 1
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      log =
        capture_log(fn ->
          result =
            zipper
            |> Sourceror.Code.Common.add_code("bar = 2", :after)
            |> Sourceror.Zipper.topmost_root()
            |> Sourceror.to_string()

          assert result == "foo = 1\nbar = 2"
        end)

      assert log =~
               "Passing an atom as the third argument to `Sourceror.Code.Common.add_code/3` is deprecated in favor of an options list."
    end

    test "adding multiple blocks" do
      zipper =
        """
        defmodule Foo do
          if foo do
            random = "what"
            url = "url"
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      with {:ok, zipper} <- Sourceror.Code.Module.move_to_defmodule(zipper),
           {:ok, zipper} <- Sourceror.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <-
             Sourceror.Code.Function.move_to_function_call_in_current_scope(zipper, :if, 2),
           {:ok, zipper} <- Sourceror.Code.Common.move_to_do_block(zipper),
           {:ok, zipper} <-
             Sourceror.Code.Function.move_to_function_call(zipper, :=, 2, fn call ->
               Sourceror.Code.Function.argument_matches_pattern?(
                 call,
                 0,
                 {:url, _, ctx} when is_atom(ctx)
               )
             end) do
        assert zipper
               |> Sourceror.Code.Common.add_code("config :app, Foo, url: url")
               |> Sourceror.Zipper.topmost_root()
               |> Sourceror.to_string() ==
                 String.trim_trailing("""
                 defmodule Foo do
                   if foo do
                     random = "what"
                     url = "url"
                     config :app, Foo, url: url
                   end
                 end
                 """)
      else
        _ ->
          flunk("Should not reach this case")
      end
    end
  end

  describe "remove_all_matches" do
    test "removes all matches" do
      source =
        """
        attributes do
          attribute :label, :string, required: true
          attribute :key, :string, :last_arg_seems_to_stick
          attribute :data, :villain
          attribute :key, :string, :another_one_that_sticks
          attribute :data, :villain
        end
        """

      zipper =
        source
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      zipper =
        Sourceror.Code.Common.remove_all_matches(
          zipper,
          fn z ->
            Sourceror.Code.Function.function_call?(z, :attribute, 2) &&
              Sourceror.Code.Function.argument_equals?(z, 1, :villain)
          end
        )

      assert Sourceror.to_string(zipper.node) ==
               """
               attributes do
                 attribute(:label, :string, required: true)
                 attribute(:key, :string, :last_arg_seems_to_stick)
                 attribute(:key, :string, :another_one_that_sticks)
               end
               """
               |> String.trim_trailing()
    end
  end

  describe "update_all_matches" do
    test "code can be replaced" do
      source =
        """
        attributes do
          attribute :label, :string, required: true
          attribute :key, :string, :last_arg_seems_to_stick
          attribute :data, :villain
          attribute :key, :string, :another_one_that_sticks
          attribute :data, :villain
        end
        """

      zipper =
        source
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, zipper} =
        Sourceror.Code.Common.update_all_matches(
          zipper,
          fn z ->
            Sourceror.Code.Function.function_call?(z, :attribute, 2) &&
              Sourceror.Code.Function.argument_equals?(z, 1, :villain)
          end,
          fn zipper ->
            {:ok,
             Zipper.replace(
               zipper,
               quote do
                 testing(:code_insertion)
               end
             )}
          end
        )

      assert Sourceror.to_string(zipper.node) ==
               """
               attributes do
                 attribute(:label, :string, required: true)
                 attribute(:key, :string, :last_arg_seems_to_stick)
                 testing(:code_insertion)
                 attribute(:key, :string, :another_one_that_sticks)
                 testing(:code_insertion)
               end
               """
               |> String.trim_trailing()
    end

    test "code can be replaced with multi line replacement" do
      source =
        """
        listings do
          query %{status: :published, order: "asc sequence"}
          filters([
            [label: :name, filter: "name"],
            [label: :status, filter: "status"]
          ])
        end
        """

      zipper =
        source
        |> Sourceror.parse_string!()
        |> Zipper.zip()

      {:ok, zipper} =
        Sourceror.Code.Common.update_all_matches(
          zipper,
          fn z ->
            Sourceror.Code.Function.function_call?(z, :filters, 1)
          end,
          fn zipper ->
            {:ok,
             Sourceror.Code.Common.replace_code(
               zipper,
               quote do
                 filter(:status)
                 filter(:order)
               end
             )}
          end
        )

      assert Sourceror.to_string(zipper.node) ==
               """
               listings do
                 query(%{status: :published, order: "asc sequence"})
                 filter(:status)
                 filter(:order)
               end
               """
               |> String.trim_trailing()
    end
  end

  describe "move_right/2" do
    test "moves a zipper to the right until a predicate matches" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()

      assert {:ok, %Zipper{node: {:__block__, _, [3]}}} =
               Common.move_right(zipper, fn
                 %Zipper{node: {:__block__, _, [3]}} -> true
                 _ -> false
               end)
    end

    test "can match the first node tested" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()

      assert {:ok, %Zipper{node: {:__block__, _, [0]}}} =
               Common.move_right(zipper, fn
                 %Zipper{node: {:__block__, _, [0]}} -> true
                 _ -> false
               end)
    end

    test "returns :error if the predicate never matches" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()

      assert Common.move_right(zipper, fn _ -> false end) == :error
    end

    test "moves a zipper to the right a given number of times" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()

      assert {:ok, %Zipper{node: {:__block__, _, [3]}}} = Common.move_right(zipper, 3)
    end

    test "returns :error if zipper cannot be moved right a given number of times" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()

      assert Common.move_right(zipper, 4) == :error
    end
  end

  describe "move_left/2" do
    test "moves a zipper to the left until a predicate matches" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()
        |> Common.rightmost()

      assert {:ok, %Zipper{node: {:__block__, _, [0]}}} =
               Common.move_left(zipper, fn
                 %Zipper{node: {:__block__, _, [0]}} -> true
                 _ -> false
               end)
    end

    test "can match the first node tested" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()
        |> Common.rightmost()

      assert {:ok, %Zipper{node: {:__block__, _, [3]}}} =
               Common.move_left(zipper, fn
                 %Zipper{node: {:__block__, _, [3]}} -> true
                 _ -> false
               end)
    end

    test "returns :error if the predicate never matches" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()
        |> Common.rightmost()

      assert Common.move_left(zipper, fn _ -> false end) == :error
    end

    test "moves a zipper to the left a given number of times" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()
        |> Common.rightmost()

      assert {:ok, %Zipper{node: {:__block__, _, [0]}}} = Common.move_left(zipper, 3)
    end

    test "returns :error if zipper cannot be moved right a given number of times" do
      zipper =
        "[0, 1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.down()
        |> Zipper.down()
        |> Common.rightmost()

      assert Common.move_left(zipper, 4) == :error
    end
  end

  describe "move_upwards/2" do
    test "moves a zipper upwards until a predicate matches" do
      {:ok, zipper} =
        """
        defmodule UpwardsTest do
          @foo 1
          def upwards_test do
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Sourceror.Code.Function.move_to_def(:upwards_test, 0)

      assert {:ok, %Zipper{node: {:defmodule, _, _}}} =
               Common.move_upwards(
                 zipper,
                 &Sourceror.Code.Function.function_call?(&1, :defmodule)
               )
    end

    test "returns :error if the predicate never matches" do
      {:ok, zipper} =
        """
        defmodule UpwardsTest do
          @foo 1
          def upwards_test do
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Sourceror.Code.Function.move_to_def(:upwards_test, 0)

      assert Common.move_upwards(zipper, fn _ -> false end) == :error
    end

    test "moves a zipper upwards a given number of times" do
      {:ok, zipper} =
        """
        defmodule UpwardsTest do
          @foo 1
          def upwards_test do
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Sourceror.Code.Function.move_to_function_call(:def, 2)

      assert {:ok, %Zipper{node: {:defmodule, _, _}}} = Common.move_upwards(zipper, 4)
    end

    test "returns :error if zipper cannot be moved up a given number of times" do
      {:ok, zipper} =
        """
        defmodule UpwardsTest do
          @foo 1
          def upwards_test do
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Sourceror.Code.Function.move_to_function_call(:def, 2)

      assert Common.move_upwards(zipper, 5) == :error
    end
  end

  describe "replace_code/2" do
    test "replaces simple values" do
      zipper =
        "[1, 2, 3]"
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.search_pattern("2")
        |> Common.replace_code(":replaced")

      expected = "[1, :replaced, 3]"

      replaced = Common.replace_code(zipper, ":replaced")
      refute replaced.supertree
      assert {:__block__, _, [:replaced]} = replaced.node
      assert expected == replaced |> Zipper.topmost_root() |> Sourceror.to_string()

      subtree_replaced = zipper |> Zipper.subtree() |> Common.replace_code(":replaced")
      assert subtree_replaced.supertree
      assert {:__block__, _, [:replaced]} = subtree_replaced.node
      assert expected == subtree_replaced |> Zipper.topmost_root() |> Sourceror.to_string()
    end

    test "replaces in blocks" do
      zipper =
        """
        block do
          one()
          two()
          three()
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.search_pattern("two()")

      expected = """
      block do
        one()
        replaced()
        three()
      end\
      """

      replaced = Common.replace_code(zipper, "replaced()")
      refute replaced.supertree
      assert {:replaced, _, []} = replaced.node
      assert expected == replaced |> Zipper.topmost_root() |> Sourceror.to_string()

      subtree_replaced = zipper |> Zipper.subtree() |> Common.replace_code("replaced()")
      assert subtree_replaced.supertree
      assert {:replaced, _, []} = subtree_replaced.node
      assert expected == subtree_replaced |> Zipper.topmost_root() |> Sourceror.to_string()
    end

    test "extends in blocks" do
      zipper =
        """
        block do
          one()
          two()
          three()
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.search_pattern("two()")

      expected =
        """
        block do
          one()
          replaced1()
          replaced2()
          three()
        end\
        """

      replaced = zipper |> Common.replace_code("replaced1()\nreplaced2()\n")
      refute replaced.supertree
      assert {:replaced1, _, []} = replaced.node
      assert expected == replaced |> Zipper.topmost_root() |> Sourceror.to_string()

      subtree_replaced =
        zipper |> Zipper.subtree() |> Common.replace_code("replaced1()\nreplaced2()\n")

      assert subtree_replaced.supertree
      assert {:replaced1, _, []} = replaced.node
      assert expected == subtree_replaced |> Zipper.topmost_root() |> Sourceror.to_string()
    end

    test "keeps newlines" do
      zipper =
        """
        block do
          one()

          two()
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.search_pattern("one()")

      expected =
        """
        block do
          replaced1()
          replaced2()

          two()
        end\
        """

      replaced = zipper |> Common.replace_code("replaced1()\nreplaced2()\n")
      refute replaced.supertree
      assert {:replaced1, _, []} = replaced.node
      assert expected == replaced |> Zipper.topmost_root() |> Sourceror.to_string()

      subtree_replaced =
        zipper |> Zipper.subtree() |> Common.replace_code("replaced1()\nreplaced2()\n")

      assert subtree_replaced.supertree
      assert {:replaced1, _, []} = replaced.node
      assert expected == subtree_replaced |> Zipper.topmost_root() |> Sourceror.to_string()
    end

    test "handles comments" do
      zipper =
        """
        block do
          one()
        end
        """
        |> Sourceror.parse_string!()
        |> Zipper.zip()
        |> Zipper.search_pattern("one()")

      expected =
        """
        block do
          # commented()
          nil
        end
        """
        |> String.trim_trailing()

      replaced = Common.replace_code(zipper, "# commented()")
      refute replaced.supertree
      assert expected == replaced |> Zipper.topmost_root() |> Sourceror.to_string()

      subtree_replaced = zipper |> Zipper.subtree() |> Common.replace_code("# commented()")

      assert subtree_replaced.supertree
      assert expected == subtree_replaced |> Zipper.topmost_root() |> Sourceror.to_string()
    end
  end

  describe "rightmost/1" do
    test "moves the zipper to the right most node with one element" do
      {:ok, zipper} =
        """
        defmodule RightmostTest do
          def foo do
            [a: 1, b: 2]
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()
        |> Sourceror.Code.Function.move_to_def(:foo, 0)

      zipper = zipper |> Zipper.down() |> Sourceror.Code.Common.rightmost()

      assert Sourceror.to_string(zipper.node) == "[a: 1, b: 2]"
    end

    test "moves the zipper to the right most node with multiple elements" do
      {:ok, zipper} =
        """
        defmodule RightmostTest do
          def foo do
            opts = %{}

            [a: 1, b: 2]
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()
        |> Sourceror.Code.Function.move_to_def(:foo, 0)

      zipper = zipper |> Zipper.down() |> Sourceror.Code.Common.rightmost()

      assert Sourceror.to_string(zipper.node) == "[a: 1, b: 2]"
    end
  end
end
