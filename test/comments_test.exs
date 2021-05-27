defmodule SourcerorTest.CommentsTest do
  use ExUnit.Case, async: true
  doctest Sourceror

  defp parse_and_merge(string) do
    {quoted, comments} =
      Code.string_to_quoted_with_comments!(string,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}},
        token_metadata: true,
        unescape: false
      )

    Sourceror.merge_comments(quoted, comments)
  end

  describe "merge_comments/2" do
    test "merges leading comments" do
      quoted =
        parse_and_merge("""
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
        parse_and_merge("""
        def a do
          :ok
          # A
        end # B
        """)

      assert {:def, meta,
              [
                {:a, _, _},
                [
                  {{:__block__, _, [:do]}, {:__block__, _, [:ok]}}
                ]
              ]} = quoted

      assert [
               %{line: 3, text: "# A"},
               %{line: 4, text: "# B"}
             ] = meta[:trailing_comments]
    end
  end

  describe "extract_comments/1" do
    test "collapses line numbers of attached node" do
      quoted =
        parse_and_merge("""
        # A
        :ok # B
        """)

      {_quoted, comments} = Sourceror.extract_comments(quoted)

      assert [
               %{line: 2, text: "# A"},
               %{line: 2, text: "# B"}
             ] = comments

      quoted =
        parse_and_merge("""
        def a do
          :ok
          # A
        end # B
        """)

      {_quoted, comments} = Sourceror.extract_comments(quoted)

      assert [
               %{line: 4, text: "# A"},
               %{line: 4, text: "# B"}
             ] = comments
    end

    test "extracts comments in the correct order" do
      quoted =
        parse_and_merge("""
        # A
        def a do # B
          # C
          :ok # D
          # E
        end # F
        # G
        """)

      {_quoted, comments} = Sourceror.extract_comments(quoted)

      assert [
               %{line: 2, text: "# A"},
               %{line: 2, text: "# B"},
               %{line: 4, text: "# C"},
               %{line: 4, text: "# D"},
               %{line: 6, text: "# E"},
               %{line: 6, text: "# F"},
               %{line: 7, text: "# G"}
             ] = comments
    end
  end
end
