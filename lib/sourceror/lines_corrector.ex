defmodule Sourceror.LinesCorrector do
  @moduledoc false

  import Sourceror, only: [get_line: 1, correct_lines: 2]

  import Sourceror.Identifier, only: [is_binary_op: 1]

  @doc """
  Corrects the line numbers of AST nodes such that they are correctly ordered.

  * If a node has no line number, it's assumed to be in the same line as the
    previous one.
  * If a node has a line number higher than the one before, it's kept as is.
  * If a node has a line number lower than the one before, its line number is
    recursively incremented by the line number difference, if it's not a
    pipeline operator.
  * If a node has leading comments, its line number is incremented by the
    newlines for those comments.
  * If a node has trailing comments, its end_of_expression and end line
    metadata are set to the line of their last child plus the newlines of the
    trailing comments list.
  """
  def correct(quoted) do
    case trailing_block(quoted) do
      {:ok, block, line} ->
        block
        |> do_correct(line)
        |> into_trailing_block(quoted)

      :error ->
        do_correct(quoted, 1)
    end
  end

  defp into_trailing_block(quoted, {:__block__, meta, [_]}) do
    {:__block__, meta, [quoted]}
  end

  defp trailing_block({:__block__, meta, [quoted]}) do
    if meta[:__sourceror__][:trailing_block] || false do
      {:ok, quoted, comments_eol_count(meta[:leading_comments])}
    else
      :error
    end
  end

  defp trailing_block(_quoted), do: :error

  defp do_correct(quoted, line) do
    quoted
    |> Macro.traverse(%{last_line: line}, &pre_correct/2, &post_correct/2)
    |> elem(0)
  end

  defp pre_correct({_form, _meta, _args} = quoted, state) do
    do_pre_correct(quoted, state)
  end

  defp pre_correct(quoted, state) do
    {quoted, state}
  end

  defp do_pre_correct({form, meta, args} = quoted, state) do
    case correction(form, meta[:line], meta[:leading_comments], state) do
      nil ->
        meta = Keyword.put(meta, :line, state.last_line)
        {{form, meta, args}, state}

      0 ->
        {quoted, state}

      correction ->
        quoted = recursive_correct_lines(quoted, correction)
        state = %{state | last_line: get_line(quoted)}
        {quoted, state}
    end
  end

  defp correction(_form, nil, _comments, _state), do: nil

  defp correction(form, _line, _comments, _state) when is_binary_op(form), do: 0

  defp correction(_form, line, nil, state) do
    max(state.last_line - line, 0)
  end

  defp correction(_form, line, [], state) do
    max(state.last_line - line, 0)
  end

  defp correction(_form, line, comments, state) do
    comments_last_line = comments_last_line(comments)
    extra_lines = if state.last_line == line, do: 1, else: 0

    extra_lines =
      if line <= comments_last_line,
        do: extra_lines + (comments_last_line - line) + 2,
        else: extra_lines

    max(state.last_line + extra_lines + comments_eol_count(comments) - line, 0)
  end

  defp post_correct({_form, _meta, _args} = quoted, state) do
    do_post_correct(quoted, state)
  end

  defp post_correct(quoted, state) do
    {quoted, state}
  end

  defp do_post_correct({_, meta, _} = quoted, state) do
    quoted = maybe_correct_binary_op(quoted)

    last_line =
      if has_trailing_comments?(quoted) do
        state.last_line + comments_eol_count(meta[:trailing_comments]) + 1
      else
        state.last_line
      end

    last_line = Sourceror.get_end_line(quoted, last_line)

    quoted =
      quoted
      |> maybe_correct_end_of_expression(last_line)
      |> maybe_correct_end(last_line)
      |> maybe_correct_closing(last_line)

    {quoted, %{state | last_line: last_line}}
  end

  defp maybe_correct_binary_op({form, meta, [{_, _, _} = left, right]} = quoted)
       when is_binary_op(form) do
    # We must ensure that, for binary operators, the operator line number is
    # not greater than the left operand. Otherwise the comment eol counts
    # will be ignored by the formatter
    left_line = get_line(left)

    if left_line > get_line(quoted) do
      {form, Keyword.put(meta, :line, left_line), [left, right]}
    else
      quoted
    end
  end

  defp maybe_correct_binary_op(quoted), do: quoted

  defp maybe_correct_end_of_expression({form, meta, args} = quoted, last_line) do
    meta =
      if meta[:end_of_expression] || has_trailing_comments?(quoted) do
        eoe = meta[:end_of_expression] || []
        eoe = Keyword.put(eoe, :line, last_line)

        Keyword.put(meta, :end_of_expression, eoe)
      else
        meta
      end

    {form, meta, args}
  end

  defp maybe_correct_end({form, meta, args}, last_line) do
    meta =
      if meta[:end] do
        put_in(meta, [:end, :line], last_line)
      else
        meta
      end

    {form, meta, args}
  end

  defp maybe_correct_closing({form, meta, args}, last_line) do
    meta =
      cond do
        meta[:do] ->
          meta

        meta[:closing] ->
          put_in(meta, [:closing, :line], last_line)

        true ->
          meta
      end

    {form, meta, args}
  end

  def has_comments?(quoted) do
    has_leading_comments?(quoted) or has_trailing_comments?(quoted)
  end

  def has_leading_comments?({_, meta, _}) do
    match?([_ | _], meta[:leading_comments])
  end

  def has_trailing_comments?({_, meta, _}) do
    match?([_ | _], meta[:trailing_comments])
  end

  defp recursive_correct_lines(ast, line_correction) do
    Macro.postwalk(ast, fn
      {_, _, _} = ast ->
        correct_lines(ast, line_correction)

      ast ->
        ast
    end)
  end

  defp comments_last_line(comments) do
    last = List.last(comments)
    last.line
  end

  defp comments_eol_count(comments, count \\ nil)

  defp comments_eol_count(nil, _count), do: 0

  defp comments_eol_count([], count), do: count || 0

  defp comments_eol_count([comment | _] = comments, nil) do
    line = comment.previous_eol_count - 1
    comments_eol_count(comments, line)
  end

  defp comments_eol_count([comment | comments], lines) do
    comments_eol_count(comments, lines + comment.next_eol_count)
  end
end
