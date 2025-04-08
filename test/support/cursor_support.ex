defmodule SourcerorTest.CursorSupport do
  @moduledoc false

  @doc """
  Extracts the `[:line, :column]` position of the first `|` character found in the text.

  Returns `{position, text}`.
  """
  def pop_cursor(text) do
    case String.split(text, "|", parts: 2) do
      [prefix, suffix] ->
        lines = String.split(prefix, "\n")
        cursor_line_length = lines |> List.last() |> String.length()
        position = [line: length(lines), column: cursor_line_length + 1]
        {position, prefix <> suffix}

      _ ->
        raise ArgumentError, "Could not find cursor in:\n\n#{text}"
    end
  end

  @doc """
  Extracts a `Sourceror.Range` from the text enclosed in `«` and `»` characters.
  """
  def pop_range(text) do
    with [before_text, after_text] <- String.split(text, "«", parts: 2),
         [range_text, after_text] <- String.split(after_text, "»", parts: 2) do
      lines_before = String.split(before_text, "\n")
      range_lines = String.split(range_text, "\n")
      last_before_line = lines_before |> List.last()

      start_line = length(lines_before)
      end_line = start_line + length(range_lines) - 1

      start_column = String.length(last_before_line)
      end_column = range_lines |> List.last() |> String.length()

      end_column =
        if last_before_line == "" do
          end_column
        else
          end_column + start_column
        end

      range = %Sourceror.Range{
        start: [line: start_line, column: start_column],
        end: [line: end_line, column: end_column + 1]
      }

      text = before_text <> range_text <> after_text

      {range, text}
    else
      _ -> raise ArgumentError, "Could not find range in:\n\n#{text}"
    end
  end
end
