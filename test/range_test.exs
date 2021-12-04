defmodule SourcerorTest.RangeTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Range

  defp to_range(string, opts \\ []) do
    string
    |> Sourceror.parse_string!()
    |> Sourceror.Range.get_range(opts)
  end

  describe "get_range/1" do
    test "with comments" do
      assert to_range(~S"""
             # Foo
             :bar
             """) == %{start: [line: 2, column: 1], end: [line: 2, column: 5]}

      assert to_range(
               ~S"""
               # Foo
               :bar
               """,
               include_comments: true
             ) == %{start: [line: 1, column: 1], end: [line: 2, column: 5]}

      assert to_range(~S"""
             # Foo
             # Bar
             :baz
             """) == %{start: [line: 3, column: 1], end: [line: 3, column: 5]}

      assert to_range(
               ~S"""
               # Foo
               # Bar
               :baz
               """,
               include_comments: true
             ) == %{start: [line: 1, column: 1], end: [line: 3, column: 5]}

      assert to_range(~S"""
             :baz # Foo
             """) == %{start: [line: 1, column: 1], end: [line: 1, column: 5]}

      assert to_range(
               ~S"""
               :baz # Foo
               """,
               include_comments: true
             ) == %{start: [line: 1, column: 1], end: [line: 1, column: 11]}

      assert to_range(~S"""
             # Foo
             :baz # Bar
             """) == %{start: [line: 2, column: 1], end: [line: 2, column: 5]}

      assert to_range(
               ~S"""
               # Foo
               :baz # Bar
               """,
               include_comments: true
             ) == %{start: [line: 1, column: 1], end: [line: 2, column: 11]}
    end

    test "numbers" do
      assert to_range("1") == %{start: [line: 1, column: 1], end: [line: 1, column: 2]}
      assert to_range("100") == %{start: [line: 1, column: 1], end: [line: 1, column: 4]}
      assert to_range("1_000") == %{start: [line: 1, column: 1], end: [line: 1, column: 6]}

      assert to_range("1.0") == %{start: [line: 1, column: 1], end: [line: 1, column: 4]}
      assert to_range("1.00") == %{start: [line: 1, column: 1], end: [line: 1, column: 5]}
      assert to_range("1_000.0") == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}
    end

    test "strings" do
      assert to_range(~S/"foo"/) == %{start: [line: 1, column: 1], end: [line: 1, column: 6]}
      assert to_range(~S/"fo\no"/) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}

      assert to_range(~S'''
             """
             foo

             bar
             """
             ''') == %{start: [line: 1, column: 1], end: [line: 5, column: 4]}

      assert to_range(~S'''
               """
               foo
               bar
               """
             ''') == %{start: [line: 1, column: 3], end: [line: 4, column: 6]}
    end

    test "strings with interpolations" do
      assert to_range(~S/"foo#{2}bar"/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 13]
             }

      assert to_range(~S'''
             "foo#{
               2
               }bar"
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 3, column: 8]
             }

      assert to_range(~S'''
             "foo#{
               2
               }
               bar"
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 4, column: 7]
             }

      assert to_range(~S'''
             "foo#{
               2
               }
               bar
             "
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 5, column: 2]
             }
    end

    test "atoms" do
      assert to_range(~S/:foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 5]}
      assert to_range(~S/:"foo"/) == %{start: [line: 1, column: 1], end: [line: 1, column: 7]}
      assert to_range(~S/:'foo'/) == %{start: [line: 1, column: 1], end: [line: 1, column: 7]}
      assert to_range(~S/:"::"/) == %{start: [line: 1, column: 1], end: [line: 1, column: 6]}

      assert to_range(~S'''
             :"foo

             bar"
             ''') == %{start: [line: 1, column: 1], end: [line: 3, column: 5]}
    end

    test "atoms with interpolations" do
      assert to_range(~S/:"foo#{2}bar"/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 14]
             }

      assert to_range(~S'''
             :"foo#{
               2
               }bar"
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 3, column: 8]
             }

      assert to_range(~S'''
             :"foo#{
               2
               }
             bar"
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 4, column: 5]
             }
    end

    test "variables" do
      assert to_range(~S/foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 4]}
    end

    test "tuples" do
      assert to_range(~S/{1, 2, 3}/) == %{start: [line: 1, column: 1], end: [line: 1, column: 10]}

      assert to_range(~S"""
             {
               1,
               2,
               3
             }
             """) == %{start: [line: 1, column: 1], end: [line: 5, column: 2]}

      assert to_range(~S"""
             {1,
              2,
                3}
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 6]}
    end

    test "2-tuples from keyword lists" do
      {_, _, [[tuple]]} = Sourceror.parse_string!(~S/[foo: :bar]/)

      assert Sourceror.Range.get_range(tuple) == %{
               start: [line: 1, column: 2],
               end: [line: 1, column: 11]
             }
    end

    test "2-tuples from partial keyword lists" do
      alias Sourceror.Zipper, as: Z

      value =
        Sourceror.parse_string!(~S"""
        config :my_app, :some_key,
          a: b
        """)
        |> Z.zip()
        |> Z.down()
        |> Z.rightmost()
        |> Z.node()

      assert Sourceror.Range.get_range(value) == %{
               start: [line: 2, column: 3],
               end: [line: 2, column: 7]
             }

      value =
        Sourceror.parse_string!(~S"""
        config :my_app, :some_key,
          a: b,
          c:
            d
        """)
        |> Z.zip()
        |> Z.down()
        |> Z.rightmost()
        |> Z.node()

      assert Sourceror.Range.get_range(value) == %{
               start: [line: 2, column: 3],
               end: [line: 4, column: 6]
             }
    end

    test "stabs" do
      alias Sourceror.Zipper, as: Z

      [{_, stabs}] =
        Sourceror.parse_string!(~S"""
        case do
          a -> b
          c, d -> e
        end
        """)
        |> Z.zip()
        |> Z.down()
        |> Z.node()

      assert Sourceror.Range.get_range(stabs) == %{
               start: [line: 2, column: 3],
               end: [line: 3, column: 12]
             }
    end

    test "qualified tuples" do
      assert to_range(~S/Foo.{Bar, Baz}/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 15]
             }

      assert to_range(~S"""
             Foo.{
               Bar,
               Bar,
               Qux
             }
             """) == %{start: [line: 1, column: 1], end: [line: 5, column: 2]}

      assert to_range(~S"""
             Foo.{Bar,
              Baz,
                Qux}
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 8]}
    end

    test "lists" do
      assert to_range(~S/[1, 2, 3]/) == %{start: [line: 1, column: 1], end: [line: 1, column: 10]}

      assert to_range(~S"""
             [
               1,
               2,
               3
             ]
             """) == %{start: [line: 1, column: 1], end: [line: 5, column: 2]}

      assert to_range(~S"""
             [1,
              2,
                3]
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 6]}
    end

    test "keyword blocks" do
      assert to_range(~S/foo do :ok end/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 15]
             }

      assert to_range(~S"""
             foo do
               :ok
             end
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 4]}
    end

    test "blocks with parens" do
      assert to_range(~S/(1; 2; 3)/) == %{start: [line: 1, column: 1], end: [line: 1, column: 10]}

      assert to_range(~S"""
             (1;
               2;
               3)
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 5]}

      assert to_range(~S"""
             (1;
               2;
               3
             )
             """) == %{start: [line: 1, column: 1], end: [line: 4, column: 2]}
    end

    test "qualified calls" do
      assert to_range(~S/foo.bar/) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}
      assert to_range(~S/foo.bar()/) == %{start: [line: 1, column: 1], end: [line: 1, column: 10]}

      assert to_range(~s/foo.bar(\n)/) == %{
               start: [line: 1, column: 1],
               end: [line: 2, column: 2]
             }

      assert to_range(~S/a.b.c/) == %{start: [line: 1, column: 1], end: [line: 1, column: 6]}

      assert to_range(~S/foo.bar(baz)/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 13]
             }

      assert to_range(~S/foo.bar("baz#{2}qux")/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 22]
             }

      assert to_range(~S/foo.bar("baz#{2}qux", [])/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 26]
             }
    end

    test "qualified calls without parens" do
      assert to_range(~S/foo.bar baz/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 12]
             }

      assert to_range(~S/foo.bar baz, qux/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 17]
             }
    end

    test "unqualified calls" do
      assert to_range(~S/foo(bar)/) == %{start: [line: 1, column: 1], end: [line: 1, column: 9]}

      assert to_range(~S"""
             foo(
               bar
               )
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 4]}
    end

    test "unqualified calls without parens" do
      assert to_range(~S/foo bar/) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}

      assert to_range(~S/foo bar baz/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 12]
             }

      assert to_range(~s/foo\n  bar/) == %{start: [line: 1, column: 1], end: [line: 2, column: 6]}
      assert to_range(~S/Foo.bar/) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}

      assert to_range(~s/Foo.\n  bar/) == %{
               start: [line: 1, column: 1],
               end: [line: 2, column: 6]
             }
    end

    test "module aliases" do
      assert to_range(~S/Foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 4]}
      assert to_range(~S/Foo.Bar/) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}

      assert to_range(~s/Foo.\n  Bar/) == %{
               start: [line: 1, column: 1],
               end: [line: 2, column: 6]
             }
    end

    test "unary operators" do
      assert to_range(~S/!foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 5]}
      assert to_range(~S/!   foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}
      assert to_range(~S/not  foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 9]}
      assert to_range(~S/@foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 5]}
      assert to_range(~S/@   foo/) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}
    end

    test "binary operators" do
      assert to_range(~S/1 + 1/) == %{start: [line: 1, column: 1], end: [line: 1, column: 6]}

      assert to_range(~S/foo when bar/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 13]
             }

      assert to_range(~S"""
              5 +
                 10
             """) == %{start: [line: 1, column: 2], end: [line: 2, column: 7]}

      assert to_range(~S/foo |> bar/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 11]
             }

      assert to_range(~S"""
             foo
             |> bar
             """) == %{start: [line: 1, column: 1], end: [line: 2, column: 7]}

      assert to_range(~S"""
             foo
             |>
             bar
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 4]}
    end

    test "ranges" do
      assert to_range(~S[1..2]) == %{start: [line: 1, column: 1], end: [line: 1, column: 5]}
      assert to_range(~S[1..2//3]) == %{start: [line: 1, column: 1], end: [line: 1, column: 8]}

      assert to_range(~S[foo..bar//baz]) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 14]
             }
    end

    test "bitstrings" do
      assert to_range(~S[<<1, 2, foo>>]) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 14]
             }

      assert to_range(~S"""
             <<1, 2,

              foo>>
             """) == %{start: [line: 1, column: 1], end: [line: 3, column: 7]}
    end

    test "sigils" do
      assert to_range(~S/~s[foo bar]/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 12]
             }

      assert to_range(~S'''
             ~s"""
             foo
             bar
             """
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 4, column: 4]
             }
    end

    test "sigils with interpolations" do
      assert to_range(~S/~s[foo#{2}bar]/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 15]
             }

      assert to_range(~S/~s[foo#{2}bar]abc/) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 18]
             }

      assert to_range(~S'''
             ~s"""
             foo#{10
              }
             bar
             """
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 5, column: 4]
             }

      assert to_range(~S'''
             ~s"""
             foo#{10
              }bar
             """abc
             ''') == %{
               start: [line: 1, column: 1],
               end: [line: 4, column: 7]
             }
    end
  end
end
