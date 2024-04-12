defmodule Sourceror.Range do
  @moduledoc false

  import Sourceror.Identifier, only: [is_unary_op: 1, is_binary_op: 1]

  defp split_on_newline(string) do
    String.split(string, ~r/\n|\r\n|\r/)
  end

  @spec get_range(Macro.t()) :: Sourceror.range() | nil
  def get_range(quoted, opts \\ []) do
    with %{} = range <- do_get_range(quoted) do
      if Keyword.get(opts, :include_comments, false) do
        add_comments_to_range(range, quoted)
      else
        range
      end
    end
  end

  defp add_comments_to_range(range, quoted) do
    comments =
      case quoted do
        {_, meta, _} ->
          meta[:leading_comments] || []

        _ ->
          []
      end

    first_comment = List.first(comments)
    last_comment = List.last(comments)

    {start_line, start_column} =
      if first_comment do
        {first_comment.line, min(range.start[:column], first_comment.column || 1)}
      else
        {range.start[:line], range.start[:column]}
      end

    end_column =
      if last_comment && last_comment.line == range.start[:line] do
        comment_length = String.length(last_comment.text)
        max(range.end[:column], (last_comment.column || 1) + comment_length)
      else
        range.end[:column]
      end

    %{
      start: [line: start_line, column: start_column],
      end: [line: range.end[:line], column: end_column]
    }
  end

  @spec do_get_range(Macro.t()) :: Sourceror.range() | nil
  defp do_get_range(quoted)

  # Module aliases starting with a non-atom or special form
  # e.g. __MODULE__.Nested, @module.Nested, module().Nested
  defp do_get_range({:__aliases__, meta, [{_, _, _} = first_segment | rest]}) do
    get_range_for_pair(first_segment, {:__aliases__, meta, rest})
  end

  # Module aliases
  defp do_get_range({:__aliases__, meta, segments}) do
    start_pos = Keyword.take(meta, [:line, :column])

    last_segment_length = List.last(segments) |> to_string() |> String.length()

    end_pos = meta[:last] |> Keyword.update!(:column, &(&1 + last_segment_length))

    %{start: start_pos, end: end_pos}
  end

  # Strings
  defp do_get_range({:__block__, meta, [string]}) when is_binary(string) do
    lines = split_on_newline(string)

    last_line = List.last(lines) || ""

    end_line = meta[:line] + length(lines)

    end_line =
      if meta[:delimiter] in [~S/"""/, ~S/'''/] do
        end_line
      else
        end_line - 1
      end

    end_column =
      if meta[:delimiter] in [~S/"""/, ~S/'''/] do
        meta[:column] + String.length(meta[:delimiter])
      else
        delimiter_count =
          if String.contains?(string, meta[:delimiter]) do
            ~r/#{meta[:delimiter]}/ |> Regex.scan(string) |> length()
          else
            0
          end

        count =
          meta[:column] + String.length(last_line) + String.length(meta[:delimiter]) +
            delimiter_count

        if end_line == meta[:line] do
          count + 1
        else
          count
        end
      end

    %{
      start: Keyword.take(meta, [:line, :column]),
      end: [line: end_line, column: end_column]
    }
  end

  # Integers, Floats
  defp do_get_range({:__block__, meta, [number]}) when is_integer(number) or is_float(number) do
    %{
      start: Keyword.take(meta, [:line, :column]),
      end: [line: meta[:line], column: meta[:column] + String.length(meta[:token])]
    }
  end

  # Atoms
  defp do_get_range({:__block__, meta, [atom]}) when is_atom(atom) do
    start_pos = Keyword.take(meta, [:line, :column])
    string = Atom.to_string(atom)

    delimiter = meta[:delimiter] || ""

    lines = split_on_newline(string)

    last_line = List.last(lines) || ""

    end_line = meta[:line] + length(lines) - 1

    end_column = meta[:column] + String.length(last_line) + String.length(delimiter)

    end_column =
      cond do
        end_line == meta[:line] && meta[:delimiter] ->
          # Column and first delimiter
          end_column + 2

        end_line == meta[:line] ->
          # Just the colon
          end_column + 1

        end_line != meta[:line] ->
          # You're beautiful as you are, Courage
          end_column
      end

    %{
      start: start_pos,
      end: [line: end_line, column: end_column]
    }
  end

  # Block with no parenthesis
  defp do_get_range({:__block__, meta, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      case args do
        [{_, _, _} | _] ->
          {first, rest} = List.pop_at(args, 0)
          {last, _} = List.pop_at(rest, -1, first)
          get_range_for_pair(first, last)

        [charlist] when is_list(charlist) ->
          string = List.to_string(charlist)
          do_get_range({:__block__, meta, [string]})

        [] ->
          nil
      end
    end
  end

  # Variables
  defp do_get_range({form, meta, context}) when is_atom(form) and is_atom(context) do
    start_pos = Keyword.take(meta, [:line, :column])

    end_pos = [
      line: start_pos[:line],
      column: start_pos[:column] + String.length(Atom.to_string(form))
    ]

    %{start: start_pos, end: end_pos}
  end

  # 2-tuples from keyword lists
  defp do_get_range({left, right}) do
    get_range_for_pair(left, right)
  end

  # Handles arguments. Lists are always wrapped in `:__block__`, so the only case
  # in which we can have a naked list is in partial keyword lists, as in `[:a, :b, c: d, e: f]`,
  # or stabs like `:foo -> :bar`
  defp do_get_range([first, _second | _] = list) do
    get_range_for_pair(first, List.last(list))
  end

  defp do_get_range([first]) do
    get_range(first)
  end

  # Stabs without right args
  # a ->
  defp do_get_range({:->, stab_meta, [left, {:__block__, right_meta, [nil]} = right]}) do
    end_pos =
      if right_meta[:column] == stab_meta[:column] do
        right_meta
        |> Keyword.take([:line, :column])
        |> Keyword.update!(:column, &(&1 + 2))
      else
        get_range(right).end
      end

    start_pos =
      case left do
        [] ->
          Keyword.take(stab_meta, [:line, :column])

        _ ->
          get_range(left).start
      end

    %{start: start_pos, end: end_pos}
  end

  # Stabs without left args
  # -> b
  defp do_get_range({:->, meta, [[], right]}) do
    start_pos = Keyword.take(meta, [:line, :column])

    with %{end: end_pos} <- get_range(right) do
      %{start: start_pos, end: end_pos}
    end
  end

  # Stabs with args
  # a -> b
  defp do_get_range({:->, _, [left, right]}) do
    get_range_for_pair(left, right)
  end

  # Argument capture syntax
  # &1
  defp do_get_range({:&, meta, [int]}) when is_integer(int) do
    start_pos = Keyword.take(meta, [:line, :column])
    int_len = int |> Integer.to_string() |> String.length()

    %{start: start_pos, end: [line: meta[:line], column: meta[:column] + int_len + 1]}
  end

  # Unwrapped Access syntax
  defp do_get_range({:., _, [Access, :get]} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Unwrapped qualified calls
  defp do_get_range({:., meta, [left, atom]}) when is_atom(atom) do
    with %{start: start_pos} <- get_range(left) do
      atom_length = atom |> inspect() |> String.length()
      %{start: start_pos, end: [line: meta[:line], column: meta[:column] + atom_length]}
    end
  end

  # Access syntax
  defp do_get_range({{:., _, [Access, :get]}, _, _} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Qualified tuple
  defp do_get_range({{:., _, [_, :{}]}, _, _} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Interpolated atoms
  defp do_get_range({{:., _, [:erlang, :binary_to_atom]}, meta, [interpolation, :utf8]}) do
    interpolation =
      Macro.update_meta(interpolation, &Keyword.put(&1, :delimiter, meta[:delimiter]))

    get_range_for_interpolation(interpolation)
  end

  # Interpolated charlists
  defp do_get_range({{:., _, [List, :to_charlist]}, meta, [segments]}) do
    start_pos = Keyword.take(meta, [:line, :column])

    end_pos = get_end_pos_for_interpolation_segments(segments, meta[:delimiter] || "'", start_pos)

    %{start: start_pos, end: end_pos}
  end

  # Charlist interpolation node
  defp do_get_range({{:., _, [Kernel, :to_string]}, meta, _}) do
    start_pos = Keyword.take(meta, [:line, :column])
    end_pos = Keyword.update!(meta[:closing], :column, &(&1 + 1))

    %{start: start_pos, end: end_pos}
  end

  # Qualified call
  defp do_get_range({{:., _, [_left, right]}, _meta, []} = quoted) when is_atom(right) do
    get_range_for_qualified_call_without_arguments(quoted)
  end

  # Anonymous function call
  defp do_get_range({{:., _, [_left]}, _meta, []} = quoted) do
    get_range_for_qualified_call_without_arguments(quoted)
  end

  # Qualified call with arguments
  defp do_get_range({{:., _, [_left, _]}, _meta, _args} = quoted) do
    get_range_for_qualified_call_with_arguments(quoted)
  end

  # Anonymous function call with arguments
  defp do_get_range({{:., _, [_left]}, _meta, _args} = quoted) do
    get_range_for_qualified_call_with_arguments(quoted)
  end

  # Unary operators
  defp do_get_range({op, meta, [arg]}) when is_unary_op(op) do
    with %{end: end_pos} <- get_range(arg) do
      start_pos = Keyword.take(meta, [:line, :column])

      end_column =
        if end_pos[:line] == meta[:line] do
          end_pos[:column]
        else
          end_pos[:column] + String.length(to_string(op))
        end

      %{start: start_pos, end: [line: end_pos[:line], column: end_column]}
    end
  end

  # Interpolation
  defp do_get_range(
         {:"::", meta,
          [
            {{:., _, [Kernel, :to_string]}, end_meta, _},
            _
          ]}
       ) do
    start_pos = [line: meta[:line], column: meta[:column]]

    end_pos = Keyword.update!(end_meta[:closing], :column, &(&1 + 1))

    %{start: start_pos, end: end_pos}
  end

  # Binary operators
  defp do_get_range({op, _, [left, right]}) when is_binary_op(op) do
    get_range_for_pair(left, right)
  end

  # Stepped ranges
  defp do_get_range({:"..//", _, [left, _middle, right]}) do
    get_range_for_pair(left, right)
  end

  # Bitstrings and interpolations
  defp do_get_range({:<<>>, meta, _} = quoted) do
    if meta[:delimiter] do
      get_range_for_interpolation(quoted)
    else
      get_range_for_bitstring(quoted)
    end
  end

  # Sigils
  defp do_get_range({sigil, meta, [{:<<>>, _, segments}, modifiers]} = quoted)
       when is_list(modifiers) do
    case Atom.to_string(sigil) do
      <<"sigil_", _name>> ->
        # Congratulations, it's a sigil!
        start_pos = Keyword.take(meta, [:line, :column])

        end_pos =
          get_end_pos_for_interpolation_segments(segments, meta[:delimiter], start_pos)
          |> Keyword.update!(:column, &(&1 + length(modifiers)))

        end_pos =
          cond do
            multiline_delimiter?(meta[:delimiter]) and !has_interpolations?(segments) ->
              # If it has no interpolations and is a multiline sigil, then the first
              # line will be incorrectly reported because the first string in the
              # segments(which is the only one) won't have a leading newline, so
              # we're compensating for that here. The end column will be at the same
              # indentation as the start column, plus the length of the multiline
              # delimiter
              [line: end_pos[:line] + 1, column: start_pos[:column] + 3]

            multiline_delimiter?(meta[:delimiter]) or has_interpolations?(segments) ->
              # If it's a multiline sigil or has interpolations, then the positions
              # will already be correctly calculated
              end_pos

            true ->
              # If it's a single line sigil, add the offset for the ~x
              Keyword.update!(end_pos, :column, &(&1 + 2))
          end

        %{
          start: start_pos,
          end: end_pos
        }

      _ ->
        get_range_for_unqualified_call(quoted)
    end
  end

  # Unqualified calls
  defp do_get_range({call, _, _} = quoted) when is_atom(call) do
    get_range_for_unqualified_call(quoted)
  end

  # Double-parenthesis unqualified calls:
  # unquote(foo)()
  defp do_get_range({{call, _, _}, _, _} = quoted) when is_atom(call) do
    get_range_for_unqualified_call(quoted)
  end

  # Catch-all
  defp do_get_range(_), do: nil

  defp get_range_for_unqualified_call({_call, meta, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      with %{end: end_pos} <- get_range(List.last(args)) do
        start_pos = Keyword.take(meta, [:line, :column])
        %{start: start_pos, end: end_pos}
      end
    end
  end

  defp get_range_for_qualified_call_without_arguments({{:., _, call}, meta, []} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      {left, right_len} =
        case call do
          [left, right] -> {left, String.length(inspect(right)) - 1}
          [left] -> {left, 0}
        end

      with %{start: start_pos} <- get_range(left) do
        identifier_pos = Keyword.take(meta, [:line, :column])

        parens_length =
          if meta[:no_parens] do
            0
          else
            2
          end

        end_pos = [
          line: identifier_pos[:line],
          column: identifier_pos[:column] + right_len + parens_length
        ]

        %{start: start_pos, end: end_pos}
      end
    end
  end

  defp get_range_for_qualified_call_with_arguments({{:., _, [left | _]}, _meta, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      get_range_for_pair(left, List.last(args) || left)
    end
  end

  defp get_range_for_node_with_closing_line({:fn, _, _} = quoted) do
    start_position = Sourceror.get_start_position(quoted)
    end_position = Sourceror.get_end_position(quoted)

    end_position = Keyword.update!(end_position, :column, &(&1 + 3))

    %{start: start_position, end: end_position}
  end

  defp get_range_for_node_with_closing_line({_, meta, _} = quoted) do
    start_position = Sourceror.get_start_position(quoted)
    end_position = Sourceror.get_end_position(quoted)

    end_position =
      cond do
        Keyword.has_key?(meta, :end_of_expression) ->
          Keyword.update!(end_position, :column, &(&1 + 1))

        Keyword.has_key?(meta, :end) ->
          Keyword.update!(end_position, :column, &(&1 + 3))

        true ->
          # If it doesn't have an end token, then it has either a ), a ] or a }
          Keyword.update!(end_position, :column, &(&1 + 1))
      end

    %{start: start_position, end: end_position}
  end

  defp get_range_for_interpolation({:<<>>, meta, segments}) do
    start_pos = Keyword.take(meta, [:line, :column])

    end_pos =
      get_end_pos_for_interpolation_segments(segments, meta[:delimiter] || "\"", start_pos)

    %{start: start_pos, end: end_pos}
  end

  def get_end_pos_for_interpolation_segments(segments, delimiter, start_pos) do
    end_pos =
      Enum.reduce(segments, start_pos, fn
        string, pos when is_binary(string) ->
          lines = split_on_newline(string)
          length = String.length(List.last(lines) || "")

          line_count = length(lines) - 1

          column =
            if line_count > 0 do
              start_pos[:column] + length
            else
              pos[:column] + length
            end

          [
            line: pos[:line] + line_count,
            column: column
          ]

        {:"::", _, [{_, meta, _}, {:binary, _, _}]}, _pos ->
          meta
          |> Keyword.fetch!(:closing)
          |> Keyword.take([:line, :column])
          # Add the closing }
          |> Keyword.update!(:column, &(&1 + 1))

        # interpolation in charlist
        {{:., _, [Kernel, :to_string]}, meta, _}, _pos ->
          meta
          |> Keyword.fetch!(:closing)
          |> Keyword.take([:line, :column])
          # Add the closing }
          |> Keyword.update!(:column, &(&1 + 1))
      end)

    cond do
      multiline_delimiter?(delimiter) and has_interpolations?(segments) ->
        [line: end_pos[:line], column: String.length(delimiter) + 1]

      has_interpolations?(segments) ->
        Keyword.update!(end_pos, :column, &(&1 + 1))

      true ->
        Keyword.update!(end_pos, :column, &(&1 + 2))
    end
  end

  defp get_range_for_pair(left, right) do
    with %{start: start_pos} <- get_range(left),
         %{end: end_pos} <- get_range(right) do
      %{start: start_pos, end: end_pos}
    end
  end

  defp has_interpolations?(segments) do
    Enum.any?(segments, fn segment ->
      match?({:"::", _, _}, segment) or match?({{:., _, [Kernel, :to_string]}, _, _}, segment)
    end)
  end

  defp multiline_delimiter?(delimiter) do
    delimiter in ~w[""" ''']
  end

  defp get_range_for_bitstring(quoted) do
    range = get_range_for_node_with_closing_line(quoted)

    # get_range_for_node_with_closing_line/1 will add 1 to the ending column
    # because it assumes it ends with ), ] or }, but bitstring closing token is
    # >>, so we need to add another 1
    update_in(range, [:end, :column], &(&1 + 1))
  end
end
