defmodule Sourceror do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias Sourceror.TraversalState

  @line_fields ~w[closing do end end_of_expression]a
  # @start_fields ~w[line do]a
  @end_fields ~w[end closing end_of_expression]a

  @type comment :: %{
          line: integer,
          previous_eol_count: integer,
          next_eol_count: integer,
          text: String.t()
        }

  @type position :: keyword
  @type range :: %{
          start: position,
          end: position
        }

  @type patch :: %{
          optional(:preserve_indentation) => boolean,
          range: range,
          change: String.t() | (String.t() -> String.t())
        }

  @type traversal_function :: (Macro.t(), TraversalState.t() -> {Macro.t(), TraversalState.t()})

  @code_module (if Version.match?(System.version(), "~> 1.13.0-dev") do
                  Code
                else
                  Sourceror.Code
                end)

  @doc """
  A wrapper around `Code.string_to_quoted_with_comments!/2` for compatibility
  with pre 1.13 Elixir versions.
  """
  defmacro string_to_quoted!(string, opts) do
    quote bind_quoted: [code_module: @code_module, string: string, opts: opts] do
      code_module.string_to_quoted_with_comments!(string, opts)
    end
  end

  @doc """
  A wrapper around `Code.string_to_quoted_with_comments/2` for compatibility
  with pre 1.13 Elixir versions.
  """
  defmacro string_to_quoted(string, opts) do
    quote bind_quoted: [code_module: @code_module, string: string, opts: opts] do
      code_module.string_to_quoted_with_comments(string, opts)
    end
  end

  @doc """
  A wrapper around `Code.quoted_to_algebra/2` for compatibility with pre 1.13
  Elixir versions.
  """
  defmacro quoted_to_algebra(quoted, opts) do
    quote bind_quoted: [code_module: @code_module, quoted: quoted, opts: opts] do
      Sourceror.Code.quoted_to_algebra(quoted, opts)
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
    with {:ok, quoted, comments} <- string_to_quoted(source, to_quoted_opts()) do
      {:ok, Sourceror.Comments.merge_comments(quoted, comments)}
    end
  end

  @doc """
  Same as `parse_string/1` but raises on error.
  """
  @spec parse_string!(String.t()) :: Macro.t()
  def parse_string!(source) do
    {quoted, comments} = string_to_quoted!(source, to_quoted_opts())
    Sourceror.Comments.merge_comments(quoted, comments)
  end

  defp to_quoted_opts do
    [
      literal_encoder: &{:ok, {:__block__, &2, [&1]}},
      token_metadata: true,
      unescape: false,
      columns: true,
      warn_on_unnecessary_quotes: false
    ]
  end

  @doc """
  Parses a single expression from the given string. It tries to parse on a
  per-line basis.

  Returns `{:ok, quoted, rest}` on success or `{:error, source}` on error.

  ## Examples
      iex> ~S"\""
      ...> 42
      ...>
      ...> :ok
      ...> "\"" |> Sourceror.parse_expression()
      {:ok, {:__block__, [trailing_comments: [], leading_comments: [],
                          token: "42", line: 2, column: 1], [42]}, "\\n:ok"}

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
      `:single_space` or `:tabs`. Defaults to `:spaces`.

    * `:format` - if set to `:splicing`, if the quoted expression is a list, it
      will strip the square brackets. This is useful to print a single element
      of a keyword list.
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

    extract_comments_opts = [collapse_comments: true, correct_lines: true] ++ opts

    {quoted, comments} = Sourceror.Comments.extract_comments(quoted, extract_comments_opts)

    text =
      quoted
      |> quoted_to_algebra(comments: comments, escape: false)
      |> Inspect.Algebra.format(line_length)
      |> IO.iodata_to_binary()
      |> String.split("\n")
      |> Enum.map_join("\n", fn line ->
        String.duplicate(indent_str, indent) <> line
      end)

    if is_list(quoted) and opts[:format] == :splicing do
      text |> String.slice(1..-2)
    else
      text
    end
  end

  @doc """
  Performs a depth-first post-order traversal of a quoted expression.

  See `postwalk/3` for more information.
  """
  @spec postwalk(Macro.t(), traversal_function) ::
          Macro.t()
  def postwalk(quoted, fun) do
    {quoted, _} = postwalk(quoted, nil, fun)
    quoted
  end

  @doc """
  Performs a depth-first post-order traversal of a quoted expression with an
  accumulator.

  `fun` is a function that will receive the current node as a first argument and
  the traversal state as the second one. It must return a `{quoted, state}`,
  in the same way it would return `{quoted, acc}` when using `Macro.postwalk/3`.

  The state is a map with the following keys:
    * `:acc` - The accumulator. Defaults to `nil` if none is given.
  """
  @spec postwalk(Macro.t(), term, traversal_function) ::
          {Macro.t(), term}
  def postwalk(quoted, acc, fun) do
    {quoted, %{acc: acc}} = Macro.traverse(quoted, %TraversalState{acc: acc}, &{&1, &2}, fun)

    {quoted, acc}
  end

  @doc """
  Performs a depth-first pre-order traversal of a quoted expression.

  See `prewalk/3` for more information.
  """
  @spec prewalk(Macro.t(), traversal_function) ::
          Macro.t()
  def prewalk(quoted, fun) do
    {quoted, _} = prewalk(quoted, nil, fun)
    quoted
  end

  @doc """
  Performs a depth-first pre-order traversal of a quoted expression with an
  accumulator.

  `fun` is a function that will receive the current node as a first argument and
  the traversal state as the second one. It must return a `{quoted, state}`,
  in the same way it would return `{quoted, acc}` when using `Macro.prewalk/3`.

  The state is a map with the following keys:
    * `:acc` - The accumulator. Defaults to `nil` if none is given.
  """
  @spec prewalk(Macro.t(), term, traversal_function) ::
          {Macro.t(), term}
  def prewalk(quoted, acc, fun) do
    {quoted, %{acc: acc}} = Macro.traverse(quoted, %TraversalState{acc: acc}, fun, &{&1, &2})

    {quoted, acc}
  end

  @doc """
  Shifts the line numbers of the node or metadata by the given `line_correction`.

  This function will update the `:line`, `:closing`, `:do`, `:end` and
  `:end_of_expression` line numbers of the node metadata if such fields are
  present.
  """
  @spec correct_lines(Macro.t() | Macro.metadata(), integer, Macro.metadata()) ::
          Macro.t() | Macro.metadata()
  def correct_lines(meta, line_correction, opts \\ [])

  def correct_lines(meta, line_correction, opts) when is_list(meta) do
    skip = Keyword.get(opts, :skip, [])

    meta
    |> apply_line_corrections(line_correction, skip)
    |> maybe_correct_line(line_correction, skip)
  end

  def correct_lines(quoted, line_correction, _opts) do
    Macro.update_meta(quoted, &correct_lines(&1, line_correction))
  end

  defp correct_line(meta, key, line_correction) do
    case Keyword.get(meta, key, []) do
      value when value != [] ->
        value =
          if value[:line] do
            put_in(value, [:line], value[:line] + line_correction)
          else
            value
          end

        [{key, value}]

      _ ->
        []
    end
  end

  defp apply_line_corrections(meta, line_correction, skip) do
    to_correct = @line_fields -- skip

    corrections = Enum.map(to_correct, &correct_line(meta, &1, line_correction))

    Enum.reduce(corrections, meta, fn correction, meta ->
      Keyword.merge(meta, correction)
    end)
  end

  defp maybe_correct_line(meta, line_correction, skip) do
    if Keyword.has_key?(meta, :line) and :line not in skip do
      Keyword.put(meta, :line, meta[:line] + line_correction)
    else
      meta
    end
  end

  @doc """
  Returns the metadata of the given node.

      iex> Sourceror.get_meta({:foo, [line: 5], []})
      [line: 5]
  """
  @spec get_meta(Macro.t()) :: Macro.metadata()
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
  Returns the line of a node. If none is found, the default value is
  returned(defaults to 1).

  A default of `nil` may also be provided if the line number is meant to be
  coalesced with a value that is not known upfront.

      iex> Sourceror.get_line({:foo, [line: 5], []})
      5

      iex> Sourceror.get_line({:foo, [], []}, 3)
      3
  """
  @spec get_line(Macro.t(), default :: integer | nil) :: integer | nil
  def get_line({_, meta, _}, default \\ 1)
      when is_list(meta) and (is_integer(default) or is_nil(default)) do
    Keyword.get(meta, :line, default)
  end

  @doc """
  Returns the column of a node. If none is found, the default value is
  returned(defaults to 1).

  A default of `nil` may also be provided if the column number is meant to be
  coalesced with a value that is not known upfront.

      iex> Sourceror.get_column({:foo, [column: 5], []})
      5

      iex> Sourceror.get_column({:foo, [], []}, 3)
      3
  """
  @spec get_column(Macro.t(), default :: integer | nil) :: integer | nil
  def get_column({_, meta, _}, default \\ 1)
      when is_list(meta) and (is_integer(default) or is_nil(default)) do
    Keyword.get(meta, :column, default)
  end

  @doc """
  Returns the line where the given node ends. It recursively checks for `end`,
  `closing` and `end_of_expression` line numbers. If none is found, the default
  value is returned(defaults to 1).

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
  @spec get_end_line(Macro.t(), integer) :: integer
  def get_end_line(quoted, default \\ 1) when is_integer(default) do
    get_end_position(quoted, line: default, column: 1)[:line]
  end

  @doc """
  Returns the start position of a node.

      iex> quoted = Sourceror.parse_string!(" :foo")
      iex> Sourceror.get_start_position(quoted)
      [line: 1, column: 2]

      iex> quoted = Sourceror.parse_string!("\\n\\nfoo()")
      iex> Sourceror.get_start_position(quoted)
      [line: 3, column: 1]

      iex> quoted = Sourceror.parse_string!("Foo.{Bar}")
      iex> Sourceror.get_start_position(quoted)
      [line: 1, column: 1]

      iex> quoted = Sourceror.parse_string!("foo[:bar]")
      iex> Sourceror.get_start_position(quoted)
      [line: 1, column: 1]

      iex> quoted = Sourceror.parse_string!("foo(:bar)")
      iex> Sourceror.get_start_position(quoted)
      [line: 1, column: 1]
  """
  @spec get_start_position(Macro.t(), position) :: position
  def get_start_position(quoted, default \\ [line: 1, column: 1])

  def get_start_position({{:., _, [Access, :get]}, _, [left | _]}, default) do
    get_start_position(left, default)
  end

  def get_start_position({{:., _, [left | _]}, _, _}, default) do
    get_start_position(left, default)
  end

  def get_start_position({_, meta, _}, default) do
    position = Keyword.take(meta, [:line, :column])

    Keyword.merge(default, position)
  end

  @doc """
  Returns the end position of the quoted expression. It recursively checks for
  `end`, `closing` and `end_of_expression` positions. If none is found, the
  default value is returned(defaults to `[line: 1, column: 1]`).

      iex> quoted = ~S"\""
      ...> A.{
      ...>   B
      ...> }
      ...> "\"" |>  Sourceror.parse_string!()
      iex> Sourceror.get_end_position(quoted)
      [line: 3, column: 1]

      iex> quoted = ~S"\""
      ...> foo do
      ...>   :ok
      ...> end
      ...> "\"" |>  Sourceror.parse_string!()
      iex> Sourceror.get_end_position(quoted)
      [line: 3, column: 1]

      iex> quoted = ~S"\""
      ...> foo(
      ...>   :a,
      ...>   :b
      ...>    )
      ...> "\"" |>  Sourceror.parse_string!()
      iex> Sourceror.get_end_position(quoted)
      [line: 4, column: 4]
  """
  @spec get_end_position(Macro.t(), position) :: position
  def get_end_position(quoted, default \\ [line: 1, column: 1]) do
    {_, position} =
      Macro.postwalk(quoted, default, fn
        {_, _, _} = quoted, end_position ->
          current_end_position = get_node_end_position(quoted, default)

          end_position =
            if compare_positions(end_position, current_end_position) == :gt do
              end_position
            else
              current_end_position
            end

          {quoted, end_position}

        terminal, end_position ->
          {terminal, end_position}
      end)

    position
  end

  defp get_node_end_position(quoted, default) do
    meta = get_meta(quoted)

    start_position = [
      line: meta[:line] || default[:line],
      column: meta[:column] || default[:column]
    ]

    get_meta(quoted)
    |> Keyword.take(@end_fields)
    |> Keyword.values()
    |> Enum.map(&Keyword.take(&1, [:line, :column]))
    |> Enum.concat([start_position])
    |> Enum.max_by(
      & &1,
      fn prev, next ->
        compare_positions(prev, next) == :gt
      end,
      fn -> default end
    )
  end

  @doc """
  Compares two positions.

  Returns `:gt` if the first position comes after the second one, and `:lt` for
  vice versa. If the two positions are equal, `:eq` is returned.

  `nil` values for lines or columns are coalesced to `0` for integer
  comparisons.
  """
  @spec compare_positions(position, position) :: :gt | :eq | :lt
  def compare_positions(left, right) do
    left = coalesce_position(left)
    right = coalesce_position(right)

    cond do
      left == right ->
        :eq

      left[:line] > right[:line] ->
        :gt

      left[:line] == right[:line] and left[:column] > right[:column] ->
        :gt

      true ->
        :lt
    end
  end

  defp coalesce_position(position) do
    line = position[:line] || 0
    column = position[:column] || 0

    [line: line, column: column]
  end

  @doc """
  Gets the range used by the given quoted expression in the source code.

  The quoted expression must have at least line and column metadata, otherwise
  it is not possible to calculate an accurate range, or to calculate it at all.
  This function is most useful when used after `Sourceror.parse_string/1`,
  before any kind of modification to the AST.

  The range is a map with `:start` and `:end` positions.

      iex> quoted = ~S"\""
      ...> def foo do
      ...>   :ok
      ...> end
      ...> "\"" |> Sourceror.parse_string!()
      iex> Sourceror.get_range(quoted)
      %{start: [line: 1, column: 1], end: [line: 3, column: 4]}

      iex> quoted = ~S"\""
      ...> Foo.{
      ...>   Bar
      ...> }
      ...> "\"" |> Sourceror.parse_string!()
      iex> Sourceror.get_range(quoted)
      %{start: [line: 1, column: 1], end: [line: 3, column: 2]}
  """
  @spec get_range(Macro.t()) :: range
  def get_range(quoted) do
    Sourceror.Range.get_range(quoted)
  end

  @doc """
  Prepends comments to the leading or trailing comments of a node.
  """
  @spec prepend_comments(
          quoted :: Macro.t(),
          comments :: [comment],
          position :: :leading | :trailing
        ) :: Macro.t()
  def prepend_comments(quoted, comments, position \\ :leading)
      when position in [:leading, :trailing] do
    do_add_comments(quoted, comments, :prepend, position)
  end

  @doc """
  Appends comments to the leading or trailing comments of a node.
  """
  @spec append_comments(
          quoted :: Macro.t(),
          comments :: [comment],
          position :: :leading | :trailing
        ) ::
          Macro.t()
  def append_comments(quoted, comments, position \\ :leading)
      when position in [:leading, :trailing] do
    do_add_comments(quoted, comments, :append, position)
  end

  defp do_add_comments({_, meta, _} = quoted, comments, mode, position) do
    key =
      case position do
        :leading -> :leading_comments
        :trailing -> :trailing_comments
      end

    current_comments = Keyword.get(meta, key, [])

    current_comments =
      case mode do
        :append -> current_comments ++ comments
        :prepend -> comments ++ current_comments
      end

    Macro.update_meta(quoted, &Keyword.put(&1, key, current_comments))
  end

  @doc false
  @spec has_closing_line?(Macro.t()) :: boolean
  def has_closing_line?({_, meta, _}) do
    for field <- @end_fields do
      Keyword.has_key?(meta, field)
    end
    |> Enum.any?()
  end

  @doc """
  Applies one or more patches to the given string.

  This functions limits itself to apply the patches in order, but it does not
  check for overlapping ranges, so make sure to pass non-overlapping patches.

  A patch is a map containing at least the range that it should patch, and the
  change to be applied in the range, for example:

      iex> original = ~S"\""
      ...> if not allowed? do
      ...>   raise "Not allowed!"
      ...> end
      ...> "\""
      iex> patch = %{
      ...>   change: "unless allowed? do\\n  raise \\"Not allowed!\\"\\nend",
      ...>   range: %{start: [line: 1, column: 1], end: [line: 3, column: 4]}
      ...> }
      iex> Sourceror.patch_string(original, [patch])
      ~S"\""
      unless allowed? do
        raise "Not allowed!"
      end
      "\""

  A range can also be a function, in which case the original text in the patch
  range will be given as an argument:

      iex> original = ~S"\""
      ...> hello :world
      ...> "\""
      iex> patch = %{
      ...>   change: &String.upcase/1,
      ...>   range: %{start: [line: 1, column: 7], end: [line: 1, column: 13]}
      ...> }
      iex> Sourceror.patch_string(original, [patch])
      ~S"\""
      hello :WORLD
      "\""

  By default, the patch will be automatically indented to match the indentation
  of the range it wants to replace if the change is a text string:

      iex> original = ~S"\""
      ...> foo do bar do
      ...>   :ok
      ...>   end end
      ...> "\""
      iex> patch = %{
      ...>   change: "baz do\\n  :not_ok\\nend",
      ...>   range: %{start: [line: 1, column: 8], end: [line: 3, column: 6]}
      ...> }
      iex> Sourceror.patch_string(original, [patch])
      ~S"\""
      foo do baz do
          :not_ok
        end end
      "\""

  If you don't want this behavior, you can add `:preserve_indentation: false` to
  your patch:

      iex> original = ~S"\""
      ...> foo do bar do
      ...>   :ok
      ...>   end end
      ...> "\""
      iex> patch = %{
      ...>   change: "baz do\\n  :not_ok\\nend",
      ...>   range: %{start: [line: 1, column: 8], end: [line: 3, column: 6]},
      ...>   preserve_indentation: false
      ...> }
      iex> Sourceror.patch_string(original, [patch])
      ~S"\""
      foo do baz do
        :not_ok
      end end
      "\""
  """
  @spec patch_string(String.t(), [patch]) :: String.t()
  def patch_string(string, patches) do
    patches = Enum.sort_by(patches, & &1.range.start[:line], &>=/2)

    lines =
      string
      |> String.split(~r/\n|\r\n|\r/)
      |> Enum.reverse()

    do_patch_string(lines, patches, [], length(lines))
    |> Enum.join("\n")
  end

  defp do_patch_string(lines, [], seen, _), do: Enum.reverse(lines) ++ seen

  defp do_patch_string([], _, seen, _), do: seen

  defp do_patch_string([line | rest], [patch | patches], seen, current_line) do
    cond do
      current_line == patch.range.start[:line] and single_line_patch?(patch) ->
        applicable_patches =
          Enum.filter([patch | patches], fn patch ->
            current_line == patch.range.start[:line] and single_line_patch?(patch)
          end)

        patched = apply_single_line_patches(line, applicable_patches)

        do_patch_string([patched | rest], patches -- applicable_patches, seen, current_line)

      current_line == patch.range.start[:line] ->
        seen = apply_multiline_patch([line | seen], patch)
        do_patch_string(rest, patches, seen, current_line - 1)

      true ->
        do_patch_string(rest, [patch | patches], [line | seen], current_line - 1)
    end
  end

  defp single_line_patch?(patch), do: patch.range.start[:line] == patch.range.end[:line]

  defp apply_single_line_patches(string, patches) do
    patches
    |> Enum.sort_by(& &1.range.start[:column], &>=/2)
    |> Enum.reduce(string, fn patch, string ->
      column_span = patch.range.end[:column] - patch.range.start[:column]
      {start, middle} = String.split_at(string, patch.range.start[:column] - 1)
      {to_patch, ending} = String.split_at(middle, column_span)

      new_text =
        if is_binary(patch.change) do
          patch.change
        else
          patch.change.(to_patch)
        end

      Enum.join([start, new_text, ending])
    end)
  end

  defp apply_multiline_patch(lines, patch) do
    line_span = patch.range.end[:line] - patch.range.start[:line] + 1

    [first | rest] = lines
    {first, first_to_patch} = String.split_at(first, patch.range.start[:column] - 1)

    {to_patch, rest} = Enum.split(rest, line_span - 1)
    {last, _} = List.pop_at(to_patch, -1, "")
    {_, last} = String.split_at(last, patch.range.end[:column] - 1)

    patch_text =
      if is_binary(patch.change) do
        patch.change
      else
        original_text = Enum.join([first_to_patch | to_patch], "\n")
        patch.change.(original_text)
      end

    [first_patch | middle_patch] = String.split(patch_text, ~r/\n|\r\n|\r/)

    middle_patch =
      if is_binary(patch.change) and Map.get(patch, :preserve_indentation, true) do
        indent = get_indent(first)

        indent =
          if String.trim(first) != "" and get_indent(List.first(middle_patch) || "") > 0 do
            # If the patch does not start at the start of the line and the next
            # lines have an additional indentation, then we need to add it to
            # prevent the "flattening" of the indentations, essentially to
            # avoid this:
            #     foo do bar do
            #       :ok
            #     end
            #     end
            indent + 1
          else
            indent
          end

        middle_patch
        |> Enum.map(&(String.duplicate("\s\s", indent) <> &1))
        |> Enum.join("\n")
      else
        middle_patch
        |> Enum.join("\n")
      end

    [first <> first_patch, middle_patch <> last | rest]
  end

  defp get_indent(string, count \\ 0)
  defp get_indent("\s\s" <> rest, count), do: get_indent(rest, count + 1)
  defp get_indent(_, count), do: count
end
