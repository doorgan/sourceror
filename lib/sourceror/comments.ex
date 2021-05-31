defmodule Sourceror.Comments do
  @moduledoc """
  Utilities to merge an un-merge comments and quoted expressions.
  """

  @doc """
  Merges the comments into the given quoted expression.

  The comments are inserted into the metadata of their closest node. Comments in
  the same line of before a node are inserted into the `:leading_comments` field
  while comments that are right before an `end` keyword are inserted into the
  `:trailing_comments` field.
  """
  @spec merge_comments(Macro.t(), list(map)) :: Macro.t()
  def merge_comments(quoted, comments) do
    {quoted, leftovers} = Macro.prewalk(quoted, comments, &do_merge_comments/2)
    {quoted, leftovers} = Macro.postwalk(quoted, leftovers, &merge_leftovers/2)

    if Enum.empty?(leftovers) do
      quoted
    else
      {:__block__, [trailing_comments: leftovers, leading_comments: []], [quoted]}
    end
  end

  defp do_merge_comments({_, _meta, _} = quoted, comments) do
    {comments, rest} = gather_comments_for_line(comments, line(quoted))

    quoted = put_comments(quoted, :leading_comments, comments)
    {quoted, rest}
  end

  defp do_merge_comments(quoted, comments), do: {quoted, comments}

  defp merge_leftovers({_, meta, _} = quoted, comments) do
    end_line = Keyword.get(meta, :end, line: 0)[:line]

    {comments, rest} = gather_comments_for_line(comments, end_line)
    quoted = put_comments(quoted, :trailing_comments, comments)

    {quoted, rest}
  end

  defp merge_leftovers(quoted, comments), do: {quoted, comments}

  defp line({_, meta, _}), do: meta[:line] || 0

  defp gather_comments_for_line(comments, line) do
    {comments, rest} =
      Enum.reduce(comments, {[], []}, fn
        comment, {comments, rest} ->
          if comment.line <= line do
            {[comment | comments], rest}
          else
            {comments, [comment | rest]}
          end
      end)

    rest = Enum.sort_by(rest, & &1.line)
    comments = Enum.sort_by(comments, & &1.line)

    {comments, rest}
  end

  defp put_comments(quoted, key, comments) do
    Macro.update_meta(quoted, &Keyword.put(&1, key, comments))
  end

  @doc """
  Does the opposite of `merge_comments/2`, it extracts the comments from the
  quoted expression and returns both as a `{quoted, comments}` tuple.
  """
  @spec extract_comments(Macro.t()) :: {Macro.t(), list(map)}
  def extract_comments(quoted) do
    Macro.postwalk(quoted, [], fn
      {_, meta, _} = quoted, acc ->
        line = meta[:line] || 1

        leading_comments =
          Keyword.get(meta, :leading_comments, [])
          |> Enum.map(fn comment ->
            %{comment | line: line}
          end)

        acc = acc ++ leading_comments

        trailing_comments =
          Keyword.get(meta, :trailing_comments, [])
          |> Enum.map(fn comment ->
            # Preserve original commet line if parent node does not have
            # ending line information
            end_line = meta[:end][:line] || meta[:closing][:line] || comment.line
            %{comment | line: end_line}
          end)

        acc = acc ++ trailing_comments

        acc = Enum.sort_by(acc, & &1.line)

        quoted =
          Macro.update_meta(quoted, fn meta ->
            meta
            |> Keyword.delete(:leading_comments)
            |> Keyword.delete(:trailing_comments)
          end)

        {quoted, acc}

      other, acc ->
        {other, acc}
    end)
  end
end
