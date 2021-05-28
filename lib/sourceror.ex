defmodule Sourceror do
  @moduledoc """
  Utilities to work with Elixir source code.
  """

  @line_fields [
    :closing,
    :do,
    :end,
    :end_of_expression
  ]

  @type traversal_state :: %{line_correction: integer}
  @type postwalk_function :: (Macro.t(), traversal_state -> {Macro.t(), traversal_state})

  code_module =
    if Version.match?(System.version(), "~> 1.13.0-dev") do
      Code
    else
      Sourceror.Code
    end

  @code_module code_module

  @spec do_parse_string(any, any) :: {:__block__, [], [{:= | {any, any, any}, list, [...]}, ...]}
  defmacro do_parse_string(string, opts \\ []) do
    quote bind_quoted: [code_module: @code_module, string: string, opts: opts], location: :keep do
      code_module.string_to_quoted_with_comments!(string, opts)
    end
  end

  defmacro quoted_to_algebra(quoted, opts \\ []) do
    quote bind_quoted: [code_module: @code_module, quoted: quoted, opts: opts], location: :keep do
      code_module.quoted_to_algebra(quoted, opts)
    end
  end

  @doc """
  Parses the source code into an extended AST suitable for source manipulation
  as described in `Code.quoted_to_algebra/2`.

  Two additional fields are added to nodes metadata:
    * `:leading_comments` - a list holding the comments found *before* the node.
    * `:trailing_comments` - a list holding the comments found before the end
      of the node. For example, comments right before the `end` keyword.

  Comments are the same maps returned by `Code.string_to_quoted_with_comments/2`.
  """
  @spec parse_string(String.t()) :: Macro.t()
  def parse_string(source) do
    {quoted, comments} =
      do_parse_string(source,
        literal_encoder: &{:ok, {:__block__, &2, [&1]}},
        token_metadata: true,
        unescape: false
      )

    Sourceror.Comments.merge_comments(quoted, comments)
  end

  @doc """
  Converts a quoted expression to a string.

  The comments line number will be ignored and the line number of the associated
  node will be used when formatting the code.

  ## Options
    * `:indent` - how many indentations to insert at the start of each line.
      Note that this only prepends the indents without checking the indentation
      of nested blocks. Defaults to `0`.

    * `:indent_type` - the type of indentation to use. It can be one of `:spaces`,
      `:single_space` or `:tabs`. Defaults to `:spaces`;
  """
  @spec to_string(Macro.t(), keyword) :: String.t()
  def to_string(quoted, opts \\ []) do
    indent = Keyword.get(opts, :indent, 0)

    indent_str =
      case Keyword.get(opts, :indent_type, :spaces) do
        :spaces -> "\s\s"
        :single_space -> "\s"
        :tabs -> "\t"
      end

    {quoted, comments} = Sourceror.Comments.extract_comments(quoted)

    quoted
    |> quoted_to_algebra(comments: comments)
    |> Inspect.Algebra.format(98)
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.map_join("\n", fn line ->
      String.duplicate(indent_str, indent) <> line
    end)
  end

  @doc """
  Performs a depth-first post-order traversal of a quoted expression, correcting
  line numbers as it goes.

  See `postwalk/3` for more information.
  """
  @spec postwalk(Macro.t(), postwalk_function) ::
          Macro.t()
  def postwalk(quoted, fun) do
    {quoted, _} = postwalk(quoted, nil, fun)
    quoted
  end

  @doc """
  Performs a depth-first post-order traversal of a quoted expression with an accumulator, correcting
  line numbers as it goes.

  `fun` is a function that will receive the current node as a first argument and
  the traversal state as the second one. It must return a `{quoted, state}`,
  in the same way it would return `{quoted, acc}` when using `Macro.postwalk/3`.

  Before calling `fun` in a node, its line numbers will be corrected by the
  `state.line_correction`. If you need to manually correct the line number of
  a node, use `correct_lines/2`.

  The state is a map with the following keys:
    * `:line_correction` - an integer representing how many lines subsequent
      nodes should be shifted. If the function *adds* more nodes to the tree
      that should go in a new line, the line numbers of the subsequent nodes
      need to be updated in order for comments to be correctly placed during the
      formatting process. If the function does this kind of change, it must
      update the `:line_correction` field by adding the amount of lines that
      should be shifted. Note that this field is cumulative, setting it to 0 will
      reset it for the whole traversal. Starts at `0`.

    * `:acc` - The accumulator. Defaults to `nil` if none is given.
  """
  @spec postwalk(Macro.t(), term, postwalk_function) ::
          {Macro.t(), term}
  def postwalk(quoted, acc, fun) do
    {quoted, %{acc: acc}} =
      Macro.postwalk(quoted, %{acc: acc, line_correction: 0}, fn
        {_, _, _} = quoted, state ->
          quoted = Macro.update_meta(quoted, &correct_lines(&1, state.line_correction))
          fun.(quoted, state)

        quoted, state ->
          fun.(quoted, state)
      end)

    {quoted, acc}
  end

  @doc """
  Shifts the line numbers of the node by the given `line_correction`.

  This function will update the `:line`, `:closing`, `:do`, `:end` and
  `:end_of_expression` line numbers of the node metadata if such fields are
  present.
  """
  @spec correct_lines(keyword, integer) :: keyword
  def correct_lines(meta, line_correction) do
    meta =
      if line = meta[:line] do
        Keyword.put(meta, :line, line + line_correction)
      else
        meta
      end

    corrections = Enum.map(@line_fields, &correct_line(meta, &1, line_correction))

    Enum.reduce(corrections, meta, fn correction, meta ->
      Keyword.merge(meta, correction)
    end)
  end

  defp correct_line(meta, key, line_correction) do
    case Keyword.get(meta, key, []) do
      value when value != [] ->
        value = put_in(value, [:line], value[:line] + line_correction)
        [{key, value}]

      _ ->
        []
    end
  end

  @doc delegate_to: {Sourceror.Comments, :merge_comments, 2}
  defdelegate merge_comments(quoted, comments), to: Sourceror.Comments

  @doc delegate_to: {Sourceror.Comments, :extract_comments, 1}
  defdelegate extract_comments(quoted), to: Sourceror.Comments
end
