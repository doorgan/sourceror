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
    {:ok, {[], normalize_metadata(metadata), list}}
  end

  defp handle_literal(integer, metadata) when is_integer(integer) do
    {:ok, {:int, normalize_metadata(metadata), integer}}
  end

  defp handle_literal(float, metadata) when is_float(float) do
    {:ok, {:float, normalize_metadata(metadata), float}}
  end

  defp normalize_nodes(ast) do
    Sourceror.prewalk(ast, &normalize_node/1)
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

  defp normalize_node({sigil, metadata, [args, modifiers]})
       when is_atom(sigil) and is_list(modifiers) do
    case Atom.to_string(sigil) do
      <<"sigil_", sigil>> when is_valid_sigil(sigil) ->
        {:"~", normalize_metadata(metadata), [<<sigil>>, args, modifiers]}

      _ ->
        {sigil, normalize_metadata(metadata), [args, modifiers]}
    end
  end

  defp normalize_node({form, metadata, args}), do: {form, normalize_metadata(metadata), args}

  defp normalize_node(quoted), do: quoted

  @doc false
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
        {:"sigil_#{name}", to_formatter_meta(meta), [args, modifiers]}

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
