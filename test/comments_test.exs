defmodule SourcerorTest.CommentsTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Comments

  defmacrop assert_to_string(quoted, expected) do
    quote bind_quoted: [quoted: quoted, expected: expected] do
      expected_formatted = expected |> Code.format_string!([]) |> IO.iodata_to_binary()

      if Version.match?(System.version(), "~> 1.16") do
        assert expected == expected_formatted, """
        The given expected code is not formatted.
        Formatted code:
        #{expected_formatted}
        """
      end

      assert Sourceror.to_string(quoted, collapse_comments: true, correct_lines: true) ==
               expected_formatted
    end
  end

  describe "merge_comments/2" do
    test "merges leading comments" do
      quoted =
        Sourceror.parse_string!("""
        # A
        :a # B
        """)

      assert {:__block__, meta, [:a]} = quoted

      assert [
               %{line: 1, text: "# A"},
               %{line: 2, text: "# B"}
             ] = meta[:leading_comments]
    end

    test "merges trailing comments" do
      quoted =
        Sourceror.parse_string!("""
        def a do
          :ok
          # A
        end # B
        """)

      assert {:__block__, block_meta,
              [
                {:def, meta,
                 [
                   {:a, _, _},
                   [
                     {{:__block__, _, [:do]}, {:__block__, _, [:ok]}}
                   ]
                 ]}
              ]} = quoted

      assert [%{line: 3, text: "# A"}] = meta[:trailing_comments]

      assert [%{line: 4, text: "# B"}] = block_meta[:trailing_comments]
    end
  end

  describe "extract_comments/1" do
    test "preserves comment line numbers" do
      quoted =
        Sourceror.parse_string!("""
        # A
        :ok # B
        """)

      {_quoted, comments} = Sourceror.Comments.extract_comments(quoted)

      assert [
               %{line: 1, text: "# A"},
               %{line: 2, text: "# B"}
             ] = comments

      quoted =
        Sourceror.parse_string!("""
        def a do
          :ok
          # A
        end # B
        """)

      {_quoted, comments} = Sourceror.Comments.extract_comments(quoted)

      assert [
               %{line: 3, text: "# A"},
               %{line: 4, text: "# B"}
             ] = comments

      quoted =
        Sourceror.parse_string!("""
        Foo.{
          A
          # A
        } # B
        """)

      {_quoted, comments} = Sourceror.Comments.extract_comments(quoted)

      assert [
               %{line: 3, text: "# A"},
               %{line: 4, text: "# B"}
             ] = comments
    end

    test "extracts comments in the correct order" do
      quoted =
        Sourceror.parse_string!("""
        # A
        def a do # B
          # C
          :ok # D
          # E
        end # F
        # G
        """)

      {_quoted, comments} = Sourceror.Comments.extract_comments(quoted)

      assert [
               %{line: 1, text: "# A"},
               %{line: 2, text: "# B"},
               %{line: 3, text: "# C"},
               %{line: 4, text: "# D"},
               %{line: 5, text: "# E"},
               %{line: 6, text: "# F"},
               %{line: 7, text: "# G"}
             ] = comments
    end

    test "collapses comments" do
      quoted =
        Sourceror.parse_string!("""
        # A
        :ok # B
        """)

      {_quoted, comments} = Sourceror.Comments.extract_comments(quoted, collapse_comments: true)

      assert [
               %{line: 0, text: "# A"},
               %{line: 1, text: "# B"}
             ] = comments

      {_quoted, comments} =
        Sourceror.Comments.extract_comments(quoted, collapse_comments: true, correct_lines: true)

      assert [
               %{line: 3, text: "# A"},
               %{line: 4, text: "# B"}
             ] = comments

      quoted =
        Sourceror.parse_string!("""
        def a do
          :ok
          # A
        end # B
        """)

      {_quoted, comments} =
        Sourceror.Comments.extract_comments(quoted, collapse_comments: true, correct_lines: true)

      assert_to_string(quoted, """
      def a do
        :ok
        # A
      end

      # B\
      """)

      assert [
               %{line: 3, text: "# A"},
               %{line: 4, text: "# B"}
             ] = comments

      quoted =
        Sourceror.parse_string!("""
        Foo.{
          A
          # A
        } # B
        """)

      {_quoted, comments} =
        Sourceror.Comments.extract_comments(quoted, collapse_comments: true, correct_lines: true)

      assert_to_string(quoted, """
      Foo.{
        A
        # A
      }

      # B\
      """)

      assert [
               %{line: 3, text: "# A"},
               %{line: 4, text: "# B"}
             ] = comments

      quoted =
        Sourceror.parse_string!("""
        Foo.{
          A
          # A
          # B
          # C
        } # X
        # Y
        # Z
        """)

      {_quoted, comments} =
        Sourceror.Comments.extract_comments(quoted, collapse_comments: true, correct_lines: true)

      assert_to_string(quoted, """
      Foo.{
        A
        # A
        # B
        # C
      }

      # X
      # Y
      # Z\
      """)

      assert [
               %{line: 3, text: "# A"},
               %{line: 4, text: "# B"},
               %{line: 5, text: "# C"},
               %{line: 6, text: "# X"},
               %{line: 7, text: "# Y"},
               %{line: 8, text: "# Z"}
             ] = comments

      quoted =
        Sourceror.parse_string!("""
        if a do
          :b # yes
        else
          :a # no
        end
        """)

      {_quoted, comments} =
        Sourceror.Comments.extract_comments(quoted, collapse_comments: true, correct_lines: true)

      assert [
               %{line: 2, text: "# yes"},
               %{line: 4, text: "# no"}
             ] = comments

      assert_to_string(quoted, """
      if a do
        # yes
        :b
      else
        # no
        :a
      end\
      """)
    end

    test "remove this line" do
      quoted =
        Sourceror.parse_string!("""
        cond do
          # cond 1
          a -> # if a
            :a
          # cond 2
          b -> # if b
            :b
        end
        """)

      {_quoted, comments} =
        Sourceror.Comments.extract_comments(quoted, collapse_comments: true, correct_lines: true)

      assert [
               %{line: 3, text: "# cond 1"},
               %{line: 4, text: "# if a"},
               %{line: 9, text: "# cond 2"},
               %{line: 10, text: "# if b"}
             ] = comments

      assert_to_string(quoted, """
      cond do
        # cond 1

        # if a
        a ->
          :a

        # cond 2

        # if b
        b ->
          :b
      end\
      """)
    end
  end
end
