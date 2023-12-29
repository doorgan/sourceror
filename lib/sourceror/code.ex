if Version.match?(System.version(), "< 1.13.0") do
  defmodule Sourceror.Code do
    @moduledoc false

    alias Sourceror.Code.Formatter
    alias Sourceror.Code.Normalizer

    @spec string_to_quoted_with_comments(List.Chars.t(), keyword) ::
            {:ok, Macro.t(), list(map())} | {:error, {location :: keyword, term, term}}
    def string_to_quoted_with_comments(string, opts \\ [])
        when is_binary(string) and is_list(opts) do
      charlist = to_charlist(string)
      file = Keyword.get(opts, :file, "nofile")
      line = Keyword.get(opts, :line, 1)
      column = Keyword.get(opts, :column, 1)

      Process.put(:code_formatter_comments, [])
      opts = [preserve_comments: &preserve_comments/5] ++ opts

      with {:ok, tokens} <-
             :sourceror_elixir.string_to_tokens(charlist, line, column, file, opts),
           {:ok, forms} <- :sourceror_elixir.tokens_to_quoted(tokens, file, opts) do
        comments = Enum.reverse(Process.get(:code_formatter_comments))
        {:ok, forms, comments}
      end
    after
      Process.delete(:code_formatter_comments)
    end

    @spec string_to_quoted_with_comments!(List.Chars.t(), keyword) :: {Macro.t(), list(map())}
    def string_to_quoted_with_comments!(string, opts \\ []) do
      case string_to_quoted_with_comments(string, opts) do
        {:ok, forms, comments} ->
          {forms, comments}

        {:error, {location, error, token}} ->
          :sourceror_errors.parse_error(
            location,
            Keyword.get(opts, :file, "nofile"),
            error,
            token
          )
      end
    end

    defp preserve_comments(line, column, tokens, comment, rest) do
      comments = Process.get(:code_formatter_comments)

      comment = %{
        line: line,
        column: column,
        previous_eol_count: previous_eol_count(tokens),
        next_eol_count: next_eol_count(rest, 0),
        text: List.to_string(comment)
      }

      Process.put(:code_formatter_comments, [comment | comments])
    end

    defp next_eol_count(~c"\s" ++ rest, count), do: next_eol_count(rest, count)
    defp next_eol_count(~c"\t" ++ rest, count), do: next_eol_count(rest, count)
    defp next_eol_count(~c"\n" ++ rest, count), do: next_eol_count(rest, count + 1)
    defp next_eol_count(~c"\r\n" ++ rest, count), do: next_eol_count(rest, count + 1)
    defp next_eol_count(_, count), do: count

    defp previous_eol_count([{token, {_, _, count}} | _])
         when token in [:eol, :",", :";"] and count > 0 do
      count
    end

    defp previous_eol_count([]), do: 1
    defp previous_eol_count(_), do: 0

    @spec quoted_to_algebra(Macro.t(), keyword) :: Inspect.Algebra.t()
    def quoted_to_algebra(quoted, opts \\ []) do
      quoted
      |> Normalizer.normalize(opts)
      |> Formatter.to_algebra(opts)
    end

    if Version.match?(System.version(), "~> 1.14 or 1.14.0-dev") do
      def classify_atom(atom) do
        apply(Macro, :classify_atom, [atom])
      end

      def inspect_atom(type, atom) do
        apply(Macro, :inspect_atom, [type, atom])
      end
    else
      def classify_atom(atom) do
        apply(Code.Identifier, :classify, [atom])
      end

      def inspect_atom(:remote_call, atom) do
        apply(Code.Identifier, :inspect_as_function, [atom])
      end
    end
  end
end
