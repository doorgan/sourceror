defmodule Sourceror do
  @moduledoc """
  Utilities to work with Elixir source code
  """

  @doc """
  Parses the source code into an extended AST suitable for source manipulation
  as described in `Code.quoted_to_algebra/2`.

  Two additional fields are added to nodes metadata:
    * `:leading_comments` - a list holding the comments found *before* the node.
    * `:trailing_comments` - a list holding the comments found before the end
      of the node. For example, comments right before the `end` keyword.

  Comments are the same maps returned by `Code.string_to_quoted_with_comments/2`.
  """
  def parse_string(source) do
    {quoted, comments} =
      Code.string_to_quoted_with_comments!(source,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}},
        token_metadata: true,
        unescape: false
      )

    Sourceror.Comments.merge_comments(quoted, comments)
  end

  @doc """
  Converts a quoted expression to a string.

  The comments line number will be ignored and the line number of the associated
  node will be used when formatting the code.
  """
  def to_string(quoted) do
    {quoted, comments} = Sourceror.Comments.extract_comments(quoted)

    quoted
    |> Code.quoted_to_algebra(comments: comments)
    |> Inspect.Algebra.format(98)
    |> IO.iodata_to_binary()
  end

  @doc """
  Performs a depth-first post-order traversal of a quoted expression, correcting
  line numbers as it goes.

  `fun` is a function that will receive the current node as a first argument and
  the traversal state as the second one. It must return a `{quoted, state}`,
  in the same way it would return `{quoted, acc}` when using `Macro.postwalk/3`.

  Before calling `fun` in a node, its line numbers will be corrected by the
  `state.line_correction`. If you need to manually correct the line number of
  a node, use `correct_lines/2`.

  The state is a map with the following keys:
    * `:line_correction` - an integer representing how many lines subsequent
      nodes should be shifted. If the function *adds* more nodes to the tree
      that should go in a new line, the line numbers of the subsequent nodes
      need to be updated in order for comments to be correctly placed during the
      formatting process. If the function does this kind of change, it must
      update the `:line_correction` field by adding the amount of lines that
      should be shifted. Note that this field is cumulative, setting it to 0 will
      reset it for the whole traversal. Starts at `0`.
  """
  def postwalk(quoted, fun) do
    {quoted, _} =
      Macro.postwalk(quoted, %{line_correction: 0}, fn
        {_, _, _} = quoted, state ->
          quoted = Macro.update_meta(quoted, &correct_lines(&1, state.line_correction))
          fun.(quoted, state)

        quoted, state ->
          fun.(quoted, state)
      end)

    quoted
  end

  @doc """
  Shifts the line numbers of the node by the given `line_correction`.

  This function will update the `:line`, `:closing`, `:do`, `:end` and
  `:end_of_expression` line numbers of the node metadata if such fields are
  present.
  """
  def correct_lines(meta, line_correction) do
    meta =
      if line = meta[:line] do
        Keyword.put(meta, :line, line + line_correction)
      else
        meta ++ [line: 1]
      end

    corrections =
      Enum.map(~w[closing do end end_of_expression]a, &correct_line(meta, &1, line_correction))

    Enum.reduce(corrections, meta, fn correction, meta ->
      Keyword.merge(meta, correction)
    end)
  end

  defp correct_line(meta, key, line_correction) do
    with value when value != [] <- Keyword.get(meta, key, []) do
      value = put_in(value, [:line], value[:line] + line_correction)
      [{key, value}]
    else
      _ -> meta
    end
  end
end