defmodule Sourceror.Comments do
  @moduledoc """
  Utilities to merge an un-merge comments and quoted expressions.
  """

  import Sourceror.Identifier, only: [is_pipeline_op: 1, is_binary_op: 1]

  @doc """
  Merges the comments into the given quoted expression.

  The comments are inserted into the metadata of their closest node. Comments in
  the same line of before a node are inserted into the `:leading_comments` field
  while comments that are right before an `end` keyword are inserted into the
  `:trailing_comments` field.
  """
  @spec merge_comments(Macro.t(), list(map)) :: Macro.t()
  def merge_comments({:__block__, _meta, []} = quoted, comments) do
    trailing_block({quoted, comments})
  end

  def merge_comments(quoted, comments) do
    {quoted, leftovers} =
      Macro.traverse(quoted, comments, &do_merge_comments/2, &merge_leftovers/2)

    case leftovers do
      [] ->
        quoted

      _ ->
        if match?({:__block__, _, [_ | _]}, quoted) and not Sourceror.Identifier.do_block?(quoted) do
          {last, args} = Sourceror.get_args(quoted) |> List.pop_at(-1)
          line = Sourceror.get_line(last)

          last =
            {:__block__,
             [
               __sourceror__: %{trailing_block: true},
               trailing_comments: leftovers,
               leading_comments: [],
               line: line
             ], [last]}

          {:__block__, Sourceror.get_meta(quoted), args ++ [last]}
        else
          line = Sourceror.get_line(quoted)

          {:__block__,
           [
             __sourceror__: %{trailing_block: true},
             trailing_comments: leftovers,
             leading_comments: [],
             line: line
           ], [quoted]}
        end
    end
  end

  defp do_merge_comments({form, _, _} = quoted, comments)
       when not is_pipeline_op(form) and not is_binary_op(form) do
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

    output =
      Macro.prewalk(quoted, [], fn
        {_, meta, _} = quoted, acc ->
          traling_block? = meta[:__sourceror__][:trailing_block] || false
          do_extract_comments(quoted, acc, collapse_comments, traling_block?)

        other, acc ->
          {other, acc}
      end)

    output
  end

  defp do_extract_comments({_, meta, [quoted]}, acc, collapse_comments, true) do
    {quoted, comments} = do_extract_comments(quoted, acc, collapse_comments, false)
    quoted = update_empty_quoted(quoted)

    {start, span} = span(quoted)

    {leading_comments, end_leading_comments} =
      trailing_block_comments(meta[:leading_comments], collapse_comments, start)

    end_line =
      if span > 0 do
        end_leading_comments + start + span
      else
        max(end_leading_comments, 1)
      end

    {trailing_comments, _} =
      trailing_block_comments(meta[:trailing_comments], collapse_comments, end_line)

    {quoted, Enum.concat([leading_comments, comments, trailing_comments])}
  end

  defp do_extract_comments({_, meta, _} = quoted, acc, collapse_comments, false) do
    leading_comments = Keyword.get(meta, :leading_comments, [])

    leading_comments =
      if collapse_comments do
        collapse_comments(meta[:line], leading_comments)
      else
        leading_comments
      end

    trailing_comments = Keyword.get(meta, :trailing_comments, [])

    trailing_comments =
      if collapse_comments do
        quoted |> Sourceror.get_end_line() |> collapse_comments(trailing_comments)
      else
        trailing_comments
      end

    acc =
      Enum.concat([acc, leading_comments, trailing_comments])
      |> Enum.sort_by(& &1.line)

    quoted =
      if meta[:__sourceror__][:trailing_block] do
        {_, _, [quoted]} = quoted
        quoted
      else
        quoted
      end

    quoted =
      Macro.update_meta(quoted, fn meta ->
        meta
        |> Keyword.delete(:leading_comments)
        |> Keyword.delete(:trailing_comments)
      end)

    {quoted, acc}
  end

  defp span({:__block__, meta, []}), do: {meta[:line], 0}

  defp span(quoted) do
    %{start: range_start, end: range_end} = Sourceror.get_range(quoted, include_comments: true)
    {range_start[:line], range_end[:line] - range_start[:line] + 1}
  end

  defp update_empty_quoted({:__block__, meta, []}) do
    {:__block__, Keyword.put(meta, :line, 1), []}
  end

  defp update_empty_quoted(quoted), do: quoted

  defp trailing_block_comments([], _collapse_comments, line), do: {[], line - 1}

  defp trailing_block_comments(comments, false, line), do: {comments, line}

  defp trailing_block_comments([comment | _] = comments, true, line) do
    prev = min(comment.previous_eol_count, 2) - 1
    line = line + prev

    {comments, line} =
      Enum.reduce(comments, {[], line}, fn comment, {acc, line} ->
        comment = %{comment | line: line}
        line = line + min(comment.next_eol_count, 2)
        {[comment | acc], line}
      end)

    {Enum.reverse(comments), line}
  end

  defp collapse_comments(_line, []), do: []

  defp collapse_comments(line, comments) do
    comments
    |> Enum.reverse()
    |> Enum.reduce({[], line}, fn comment, {acc, line} ->
      line = line - comment.next_eol_count
      comment = %{comment | line: line}
      {[comment | acc], line}
    end)
    |> elem(0)
  end

  defp trailing_block({quoted, []}), do: quoted

  defp trailing_block({{_form, meta, _args} = quoted, leftovers}) do
    {:__block__,
     [
       __sourceror__: %{trailing_block: true},
       trailing_comments: leftovers,
       leading_comments: [],
       line: meta[:line]
     ], [quoted]}
  end
end
