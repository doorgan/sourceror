defmodule Sourceror.Range do
  @moduledoc false

  import Sourceror.Identifier, only: [is_unary_op: 1, is_binary_op: 1]

  defp split_on_newline(string) do
    String.split(string, ~r/\n|\r\n|\r/)
  end

  @spec get_range(Macro.t) :: Sourceror.range
  def get_range(quoted)

  # Module aliases
  def get_range({:__aliases__, meta, segments}) do
    start_pos = Keyword.take(meta, [:line, :column])

    length = Enum.join(segments, ".") |> String.length()

    %{
      start: start_pos,
      end: [line: meta[:line], column: meta[:column] + length]
    }
  end

  # Strings
  def get_range({:__block__, meta, [string]}) when is_binary(string) do
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
        count = meta[:column] + String.length(last_line) + String.length(meta[:delimiter])

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
  def get_range({:__block__, meta, [number]}) when is_integer(number) or is_float(number) do
    %{
      start: Keyword.take(meta, [:line, :column]),
      end: [line: meta[:line], column: meta[:column] + String.length(meta[:token])]
    }
  end

  # Atoms
  def get_range({:__block__, meta, [atom]}) when is_atom(atom) do
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
  def get_range({:__block__, _, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      {first, rest} = List.pop_at(args, 0)
      {last, _} = List.pop_at(rest, -1, first)

      %{
        start: get_range(first).start,
        end: get_range(last).end
      }
    end
  end

  # Variables
  def get_range({form, meta, context}) when is_atom(form) and is_atom(context) do
    start_pos = Keyword.take(meta, [:line, :column])

    end_pos = [
      line: start_pos[:line],
      column: start_pos[:column] + String.length(Atom.to_string(form))
    ]

    %{start: start_pos, end: end_pos}
  end

  # Access syntax
  def get_range({{:., _, [Access, :get]}, _, _} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Qualified tuple
  def get_range({{:., _, [_, :{}]}, _, _} = quoted) do
    get_range_for_node_with_closing_line(quoted)
  end

  # Interpolated atoms
  def get_range({{:., _, [:erlang, :binary_to_atom]}, meta, [interpolation, :utf8]}) do
    interpolation =
      Macro.update_meta(interpolation, &Keyword.put(&1, :delimiter, meta[:delimiter]))

    get_range_for_interpolation(interpolation)
  end

  # Qualified call
  def get_range({{:., _, [left, right]}, meta, []}) when is_atom(right) do
    left_range = get_range(left)
    start_pos = left_range.start

    parens_length =
      if meta[:no_parens] do
        0
      else
        2
      end

    end_pos = [
      line: left_range.end[:line],
      column: left_range.end[:column] + 1 + String.length(Atom.to_string(right)) + parens_length
    ]

    %{start: start_pos, end: end_pos}
  end

  def get_range({{:., _, [left, _]}, _meta, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      start_pos = get_range(left).start
      end_pos = get_range(List.last(args) || left).end

      %{start: start_pos, end: end_pos}
    end
  end

  # Unary operators
  def get_range({op, meta, [arg]}) when is_unary_op(op) do
    start_pos = Keyword.take(meta, [:line, :column])
    arg_range = get_range(arg)

    end_column =
      if arg_range.end[:line] == meta[:line] do
        arg_range.end[:column]
      else
        arg_range.end[:column] + String.length(to_string(op))
      end

    %{start: start_pos, end: [line: arg_range.end[:line], column: end_column]}
  end

  # Binary operators
  def get_range({op, _, [left, right]}) when is_binary_op(op) do
    %{
      start: get_range(left).start,
      end: get_range(right).end
    }
  end

  # Stepped ranges
  def get_range({:"..//", _, [left, _middle, right]}) do
    %{
      start: get_range(left).start,
      end: get_range(right).end
    }
  end

  # Bitstrings and interpolations
  def get_range({:<<>>, meta, _} = quoted) do
    if meta[:delimiter] do
      get_range_for_interpolation(quoted)
    else
      get_range_for_bitstring(quoted)
    end
  end

  # Sigils
  def get_range({sigil, meta, [{:<<>>, _, segments}, modifiers]}) when is_list(modifiers) do
    case Atom.to_string(sigil) do
      <<"sigil_", _name>> ->
        # Congratulations, it's a sigil!
        start_pos = Keyword.take(meta, [:line, :column])

        end_pos = get_end_pos_for_interpolation_segments(segments, start_pos)

        %{
          start: start_pos,
          end: Keyword.update!(end_pos, :column, & &1 + length(modifiers))
        }

      _ ->
        # Regular call
        raise "not implemented"
    end
  end

  # Unqualified calls
  def get_range({call, _, _} = quoted) when is_atom(call) do
    get_range_for_unqualified_call(quoted)
  end

  def get_range_for_unqualified_call({_call, meta, args} = quoted) do
    if Sourceror.has_closing_line?(quoted) do
      get_range_for_node_with_closing_line(quoted)
    else
      start_pos = Keyword.take(meta, [:line, :column])
      end_pos = get_range(List.last(args)).end

      %{start: start_pos, end: end_pos}
    end
  end

  def get_range_for_node_with_closing_line({_, meta, _} = quoted) do
    start_position = Sourceror.get_start_position(quoted)
    end_position = Sourceror.get_end_position(quoted)

    end_position =
      if Keyword.has_key?(meta, :end) do
        Keyword.update!(end_position, :column, &(&1 + 3))
      else
        # If it doesn't have an end token, then it has either a ), a ] or a }
        Keyword.update!(end_position, :column, &(&1 + 1))
      end

    %{start: start_position, end: end_position}
  end

  def get_range_for_interpolation({:<<>>, meta, segments}) do
    start_pos = Keyword.take(meta, [:line, :column])

    end_pos = get_end_pos_for_interpolation_segments(segments, start_pos)

    %{start: start_pos, end: end_pos}
  end

  def get_end_pos_for_interpolation_segments(segments, start_pos) do
    end_pos = Enum.reduce(segments, start_pos, fn
      string, pos when is_binary(string) ->
        lines = split_on_newline(string)
        length = String.length(List.last(lines) || "")

        [
          line: pos[:line] + length(lines) - 1,
          column: pos[:column] + length
        ]

      {:"::", _, [{_, meta, _}, {:binary, _, _}]}, _pos ->
        meta
        |> Keyword.get(:closing)
        |> Keyword.take([:line, :column])
        # Add the closing }
        |> Keyword.update!(:column, &(&1 + 1))
    end)

    Keyword.update!(end_pos, :column, &(&1 + 1))
  end

  def get_range_for_bitstring(quoted) do
    range = get_range_for_node_with_closing_line(quoted)

    # get_range_for_node_with_closing_line/1 will add 1 to the ending column
    # because it assumes it ends with ), ] or }, but bitstring closing token is
    # >>, so we need to add another 1
    update_in(range, [:end, :column], &(&1 + 1))
  end
end
