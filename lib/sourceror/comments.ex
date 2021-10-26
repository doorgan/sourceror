defmodule Sourceror.Comments do
  @moduledoc """
  Utilities to merge an un-merge comments and quoted expressions.
  """

  import Sourceror.Identifier, only: [is_pipeline_op: 1]

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

  defp do_merge_comments({form, _, _} = quoted, comments) when not is_pipeline_op(form) do
    {comments, rest} = gather_leading_comments_for_node(quoted, comments)

    quoted = put_comments(quoted, :leading_comments, comments)
    {quoted, rest}
  end

  defp do_merge_comments(quoted, comments), do: {quoted, comments}

  defp merge_leftovers({_, _, _} = quoted, comments) do
    {comments, rest} = gather_trailing_comments_for_node(quoted, comments)
    quoted = put_comments(quoted, :trailing_comments, comments)

    {quoted, rest}
  end

  defp merge_leftovers(quoted, comments), do: {quoted, comments}

  defp gather_leading_comments_for_node(quoted, comments) do
    line = Sourceror.get_line(quoted, 0)

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

  defp gather_trailing_comments_for_node(quoted, comments) do
    line = Sourceror.get_end_line(quoted, 0)
    has_closing_line? = Sourceror.has_closing_line?(quoted)

    {comments, rest} =
      Enum.reduce(comments, {[], []}, fn
        comment, {comments, rest} ->
          cond do
            has_closing_line? and comment.line < line ->
              {[comment | comments], rest}

            not has_closing_line? and comment.line <= line ->
              {[comment | comments], rest}

            true ->
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
  def extract_comments(quoted, opts \\ []) do
    collapse_comments = Keyword.get(opts, :collapse_comments, false)
    correct_lines = Keyword.get(opts, :correct_lines, false)

    quoted =
      if correct_lines do
        Sourceror.LinesCorrector.correct(quoted)
      else
        quoted
      end

    Macro.postwalk(quoted, [], fn
      {_, _, _} = quoted, acc ->
        do_extract_comments(quoted, acc, collapse_comments)

      other, acc ->
        {other, acc}
    end)
  end

  defp do_extract_comments({_, meta, _} = quoted, acc, collapse_comments) do
    leading_comments = Keyword.get(meta, :leading_comments, [])

    leading_comments =
      if collapse_comments do
        Enum.map(
          leading_comments,
          &%{&1 | line: meta[:line] - 1}
        )
      else
        leading_comments
      end

    trailing_comments = Keyword.get(meta, :trailing_comments, [])

    trailing_comments =
      if collapse_comments do
        collapse_trailing_comments(quoted, trailing_comments)
      else
        trailing_comments
      end

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

  defp collapse_trailing_comments(quoted, trailing_comments) do
    meta = Sourceror.get_meta(quoted)

    comments =
      Enum.map(trailing_comments, fn comment ->
        line = meta[:end_of_expression][:line] || meta[:line]

        %{comment | line: line - 2, previous_eol_count: 1}
      end)

    comments =
      case comments do
        [first | rest] ->
          [%{first | previous_eol_count: 0} | rest]

        _ ->
          comments
      end

    case List.pop_at(comments, -1) do
      {last, rest} when is_map(last) ->
        rest ++ [%{last | next_eol_count: 2}]

      _ ->
        comments
    end
  end
end
