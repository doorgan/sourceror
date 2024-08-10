defmodule Sourceror.Zipper do
  @moduledoc """
  Tree-like data structure that provides enhanced navigation and modification
  of an Elixir AST.

  This implementation is based on Gérard Huet [Functional pearl: the zipper](https://www.st.cs.uni-saarland.de/edu/seminare/2005/advanced-fp/docs/huet-zipper.pdf)
  and Clojure's `clojure.zip` API.

  A zipper is a data structure that represents a location in a tree from the
  perspective of the current node, also called the *focus*.

  It is represented by a struct containing a `:node` and `:path`, which is a
  private field used to track the position of the `:node` with regards to
  the entire tree. The `:path` is an implementation detail that should be
  considered private.

  For more information and examples, see the following guides:

    * [Zippers](zippers.html) (an introduction)
    * [Expand multi-alias syntax](expand_multi_alias.html) (an example)

  """

  import Kernel, except: [node: 1]
  import Sourceror.Identifier, only: [is_reserved_block_name: 1]

  alias Sourceror.Zipper, as: Z

  defstruct [:node, :path, :supertree]

  @type t :: %Z{
          node: tree,
          path: path | nil,
          supertree: t | nil
        }

  @opaque path :: %{
            left: [tree] | nil,
            parent: t,
            right: [tree] | nil
          }

  @type tree :: Macro.t()

  @compile {:inline, new: 1, new: 3}
  defp new(node), do: %Z{node: node}
  defp new(node, nil, supertree), do: %Z{node: node, supertree: supertree}

  defp new(node, %{left: _, parent: _, right: _} = path, supertree),
    do: %Z{node: node, path: path, supertree: supertree}

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
    path = %{left: left, right: right, parent: new_from_path(ancestors)}
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
  Walks the `zipper` to the top of the current subtree and returns that `zipper`.
  """
  @spec top(t) :: t
  def top(%Z{path: nil} = zipper), do: zipper
  def top(zipper), do: zipper |> up() |> top()

  @doc """
  Walks the `zipper` to the topmost node, breaking out of any subtrees and returns the top-most `zipper`.
  """
  @spec topmost(t) :: t
  def topmost(%Z{supertree: supertree} = zipper) when not is_nil(supertree) do
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
  def node(%Z{node: tree}), do: tree

  @doc """
  Returns the `zipper` of the leftmost child of the `node` at this `zipper`, or
  `nil` if there's no children.
  """
  @spec down(t) :: t | nil
  def down(%Z{node: tree, supertree: supertree} = zipper) do
    case children(tree) do
      nil -> nil
      [] -> nil
      [first] -> new(first, %{parent: zipper, left: nil, right: nil}, supertree)
      [first | rest] -> new(first, %{parent: zipper, left: nil, right: rest}, supertree)
    end
  end

  @doc """
  Returns the `zipper` for the parent `node` of the given `zipper`, or `nil` if
  the `zipper` points to the root.
  """
  @spec up(t) :: t | nil
  def up(%Z{path: nil}), do: nil

  def up(%Z{node: tree, path: path, supertree: supertree}) do
    children = Enum.reverse(path.left || []) ++ [tree] ++ (path.right || [])
    %Z{node: parent, path: parent_path} = path.parent
    new(make_node(parent, children), parent_path, supertree)
  end

  @doc """
  Returns the `zipper` of the left sibling of the `node` at this `zipper`, or
  `nil`.
  """
  @spec left(t) :: t | nil
  def left(zipper)

  def left(%Z{node: tree, path: %{left: [ltree | l], right: r} = path, supertree: supertree}),
    do: new(ltree, %{path | left: l, right: [tree | r || []]}, supertree)

  def left(_), do: nil

  @doc """
  Returns the leftmost sibling of the `node` at this `zipper`, or itself.
  """
  @spec leftmost(t) :: t
  def leftmost(%Z{node: tree, path: %{left: [_ | _] = l} = path, supertree: supertree}) do
    [left | rest] = Enum.reverse(l)
    r = rest ++ [tree] ++ (path.right || [])
    new(left, %{path | left: nil, right: r}, supertree)
  end

  def leftmost(zipper), do: zipper

  @doc """
  Returns the zipper of the right sibling of the `nod`e at this `zipper`, or
  nil.
  """
  @spec right(t) :: t | nil
  def right(zipper)

  def right(%Z{node: tree, path: %{right: [rtree | r]} = path, supertree: supertree}),
    do: new(rtree, %{path | right: r, left: [tree | path.left || []]}, supertree)

  def right(_), do: nil

  @doc """
  Returns the rightmost sibling of the `node` at this `zipper`, or itself.
  """
  @spec rightmost(t) :: t
  def rightmost(%Z{node: tree, path: %{right: [_ | _] = r} = path, supertree: supertree}) do
    [right | rest] = Enum.reverse(r)
    l = rest ++ [tree] ++ (path.left || [])
    new(right, %{path | left: l, right: nil}, supertree)
  end

  def rightmost(zipper), do: zipper

  @doc """
  Replaces the current `node` in the `zipper` with a new `node`.
  """
  @spec replace(t, tree) :: t
  def replace(%Z{} = zipper, node), do: %{zipper | node: node}

  @doc """
  Replaces the current `node` in the zipper with the result of applying `fun` to
  the `node`.
  """
  @spec update(t, (tree -> tree)) :: t
  def update(%Z{node: tree} = zipper, fun) when is_function(fun, 1),
    do: %{zipper | node: fun.(tree)}

  @doc """
  Removes the `node` at the zipper, returning the `zipper` that would have
  preceded it in a depth-first walk. Raises an `ArgumentError` when attempting
  to remove the top level `node`.
  """
  @spec remove(t) :: t
  def remove(zipper)

  def remove(%Z{path: nil}),
    do: raise(ArgumentError, message: "Cannot remove the top level node.")

  def remove(%Z{path: path, supertree: supertree} = zipper) do
    case path.left do
      [{:__block__, meta, [name]} = left | rest] when is_reserved_block_name(name) ->
        if meta[:format] == :keyword do
          left
          |> new(%{path | left: rest}, supertree)
          |> do_prev()
        else
          zipper
          |> replace({:__block__, meta, []})
          |> up()
        end

      [left | rest] ->
        left
        |> new(%{path | left: rest}, supertree)
        |> do_prev()

      _ ->
        children = path.right || []
        %Z{node: parent, path: parent_path} = path.parent

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

  def insert_left(%Z{path: nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_left(%Z{node: tree, path: path, supertree: supertree}, child) do
    new(tree, %{path | left: [child | path.left || []]}, supertree)
  end

  @doc """
  Inserts the `child` as the right sibling of the `node` at this `zipper`,
  without moving. Raises an `ArgumentError` when attempting to insert a sibling
  at the top level.
  """
  @spec insert_right(t, tree) :: t
  def insert_right(zipper, child)

  def insert_right(%Z{path: nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_right(%Z{node: tree, path: path, supertree: supertree}, child) do
    new(tree, %{path | right: [child | path.right || []]}, supertree)
  end

  @doc """
  Inserts the `child` as the leftmost `child` of the `node` at this `zipper`,
  without moving.
  """
  def insert_child(%Z{node: tree, path: path, supertree: supertree}, child) do
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
  def append_child(%Z{node: tree, path: path, supertree: supertree}, child) do
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
  """
  def next(%Z{node: tree} = zipper) do
    if branch?(tree) && down(zipper), do: down(zipper), else: skip(zipper)
  end

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
  """
  @spec skip(t, direction :: :next | :prev) :: t | nil
  def skip(zipper, direction \\ :next)
  def skip(zipper, :next), do: right(zipper) || next_up(zipper)
  def skip(zipper, :prev), do: left(zipper) || prev_up(zipper)

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
         %Z{} = child <- down(zipper) do
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
  def traverse(zipper, fun) do
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
  def traverse(%Z{} = zipper, acc, fun) do
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

  def traverse_while(%Z{} = zipper, fun) do
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

  def traverse_while(%Z{} = zipper, acc, fun) do
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

  defp into(%Z{path: nil} = zipper, %Z{path: path, supertree: supertree}),
    do: %{zipper | path: path, supertree: supertree}

  @doc """
  Searches `zipper` for the given pattern, moving to that pattern or to the
  location of `__cursor__()` in that pattern.
  """
  @spec search_pattern(t(), String.t() | t()) :: t() | nil
  def search_pattern(%Z{} = zipper, pattern) when is_binary(pattern) do
    pattern
    |> Sourceror.parse_string!()
    |> zip()
    |> then(&search_pattern(zipper, &1))
  end

  def search_pattern(%Z{} = zipper, %Z{} = pattern_zipper) do
    if contains_cursor?(pattern_zipper) do
      search_to_cursor(zipper, pattern_zipper)
    else
      search_to_exact(zipper, pattern_zipper)
    end
  end

  defp search_to_cursor(%Z{} = zipper, %Z{} = pattern_zipper) do
    with match_kind when is_atom(match_kind) <- match_zippers(zipper, pattern_zipper),
         %Z{} = new_zipper <- move_to_cursor(zipper, pattern_zipper) do
      new_zipper
    else
      _ ->
        zipper |> next() |> search_to_cursor(pattern_zipper)
    end
  end

  defp search_to_cursor(nil, _), do: nil

  defp search_to_exact(%Z{} = zipper, %Z{} = pattern_zipper) do
    if similar_or_skip?(zipper.node, pattern_zipper.node) do
      zipper
    else
      zipper |> next() |> search_to_exact(pattern_zipper)
    end
  end

  defp search_to_exact(nil, _), do: nil

  defp contains_cursor?(%Z{} = zipper) do
    !!find(zipper, &match?({:__cursor__, _, []}, &1))
  end

  defp similar_or_skip?(_, {:__, _, _}), do: true

  defp similar_or_skip?({:__block__, _, [left]}, right) do
    similar_or_skip?(left, right)
  end

  defp similar_or_skip?(left, {:__block__, _, [right]}) do
    similar_or_skip?(left, right)
  end

  defp similar_or_skip?({call1, _, args1}, {call2, _, args2}) do
    similar_or_skip?(call1, call2) and similar_or_skip?(args1, args2)
  end

  defp similar_or_skip?({l1, r1}, {l2, r2}) do
    similar_or_skip?(l1, l2) and similar_or_skip?(r1, r2)
  end

  defp similar_or_skip?(list1, list2) when is_list(list1) and is_list(list2) do
    length(list1) == length(list2) and
      [list1, list2]
      |> Enum.zip()
      |> Enum.all?(fn {el1, el2} ->
        similar_or_skip?(el1, el2)
      end)
  end

  defp similar_or_skip?(same, same), do: true

  defp similar_or_skip?(_, _), do: false

  @doc """
  Matches `zipper` against the given pattern, moving to the location of `__cursor__()`.

  Use `__cursor__()` to match a cursor in the provided source code. Use `__` to skip any code at a point.

  For example:

  ```elixir
  zipper =
    \"\"\"
    if true do
      10
    end
    \"\"\"
    |> Sourceror.Zipper.zip()

  pattern =
    \"\"\"
    if __ do
      __cursor__()
    end
    \"\"\"

  zipper
  |> Zipper.move_to_cursor(pattern)
  |> Zipper.node()
  # => 10
  ```
  """
  @spec move_to_cursor(t(), String.t() | t()) :: t() | nil
  def move_to_cursor(%Z{} = zipper, pattern) when is_binary(pattern) do
    pattern
    |> Sourceror.parse_string!()
    |> zip()
    |> then(&move_to_cursor(zipper, &1))
  end

  def move_to_cursor(%Z{} = zipper, %Z{node: {:__cursor__, _, []}}) do
    zipper
  end

  def move_to_cursor(%Z{} = zipper, %Z{} = pattern_zipper) do
    case match_zippers(zipper, pattern_zipper) do
      :skip -> move_zippers(zipper, pattern_zipper, &skip/1)
      :next -> move_zippers(zipper, pattern_zipper, &next/1)
      _ -> nil
    end
  end

  defp move_zippers(zipper, pattern_zipper, move) do
    with %Z{} = zipper <- move.(zipper),
         %Z{} = pattern_zipper <- move.(pattern_zipper) do
      move_to_cursor(zipper, pattern_zipper)
    end
  end

  defp match_zippers(%Z{node: zipper_node}, %Z{node: pattern_node}) do
    case {zipper_node, pattern_node} do
      {_, {:__, _, _}} ->
        :skip

      {{call, _, _}, {call, _, _}} ->
        :next

      {{{call, _, _}, _, _}, {{call, _, _}, _, _}} ->
        :next

      {{_, _}, {_, _}} ->
        :next

      {same, same} ->
        :next

      {left, right} when is_list(left) and is_list(right) ->
        :next

      _ ->
        false
    end
  end

  @doc """
  Returns a `zipper` to the `node` that satisfies the `predicate` function, or
  `nil` if none is found.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.
  """
  @spec find(t, direction :: :prev | :next, predicate :: (tree -> any)) :: t | nil
  def find(%Z{} = zipper, direction \\ :next, predicate)
      when direction in [:next, :prev] and is_function(predicate, 1) do
    do_find(zipper, move(direction), predicate)
  end

  defp do_find(nil, _move, _predicate), do: nil

  defp do_find(%Z{node: tree} = zipper, move, predicate) do
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
  """
  @spec find_all(t, direction :: :prev | :next, predicate :: (tree -> any)) :: t | []
  def find_all(%Z{} = zipper, direction \\ :next, predicate)
      when direction in [:next, :prev] and is_function(predicate, 1) do
    do_find_all(zipper, move(direction), predicate, [])
  end

  defp do_find_all(nil, _move, _predicate, buffer), do: Enum.reverse(buffer)

  defp do_find_all(%Z{node: tree} = zipper, move, predicate, buffer) do
    if predicate.(tree) do
      zipper |> move.() |> do_find_all(move, predicate, [zipper | buffer])
    else
      zipper |> move.() |> do_find_all(move, predicate, buffer)
    end
  end

  @spec find_value(t, (tree -> any)) :: any | nil
  def find_value(%Z{} = zipper, direction \\ :next, fun)
      when direction in [:next, :prev] and is_function(fun, 1) do
    do_find_value(zipper, move(direction), fun)
  end

  defp do_find_value(nil, _move, _fun), do: nil

  defp do_find_value(%Z{node: tree} = zipper, move, fun) do
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
  def subtree(%Z{} = zipper),
    do: %{zipper | path: nil, supertree: zipper}

  @doc """
  Runs the function `fun` on the subtree of the currently focused `node` and
  returns the updated `zipper`.

  `fun` must return a zipper, which may be positioned at the top of the subtree.
  """
  def within(%Z{} = zipper, fun) when is_function(fun, 1) do
    updated = zipper |> subtree() |> fun.() |> top()
    into(updated, updated.supertree || zipper)
  end
end
