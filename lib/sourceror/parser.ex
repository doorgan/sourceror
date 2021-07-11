defmodule Sourceror.Parser do
  @moduledoc false

  require Sourceror

  defguard is_valid_sigil(letter) when letter in ?a..?z or letter in ?A..?Z

  def parse(string) do
    {quoted, comments} = Sourceror.string_to_quoted!(string, to_quoted_opts())

    quoted = normalize_nodes(quoted)

    Sourceror.Comments.merge_comments(quoted, comments)
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
    {:ok, {:string, metadata, string}}
  end

  defp handle_literal({left, right}, metadata) do
    {:ok, {:{}, metadata, [left, right]}}
  end

  defp handle_literal(list, metadata) when is_list(list) do
    {:ok, {[], metadata, list}}
  end

  defp handle_literal(integer, metadata) when is_integer(integer) do
    {:ok, {:int, metadata, integer}}
  end

  defp handle_literal(float, metadata) when is_float(float) do
    {:ok, {:float, metadata, float}}
  end

  defp normalize_nodes(ast) do
    Sourceror.prewalk(ast, &normalize_node/1)
  end

  defp normalize_node({:atom, metadata, atom}) when is_atom(atom) do
    if metadata[:__literal__] do
      {:atom, Keyword.drop(metadata, [:__literal__]), atom}
    else
      {:var, metadata, atom}
    end
  end

  defp normalize_node({name, metadata, context})
       when is_atom(name) and is_atom(context) do
    {:var, metadata, name}
  end

  defp normalize_node({sigil, metadata, [args, modifiers]} = quoted)
       when is_atom(sigil) and is_list(modifiers) do
    case Atom.to_string(sigil) do
      <<"sigil_", sigil>> when is_valid_sigil(sigil) ->
        {{:sigil, <<sigil>>}, metadata, [args, modifiers]}

      _ ->
        quoted
    end
  end

  defp normalize_node(quoted), do: quoted

  @doc false
  def to_formatter_ast(quoted) do
    Sourceror.prewalk(quoted, fn
      {:atom, meta, atom} when is_atom(atom) ->
        block(meta, atom)

      {:string, meta, string} when is_binary(string) ->
        block(meta, string)

      {:int, meta, int} when is_integer(int) ->
        block(meta, int)

      {:float, meta, float} when is_float(float) ->
        block(meta, float)

      {[], meta, list} ->
        block(meta, list)

      {{:sigil, name}, meta, [args, modifiers]} ->
        {:"sigil_#{name}", meta, [args, modifiers]}

      {:var, meta, name} ->
        {name, meta, nil}

      {:{}, meta, [left, right]} ->
        block(meta, {left, right})

      quoted ->
        quoted
    end)
  end

  defp block(metadata, value), do: {:__block__, metadata, [value]}
end
