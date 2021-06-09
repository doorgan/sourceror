defmodule SourcerorTest do
  use ExUnit.Case, async: true
  doctest Sourceror

  test "parse_string!/2 and to_string/2 idempotency" do
    source =
      ~S"""
      foo()

      # Bar
      """
      |> String.trim()

    assert source == Sourceror.parse_string!(source) |> Sourceror.to_string()

    source =
      ~S"""
      # A
      foo do
        # B
        :ok

        # C
      end

      # D
      """
      |> String.trim()

    assert source == Sourceror.parse_string!(source) |> Sourceror.to_string()
  end

  describe "parse_string!/2" do
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

      assert leading_comments == [
               %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# B"},
               %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# A"}
             ]

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
end
