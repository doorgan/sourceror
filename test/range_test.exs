defmodule SourcerorTest.RangeTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Range

  import SourcerorTest.RangeSupport, only: [decorate: 2]

  alias SourcerorTest.Support.Corpus

  defp to_range(string, opts \\ []) do
    string
    |> Sourceror.parse_string!()
    |> Sourceror.Range.get_range(opts)
  end

  describe "get_range/1" do
    test "with comments" do
      code = ~S"""
      # Foo
      :bar
      """

      assert decorate(code, to_range(code)) ==
               """
               # Foo
               «:bar»
               """
               |> String.trim_trailing()

      assert decorate(code, to_range(code, include_comments: true)) ==
               """
               «# Foo
               :bar»
               """
               |> String.trim_trailing()

      code = ~S"""
      # Foo
      # Bar
      :baz
      """

      assert decorate(code, to_range(code)) ==
               """
               # Foo
               # Bar
               «:baz»
               """
               |> String.trim_trailing()

      assert decorate(code, to_range(code, include_comments: true)) ==
               """
               «# Foo
               # Bar
               :baz»
               """
               |> String.trim_trailing()

      code = ~S"""
      :baz # Foo
      """

      assert decorate(code, to_range(code)) ==
               """
               «:baz» # Foo
               """
               |> String.trim_trailing()

      assert decorate(code, to_range(code, include_comments: true)) ==
               """
               «:baz # Foo»
               """
               |> String.trim_trailing()

      code = ~S"""
      # Foo
      :baz # Bar
      """

      assert decorate(code, to_range(code)) ==
               """
               # Foo
               «:baz» # Bar
               """
               |> String.trim_trailing()

      assert decorate(code, to_range(code, include_comments: true)) ==
               """
               «# Foo
               :baz # Bar»
               """
               |> String.trim_trailing()
    end

    test "numbers" do
      code = "1"
      assert decorate(code, to_range(code)) == "«1»"
      code = "100"
      assert decorate(code, to_range(code)) == "«100»"
      code = "1_000"
      assert decorate(code, to_range(code)) == "«1_000»"

      code = "1.0"
      assert decorate(code, to_range(code)) == "«1.0»"
      code = "1.00"
      assert decorate(code, to_range(code)) == "«1.00»"
      code = "1_000.0"
      assert decorate(code, to_range(code)) == "«1_000.0»"
    end

    test "strings" do
      code = ~S/"foo"/
      assert decorate(code, to_range(code)) == "«\"foo\"»"
      code = ~S/"fo\no"/
      assert decorate(code, to_range(code)) == "«\"fo\\no\"»"

      code = ~S/"key: \"value\""/
      assert decorate(code, to_range(code)) == "«\"key: \\\"value\\\"\"»"

      code = ~S'''
      """
      foo

      bar
      """
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «"""
               foo

               bar
               """»
               '''
               |> String.trim_trailing()

      code = ~S'''
        """
        foo
        bar
        """
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
                 «"""
                 foo
                 bar
                 """»
               '''
               |> String.trim_trailing()
    end

    test "strings with interpolations" do
      code = ~S/"foo#{2}bar"/
      assert decorate(code, to_range(code)) == ~S/«"foo#{2}bar"»/

      code = ~S'''
      "foo#{
        2
        }bar"
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «"foo#{
                 2
                 }bar"»
               '''
               |> String.trim_trailing()

      code = ~S'''
      "foo#{
        2
        }
        bar"
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «"foo#{
                 2
                 }
                 bar"»
               '''
               |> String.trim_trailing()

      code = ~S'''
      "foo#{
        2
        }
        bar
      "
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «"foo#{
                 2
                 }
                 bar
               "»
               '''
               |> String.trim_trailing()
    end

    test "child of string with interpolations" do
      code = ~S"""
      "foo#{
        2
        }bar"
      """

      string =
        code
        |> Sourceror.parse_string!()
        |> Sourceror.Zipper.zip()

      interpolation =
        string |> Sourceror.Zipper.down() |> Sourceror.Zipper.right() |> Sourceror.Zipper.node()

      assert decorate(code, Sourceror.get_range(interpolation)) ==
               ~S"""
               "foo«#{
                 2
                 }»bar"
               """
               |> String.trim_trailing()
    end

    test "charlists" do
      code = ~S/'foo'/
      assert decorate(code, to_range(code)) == "«'foo'»"
      code = ~S/'fo\no'/
      assert decorate(code, to_range(code)) == "«'fo\\no'»"

      code = ~S"""
      '''
      foo

      bar
      '''
      """

      assert decorate(code, to_range(code)) ==
               ~S"""
               «'''
               foo

               bar
               '''»
               """
               |> String.trim_trailing()

      code = ~S"""
        '''
        foo
        bar
        '''
      """

      assert decorate(code, to_range(code)) ==
               ~S"""
                 «'''
                 foo
                 bar
                 '''»
               """
               |> String.trim_trailing()
    end

    test "charlists with interpolations" do
      code = ~S/'foo#{2}bar'/
      assert decorate(code, to_range(code)) == ~S/«'foo#{2}bar'»/

      code = ~S"""
      'foo#{
        2
        }bar'
      """

      assert decorate(code, to_range(code)) ==
               ~S"""
               «'foo#{
                 2
                 }bar'»
               """
               |> String.trim_trailing()

      code = ~S"""
      'foo#{
        2
        }
        bar'
      """

      assert decorate(code, to_range(code)) ==
               ~S"""
               «'foo#{
                 2
                 }
                 bar'»
               """
               |> String.trim_trailing()

      code = ~S"""
      'foo#{
        2
        }
        bar
      '
      """

      assert decorate(code, to_range(code)) ==
               ~S"""
               «'foo#{
                 2
                 }
                 bar
               '»
               """
               |> String.trim_trailing()
    end

    test "atoms" do
      code = ~S/:foo/
      assert decorate(code, to_range(code)) == "«:foo»"
      code = ~S/:"foo"/
      assert decorate(code, to_range(code)) == "«:\"foo\"»"
      code = ~S/:'foo'/
      assert decorate(code, to_range(code)) == "«:'foo'»"
      code = ~S/:"::"/
      assert decorate(code, to_range(code)) == "«:\"::\"»"

      code = ~S'''
      :"foo

      bar"
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «:"foo

               bar"»
               '''
               |> String.trim_trailing()
    end

    test "atoms with interpolations" do
      code = ~S/:"foo#{2}bar"/
      assert decorate(code, to_range(code)) == ~S/«:"foo#{2}bar"»/

      code = ~S'''
      :"foo#{
        2
        }bar"
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «:"foo#{
                 2
                 }bar"»
               '''
               |> String.trim_trailing()

      code = ~S'''
      :"foo#{
        2
        }
      bar"
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «:"foo#{
                 2
                 }
               bar"»
               '''
               |> String.trim_trailing()
    end

    test "variables" do
      code = ~S/foo/
      assert decorate(code, to_range(code)) == "«foo»"
    end

    test "tuples" do
      code = ~S/{1, 2, 3}/
      assert decorate(code, to_range(code)) == "«{1, 2, 3}»"

      code = ~S"""
      {
        1,
        2,
        3
      }
      """

      assert decorate(code, to_range(code)) ==
               """
               «{
                 1,
                 2,
                 3
               }»
               """
               |> String.trim_trailing()

      code = ~S"""
      {1,
       2,
         3}
      """

      assert decorate(code, to_range(code)) ==
               """
               «{1,
                2,
                  3}»
               """
               |> String.trim_trailing()
    end

    test "2-tuples from keyword lists" do
      code = ~S"[foo: :bar]"
      {_, _, [[tuple]]} = Sourceror.parse_string!(code)

      range = Sourceror.Range.get_range(tuple)
      assert decorate(code, range) == ~S"[«foo: :bar»]"
    end

    test "2-tuples from partial keyword lists" do
      alias Sourceror.Zipper, as: Z

      code = ~S"""
      config :my_app, :some_key,
        a: b
      """

      value =
        code
        |> Sourceror.parse_string!()
        |> Z.zip()
        |> Z.down()
        |> Z.rightmost()
        |> Z.node()

      range = Sourceror.Range.get_range(value)

      assert decorate(code, range) ==
               ~S"""
               config :my_app, :some_key,
                 «a: b»
               """
               |> String.trim_trailing()

      code = ~S"""
      config :my_app, :some_key,
        a: b,
        c:
          d
      """

      value =
        code
        |> Sourceror.parse_string!()
        |> Z.zip()
        |> Z.down()
        |> Z.rightmost()
        |> Z.node()

      range = Sourceror.Range.get_range(value)

      assert decorate(code, range) ==
               ~S"""
               config :my_app, :some_key,
                 «a: b,
                 c:
                   d»
               """
               |> String.trim_trailing()
    end

    test "do/end blocks that also have :end_of_expression" do
      alias Sourceror.Zipper, as: Z

      code = ~S"""
      foo do
        x ->
          bar do
            a -> b
            c, d -> e
          end

        :foo
      end
      """

      value =
        code
        |> Sourceror.parse_string!()
        |> Z.zip()
        |> Z.find(fn
          {:bar, _, _} -> true
          _ -> false
        end)
        |> Z.node()

      range = Sourceror.Range.get_range(value)

      assert decorate(code, range) ==
               ~S"""
               foo do
                 x ->
                   «bar do
                     a -> b
                     c, d -> e
                   end»

                 :foo
               end
               """
               |> String.trim_trailing()
    end

    test "stabs" do
      alias Sourceror.Zipper, as: Z

      code = ~S"""
      case do
        a -> b
        c, d -> e
      end
      """

      [{_, stabs}] =
        code
        |> Sourceror.parse_string!()
        |> Z.zip()
        |> Z.down()
        |> Z.node()

      range = Sourceror.Range.get_range(stabs)

      assert decorate(code, range) ==
               ~S"""
               case do
                 «a -> b
                 c, d -> e»
               end
               """
               |> String.trim_trailing()
    end

    test "stab without args" do
      code = ~S"fn -> :ok end"
      {:fn, _, [stab]} = Sourceror.parse_string!(code)

      range = Sourceror.Range.get_range(stab)
      assert decorate(code, range) == "fn «-> :ok» end"

      code = ~S"""
      fn ->
        :ok
      end
      """

      {:fn, _, [stab]} = Sourceror.parse_string!(code)

      range = Sourceror.Range.get_range(stab)

      assert decorate(code, range) ==
               """
               fn «->
                 :ok»
               end
               """
               |> String.trim()
    end

    test "stab without body" do
      code = ~S"fn -> end"
      {:fn, _, [stab]} = Sourceror.parse_string!(code)

      range = Sourceror.Range.get_range(stab)
      assert decorate(code, range) == "fn «->» end"

      code = ~S"""
      fn a ->
      end
      """

      {:fn, _, [stab]} = Sourceror.parse_string!(code)

      range = Sourceror.Range.get_range(stab)

      assert decorate(code, range) ==
               """
               fn «a ->»
               end
               """
               |> String.trim()
    end

    test "anonymous functions" do
      code = ~S"fn -> :ok end"
      assert decorate(code, to_range(code)) == "«fn -> :ok end»"

      code = ~S"""
      fn ->
        :ok
      end
      """

      assert decorate(code, to_range(code)) ==
               """
               «fn ->
                 :ok
               end»
               """
               |> String.trim()

      code = ~S"""
      fn -> end
      """

      assert decorate(code, to_range(code)) ==
               """
               «fn -> end»
               """
               |> String.trim()

      code = ~S"""
      fn ->
      end
      """

      assert decorate(code, to_range(code)) ==
               """
               «fn ->
               end»
               """
               |> String.trim()
    end

    test "qualified tuples" do
      code = ~S/Foo.{Bar, Baz}/
      assert decorate(code, to_range(code)) == "«Foo.{Bar, Baz}»"

      code = ~S"""
      Foo.{
        Bar,
        Bar,
        Qux
      }
      """

      assert decorate(code, to_range(code)) ==
               """
               «Foo.{
                 Bar,
                 Bar,
                 Qux
               }»
               """
               |> String.trim_trailing()

      code = ~S"""
      Foo.{Bar,
       Baz,
         Qux}
      """

      assert decorate(code, to_range(code)) ==
               """
               «Foo.{Bar,
                Baz,
                  Qux}»
               """
               |> String.trim_trailing()
    end

    test "lists" do
      code = ~S/[1, 2, 3]/
      assert decorate(code, to_range(code)) == "«[1, 2, 3]»"

      code = ~S"""
      [
        1,
        2,
        3
      ]
      """

      assert decorate(code, to_range(code)) ==
               """
               «[
                 1,
                 2,
                 3
               ]»
               """
               |> String.trim_trailing()

      code = ~S"""
      [1,
       2,
         3]
      """

      assert decorate(code, to_range(code)) ==
               """
               «[1,
                2,
                  3]»
               """
               |> String.trim_trailing()
    end

    test "keyword blocks" do
      code = ~S/foo do :ok end/
      assert decorate(code, to_range(code)) == "«foo do :ok end»"

      code = ~S"""
      foo do
        :ok
      end
      """

      assert decorate(code, to_range(code)) ==
               """
               «foo do
                 :ok
               end»
               """
               |> String.trim()
    end

    test "blocks with parens" do
      code = ~S/(1; 2; 3)/
      assert decorate(code, to_range(code)) == "«(1; 2; 3)»"

      code = ~S"""
      (1;
        2;
        3)
      """

      assert decorate(code, to_range(code)) ==
               """
               «(1;
                 2;
                 3)»
               """
               |> String.trim_trailing()

      code = ~S"""
      (1;
        2;
        3
      )
      """

      assert decorate(code, to_range(code)) ==
               """
               «(1;
                 2;
                 3
               )»
               """
               |> String.trim_trailing()
    end

    test "qualified calls" do
      code = ~S/foo.bar/
      assert decorate(code, to_range(code)) == "«foo.bar»"

      code = ~S/foo.bar()/
      assert decorate(code, to_range(code)) == "«foo.bar()»"

      code = ~S/foo.()/
      assert decorate(code, to_range(code)) == "«foo.()»"

      code = ~S/foo.bar.()/
      assert decorate(code, to_range(code)) == "«foo.bar.()»"

      code = ~s/foo.bar(\n)/
      assert decorate(code, to_range(code)) == "«foo.bar(\n)»"

      code = ~s/foo.bar.(\n)/
      assert decorate(code, to_range(code)) == "«foo.bar.(\n)»"

      code = ~S/a.b.c/
      assert decorate(code, to_range(code)) == "«a.b.c»"

      code = ~S/foo.bar(baz)/
      assert decorate(code, to_range(code)) == "«foo.bar(baz)»"

      code = ~S/foo.bar.(baz)/
      assert decorate(code, to_range(code)) == "«foo.bar.(baz)»"

      code = ~s/foo.bar.(\nbaz)/
      assert decorate(code, to_range(code)) == "«foo.bar.(\nbaz)»"

      code = ~S/foo.bar("baz#{2}qux")/
      assert decorate(code, to_range(code)) == ~S"«foo.bar(\"baz#{2}qux\")»"

      code = ~S/foo.bar("baz#{2}qux", [])/
      assert decorate(code, to_range(code)) == ~S"«foo.bar(\"baz#{2}qux\", [])»"

      code = ~S/foo."b-a-r"/
      assert decorate(code, to_range(code)) == "«foo.\"b-a-r\"»"

      code = ~S/foo."b-a-r"()/
      assert decorate(code, to_range(code)) == "«foo.\"b-a-r\"()»"

      code = ~S/foo."b-a-r"(1)/
      assert decorate(code, to_range(code)) == "«foo.\"b-a-r\"(1)»"
    end

    test "qualified calls without parens" do
      code = ~S/foo.bar baz/
      assert decorate(code, to_range(code)) == "«foo.bar baz»"

      code = ~S/foo.bar baz, qux/
      assert decorate(code, to_range(code)) == "«foo.bar baz, qux»"

      code = ~S/foo."b-a-r" baz/
      assert decorate(code, to_range(code)) == "«foo.\"b-a-r\" baz»"
    end

    test "unqualified calls" do
      code = ~S/foo(bar)/
      assert decorate(code, to_range(code)) == "«foo(bar)»"

      code = ~S"""
      foo(
        bar
        )
      """

      assert decorate(code, to_range(code)) ==
               """
               «foo(
                 bar
                 )»
               """
               |> String.trim_trailing()
    end

    test "unqualified calls without parens" do
      code = ~S/foo bar/
      assert decorate(code, to_range(code)) == "«foo bar»"

      code = ~S/foo bar baz/
      assert decorate(code, to_range(code)) == "«foo bar baz»"

      code = ~s/foo\n  bar/
      assert decorate(code, to_range(code)) == "«foo\n  bar»"

      code = ~S/Foo.bar/
      assert decorate(code, to_range(code)) == "«Foo.bar»"

      code = ~s/Foo.\n  bar/
      assert decorate(code, to_range(code)) == "«Foo.\n  bar»"
    end

    test "unqualified double calls" do
      code = ~S/unquote(foo)()/
      assert decorate(code, to_range(code)) == "«unquote(foo)()»"
    end

    test "module aliases" do
      code = ~S/Foo/
      assert decorate(code, to_range(code)) == "«Foo»"

      code = ~S/Foo.Bar/
      assert decorate(code, to_range(code)) == "«Foo.Bar»"

      code = ~s/Foo.\n  Bar/
      assert decorate(code, to_range(code)) == "«Foo.\n  Bar»"

      code = ~s/__MODULE__/
      assert decorate(code, to_range(code)) == "«__MODULE__»"

      code = ~s/__MODULE__.Bar/
      assert decorate(code, to_range(code)) == "«__MODULE__.Bar»"

      code = ~s/@foo.Bar/
      assert decorate(code, to_range(code)) == "«@foo.Bar»"

      code = ~s/foo().Bar/
      assert decorate(code, to_range(code)) == "«foo().Bar»"

      code = ~s/foo.bar.().Baz/
      assert decorate(code, to_range(code)) == "«foo.bar.().Baz»"
    end

    test "unary operators" do
      code = ~S/!foo/
      assert decorate(code, to_range(code)) == "«!foo»"

      code = ~S/!   foo/
      assert decorate(code, to_range(code)) == "«!   foo»"

      code = ~S/not  foo/
      assert decorate(code, to_range(code)) == "«not  foo»"

      code = ~S/@foo/
      assert decorate(code, to_range(code)) == "«@foo»"

      code = ~S/@   foo/
      assert decorate(code, to_range(code)) == "«@   foo»"
    end

    test "binary operators" do
      code = ~S/1 + 1/
      assert decorate(code, to_range(code)) == "«1 + 1»"

      code = ~S/foo when bar/
      assert decorate(code, to_range(code)) == "«foo when bar»"

      code = ~S"""
       5 +
          10
      """

      assert decorate(code, to_range(code)) ==
               """
                «5 +
                   10»
               """
               |> String.trim_trailing()

      code = ~S/foo |> bar/
      assert decorate(code, to_range(code)) == "«foo |> bar»"

      code = ~S"""
      foo
      |> bar
      """

      assert decorate(code, to_range(code)) ==
               """
               «foo
               |> bar»
               """
               |> String.trim_trailing()

      code = ~S"""
      foo
      |>
      bar
      """

      assert decorate(code, to_range(code)) ==
               """
               «foo
               |>
               bar»
               """
               |> String.trim_trailing()
    end

    test "ranges" do
      code = ~S[1..2]
      assert decorate(code, to_range(code)) == "«1..2»"

      code = ~S[1..2//3]
      assert decorate(code, to_range(code)) == "«1..2//3»"

      code = ~S[foo..bar//baz]
      assert decorate(code, to_range(code)) == "«foo..bar//baz»"
    end

    test "bitstrings" do
      code = ~S[<<1, 2, foo>>]
      assert decorate(code, to_range(code)) == "«<<1, 2, foo>>»"

      code = ~S"""
      <<1, 2,

       foo>>
      """

      assert decorate(code, to_range(code)) ==
               """
               «<<1, 2,

                foo>>»
               """
               |> String.trim_trailing()
    end

    test "sigils" do
      code = ~S/~s[foo bar]/
      assert decorate(code, to_range(code)) == "«~s[foo bar]»"

      code = ~S'''
      ~s"""
      foo
      bar
      """
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «~s"""
               foo
               bar
               """»
               '''
               |> String.trim_trailing()
    end

    test "sigils with interpolations" do
      code = ~S/~s[foo#{2}bar]/
      assert decorate(code, to_range(code)) == ~S/«~s[foo#{2}bar]»/

      code = ~S/~s[foo#{2}bar]abc/
      assert decorate(code, to_range(code)) == ~S/«~s[foo#{2}bar]abc»/

      code = ~S'''
      ~s"""
      foo#{10
       }
      bar
      """
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «~s"""
               foo#{10
                }
               bar
               """»
               '''
               |> String.trim_trailing()

      code = ~S'''
      ~s"""
      foo#{10
       }bar
      """abc
      '''

      assert decorate(code, to_range(code)) ==
               ~S'''
               «~s"""
               foo#{10
                }bar
               """abc»
               '''
               |> String.trim_trailing()
    end

    test "captures" do
      code = ~S"&foo/1"
      assert decorate(code, to_range(code)) == "«&foo/1»"

      code = ~S"&Foo.bar/1"
      assert decorate(code, to_range(code)) == "«&Foo.bar/1»"

      code = ~S"&__MODULE__.Foo.bar/1"
      assert decorate(code, to_range(code)) == "«&__MODULE__.Foo.bar/1»"
    end

    test "captures with arguments" do
      code = ~S"&foo(&1, :bar)"
      assert decorate(code, to_range(code)) == "«&foo(&1, :bar)»"

      code = ~S"& &1.foo"
      assert decorate(code, to_range(code)) == "«& &1.foo»"

      code = ~S"& &1"
      assert decorate(code, to_range(code)) == "«& &1»"

      # This range currently ends on column 5, though it should be column 6,
      # and appears to be a limitation of the parser, which does not include
      # any metadata about the parens. That is, this currently holds:
      #
      #     Sourceror.parse_string!("& &1") == Sourceror.parse_string!("&(&1)")
      #
      # assert to_range(~S"&(&1)") == %{
      #          start: [line: 1, column: 1],
      #          end: [line: 1, column: 6]
      #        }
    end

    test "arguments in captures" do
      code = ~S"& &1"
      {:&, _, [{:&, _, _} = arg]} = Sourceror.parse_string!(code)

      range = Sourceror.Range.get_range(arg)
      assert decorate(code, range) == "& «&1»"
    end

    test "Access syntax" do
      code = ~S"foo[bar]"
      assert decorate(code, to_range(code)) == "«foo[bar]»"

      code = ~S"foo[bar]"
      {{:., _, [Access, :get]} = access, _, _} = Sourceror.parse_string!(code)

      range = Sourceror.Range.get_range(access)
      assert decorate(code, range) == "foo«[bar]»"
    end

    test "should never raise" do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Corpus.walk!(fn quoted, path ->
          try do
            Sourceror.get_range(quoted)
          rescue
            e ->
              flunk("""
              Expected a range from expression (#{path}):

                  #{inspect(quoted)}

              Got error:

                  #{Exception.format(:error, e)}
              """)
          end
        end)
      end)
    end
  end
end
