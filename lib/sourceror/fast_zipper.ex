defmodule Sourceror.FastZipper do
  @moduledoc """
  High performance alternative to `Sourceror.Zipper`.

  This implementation is experimental and may change in the future.
  Use this module *only* if performance is a concern and the experimental
  nature of this module is worth the performance savings.

  This implementation is also NOT compatible with `Sourceror.Zipper`.

  ## Usage

  This implementation uses records instead of structs, so you should use
  `zipper/1`, `zipper/2`, `path/1` and `path/2` to read, create or update
  zippers and their paths:

      # Zipper
      %Zipper{node: 42}

      # FastZipper
      zipper(node: 42)

      # Zipper
      zipper.path

      # FastZipper
      zipper(zipper, :path)

      # Zipper
      %Zipper{zipper | node: 42}

      # FastZipper
      zipper(zipper, node: 42)


      # Zipper
      case zipper do
        %Zipper{node: 42} ->
          # do something

        %Zipper{node: nil} ->
          # do something else
      end

      # FastZipper
      case zipper do
        zipper(node: 42) ->
          # do something

        zipper(node: nil) ->
      end

      # Zipper
      zipper.path.left

      # FastZipper
      zipper |> zipper(:path) |> path(:left)
  """

  import Kernel, except: [node: 1]
  import Sourceror.Identifier, only: [is_reserved_block_name: 1]

  require Record

  Record.defrecord(:zipper, [:node, :path, :supertree])
  Record.defrecord(:path, [:left, :parent, :right])

  @type t ::
          record(:zipper,
            node: tree,
            path: path | nil,
            supertree: t | nil
          )

  @opaque path ::
            record(:path,
              left: [tree] | nil,
              parent: t,
              right: [tree] | nil
            )

  @type tree :: Macro.t()

  @compile {:inline, new: 1, new: 3, left: 1, right: 1, up: 1, down: 1, children: 1, branch?: 1}
  defp new(node), do: zipper(node: node)
  defp new(node, nil, supertree), do: zipper(node: node, supertree: supertree)

  defp new(node, path(left: _, parent: _, right: _) = path, supertree),
    do: zipper(node: node, path: path, supertree: supertree)

  @spec branch?(tree) :: boolean
  def branch?({_, _, args}) when is_list(args), do: true
  def branch?({_, _}), do: true
  def branch?(list) when is_list(list), do: true
  def branch?(_), do: false

  @doc """
  Returns a list of children of the `node`. Returns `nil` if the node is a leaf.
  """
  @spec children(tree) :: [tree] | nil
  def children({form, _, args}) when is_atom(form) and is_list(args), do: args
  def children({form, _, args}) when is_list(args), do: [form | args]
  def children({left, right}), do: [left, right]
  def children(list) when is_list(list), do: list
  def children(_), do: nil

  @doc """
  Returns a new branch `node`, given an existing `node` and new `children`.
  """
  @spec make_node(tree, [tree]) :: tree
  def make_node(node, children)
  def make_node({form, meta, _}, args) when is_atom(form), do: {form, meta, args}
  def make_node({_form, meta, args}, [first | rest]) when is_list(args), do: {first, meta, rest}
  def make_node({_, _}, [left, right]), do: {left, right}
  def make_node({_, _}, args), do: {:{}, [], args}

  def make_node(list, children) when is_list(list), do: children

  @doc """
  Creates a `zipper` from a tree `node`.
  """
  @spec zip(tree) :: t
  def zip(node), do: new(node)

  @doc """
  Creates a `zipper` from a tree `node` focused at the innermost descendant containing `position`.

  Returns `{:ok, zipper}` if `position` is within `node`, else `:error`.

  Modifying `node` prior to using `at/2` is not recommended as added or
  changed descendants may not contain accurate position metadata used to
  find the focus.
  """
  @spec at(Macro.t(), Sourceror.position()) :: {:ok, t} | :error
  def at(node, position) when is_list(position) do
    with {:ok, path} <- fetch_path_to(node, position) do
      case path do
        [{node, [], []}, {{:__block__, _, [node]}, _, _} = block_wrapper | ancestors] ->
          {:ok, new_from_path([block_wrapper | ancestors])}

        _ ->
          {:ok, new_from_path(path)}
      end
    end
  end

  defp new_from_path([{node, [], []}]) do
    new(node)
  end

  defp new_from_path([{node, left, right} | ancestors]) do
    path = path(left: left, right: right, parent: new_from_path(ancestors))
    new(node, path, nil)
  end

  defp fetch_path_to(node, position) do
    if node_contains?(node, position) do
      {:ok, path_to(position, [{node, [], []}])}
    else
      :error
    end
  end

  defp path_to(position, [{parent, _parent_left, _parent_right} | _] = path) do
    {left, node_and_right} =
      parent
      |> children()
      |> Enum.split_while(fn child ->
        not node_contains?(child, position)
      end)

    case node_and_right do
      [] ->
        path

      [node | right] ->
        reversed_left = Enum.reverse(left)
        path_to(position, [{node, reversed_left, right} | path])
    end
  end

  defp node_contains?(node, position) do
    case Sourceror.get_range(node) do
      %Sourceror.Range{} = range ->
        Sourceror.compare_positions(position, range.start) in [:gt, :eq] and
          Sourceror.compare_positions(position, range.end) == :lt

      nil ->
        false
    end
  end

  @doc """
  Walks the `zipper` to the innermost node that contains the
  `range` or to the first node that perfectly matches it.

  Returns `nil` if the `range` is not contained in the `zipper`.

  Modifying `zipper` prior to using `at_range/2` is not recommended as added or changed
  descendants may not contain accurate position metadata used to find the focus.
  """
  @spec at_range(t, Sourceror.Range.t()) :: t | nil
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def at_range(zipper, %Sourceror.Range{} = range) do
    zipper
    |> traverse_while(nil, fn
      zipper(node: node) = zipper, acc ->
        node_range = Sourceror.get_range(node)

        cond do
          is_nil(node_range) ->
            {:cont, zipper, acc}

          # range ends before node start
          # halting to avoid unnecessary traversals
          Sourceror.compare_positions(range.end, node_range.start) == :lt ->
            {:halt, zipper, acc}

          # range starts after node end
          # no need to traverse node's children
          Sourceror.compare_positions(range.start, node_range.end) == :gt ->
            {:skip, zipper, acc}

          # range starts before node start
          Sourceror.compare_positions(range.start, node_range.start) == :lt ->
            {:cont, zipper, acc}

          # range ends after node end
          Sourceror.compare_positions(range.end, node_range.end) == :gt ->
            {:cont, zipper, acc}

          # range is the same as parent's so they are the "same"
          # (you may comment this and take look at the broken test)
          not is_nil(acc) and is_tuple(zipper(acc, :node)) and
              Sourceror.get_range(zipper(acc, :node)) == node_range ->
            {:cont, zipper, acc}

          # range is inside node
          true ->
            {:cont, zipper, zipper}
        end
    end)
    |> elem(1)
  end

  @doc """
  Walks the `zipper` to the top of the current subtree and returns that `zipper`.
  """
  @spec top(t) :: t
  def top(zipper(path: nil) = zipper), do: zipper
  def top(zipper), do: zipper |> up() |> top()

  @doc """
  Walks the `zipper` to the topmost node, breaking out of any subtrees and returns the top-most `zipper`.
  """
  @spec topmost(t) :: t
  def topmost(zipper(supertree: supertree) = zipper) when not is_nil(supertree) do
    topmost(into(top(zipper), supertree))
  end

  def topmost(zipper), do: top(zipper)

  @doc """
  Walks the `zipper` to the top of the current subtree and returns the that `node`.
  """
  @spec root(t) :: tree
  def root(zipper), do: zipper |> top() |> node()

  @doc """
  Walks the `zipper` to the topmost node, breaking out of any subtrees and returns the root `node`.
  """
  @spec topmost_root(t) :: tree
  def topmost_root(zipper), do: zipper |> topmost() |> node()

  @doc """
  Returns the `node` at the `zipper`.
  """
  @spec node(t) :: tree
  def node(zipper(node: tree)), do: tree

  @doc """
  Returns the `zipper` of the leftmost child of the `node` at this `zipper`, or
  `nil` if there's no children.

  If passed `nil`, this function returns `nil`.
  """
  @spec down(t) :: t | nil
  @spec down(nil) :: nil
  def down(zipper(node: tree, supertree: supertree) = zipper) do
    case children(tree) do
      nil -> nil
      [] -> nil
      [first] -> new(first, path(parent: zipper, left: nil, right: nil), supertree)
      [first | rest] -> new(first, path(parent: zipper, left: nil, right: rest), supertree)
    end
  end

  def down(nil), do: nil

  @doc """
  Returns the `zipper` for the parent `node` of the given `zipper`, or `nil` if
  the `zipper` points to the root.
  """
  @spec up(t) :: t | nil
  def up(zipper(path: nil)), do: nil

  def up(zipper(node: tree, path: path, supertree: supertree)) do
    children = Enum.reverse(path(path, :left) || []) ++ [tree] ++ (path(path, :right) || [])
    zipper(node: parent, path: parent_path) = path(path, :parent)
    new(make_node(parent, children), parent_path, supertree)
  end

  @doc """
  Returns the `zipper` of the left sibling of the `node` at this `zipper`, or
  `nil`.

  If passed `nil`, this function returns `nil`.
  """
  @spec left(t) :: t | nil
  @spec left(nil) :: nil
  def left(zipper)

  def left(
        zipper(node: tree, path: path(left: [ltree | l], right: r) = path, supertree: supertree)
      ),
      do: new(ltree, path(path, left: l, right: [tree | r || []]), supertree)

  def left(_), do: nil

  @doc """
  Returns the leftmost sibling of the `node` at this `zipper`, or itself.

  If passed `nil`, this function returns `nil`.
  """
  @spec leftmost(t) :: t
  @spec leftmost(nil) :: nil
  def leftmost(zipper(node: tree, path: path(left: [_ | _] = l) = path, supertree: supertree)) do
    [left | rest] = Enum.reverse(l)
    r = rest ++ [tree] ++ (path(path, :right) || [])
    new(left, path(path, left: nil, right: r), supertree)
  end

  def leftmost(zipper() = zipper), do: zipper
  def leftmost(nil), do: nil

  @doc """
  Returns the zipper of the right sibling of the `nod`e at this `zipper`, or
  nil.

  If passed `nil`, this function returns `nil`.
  """
  @spec right(t) :: t | nil
  @spec right(nil) :: nil
  def right(zipper)

  def right(zipper(node: tree, path: path(right: [rtree | r]) = path, supertree: supertree)),
    do: new(rtree, path(path, right: r, left: [tree | path(path, :left) || []]), supertree)

  def right(_), do: nil

  @doc """
  Returns the rightmost sibling of the `node` at this `zipper`, or itself.

  If passed `nil`, this function returns `nil`.
  """
  @spec rightmost(t) :: t
  @spec rightmost(nil) :: nil
  def rightmost(zipper(node: tree, path: path(right: [_ | _] = r) = path, supertree: supertree)) do
    [right | rest] = Enum.reverse(r)
    l = rest ++ [tree] ++ (path(path, :left) || [])
    new(right, path(path, left: l, right: nil), supertree)
  end

  def rightmost(zipper() = zipper), do: zipper
  def rightmost(nil), do: nil

  @doc """
  Replaces the current `node` in the `zipper` with a new `node`.
  """
  @spec replace(t, tree) :: t
  def replace(zipper() = zipper, node), do: zipper(zipper, node: node)

  @doc """
  Replaces the current `node` in the zipper with the result of applying `fun` to
  the `node`.
  """
  @spec update(t, (tree -> tree)) :: t
  def update(zipper(node: tree) = zipper, fun) when is_function(fun, 1),
    do: zipper(zipper, node: fun.(tree))

  @doc """
  Removes the `node` at the zipper, returning the `zipper` that would have
  preceded it in a depth-first walk. Raises an `ArgumentError` when attempting
  to remove the top level `node`.
  """
  @spec remove(t) :: t
  def remove(zipper)

  def remove(zipper(path: nil)),
    do: raise(ArgumentError, message: "Cannot remove the top level node.")

  def remove(zipper(path: path, supertree: supertree) = zipper) do
    case path(path, :left) do
      [{:__block__, meta, [name]} = left | rest] when is_reserved_block_name(name) ->
        if meta[:format] == :keyword do
          left
          |> new(path(path, left: rest), supertree)
          |> do_prev()
        else
          zipper
          |> replace({:__block__, meta, []})
          |> up()
        end

      [left | rest] ->
        left
        |> new(path(path, left: rest), supertree)
        |> do_prev()

      _ ->
        children = path(path, :right) || []
        zipper(node: parent, path: parent_path) = path(path, :parent)

        parent
        |> make_node(children)
        |> new(parent_path, supertree)
    end
  end

  @doc """
  Inserts the `child` as the left sibling of the `node` at this `zipper`,
  without moving. Raises an `ArgumentError` when attempting to insert a sibling
  at the top level.
  """
  @spec insert_left(t, tree) :: t
  def insert_left(zipper, child)

  def insert_left(zipper(path: nil), _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_left(zipper(node: tree, path: path, supertree: supertree), child) do
    new(tree, path(path, left: [child | path(path, :left) || []]), supertree)
  end

  @doc """
  Inserts the `child` as the right sibling of the `node` at this `zipper`,
  without moving. Raises an `ArgumentError` when attempting to insert a sibling
  at the top level.
  """
  @spec insert_right(t, tree) :: t
  def insert_right(zipper, child)

  def insert_right(zipper(path: nil), _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_right(zipper(node: tree, path: path, supertree: supertree), child) do
    new(tree, path(path, right: [child | path(path, :right) || []]), supertree)
  end

  @doc """
  Inserts the `child` as the leftmost `child` of the `node` at this `zipper`,
  without moving.
  """
  def insert_child(zipper(node: tree, path: path, supertree: supertree), child) do
    tree
    |> do_insert_child(child)
    |> new(path, supertree)
  end

  defp do_insert_child(list, child) when is_list(list), do: [child | list]

  defp do_insert_child({left, right}, child), do: {:{}, [], [child, left, right]}

  defp do_insert_child({form, meta, args}, child) when is_list(args),
    do: {form, meta, [child | args]}

  @doc """
  Inserts the `child` as the rightmost `child` of the `node` at this `zipper`,
  without moving.
  """
  def append_child(zipper(node: tree, path: path, supertree: supertree), child) do
    tree
    |> do_append_child(child)
    |> new(path, supertree)
  end

  defp do_append_child(list, child) when is_list(list), do: list ++ [child]

  defp do_append_child({left, right}, child), do: {:{}, [], [left, right, child]}

  defp do_append_child({form, meta, args}, child) when is_list(args),
    do: {form, meta, args ++ [child]}

  @doc """
  Returns the following `zipper` in depth-first pre-order.

  If passed `nil`, this function returns `nil`.
  """
  @spec next(t) :: t | nil
  @spec next(nil) :: nil
  def next(zipper(node: tree) = zipper) do
    if branch?(tree) && down(zipper), do: down(zipper), else: skip(zipper)
  end

  def next(nil), do: nil

  @doc """
  Returns the `zipper` of the right sibling of the `node` at this `zipper`, or
  the next `zipper` when no right sibling is available.

  This allows to skip subtrees while traversing the siblings of a node.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.

  If no right/left sibling is available, this function returns the same value as
  `next/1`/`prev/1`.

  The function `skip/1` behaves like the `:skip` in `traverse_while/2` and
  `traverse_while/3`.

  If passed `nil`, this function returns `nil`.
  """
  @spec skip(t, direction :: :next | :prev) :: t | nil
  @spec skip(nil, direction :: :next | :prev) :: nil
  def skip(zipper, direction \\ :next)
  def skip(zipper() = zipper, :next), do: right(zipper) || next_up(zipper)
  def skip(zipper() = zipper, :prev), do: left(zipper) || prev_up(zipper)
  def skip(nil, _direction), do: nil

  defp next_up(zipper) do
    if parent = up(zipper), do: right(parent) || next_up(parent)
  end

  defp prev_up(zipper) do
    if parent = up(zipper), do: left(parent) || prev_up(parent)
  end

  @doc """
  Returns the previous `zipper` in depth-first pre-order. If it's already at
  the end, it returns `nil`.
  """
  @spec prev(t) :: t
  def prev(zipper) do
    if left = left(zipper) do
      do_prev(left)
    else
      up(zipper)
    end
  end

  defp do_prev(zipper) do
    with true <- branch?(node(zipper)),
         zipper() = child <- down(zipper) do
      do_prev(rightmost(child))
    else
      _ -> zipper
    end
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given `fun` for each
  `node`. When the traversal is finished, the zipper will be back where it
  began.

  If the `zipper` is not at the top, just the subtree will be traversed.

  The function must return a `zipper`.
  """
  @spec traverse(t, (t -> t)) :: t
  def traverse(zipper() = zipper, fun) do
    zipper |> subtree() |> do_traverse(fun) |> into(zipper)
  end

  defp do_traverse(zipper, fun) do
    zipper = fun.(zipper)
    if next = next(zipper), do: do_traverse(next, fun), else: top(zipper)
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given `fun` for each
  `node` with an accumulator. When the traversal is finished, the zipper
  will be back where it began.

  If the `zipper` is not at the top, just the subtree will be traversed.
  """
  @spec traverse(t, term, (t, term -> {t, term})) :: {t, term}
  def traverse(zipper() = zipper, acc, fun) do
    {updated, acc} = zipper |> subtree() |> do_traverse(acc, fun)
    {into(updated, zipper), acc}
  end

  defp do_traverse(zipper, acc, fun) do
    {zipper, acc} = fun.(zipper, acc)
    if next = next(zipper), do: do_traverse(next, acc, fun), else: {top(zipper), acc}
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given `fun` for each
  `node`.

  The traversing will continue if `fun` returns `{:cont, zipper}`, skipped for
  `{:skip, zipper}` and halted for `{:halt, zipper}`. When the traversal is
  finished, the `zipper` will be back where it began.

  If the `zipper` is not at the top, just the subtree will be traversed.

  The function must return a `zipper`.
  """
  @spec traverse_while(t, (t -> {:cont, t} | {:halt, t} | {:skip, t})) :: t
  def traverse_while(zipper, fun)

  def traverse_while(zipper() = zipper, fun) do
    zipper |> subtree() |> do_traverse_while(fun) |> into(zipper)
  end

  defp do_traverse_while(zipper, fun) do
    case fun.(zipper) do
      {:cont, zipper} ->
        if next = next(zipper), do: do_traverse_while(next, fun), else: top(zipper)

      {:skip, zipper} ->
        if skipped = skip(zipper), do: do_traverse_while(skipped, fun), else: top(zipper)

      {:halt, zipper} ->
        top(zipper)
    end
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given `fun` for each
  `node` with an accumulator. When the traversal is finished, the `zipper`
  will be back where it began.

  The traversing will continue if `fun` returns `{:cont, zipper, acc}`, skipped
  for `{:skip, zipper, acc}` and halted for `{:halt, zipper, acc}`

  If the `zipper` is not at the top, just the subtree will be traversed.
  """
  @spec traverse_while(
          t,
          term,
          (t, term -> {:cont, t, term} | {:halt, t, term} | {:skip, t, term})
        ) :: {t, term}
  def traverse_while(zipper, acc, fun)

  def traverse_while(zipper() = zipper, acc, fun) do
    {updated, acc} = zipper |> subtree() |> do_traverse_while(acc, fun)
    {into(updated, zipper), acc}
  end

  defp do_traverse_while(zipper, acc, fun) do
    case fun.(zipper, acc) do
      {:cont, zipper, acc} ->
        if next = next(zipper), do: do_traverse_while(next, acc, fun), else: {top(zipper), acc}

      {:skip, zipper, acc} ->
        if skip = skip(zipper), do: do_traverse_while(skip, acc, fun), else: {top(zipper), acc}

      {:halt, zipper, acc} ->
        {top(zipper), acc}
    end
  end

  @compile {:inline, into: 2}
  defp into(zipper, nil), do: zipper

  defp into(zipper(path: nil) = zipper, zipper(path: path, supertree: supertree)),
    do: zipper(zipper, path: path, supertree: supertree)

  @doc """
  Searches forward in `zipper` for the given pattern, moving to that
  pattern or a location inside that pattern.

  Note that the search may continue outside of `zipper` in a depth-first
  order. If this isn't desirable, call this function with a `subtree/1`.

  If passed `nil`, this function returns `nil`.

  There are two special forms that can be used inside patterns:

    * `__cursor__()` - if the pattern matches, the zipper will be focused
      at the location of `__cursor__()`, if present
    * `__` - "wildcard match" that will match a single node of any form.

  ## Examples

      iex> zipper =
      ...>   \"""
      ...>   defmodule Example do
      ...>     def my_function(arg1, arg2) do
      ...>       arg1 + arg2
      ...>     end
      ...>   end
      ...>   \"""
      ...>   |> Sourceror.parse_string!()
      ...>   |> zip()
      ...> found = search_pattern(zipper, "my_function(arg1, arg2)")
      ...> {:my_function, _, [{:arg1, _, _}, {:arg2, _, _}]} = node(found)
      ...> found = search_pattern(zipper, "my_function(__, __)")
      ...> {:my_function, _, [{:arg1, _, _}, {:arg2, _, _}]} = node(found)
      ...> found = search_pattern(zipper, "def my_function(__, __cursor__()), __")
      ...> {:arg2, _, _} = node(found)

  """
  @spec search_pattern(t, String.t() | t) :: t | nil
  @spec search_pattern(nil, String.t() | t) :: nil
  def search_pattern(zipper() = zipper, pattern) when is_binary(pattern) do
    pattern
    |> Sourceror.parse_string!()
    |> zip()
    |> then(&search_pattern(zipper, &1))
  end

  def search_pattern(zipper() = zipper, zipper() = pattern_zipper) do
    case find_pattern(zipper, pattern_zipper, :error) do
      {:ok, found} -> found
      :error -> zipper |> next() |> search_pattern(pattern_zipper)
    end
  end

  def search_pattern(nil, _pattern), do: nil

  @doc """
  Matches `zipper` against the given pattern, moving to the location of `__cursor__()`.

  This function only moves `zipper` if the current node matches the pattern.
  To search for a pattern in `zipper`, use `search_pattern/2`.

  There are two special forms that can be used inside patterns:

    * `__cursor__()` - if the pattern matches, the zipper will be focused
      at the location of `__cursor__()`, if present
    * `__` - "wildcard match" that will match a single node of any form.

  If passed `nil`, this function returns `nil`.

  ## Examples

      iex> zipper =
      ...>   \"""
      ...>   if true do
      ...>     10
      ...>   end
      ...>   \"""
      ...>   |> Sourceror.parse_string!()
      ...>   |> zip()
      iex> pattern =
      ...>   \"""
      ...>   if __ do
      ...>     __cursor__()
      ...>   end
      ...>   \"""
      iex> found = move_to_cursor(zipper, pattern)
      iex> {:__block__, _, [10]} = node(found)

  """
  @spec move_to_cursor(t, String.t() | t) :: t | nil
  @spec move_to_cursor(nil, String.t() | t) :: nil
  def move_to_cursor(zipper() = zipper, pattern) when is_binary(pattern) do
    pattern
    |> Sourceror.parse_string!()
    |> zip()
    |> then(&move_to_cursor(zipper, &1))
  end

  def move_to_cursor(zipper() = zipper, zipper() = pattern_zipper) do
    case find_pattern(zipper, pattern_zipper, :error) do
      {:ok, found} -> found
      :error -> nil
    end
  end

  def move_to_cursor(nil, _pattern), do: nil

  defp find_pattern(zipper() = zipper, zipper() = pattern_zipper, result) do
    case zipper(pattern_zipper, :node) do
      {:__cursor__, _, []} ->
        find_pattern(skip(zipper), next(pattern_zipper), {:ok, zipper})

      {:__, _, nil} ->
        find_pattern(skip(zipper), next(pattern_zipper), result)

      _ ->
        case {move_similar_zippers(zipper, pattern_zipper), result} do
          {{next_zipper, next_pattern_zipper}, {:ok, _}} ->
            find_pattern(next_zipper, next_pattern_zipper, result)

          {{next_zipper, next_pattern_zipper}, :error} ->
            find_pattern(next_zipper, next_pattern_zipper, {:ok, zipper})

          {nil, _} ->
            :error
        end
    end
  end

  defp find_pattern(_zipper, nil, result), do: result
  defp find_pattern(nil, _pattern, _result), do: :error

  # Moves a pair of zippers one step so long as the outermost structure
  # matches. Notably, this function unwraps single-element blocks, so
  # {:__block__, _, [:foo]} and :foo would match, and the zippers would
  # be moved to the next node.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp move_similar_zippers(zipper() = zipper, zipper() = pattern_zipper) do
    case {zipper(zipper, :node), zipper(pattern_zipper, :node)} do
      {{:__block__, _, [_left]}, _right} ->
        move_similar_zippers(next(zipper), pattern_zipper)

      {_left, {:__block__, _, [_right]}} ->
        move_similar_zippers(zipper, next(pattern_zipper))

      {_, {:__, _, nil}} ->
        {skip(zipper), skip(pattern_zipper)}

      {{call, _, _}, {call, _, _}} when is_atom(call) ->
        {next(zipper), next(pattern_zipper)}

      {{{_, _, _}, _, _}, {{_, _, _}, _, _}} ->
        {next(zipper), next(pattern_zipper)}

      {{_, _}, {_, _}} ->
        {next(zipper), next(pattern_zipper)}

      {same, same} ->
        {skip(zipper), skip(pattern_zipper)}

      {left, right} when is_list(left) and is_list(right) and length(left) == length(right) ->
        {next(zipper), next(pattern_zipper)}

      _ ->
        nil
    end
  end

  @doc """
  Returns a `zipper` to the `node` that satisfies the `predicate` function, or
  `nil` if none is found.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.

  If passed `nil`, this function returns `nil`.
  """
  @spec find(t, direction :: :prev | :next, predicate :: (tree -> any)) :: t | nil
  @spec find(nil, direction :: :prev | :next, predicate :: (tree -> any)) :: nil
  def find(zipper, direction \\ :next, predicate)

  def find(zipper() = zipper, direction, predicate)
      when direction in [:next, :prev] and is_function(predicate, 1) do
    do_find(zipper, move(direction), predicate)
  end

  def find(nil, _direction, _predicate), do: nil

  defp do_find(nil, _move, _predicate), do: nil

  defp do_find(zipper(node: tree) = zipper, move, predicate) do
    if predicate.(tree) do
      zipper
    else
      zipper |> move.() |> do_find(move, predicate)
    end
  end

  @doc """
  Returns a list of `zippers` to each `node` that satisfies the `predicate` function, or
  an empty list if none are found.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.

  If passed `nil`, this function returns the empty list.
  """
  @spec find_all(t, direction :: :prev | :next, predicate :: (tree -> any)) :: [t]
  @spec find_all(nil, direction :: :prev | :next, predicate :: (tree -> any)) :: []
  def find_all(zipper, direction \\ :next, predicate)

  def find_all(zipper() = zipper, direction, predicate)
      when direction in [:next, :prev] and is_function(predicate, 1) do
    do_find_all(zipper, move(direction), predicate, [])
  end

  def find_all(nil, _direction, _predicate), do: nil

  defp do_find_all(nil, _move, _predicate, buffer), do: Enum.reverse(buffer)

  defp do_find_all(zipper(node: tree) = zipper, move, predicate, buffer) do
    if predicate.(tree) do
      zipper |> move.() |> do_find_all(move, predicate, [zipper | buffer])
    else
      zipper |> move.() |> do_find_all(move, predicate, buffer)
    end
  end

  @doc """
  Like `find/3`, but returns the first non-falsy value returned by `fun`.

  If passed `nil`, this function returns `nil`.
  """
  @spec find_value(t, (tree -> term)) :: term | nil
  @spec find_value(nil, (tree -> term)) :: nil
  def find_value(zipper, direction \\ :next, fun)

  def find_value(zipper() = zipper, direction, fun)
      when direction in [:next, :prev] and is_function(fun, 1) do
    do_find_value(zipper, move(direction), fun)
  end

  def find_value(nil, _direction, _fun), do: nil

  defp do_find_value(nil, _move, _fun), do: nil

  defp do_find_value(zipper(node: tree) = zipper, move, fun) do
    result = fun.(tree)

    if result do
      result
    else
      zipper |> move.() |> do_find_value(move, fun)
    end
  end

  defp move(:next), do: &next/1
  defp move(:prev), do: &prev/1

  @doc """
  Returns a new `zipper` that is a subtree of the currently focused `node`.
  """
  @spec subtree(t) :: t
  @compile {:inline, subtree: 1}
  def subtree(zipper() = zipper),
    do: zipper(zipper, path: nil, supertree: zipper)

  @doc """
  Moves to the top and breaks out of a subtree.

  Returns `nil` if `zipper` is not a subtree.
  """
  @spec supertree(t) :: t | nil
  def supertree(zipper(supertree: supertree) = zipper) when not is_nil(supertree) do
    zipper |> top() |> into(zipper(zipper, :supertree))
  end

  def supertree(zipper()), do: nil

  @doc """
  Runs the function `fun` on the subtree of the currently focused `node` and
  returns the updated `zipper`.

  `fun` must return a zipper, which may be positioned at the top of the subtree.
  """
  def within(zipper() = zipper, fun) when is_function(fun, 1) do
    updated = zipper |> subtree() |> fun.() |> top()
    into(updated, zipper(updated, :supertree) || zipper)
  end
end
