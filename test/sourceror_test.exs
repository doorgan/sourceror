defmodule SourcerorTest do
  use ExUnit.Case, async: true
  doctest Sourceror

  defmacrop assert_same(string, opts \\ []) do
    quote bind_quoted: [string: string, opts: opts] do
      formatted = string |> Code.format_string!([]) |> IO.iodata_to_binary()

      if Version.match?(System.version(), "~> 1.16") do
        assert formatted == String.trim(string), """
        The given expected code is not formatted.
        Formatted code:
        #{formatted}
        """
      end

      assert formatted == Sourceror.parse_string!(string) |> Sourceror.to_string(opts)
    end
  end

  describe "parse_string!/2 and to_string/2 comment position preservation" do
    test "empty string" do
      assert_same("")
    end

    test "just some comments" do
      assert_same(~S"""
      # comment

      # another comment
      """)
    end

    test "blocks" do
      assert_same(~S"""
      foo()

      baz()

      # Bar
      """)

      assert_same(~S"""
      foo()
      # Bar
      """)
    end

    test "do blocks" do
      assert_same(~S"""
      # A
      foo do
        # B
        :ok

        # C
      end

      # D
      """)
    end

    test "qualified tuples" do
      assert_same(~S"""
      # 1
      A.{
        # 2
        B,
        C,
        # 3
        D

        # 4
      }

      # 5
      """)
    end

    test "dot call and do block" do
      assert_same(~S"""
      # 1
      a.b c do
        # 4
        d

        # 5
      end

      # 6
      """)
    end

    test "newlines between comments and function calls" do
      assert_same(~S"""
      # a
      # paragraph

      fun()
      """)
    end

    test "pipelines" do
      # see https://github.com/doorgan/sourceror/issues/27
      assert_same(~S"""
      # a comment for foo
      # a second comment for foo
      foo |> bar.baz(args: 2)

      # comment for function call
      function_call
      # comment for bop
      |> bop()

      # comment for big
      big
      # comment for long
      |> long()
      # comment for chain
      # second comment for chain
      |> chain()
      """)

      assert_same(~S"""
      # a comment
      # a comment for baz
      foo |> baz()
      # comment for bar
      bar
      # comment for bop
      |> bop()
      """)
    end

    test "spacing" do
      assert_same(~S"""
      # a

      # b
      foo = bar()
      """)

      assert_same(~S"""
      # General application configuration
      import Config

      # Use Jason for JSON parsing in Phoenix
      config :phoenix, :json_library, Jason

      # Import environment specific config. This must remain at the bottom
      # of this file so it overrides the configuration defined above.
      import_config "#{config_env()}.exs"
      """)
    end

    test "lists" do
      assert_same(~S"""
      [
        1,
        # a
        # b
        2
      ]
      """)
    end

    test "binary ops" do
      assert_same(~S"""
      # foo
      %{
        a: a
      } = x
      """)
    end

    test "function definitions in large comments" do
      assert_same(~S"""
      # large
      # comment
      # block

      # large
      # comment
      # block

      def request(%S3{http_method: :head} = op), do: head_object(op)

      ###
      ### ListObjectVersions request (see Core.Storage.list_object_versions/2)
      ###

      # A request error
      def request(%S3{http_method: :head} = op), do: head_object(op)
      """)
    end

    test "after expression" do
      code = ~S"""
      bar()
      # test-comment
      foo()
      """

      assert_same(code)
    end

    test "last line in def" do
      code = ~S"""
      def a_fun do
        :return_value
        # test-comment
      end
      """

      assert_same(code)
    end

    test "in directly executed anonymous function" do
      code = ~S"""
      (fn x ->
         # test-comment
         x * x
       end).()
      """

      assert_same(code)
    end

    test "multiple comment blocks" do
      code = ~S"""
      defmodule Z do
        alias B
        alias A

        def a do
          # test1
          # test2
          # line1
          # line2
          :ok
        end

        # test
        defp z do
          1
        end
      end
      """

      assert_same(code)
    end

    test "multiline comments in list" do
      code = ~S"""
      [
        :field_1,

        #######################################################
        ### Another comment
        #######################################################

        :field_2
      ]
      """

      assert_same(code)
    end

    test "with a :do in the args" do
      assert_same("""
      defp foo(state, {:do, :code}) do
        # Lorem ispum
        state
      end
      """)
    end
  end

  describe "parse_string!/2" do
    test "returns an empty block for an emtpy string" do
      assert Sourceror.parse_string!("") == {:__block__, [], []}
    end

    test "raises on invalid string" do
      assert_raise SyntaxError, fn ->
        Sourceror.parse_string!(":ok end")
      end

      assert_raise TokenMissingError, fn ->
        Sourceror.parse_string!("do :ok")
      end
    end
  end

  describe "parse_expression/2" do
    test "parses only the first valid expression" do
      parsed =
        Sourceror.parse_expression(~S"""
        foo do
          :ok
        end

        42
        """)

      assert {:ok, {:foo, _, [[{{_, _, [:do]}, {_, _, [:ok]}}]]}, _} = parsed
    end

    test "does not success on empty strings" do
      assert {:error, _} = Sourceror.parse_expression("")

      assert {:ok, {:__block__, _, [:ok]}, ""} =
               Sourceror.parse_expression(~S"""

               :ok
               """)
    end

    test "parses starting from line" do
      source = ~S"""
      :a
      foo do
        :ok
      end
      :c
      """

      assert {:ok, {_, _, [:a]}, _} = Sourceror.parse_expression(source, from_line: 1)

      assert {:ok, {:foo, _, [[{{_, _, [:do]}, {_, _, [:ok]}}]]}, _} =
               Sourceror.parse_expression(source, from_line: 2)

      assert {:ok, {_, _, [:c]}, _} = Sourceror.parse_expression(source, from_line: 5)
    end
  end

  describe "postwalk/2" do
  end

  describe "to_string/2" do
    test "produces formatted output" do
      source = """
      def foo do :bar end
      """

      expected = Code.format_string!(source) |> IO.iodata_to_binary()
      actual = Sourceror.parse_string!(source) |> Sourceror.to_string()

      assert expected == actual
    end

    test "indents code" do
      source = ~S"""
      def foo do
        :bar
      end
      """

      expected =
        String.trim_trailing(~S"""
          def foo do
            :bar
          end
        """)

      actual =
        source
        |> Sourceror.parse_string!()
        |> Sourceror.to_string(indent: 1)

      assert expected == actual

      expected =
        String.trim_trailing(~S"""
           def foo do
             :bar
           end
        """)

      actual =
        source
        |> Sourceror.parse_string!()
        |> Sourceror.to_string(indent: 3, indent_type: :single_space)

      assert expected == actual

      expected =
        String.trim_trailing("""
        \tdef foo do
        \t  :bar
        \tend
        """)

      actual =
        source
        |> Sourceror.parse_string!()
        |> Sourceror.to_string(indent: 1, indent_type: :tabs)

      assert expected == actual
    end

    test "does not escape characters twice" do
      assert_same(~S'''
      defmodule Sample do
        @moduledoc """
        Documentation for `Sample`.
        """

        @doc """
        Hello world.

        ## Examples

            iex> Sample.hello()
            :world

        """
        def hello do
          :world
        end
      end
      ''')
    end

    test "with format: :splicing" do
      assert "a: b" == Sourceror.to_string([{:a, {:b, [], nil}}], format: :splicing)
      assert "1, 2, 3" == Sourceror.to_string([1, 2, 3], format: :splicing)
      assert "{:foo, :bar}" == Sourceror.to_string({:foo, :bar}, format: :splicing)
    end

    test "last tuple element as keyword list must keep its format" do
      code = ~S({:wrapped, [opt1: true, opt2: false]})
      assert code |> Sourceror.parse_string!() |> Sourceror.to_string() == code

      code = ~S({:unwrapped, opt1: true, opt2: false})
      assert code |> Sourceror.parse_string!() |> Sourceror.to_string() == code
    end

    test "last tuple element as keyword list must keep its format (2-tuples)" do
      code = ~S({:wrapped, 1, [opt1: true, opt2: false]})
      assert code |> Sourceror.parse_string!() |> Sourceror.to_string() == code

      code = ~S({:unwrapped, 1, opt1: true, opt2: false})
      assert code |> Sourceror.parse_string!() |> Sourceror.to_string() == code
    end

    test "supports locals_without_parens" do
      opts = [locals_without_parens: [defparsec: :*]]

      code = ~S"defparsec :do_parse, parser"

      assert code |> Sourceror.parse_string!() |> Sourceror.to_string() ==
               ~S"defparsec(:do_parse, parser)"

      assert code |> Sourceror.parse_string!() |> Sourceror.to_string(opts) == code
    end

    test "with optional quoted_to_algebra" do
      quoted_to_algebra = fn _quoted, opts ->
        assert is_function(opts[:quoted_to_algebra], 2)
        assert opts[:trailing_comma] == true

        {:doc_group,
         {:doc_group,
          {:doc_cons,
           {:doc_nest,
            {:doc_cons, "[",
             {:doc_cons, {:doc_break, "", :strict},
              {:doc_force, {:doc_group, {:doc_cons, "1", ","}, :self}}}}, 2, :break},
           {:doc_cons, {:doc_break, "", :strict}, "]"}}, :self}, :self}
      end

      code = """
      [
        1,
      ]\
      """

      assert code ==
               code
               |> Sourceror.parse_string!()
               |> Sourceror.to_string(
                 quoted_to_algebra: quoted_to_algebra,
                 trailing_comma: true
               )
    end
  end

  describe "correct_lines/2" do
    test "corrects all line fields" do
      assert [line: 2] = Sourceror.correct_lines([line: 1], 1)
      assert [closing: [line: 2]] = Sourceror.correct_lines([closing: [line: 1]], 1)
      assert [do: [line: 2]] = Sourceror.correct_lines([do: [line: 1]], 1)
      assert [end: [line: 2]] = Sourceror.correct_lines([end: [line: 1]], 1)

      assert [end_of_expression: [line: 2]] =
               Sourceror.correct_lines([end_of_expression: [line: 1]], 1)

      assert [
               line: 2,
               closing: [line: 2],
               do: [line: 2],
               end: [line: 2],
               end_of_expression: [line: 2]
             ] =
               Sourceror.correct_lines(
                 [
                   line: 1,
                   closing: [line: 1],
                   do: [line: 1],
                   end: [line: 1],
                   end_of_expression: [line: 1]
                 ],
                 1
               )
    end
  end

  describe "get_start_position/2" do
    test "returns the start position" do
      quoted = Sourceror.parse_string!(" :foo")
      assert Sourceror.get_start_position(quoted) == [line: 1, column: 2]

      quoted = Sourceror.parse_string!("\n\nfoo()")
      assert Sourceror.get_start_position(quoted) == [line: 3, column: 1]

      quoted = Sourceror.parse_string!("Foo.{Bar}")
      assert Sourceror.get_start_position(quoted) == [line: 1, column: 1]

      quoted = Sourceror.parse_string!("foo[:bar]")
      assert Sourceror.get_start_position(quoted) == [line: 1, column: 1]

      quoted = Sourceror.parse_string!("foo(:bar)")
      assert Sourceror.get_start_position(quoted) == [line: 1, column: 1]

      quoted = Sourceror.parse_string!("%{a: 1}")
      assert Sourceror.get_start_position(quoted) == [line: 1, column: 1]
    end
  end

  describe "get_end_position/2" do
    test "returns the correct positions" do
      quoted =
        ~S"""
        A.{
          B
        }
        """
        |> Sourceror.parse_string!()

      assert Sourceror.get_end_position(quoted) == [line: 3, column: 1]

      quoted =
        ~S"""
        foo do
          :ok
        end
        """
        |> Sourceror.parse_string!()

      assert Sourceror.get_end_position(quoted) == [line: 3, column: 1]

      quoted =
        ~S"""
           foo(
             :a,
             :b
           )
        """
        |> Sourceror.parse_string!()

      assert Sourceror.get_end_position(quoted) == [line: 4, column: 4]

      quoted =
        ~S"""
        foo(1)
        foo 1
        foo bar()
        _
        """
        |> Sourceror.parse_string!()

      {_, _, [parens, without_parens, nested, _]} = quoted

      assert Sourceror.get_end_position(parens) == [line: 1, column: 6]
      assert Sourceror.get_end_position(without_parens) == [line: 2, column: 5]
      assert Sourceror.get_end_position(nested) == [line: 3, column: 9]
    end
  end

  describe "compare_positions/2" do
    test "correctly compares positions" do
      assert Sourceror.compare_positions([line: 1, column: 1], line: 1, column: 1) == :eq
      assert Sourceror.compare_positions([line: nil, column: nil], line: nil, column: nil) == :eq
      assert Sourceror.compare_positions([line: 2, column: 1], line: 1, column: 1) == :gt
      assert Sourceror.compare_positions([line: 1, column: 5], line: 1, column: 1) == :gt
      assert Sourceror.compare_positions([line: 1, column: 1], line: 2, column: 1) == :lt
      assert Sourceror.compare_positions([line: 1, column: 1], line: 1, column: 5) == :lt
      assert Sourceror.compare_positions([line: 1, column: 1], line: 2, column: 2) == :lt
    end

    test "nil is strictly less than integers" do
      assert Sourceror.compare_positions([line: nil, column: nil], line: 1, column: 1) == :lt
      assert Sourceror.compare_positions([line: 1, column: 1], line: nil, column: nil) == :gt
    end
  end

  describe "get_range/1" do
    test "returns the correct range" do
      quoted =
        ~S"""
        def foo do
          :ok
        end
        """
        |> Sourceror.parse_string!()

      assert Sourceror.get_range(quoted) == %{
               start: [line: 1, column: 1],
               end: [line: 3, column: 4]
             }

      quoted =
        ~S"""
        Foo.{
          Bar
        }
        """
        |> Sourceror.parse_string!()

      assert Sourceror.get_range(quoted) == %{
               start: [line: 1, column: 1],
               end: [line: 3, column: 2]
             }
    end

    test "returns the correct column for calls with and without parens" do
      quoted =
        ~S"""
        foo(1)
        foo 1
        foo bar()
        _
        """
        |> Sourceror.parse_string!()

      {_, _, [parens, without_parens, nested_without_parens, _]} = quoted

      assert Sourceror.get_range(parens) == %{
               start: [line: 1, column: 1],
               end: [line: 1, column: 7]
             }

      assert Sourceror.get_range(without_parens) == %{
               start: [line: 2, column: 1],
               end: [line: 2, column: 6]
             }

      assert Sourceror.get_range(nested_without_parens) == %{
               start: [line: 3, column: 1],
               end: [line: 3, column: 10]
             }
    end
  end

  describe "prepend_comments/3" do
    test "prepends comments to node" do
      comments = [
        %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# B"}
      ]

      quoted =
        Sourceror.parse_string!(~S"""
        # A
        :ok
        """)

      quoted = Sourceror.prepend_comments(quoted, comments)
      leading_comments = Sourceror.get_meta(quoted)[:leading_comments]

      assert [
               %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# B"},
               %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# A"}
             ] = leading_comments

      assert Sourceror.to_string(quoted) ==
               ~S"""
               # B
               # A
               :ok
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        :ok
        """)

      quoted = Sourceror.prepend_comments(quoted, comments)
      leading_comments = Sourceror.get_meta(quoted)[:leading_comments]

      assert leading_comments == [
               %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# B"}
             ]

      assert Sourceror.to_string(quoted) ==
               ~S"""
               # B
               :ok
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        foo do
          :ok
          # A
        end
        """)

      quoted = Sourceror.prepend_comments(quoted, comments, :trailing)
      trailing_comments = Sourceror.get_meta(quoted)[:trailing_comments]

      assert [%{text: "# B"}, %{text: "# A"}] = trailing_comments

      assert Sourceror.to_string(quoted) ==
               ~S"""
               foo do
                 :ok
                 # B
                 # A
               end
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        foo do
          :ok
        end
        """)

      quoted = Sourceror.prepend_comments(quoted, comments, :trailing)
      trailing_comments = Sourceror.get_meta(quoted)[:trailing_comments]

      assert [%{text: "# B"}] = trailing_comments

      assert Sourceror.to_string(quoted) ==
               ~S"""
               foo do
                 :ok
                 # B
               end
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        Foo.{
          Bar
        }
        """)

      quoted = Sourceror.prepend_comments(quoted, comments, :trailing)

      assert Sourceror.to_string(quoted) ==
               ~S"""
               Foo.{
                 Bar
                 # B
               }
               """
               |> String.trim()
    end
  end

  describe "append_comments/3" do
    test "appends comments to node" do
      comments = [
        %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# B"}
      ]

      quoted =
        Sourceror.parse_string!(~S"""
        # A
        :ok
        """)

      quoted = Sourceror.append_comments(quoted, comments)
      leading_comments = Sourceror.get_meta(quoted)[:leading_comments]

      assert [%{text: "# A"}, %{text: "# B"}] = leading_comments

      assert Sourceror.to_string(quoted) ==
               ~S"""
               # A
               # B
               :ok
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        :ok
        """)

      quoted = Sourceror.append_comments(quoted, comments)
      leading_comments = Sourceror.get_meta(quoted)[:leading_comments]

      assert [%{text: "# B"}] = leading_comments

      assert Sourceror.to_string(quoted) ==
               ~S"""
               # B
               :ok
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        foo do
          :ok

          # A
        end
        """)

      quoted = Sourceror.append_comments(quoted, comments, :trailing)
      trailing_comments = Sourceror.get_meta(quoted)[:trailing_comments]

      assert [%{text: "# A"}, %{text: "# B"}] = trailing_comments

      assert Sourceror.to_string(quoted) ==
               ~S"""
               foo do
                 :ok

                 # A
                 # B
               end
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        foo do
          :ok
        end
        """)

      quoted = Sourceror.append_comments(quoted, comments, :trailing)
      trailing_comments = Sourceror.get_meta(quoted)[:trailing_comments]

      assert [%{text: "# B"}] = trailing_comments

      assert Sourceror.to_string(quoted) ==
               ~S"""
               foo do
                 :ok
                 # B
               end
               """
               |> String.trim()

      quoted =
        Sourceror.parse_string!(~S"""
        Foo.{
          Bar
        }
        """)

      quoted = Sourceror.append_comments(quoted, comments, :trailing)

      assert Sourceror.to_string(quoted) ==
               ~S"""
               Foo.{
                 Bar
                 # B
               }
               """
               |> String.trim()
    end
  end

  describe "patch_string/2" do
    test "patches single line ranges" do
      original = ~S"""
      hello wod do
        :ok
      end
      """

      patch = %{
        change: "world",
        range: %{start: [line: 1, column: 7], end: [line: 1, column: 10]}
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             hello world do
               :ok
             end
             """
    end

    test "patches multiple ranges in a single line" do
      original = ~S"foo bar baz"

      patches = [
        %{
          change: "something long",
          range: %{start: [line: 1, column: 5], end: [line: 1, column: 8]}
        },
        %{
          change: "a",
          range: %{start: [line: 1, column: 1], end: [line: 1, column: 4]}
        },
        %{
          change: "c",
          range: %{start: [line: 1, column: 9], end: [line: 1, column: 12]}
        }
      ]

      assert Sourceror.patch_string(original, patches) == ~S"a something long c"
    end

    test "patches multiple ranges in a single line with single and multiline changes" do
      original = ~S"foo bar baz"

      patches = [
        %{
          change: "something long",
          range: %{start: [line: 1, column: 5], end: [line: 1, column: 8]}
        },
        %{
          change: "a",
          range: %{start: [line: 1, column: 1], end: [line: 1, column: 4]}
        },
        %{
          change: """
          [
            next
          ]
          """,
          range: %{start: [line: 1, column: 9], end: [line: 1, column: 12]}
        }
      ]

      assert Sourceror.patch_string(original, patches) == ~S"""
             a something long [
               next
             ]
             """
    end

    test "patches multiple line ranges" do
      original = ~S"""
      if !allowed? do
        raise "Not allowed!"
      end
      """

      patch_text =
        ~S"""
        unless allowed? do
          raise "Not allowed!"
        end
        """
        |> String.trim()

      patch = %{
        change: patch_text,
        range: %{start: [line: 1, column: 1], end: [line: 3, column: 4]}
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             unless allowed? do
               raise "Not allowed!"
             end
             """
    end

    test "patches multiline ranges" do
      original = ~S"""
      foo do
        some_call(bar do
          :baz
          end)
      end
      """

      patch_text =
        ~S"""
        whatever do
          :inner
        end
        """
        |> String.trim()

      patch = %{
        change: patch_text,
        range: %{start: [line: 2, column: 13], end: [line: 4, column: 8]}
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             foo do
               some_call(whatever do
                 :inner
               end)
             end
             """
    end

    test "patches single line range with multiple lines" do
      original = ~S"""
      hello world do
        :ok
      end
      """

      patch = %{
        change: """
        [
          1,
          2,
          3
        ]\
        """,
        range: %{start: [line: 2, column: 3], end: [line: 2, column: 6]}
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             hello world do
               [
                 1,
                 2,
                 3
               ]
             end
             """

      original = """
      outer do
        inner :ok
      end
      """

      patch = %{
        change: """
        [
          1,
          2,
          3
        ]\
        """,
        range: %{start: [line: 2, column: 9], end: [line: 2, column: 12]}
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             outer do
               inner [
                 1,
                 2,
                 3
               ]
             end
             """
    end

    test "patches single line range with multiple lines allowing user to skip indentation fixes" do
      original = ~S"""
      hello world do
        :ok
      end
      """

      patch = %{
        change: """
        [
          1,
          2,
          3
        ]\
        """,
        range: %{start: [line: 2, column: 3], end: [line: 2, column: 6]},
        preserve_indentation: false
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             hello world do
               [
               1,
               2,
               3
             ]
             end
             """
    end

    test "applies multiple patches" do
      original =
        ~S"""
        if not allowed? do raise "Not allowed!"
        end

        unless not allowed? do
          :allowed
        end
        """
        |> String.trim()

      patch1 = %{
        change:
          String.trim(~S"""
          unless allowed? do
            raise "Not allowed!"
          end
          """),
        range: %{
          start: [line: 1, column: 1],
          end: [line: 2, column: 4]
        }
      }

      patch2 = %{
        change:
          String.trim(~S"""
          if allowed? do
            :allowed
          end
          """),
        range: %{
          start: [line: 4, column: 1],
          end: [line: 7, column: 4]
        }
      }

      assert Sourceror.patch_string(original, [patch1, patch2]) ==
               ~S"""
               unless allowed? do
                 raise "Not allowed!"
               end

               if allowed? do
                 :allowed
               end
               """
               |> String.trim()
    end

    test "allows the user to skip indentation fixes" do
      original = ~S"""
      foo do
        bar do
          :ok
        end
      end
      """

      patch = %{
        change:
          String.trim(~S"""
          baz do
            :not_ok
          end
          """),
        range: %{
          start: [line: 2, column: 3],
          end: [line: 4, column: 6]
        },
        preserve_indentation: false
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             foo do
               baz do
               :not_ok
             end
             end
             """
    end

    test "function patches" do
      original = ~S"""
      hello world do
        :ok
      end
      """

      patch = %{
        change: &String.upcase/1,
        range: %{start: [line: 1, column: 7], end: [line: 1, column: 12]}
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             hello WORLD do
               :ok
             end
             """

      original = ~S"""
      foo do
        bar do
          :ok
        end
      end
      """

      patch = %{
        change: &String.upcase/1,
        range: %{
          start: [line: 2, column: 3],
          end: [line: 4, column: 6]
        }
      }

      assert Sourceror.patch_string(original, [patch]) == ~S"""
             foo do
               BAR DO
                 :OK
               END
             end
             """
    end
  end
end
