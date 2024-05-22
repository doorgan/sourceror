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

  alias Sourceror.Zipper, as: Z

  defstruct [:node, :path]

  @type t :: %Z{
          node: tree,
          path: path | nil
        }

  @opaque path :: %{
            left: [tree] | nil,
            parent: t,
            right: [tree] | nil
          }

  @type tree :: Macro.t()

  @compile {:inline, new: 1, new: 2}
  defp new(node), do: %Z{node: node}
  defp new(node, nil), do: %Z{node: node}
  defp new(node, %{left: _, parent: _, right: _} = path), do: %Z{node: node, path: path}

  @spec branch?(tree) :: boolean
  def branch?({_, _, args}) when is_list(args), do: true
  def branch?({_, _}), do: true
  def branch?(list) when is_list(list), do: true
  def branch?(_), do: false

  @doc """
  Returns a list of children of the node.
  """
  @spec children(tree) :: [tree]
  def children({form, _, args}) when is_atom(form) and is_list(args), do: args
  def children({form, _, args}) when is_list(args), do: [form | args]
  def children({left, right}), do: [left, right]
  def children(list) when is_list(list), do: list

  @doc """
  Returns a new branch node, given an existing node and new children.
  """
  @spec make_node(tree, [tree]) :: tree

  def make_node({form, meta, _}, args) when is_atom(form), do: {form, meta, args}

  def make_node({_form, meta, args}, [first | rest]) when is_list(args), do: {first, meta, rest}

  def make_node({_, _}, [left, right]), do: {left, right}
  def make_node({_, _}, args), do: {:{}, [], args}

  def make_node(list, children) when is_list(list), do: children

  @doc """
  Creates a zipper from a tree node.
  """
  @spec zip(tree) :: t
  def zip(term), do: new(term)

  @doc """
  Walks the zipper all the way up and returns the top zipper.
  """
  @spec top(t) :: t
  def top(%Z{path: nil} = zipper), do: zipper
  def top(zipper), do: zipper |> up() |> top()

  @doc """
  Walks the zipper all the way up and returns the root node.
  """
  @spec root(t) :: tree
  def root(zipper), do: zipper |> top() |> node()

  @doc """
  Returns the node at the zipper.
  """
  @spec node(t) :: tree
  def node(%Z{node: tree}), do: tree

  @doc """
  Returns the zipper of the leftmost child of the node at this zipper, or
  nil if no there's no children.
  """
  @spec down(t) :: t | nil
  def down(%Z{node: tree} = zipper) do
    with true <- branch?(tree), [first | rest] <- children(tree) do
      rest =
        if rest == [] do
          nil
        else
          rest
        end

      new(first, %{parent: zipper, left: nil, right: rest})
    else
      _ -> nil
    end
  end

  @doc """
  Returns the zipper of the parent of the node at this zipper, or nil if at the
  top.
  """
  @spec up(t) :: t | nil
  def up(%Z{path: nil}), do: nil

  def up(%Z{node: tree, path: path}) do
    children = Enum.reverse(path.left || []) ++ [tree] ++ (path.right || [])
    %Z{node: parent, path: parent_path} = path.parent
    new(make_node(parent, children), parent_path)
  end

  @doc """
  Returns the zipper of the left sibling of the node at this zipper, or nil.
  """
  @spec left(t) :: t | nil
  def left(%Z{node: tree, path: %{left: [ltree | l], right: r} = path}),
    do: new(ltree, %{path | left: l, right: [tree | r || []]})

  def left(_), do: nil

  @doc """
  Returns the leftmost sibling of the node at this zipper, or itself.
  """
  @spec leftmost(t) :: t
  def leftmost(%Z{node: tree, path: %{left: [_ | _] = l} = path}) do
    [left | rest] = Enum.reverse(l)
    r = rest ++ [tree] ++ (path.right || [])
    new(left, %{path | left: nil, right: r})
  end

  def leftmost(zipper), do: zipper

  @doc """
  Returns the zipper of the right sibling of the node at this zipper, or nil.
  """
  @spec right(t) :: t | nil
  def right(%Z{node: tree, path: %{right: [rtree | r]} = path}),
    do: new(rtree, %{path | right: r, left: [tree | path.left || []]})

  def right(_), do: nil

  @doc """
  Returns the rightmost sibling of the node at this zipper, or itself.
  """
  @spec rightmost(t) :: t
  def rightmost(%Z{node: tree, path: %{right: [_ | _] = r} = path}) do
    [right | rest] = Enum.reverse(r)
    l = rest ++ [tree] ++ (path.left || [])
    new(right, %{path | left: l, right: nil})
  end

  def rightmost(zipper), do: zipper

  @doc """
  Replaces the current node in the zipper with a new node.
  """
  @spec replace(t, tree) :: t
  def replace(%Z{path: path}, tree), do: new(tree, path)

  @doc """
  Replaces the current node in the zipper with the result of applying `fun` to
  the node.
  """
  @spec update(t, (tree -> tree)) :: t
  def update(%Z{node: tree, path: path}, fun) when is_function(fun, 1), do: new(fun.(tree), path)

  @doc """
  Removes the node at the zipper, returning the zipper that would have preceded
  it in a depth-first walk.
  """
  @spec remove(t) :: t
  def remove(%Z{path: nil}),
    do: raise(ArgumentError, message: "Cannot remove the top level node.")

  def remove(%Z{path: path}) do
    case path.left do
      [left | rest] ->
        left
        |> new(%{path | left: rest})
        |> prev_after_remove()

      _ ->
        children = path.right || []
        %Z{node: parent, path: parent_path} = path.parent

        parent
        |> make_node(children)
        |> new(parent_path)
    end
  end

  defp prev_after_remove(zipper) do
    with true <- branch?(node(zipper)),
         %Z{} = child <- down(zipper) do
      prev_after_remove(rightmost(child))
    else
      _ -> zipper
    end
  end

  @doc """
  Inserts the item as the left sibling of the node at this zipper, without
  moving. Raises an `ArgumentError` when attempting to insert a sibling at the
  top level.
  """
  @spec insert_left(t, tree) :: t
  def insert_left(%Z{path: nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_left(%Z{node: tree, path: path}, child) do
    new(tree, %{path | left: [child | path.left || []]})
  end

  @doc """
  Inserts the item as the right sibling of the node at this zipper, without
  moving. Raises an `ArgumentError` when attempting to insert a sibling at the
  top level.
  """
  @spec insert_right(t, tree) :: t
  def insert_right(%Z{path: nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_right(%Z{node: tree, path: path}, child) do
    new(tree, %{path | right: [child | path.right || []]})
  end

  @doc """
  Inserts the item as the leftmost child of the node at this zipper,
  without moving.
  """
  def insert_child(%Z{node: tree, path: path}, child) do
    tree
    |> do_insert_child(child)
    |> new(path)
  end

  @doc """
  Inserts the item as the rightmost child of the node at this zipper,
  without moving.
  """
  def append_child(%Z{node: tree, path: path}, child) do
    tree
    |> do_append_child(child)
    |> new(path)
  end

  @doc """
  Returns the following zipper in depth-first pre-order.
  """
  def next(%Z{node: tree} = zipper) do
    if branch?(tree) && down(zipper), do: down(zipper), else: skip(zipper)
  end

  @doc """
  Returns the zipper of the right sibling of the node at this zipper, or the
  next zipper when no right sibling is available.

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
    if parent = up(zipper) do
      right(parent) || next_up(parent)
    end
  end

  defp prev_up(zipper) do
    if parent = up(zipper) do
      left(parent) || prev_up(parent)
    end
  end

  @doc """
  Returns the previous zipper in depth-first pre-order. If it's already at
  the end, it returns nil.
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
  Traverses the tree in depth-first pre-order calling the given function for
  each node. When the traversal is finished, the zipper will be back where it began.

  If the zipper is not at the top, just the subtree will be traversed.

  The function must return a zipper.
  """
  @spec traverse(t, (t -> t)) :: t
  def traverse(%Z{path: nil} = zipper, fun) do
    do_traverse(zipper, fun)
  end

  def traverse(%Z{node: tree, path: path}, fun) do
    %Z{node: updated} =
      tree
      |> new()
      |> do_traverse(fun)

    new(updated, path)
  end

  defp do_traverse(zipper, fun) do
    zipper = fun.(zipper)
    if next = next(zipper), do: do_traverse(next, fun), else: top(zipper)
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node with an accumulator. When the traversal is finished, the zipper
  will be back where it began.

  If the zipper is not at the top, just the subtree will be traversed.
  """
  @spec traverse(t, term, (t, term -> {t, term})) :: {t, term}
  def traverse(%Z{path: nil} = zipper, acc, fun) do
    do_traverse(zipper, acc, fun)
  end

  def traverse(%Z{node: tree, path: path}, acc, fun) do
    {%Z{node: updated}, acc} =
      tree
      |> new()
      |> do_traverse(acc, fun)

    {new(updated, path), acc}
  end

  defp do_traverse(zipper, acc, fun) do
    {zipper, acc} = fun.(zipper, acc)
    if next = next(zipper), do: do_traverse(next, acc, fun), else: {top(zipper), acc}
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node.

  The traversing will continue if the function returns `{:cont, zipper}`,
  skipped for `{:skip, zipper}` and halted for `{:halt, zipper}`. When the
  traversal is finished, the zipper will be back where it began.

  If the zipper is not at the top, just the subtree will be traversed.

  The function must return a zipper.
  """
  @spec traverse_while(t, (t -> {:cont, t} | {:halt, t} | {:skip, t})) :: t
  def traverse_while(%Z{path: nil} = zipper, fun) do
    do_traverse_while(zipper, fun)
  end

  def traverse_while(%Z{node: tree, path: path}, fun) do
    %Z{node: updated} =
      tree
      |> new()
      |> do_traverse_while(fun)

    new(updated, path)
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
  Traverses the tree in depth-first pre-order calling the given function for
  each node with an accumulator. When the traversal is finished, the zipper
  will be back where it began.

  The traversing will continue if the function returns `{:cont, zipper, acc}`,
  skipped for `{:skip, zipper, acc}` and halted for `{:halt, zipper, acc}`

  If the zipper is not at the top, just the subtree will be traversed.
  """
  @spec traverse_while(
          t,
          term,
          (t, term -> {:cont, t, term} | {:halt, t, term} | {:skip, t, term})
        ) :: {t, term}
  def traverse_while(%Z{path: nil} = zipper, acc, fun) do
    do_traverse_while(zipper, acc, fun)
  end

  def traverse_while(%Z{node: tree, path: path}, acc, fun) do
    {%Z{node: updated}, acc} =
      tree
      |> new()
      |> do_traverse_while(acc, fun)

    {new(updated, path), acc}
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

  @doc """
  Returns a zipper to the node that satisfies the predicate function, or `nil`
  if none is found.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.
  """
  @spec find(t, direction :: :prev | :next, predicate :: (tree -> any)) :: t | nil
  def find(zipper, direction \\ :next, predicate)

  def find(nil, _direction, _predicate), do: nil

  def find(%Z{node: tree} = zipper, direction, predicate)
      when direction in [:next, :prev] and is_function(predicate) do
    if predicate.(tree) do
      zipper
    else
      zipper =
        case direction do
          :next -> next(zipper)
          :prev -> prev(zipper)
        end

      zipper && find(zipper, direction, predicate)
    end
  end

  defp do_insert_child({form, meta, args}, child) when is_list(args) do
    {form, meta, [child | args]}
  end

  defp do_insert_child(list, child) when is_list(list), do: [child | list]
  defp do_insert_child({left, right}, child), do: {:{}, [], [child, left, right]}

  defp do_append_child({form, meta, args}, child) when is_list(args) do
    {form, meta, args ++ [child]}
  end

  defp do_append_child(list, child) when is_list(list), do: list ++ [child]
  defp do_append_child({left, right}, child), do: {:{}, [], [left, right, child]}

  @doc """
  Returns a new zipper that is a subtree of the currently focused node.
  """
  @spec subtree(t) :: t
  def subtree(%Z{} = zipper) do
    zipper
    |> node()
    |> zip()
  end
end
