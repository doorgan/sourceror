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
    {quoted, leftovers} =
      Macro.traverse(quoted, comments, &do_merge_comments/2, &merge_leftovers/2)

    case leftovers do
      [] ->
        quoted

      _ ->
        line = Sourceror.get_line(quoted)
        {:__block__, [trailing_comments: leftovers, leading_comments: [], line: line], [quoted]}
    end
  end

  defp do_merge_comments({_, _, _} = quoted, comments) do
    line = Sourceror.get_line(quoted, 0)
    {comments, rest} = gather_comments_for_line(comments, line)

    quoted = put_comments(quoted, :leading_comments, comments)
    {quoted, rest}
  end

  defp do_merge_comments(quoted, comments), do: {quoted, comments}

  defp merge_leftovers(quoted, comments) do
    end_line = Sourceror.get_end_line(quoted, 0)

    {comments, rest} = gather_comments_for_line(comments, end_line)
    quoted = put_comments(quoted, :trailing_comments, comments)

    {quoted, rest}
  end

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
      {_, _, _} = quoted, acc ->
        do_extract_comments(quoted, acc)

      other, acc ->
        {other, acc}
    end)
  end

  defp do_extract_comments({_, meta, _} = quoted, acc) do
    leading_comments = Keyword.get(meta, :leading_comments, [])
    trailing_comments = Keyword.get(meta, :trailing_comments, [])

    acc =
      Enum.concat([acc, leading_comments, trailing_comments])
      |> Enum.sort_by(& &1.line)

    quoted =
      Macro.update_meta(quoted, fn meta ->
        meta
        |> Keyword.delete(:leading_comments)
        |> Keyword.delete(:trailing_comments)
      end)

    {quoted, acc}
  end
end
