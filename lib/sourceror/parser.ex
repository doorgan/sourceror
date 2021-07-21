defmodule Sourceror.Parser do
  @moduledoc false

  require Sourceror

  defguard is_valid_sigil(letter) when letter in ?a..?z or letter in ?A..?Z

  def parse!(string) do
    with {quoted, comments} <- Sourceror.string_to_quoted!(string, to_quoted_opts()) do
      quoted = normalize_nodes(quoted)

      Sourceror.Comments.merge_comments(quoted, comments)
    end
  end

  def parse(string) do
    with {:ok, quoted, comments} <- Sourceror.string_to_quoted(string, to_quoted_opts()) do
      quoted = normalize_nodes(quoted)

      {:ok, Sourceror.Comments.merge_comments(quoted, comments)}
    end
  end

  defp to_quoted_opts do
    [
      literal_encoder: &handle_literal/2,
      token_metadata: true,
      unescape: false,
      columns: true,
      warn_on_unnecessary_quotes: false
    ]
  end

  defp handle_literal(atom, metadata) when is_atom(atom) do
    {:ok, {:atom, metadata ++ [__literal__: true], atom}}
  end

  defp handle_literal(string, metadata) when is_binary(string) do
    {:ok, {:string, normalize_metadata(metadata), string}}
  end

  defp handle_literal({left, right}, metadata) do
    {:ok, {:{}, normalize_metadata(metadata), [left, right]}}
  end

  defp handle_literal(list, metadata) when is_list(list) do
    if metadata[:delimiter] do
      {:ok, {:charlist, metadata, List.to_string(list)}}
    else
      {:ok, {[], normalize_metadata(metadata), list}}
    end
  end

  defp handle_literal(integer, metadata) when is_integer(integer) do
    {:ok, {:int, normalize_metadata(metadata), integer}}
  end

  defp handle_literal(float, metadata) when is_float(float) do
    {:ok, {:float, normalize_metadata(metadata), float}}
  end

  @doc """
  Converts regular AST nodes into Sourceror AST nodes.
  """
  @spec normalize_nodes(Sourceror.ast_node()) :: Sourceror.ast_node()
  def normalize_nodes(ast) do
    Sourceror.postwalk(ast, &normalize_node/1)
  end

  defp normalize_node({:atom, metadata, atom}) when is_atom(atom) do
    if metadata[:__literal__] do
      {:atom, normalize_metadata(metadata), atom}
    else
      {:var, normalize_metadata(metadata), atom}
    end
  end

  defp normalize_node({name, metadata, context})
       when is_atom(name) and is_atom(context) do
    {:var, normalize_metadata(metadata), name}
  end

  defp normalize_node({:<<>>, metadata, segments}) do
    metadata = normalize_metadata(metadata)

    start_pos = Map.take(metadata, [:line, :column])

    if metadata[:delimiter] do
      metadata =
        if metadata.delimiter in ~w[""" '''] do
          Map.put(metadata, :indentation, metadata.indentation)
        else
          metadata
        end

      start_pos =
        if metadata.delimiter in ~w[""" '''] do
          %{
            line: start_pos.line + 1,
            column: metadata.indentation + 1
          }
        else
          %{
            line: start_pos.line,
            column: start_pos.column + 2 + String.length(metadata.delimiter)
          }
        end

      {{:<<>>, :string}, metadata, normalize_interpolation(segments, start_pos)}
    else
      {:<<>>, normalize_metadata(metadata), segments}
    end
  end

  defp normalize_node(
         {{:., _, [:erlang, :binary_to_atom]}, metadata, [{:<<>>, _, segments}, :utf8]}
       ) do
    metadata = normalize_metadata(metadata)
    start_pos = Map.take(metadata, [:line, :column])

    metadata =
      if metadata.delimiter in ~w[""" '''] do
        Map.put(metadata, :indentation, metadata.indentation)
      else
        metadata
      end

    start_pos =
      if metadata.delimiter in ~w[""" '''] do
        %{
          line: start_pos.line + 1,
          column: metadata.indentation + 1
        }
      else
        %{
          line: start_pos.line,
          column: start_pos.column + 2 + String.length(metadata.delimiter)
        }
      end

    {{:<<>>, :atom}, metadata, normalize_interpolation(segments, start_pos)}
  end

  defp normalize_node({sigil, metadata, [args, modifiers]})
       when is_atom(sigil) and is_list(modifiers) do
    case Atom.to_string(sigil) do
      <<"sigil_", sigil>> when is_valid_sigil(sigil) ->
        {:<<>>, args_meta, args} = args

        start_pos = Map.take(args_meta, [:line, :column])

        metadata = normalize_metadata(metadata)

        metadata =
          if metadata.delimiter in ~w[""" '''] do
            Map.put(metadata, :indentation, args_meta.indentation)
          else
            metadata
          end

        start_pos =
          if metadata.delimiter in ~w[""" '''] do
            %{
              line: start_pos.line + 1,
              column: args_meta.indentation + 1
            }
          else
            %{
              line: start_pos.line,
              column: start_pos.column + 2 + String.length(metadata.delimiter)
            }
          end

        {:"~", metadata, [<<sigil>>, normalize_interpolation(args, start_pos), modifiers]}

      _ ->
        {sigil, normalize_metadata(metadata), [args, modifiers]}
    end
  end

  defp normalize_node({form, metadata, args}), do: {form, normalize_metadata(metadata), args}

  defp normalize_node(quoted), do: quoted

  defp normalize_interpolation(segments, start_pos) do
    {segments, _} =
      Enum.reduce(segments, {[], start_pos}, fn
        string, {segments, pos} when is_binary(string) ->
          lines = split_on_newline(string)
          length = String.length(List.last(lines) || "")

          line_count = length(lines) - 1

          column =
            if line_count > 0 do
              start_pos.column + length
            else
              pos.column + length
            end

          {[{:string, pos, string} | segments],
           %{
             line: pos.line + line_count,
             column: column + 1
           }}

        {:"::", _, [{_, meta, _}, {_, _, :binary}]} = segment, {segments, _pos} ->
          pos =
            meta.closing
            |> Map.take([:line, :column])
            # Add the closing }
            |> Map.update!(:column, &(&1 + 1))

          {[segment | segments], pos}
      end)

    Enum.reverse(segments)
  end

  defp split_on_newline(string) do
    String.split(string, ~r/\n|\r\n|\r/)
  end

  @doc """
  Converts Sourceror AST back to regular Elixir AST for use with the formatter.
  """
  def to_formatter_ast(quoted) do
    Sourceror.prewalk(quoted, fn
      {:atom, meta, atom} when is_atom(atom) ->
        block(to_formatter_meta(meta), atom)

      {:string, meta, string} when is_binary(string) ->
        block(to_formatter_meta(meta), string)

      {:int, meta, int} when is_integer(int) ->
        block(to_formatter_meta(meta), int)

      {:float, meta, float} when is_float(float) ->
        block(to_formatter_meta(meta), float)

      {[], meta, list} ->
        block(to_formatter_meta(meta), list)

      {:"~", meta, [name, args, modifiers]} ->
        args_meta = Map.take(meta, [:line, :column, :indentation])
        meta = Map.drop(meta, [:indentation])

        args =
          Enum.map(args, fn
            {:string, _, string} -> string
            quoted -> quoted
          end)

        {:"sigil_#{name}", to_formatter_meta(meta), [{:<<>>, args_meta, args}, modifiers]}

      {{:<<>>, :atom}, meta, segments} ->
        meta = to_formatter_meta(meta)
        dot_meta = Keyword.take(meta, [:line, :column])
        args_meta = Keyword.take(meta, [:line, :column, :indentation])
        meta = Keyword.drop(meta, [:indentation])

        args =
          Enum.map(segments, fn
            {:string, _, string} -> string
            quoted -> quoted
          end)

        {{:., dot_meta, [:erlang, :binary_to_atom]}, meta, [{:<<>>, args_meta, args}]}

      {{:<<>>, :string}, meta, args} ->
        args =
          Enum.map(args, fn
            {:string, _, string} -> string
            quoted -> quoted
          end)

        {:<<>>, meta, args}

      {:var, meta, name} ->
        {name, to_formatter_meta(meta), nil}

      {:{}, meta, [left, right]} ->
        block(to_formatter_meta(meta), {left, right})

      {form, meta, args} ->
        {form, to_formatter_meta(meta), args}

      quoted ->
        quoted
    end)
  end

  defp block(metadata, value), do: {:__block__, metadata, [value]}

  defp normalize_metadata(metadata) do
    meta = Map.new(metadata) |> Map.drop([:__literal__])

    for key <- ~w[last end_of_expression closing do end]a,
        meta[key] != nil,
        into: meta,
        do: {key, normalize_metadata(meta[key])}
  end

  defp to_formatter_meta(metadata) do
    meta = Map.to_list(metadata)

    extra =
      for key <- ~w[last end_of_expression closing do end]a,
          meta[key] != nil,
          do: {key, to_formatter_meta(meta[key])}

    Keyword.merge(meta, extra)
  end
end
