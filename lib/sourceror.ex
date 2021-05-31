defmodule Sourceror do
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias Sourceror.PostwalkState

  @line_fields ~w[closing do end end_of_expression]a
  @end_fields ~w[end closing end_of_expression]a

  @type postwalk_function :: (Macro.t(), PostwalkState.t() -> {Macro.t(), PostwalkState.t()})

  code_module =
    if Version.match?(System.version(), "~> 1.13.0-dev") do
      Code
    else
      Sourceror.Code
    end

  @code_module code_module

  @doc """
  A wrapper around `Code.string_to_quoted_with_comments!/2` for compatibility
  with pre 1.13 Elixir versions.
  """
  defmacro string_to_quoted!(string, opts) do
    quote bind_quoted: [code_module: @code_module, string: string, opts: opts], location: :keep do
      code_module.string_to_quoted_with_comments!(string, opts)
    end
  end

  @doc """
  A wrapper around `Code.string_to_quoted_with_comments/2` for compatibility
  with pre 1.13 Elixir versions.
  """
  defmacro string_to_quoted(string, opts) do
    quote bind_quoted: [code_module: @code_module, string: string, opts: opts], location: :keep do
      code_module.string_to_quoted_with_comments(string, opts)
    end
  end

  @doc """
  A wrapper around `Code.quoted_to_algebra/2` for compatibility with pre 1.13
  Elixir versions.
  """
  defmacro quoted_to_algebra(quoted, opts) do
    quote bind_quoted: [code_module: @code_module, quoted: quoted, opts: opts], location: :keep do
      code_module.quoted_to_algebra(quoted, opts)
    end
  end

  @doc """
  Parses the source code into an extended AST suitable for source manipulation
  as described in `Code.quoted_to_algebra/2`.

  Two additional fields are added to nodes metadata:
    * `:leading_comments` - a list holding the comments found *before* the node.
    * `:trailing_comments` - a list holding the comments found before the end of
      the node. For example, comments right before the `end` keyword.

  Comments are the same maps returned by `Code.string_to_quoted_with_comments/2`.
  """
  @spec parse_string(String.t()) :: {:ok, Macro.t()} | {:error, term()}
  def parse_string(source) do
    to_quoted_opts = [
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      token_metadata: true,
      unescape: false
    ]

    with {:ok, quoted, comments} <- string_to_quoted(source, to_quoted_opts) do
      {:ok, Sourceror.Comments.merge_comments(quoted, comments)}
    end
  end

  @doc """
  Same as `parse_string/1` but raises on error.
  """
  @spec parse_string!(String.t()) :: Macro.t()
  def parse_string!(source) do
    case parse_string(source) do
      {:ok, quoted} ->
        quoted

      {:error, {location, error, token}} ->
        :sourceror_errors.parse_error(location, "nofile", error, token)
    end
  end

  @doc """
  Parses a single expression from the given string.

  Returns `{:ok, quoted, rest}` on success or `{:error, source}` on error.

  ## Examples
      iex> ~S"\""
      ...> 42
      ...>
      ...> :ok
      ...> "\"" |> Sourceror.parse_expression()
      {:ok, {:__block__, [trailing_comments: [], leading_comments: [],
                          token: "42", line: 2], [42]}, "\\n:ok"}

  ## Options
    * `:from_line` - The line at where the parsing should start. Defaults to `1`.
  """
  @spec parse_expression(String.t(), keyword) ::
          {:ok, Macro.t(), String.t()} | {:error, String.t()}
  def parse_expression(string, opts \\ []) do
    from_line = Keyword.get(opts, :from_line, 1)

    lines =
      Regex.split(~r/\r\n|\r|\n/, String.trim(string))
      |> Enum.drop(from_line - 1)

    do_parse_expression(lines, "")
  end

  defp do_parse_expression([], acc), do: {:error, acc}

  defp do_parse_expression([line | rest], acc) do
    string = Enum.join([acc, line], "\n")

    case parse_string(string) do
      # Skip empty lines
      {:ok, {:__block__, _, []}} ->
        do_parse_expression(rest, string)

      {:ok, quoted} ->
        {:ok, quoted, Enum.join(rest, "\n")}

      {:error, _reason} ->
        do_parse_expression(rest, string)
    end
  end

  @doc """
  Converts a quoted expression to a string.

  The comments line number will be ignored and the line number of the associated
  node will be used when formatting the code.

  ## Options
    * `:line_length` - The max line length for the formatted code.

    * `:indent` - how many indentations to insert at the start of each line.
      Note that this only prepends the indents without checking the indentation
      of nested blocks. Defaults to `0`.

    * `:indent_type` - the type of indentation to use. It can be one of `:spaces`,
      `:single_space` or `:tabs`. Defaults to `:spaces`;
  """
  @spec to_string(Macro.t(), keyword) :: String.t()
  def to_string(quoted, opts \\ []) do
    indent = Keyword.get(opts, :indent, 0)
    line_length = Keyword.get(opts, :line_length, 98)

    indent_str =
      case Keyword.get(opts, :indent_type, :spaces) do
        :spaces -> "\s\s"
        :single_space -> "\s"
        :tabs -> "\t"
      end

    {quoted, comments} = Sourceror.Comments.extract_comments(quoted)

    quoted
    |> quoted_to_algebra(comments: comments)
    |> Inspect.Algebra.format(line_length)
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
  Performs a depth-first post-order traversal of a quoted expression with an
  accumulator, correcting line numbers as it goes.

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
      should be shifted. Note that this field is cumulative, setting it to 0
      will reset it for the whole traversal. Starts at `0`.

    * `:acc` - The accumulator. Defaults to `nil` if none is given.
  """
  @spec postwalk(Macro.t(), term, postwalk_function) ::
          {Macro.t(), term}
  def postwalk(quoted, acc, fun) do
    {quoted, %{acc: acc}} =
      Macro.postwalk(quoted, %PostwalkState{acc: acc}, fn
        {_, _, _} = quoted, state ->
          quoted = Macro.update_meta(quoted, &correct_lines(&1, state.line_correction))
          fun.(quoted, state)

        quoted, state ->
          fun.(quoted, state)
      end)

    {quoted, acc}
  end

  @doc """
  Shifts the line numbers of the node or metadata by the given `line_correction`.

  This function will update the `:line`, `:closing`, `:do`, `:end` and
  `:end_of_expression` line numbers of the node metadata if such fields are
  present.
  """
  @spec correct_lines(Macro.t() | keyword, integer) :: keyword
  def correct_lines(meta, line_correction) when is_list(meta) do
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

  def correct_lines(quoted, line_correction) do
    Macro.update_meta(quoted, &correct_lines(&1, line_correction))
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

  @doc """
  Returns the metadata of the given node.

      iex> Sourceror.get_meta({:foo, [line: 5], []})
      [line: 5]
  """
  @spec get_meta(Macro.t()) :: keyword
  def get_meta({_, meta, _}) when is_list(meta) do
    meta
  end

  @doc """
  Returns the arguments of the node.

      iex> Sourceror.get_args({:foo, [], [{:__block__, [], [:ok]}]})
      [{:__block__, [], [:ok]}]
  """
  @spec get_args(Macro.t()) :: [Macro.t()]
  def get_args({_, _, args}) do
    args
  end

  @doc """
  Updates the arguments for the given node.

      iex> node = {:foo, [line: 1], [{:__block__, [line: 1], [2]}]}
      iex> updater = fn args -> Enum.map(args, &Sourceror.correct_lines(&1, 2)) end
      iex> Sourceror.update_args(node, updater)
      {:foo, [line: 1], [{:__block__, [line: 3], [2]}]}
  """
  @spec update_args(Macro.t(), ([Macro.t()] -> [Macro.t()])) :: Macro.t()
  def update_args({form, meta, args}, fun) when is_function(fun, 1) and is_list(args) do
    {form, meta, fun.(args)}
  end

  @doc """
  Returns the line of a node.

      iex> Sourceror.get_line({:foo, [line: 5], []})
      5

      iex> Sourceror.get_line({:foo, [], []}, 3)
      3

      iex> Sourceror.get_line(:ok)
      1
  """
  @spec get_line(Macro.t(), default :: integer) :: integer
  def get_line(quoted, default \\ 1)

  def get_line({_, meta, _}, default) when is_list(meta) do
    Keyword.get(meta, :line, default)
  end

  def get_line(_, default) do
    default
  end

  @doc """
  Returns the line where the given node ends. It recursively checks for `end`,
  `closing` and `end_of_expression` line numbers.

      iex> Sourceror.get_end_line({:foo, [end: [line: 4]], []})
      4

      iex> Sourceror.get_end_line({:foo, [closing: [line: 2]], []})
      2

      iex> Sourceror.get_end_line({:foo, [end_of_expression: [line: 5]], []})
      5

      iex> Sourceror.get_end_line({:foo, [closing: [line: 2], end: [line: 4]], []})
      4

      iex> "\""
      ...> alias Foo.{
      ...>   Bar
      ...> }
      ...> "\"" |> Sourceror.parse_string!() |> Sourceror.get_end_line()
      3
  """
  @spec get_end_line(Macro.t(), integer()) :: integer()
  def get_end_line(quoted, default \\ 1) do
    {_, line} =
      Macro.postwalk(quoted, default, fn
        {_, _, _} = quoted, end_line ->
          {quoted, max(end_line, get_node_end_line(quoted, default))}

        terminal, end_line ->
          {terminal, end_line}
      end)

    line
  end

  defp get_node_end_line(quoted, default) do
    get_meta(quoted)
    |> Keyword.take(@end_fields)
    |> Keyword.values()
    |> Enum.map(&Keyword.get(&1, :line))
    |> Enum.max(fn -> default end)
  end

  @doc """
  Returns how many lines a quoted expression used in the original source code.

      iex> "foo do :ok end" |> Sourceror.parse_string!() |> Sourceror.get_line_span()
      1

      iex> "\""
      ...> foo do
      ...>   :ok
      ...> end
      ...> "\"" |> Sourceror.parse_string!() |> Sourceror.get_line_span()
      3
  """
  @spec get_line_span(Macro.t()) :: integer()
  def get_line_span(quoted) do
    start_line = get_line(quoted)
    end_line = get_end_line(quoted)

    1 + end_line - start_line
  end
end
