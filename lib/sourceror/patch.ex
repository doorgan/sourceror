defmodule Sourceror.Patch do
  @moduledoc """
  Functions that generate patches for common operations.

  Functions in this module assume that the AST was parsed using Sourceror
  functions and that it wasn't modified. If you changed the tree before calling
  `Sourceror.Patch` functions, then the patch ranges are not guaranteed to match
  1:1 with the original source code.
  """

  @doc """
  Renames a qualified or unqualified function call.

  ## Examples

      iex> original = "String.to_atom(foo)"
      iex> ast = Sourceror.parse_string!(original)
      iex> patches = Sourceror.Patch.rename_call(ast, :to_existing_atom)
      iex> Sourceror.patch_string(original, patches)
      "String.to_existing_atom(foo)"
  """
  @spec rename_call(call :: Macro.t(), new_name :: atom | String.t()) :: [Sourceror.patch()]
  def rename_call({{:., _, [_, call]}, meta, _}, new_name) do
    new_name = to_string(new_name)

    start_pos = [line: meta[:line], column: meta[:column]]
    end_pos = [line: meta[:line], column: meta[:column] + String.length(to_string(call))]
    range = %{start: start_pos, end: end_pos}

    [%{range: range, change: new_name}]
  end

  def rename_call({call, meta, args}, new_name) when is_atom(call) and is_list(args) do
    new_name = to_string(new_name)

    start_pos = [line: meta[:line], column: meta[:column]]
    end_pos = [line: meta[:line], column: meta[:column] + String.length(to_string(call))]
    range = %{start: start_pos, end: end_pos}

    [%{range: range, change: new_name}]
  end

  @doc """
  Renames an identifier(ie a variable name).

  ## Examples

      iex> original = "foo"
      iex> ast = Sourceror.parse_string!(original)
      iex> patches = Sourceror.Patch.rename_identifier(ast, :bar)
      iex> Sourceror.patch_string(original, patches)
      "bar"
  """
  @spec rename_call(call :: Macro.t(), new_name :: atom | String.t()) :: [Sourceror.patch()]
  def rename_identifier({identifier, meta, context}, new_name) when is_atom(context) do
    new_name = to_string(new_name)

    start_pos = [line: meta[:line], column: meta[:column]]
    end_pos = [line: meta[:line], column: meta[:column] + String.length(to_string(identifier))]
    range = %{start: start_pos, end: end_pos}

    [%{range: range, change: new_name}]
  end

  @doc """
  Generates patches that rename the keys of a keyword list.

  The replacements is a keyword list, with the keys to replace as keys, and the
  replacement as the value.

  ## Examples

      iex> original = "[a: b, c: d, e: f]"
      iex> ast = Sourceror.parse_string!(original)
      iex> patches = Sourceror.Patch.rename_kw_keys(ast, a: :foo, e: :bar)
      iex> Sourceror.patch_string(original, patches)
      "[foo: b, c: d, bar: f]"
  """
  @spec rename_kw_keys(keyword :: Macro.t(), replacements :: keyword) :: [Sourceror.patch()]
  def rename_kw_keys({:__block__, _, [elems]}, replacements) when is_list(elems) do
    for {{_, meta, [key]} = quoted, _} <- elems,
        meta[:format] == :keyword,
        new_key = replacements[key],
        new_key != nil do
      range =
        quoted
        |> Sourceror.get_range()
        |> update_in([:end, :column], &(&1 - 1))

      %{range: range, change: to_string(new_key)}
    end
  end
end
