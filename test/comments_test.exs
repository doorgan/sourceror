defmodule SourcerorTest.CommentsTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Comments

  describe "merge_comments/2" do
    test "merges leading comments" do
      quoted =
        Sourceror.parse_string!("""
        # A
        :a # B
        """)

      assert {:atom, meta, :a} = quoted

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
                   {:var, _, :a},
                   [
                     {{:atom, _, :do}, {:atom, _, :ok}}
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
               %{line: 2, text: "# A"},
               %{line: 2, text: "# B"}
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

      assert [
               %{line: 5, text: "# A"},
               %{line: 7, text: "# B"}
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

      assert [
               %{line: 5, text: "# A"},
               %{line: 7, text: "# B"}
             ] = comments

      assert Sourceror.to_string(quoted, collapse_comments: true, correct_lines: true) ==
               """
               Foo.{
                 A

                 # A
               }

               # B
               """
               |> String.trim()
    end
  end
end
