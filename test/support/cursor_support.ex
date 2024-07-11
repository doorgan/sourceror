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
end
