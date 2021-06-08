defmodule Sourceror.LinesCorrector do
  @moduledoc false

  import Sourceror, only: [get_line: 1, correct_lines: 2]

  @doc """
  Corrects the line numbers of AST nodes such that they are correctly ordered.

  * If a node has no line number, it's assumed to be in the same line as the previous one.
  * If a node has a line number higher than the one before, it's kept as is.
  * If a node has a line number lower than the one before, it's incremented to be one line higher than it's predecessor
  * If a node has leading comments, it's line number is incremented by the length of the comments list
  * If a node has trailing comments, it's end_of_expression and end line metadata are set to the line of their last child plus the trailing comments list length
  """
  def correct(quoted) do
    {ast, _} = Macro.traverse(quoted, %{last_line: 1}, &pre_correct/2, &post_correct/2)
    ast
  end

  defp pre_correct({form, meta, args} = quoted, state) do
    {quoted, state} =
      cond do
        is_nil(meta[:line]) ->
          meta = Keyword.put(meta, :line, state.last_line)
          {{form, meta, args}, state}

        get_line(quoted) < state.last_line ->
          correction = state.last_line + 1 - get_line(quoted)
          quoted = correct_lines(quoted, correction)
          {quoted, %{state | last_line: get_line(quoted)}}

        true ->
          {quoted, %{state | last_line: get_line(quoted)}}
      end

    if has_leading_comments?(quoted) do
      leading_comments = length(meta[:leading_comments])
      meta = Keyword.put(meta, :line, state.last_line + leading_comments + 1)
      {{form, meta, args}, %{state | last_line: meta[:line]}}
    else
      {quoted, state}
    end
  end

  defp pre_correct(quoted, state) do
    {quoted, state}
  end

  defp post_correct({form, meta, args} = quoted, state) do
    last_line = Sourceror.get_end_line(quoted, state.last_line)

    last_line =
      if has_trailing_comments?(quoted) do
        last_line + length(meta[:trailing_comments] || []) + 1
      else
        last_line
      end

    eoe = meta[:end_of_expression] || []
    eoe = Keyword.put(eoe, :line, last_line)

    meta = Keyword.put(meta, :end_of_expression, eoe)

    meta =
      if meta[:end] do
        put_in(meta, [:end, :line], eoe[:line])
      else
        meta
      end

    meta =
      if meta[:closing] do
        put_in(meta, [:closing, :line], eoe[:line])
      else
        meta
      end

    {{form, meta, args}, %{state | last_line: last_line}}
  end

  defp post_correct(quoted, state) do
    {quoted, state}
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
end
