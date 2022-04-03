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
  * If a node has leading comments, it's line number is incremented by the
    length of the comments list
  * If a node has trailing comments, it's end_of_expression and end line
    metadata are set to the line of their last child plus the trailing comments
    list length
  """
  def correct(quoted) do
    {ast, _} =
      Macro.traverse(quoted, %{last_line: 1, last_form: nil}, &pre_correct/2, &post_correct/2)

    ast
  end

  defp pre_correct({form, meta, args} = quoted, state) do
    {quoted, state} =
      cond do
        is_nil(meta[:line]) ->
          meta = Keyword.put(meta, :line, state.last_line)
          {{form, meta, args}, %{state | last_form: form}}

        get_line(quoted) <= state.last_line and not is_binary_op(form) ->
          correction = state.last_line - get_line(quoted)
          quoted = recursive_correct_lines(quoted, correction)
          {quoted, %{state | last_line: get_line(quoted), last_form: form}}

        true ->
          {quoted, %{state | last_form: form}}
      end

    if has_leading_comments?(quoted) do
      leading_comments = length(meta[:leading_comments])
      quoted = recursive_correct_lines(quoted, leading_comments + 1)
      {quoted, %{state | last_line: meta[:line]}}
    else
      {quoted, state}
    end
  end

  defp pre_correct(quoted, state) do
    {quoted, state}
  end

  defp post_correct({_, meta, _} = quoted, state) do
    quoted =
      with {form, meta, [{_, _, _} = left, right]} when is_binary_op(form) <- quoted do
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

    last_line = Sourceror.get_end_line(quoted, state.last_line)

    last_line =
      if has_trailing_comments?(quoted) do
        if Sourceror.Identifier.do_block?(quoted) do
          last_line + length(meta[:trailing_comments] || []) + 2
        else
          last_line + length(meta[:trailing_comments] || []) + 1
        end
      else
        last_line
      end

    quoted =
      quoted
      |> maybe_correct_end_of_expression(last_line)
      |> maybe_correct_end(last_line)
      |> maybe_correct_closing(last_line)

    {quoted, %{state | last_line: last_line}}
  end

  defp post_correct(quoted, state) do
    {quoted, state}
  end

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
end
