defmodule Sourceror.Zipper do
  @moduledoc """
  Implements a Zipper for the Elixir AST based on Gérard Huet [Functional
  pearl: the
  zipper](https://www.st.cs.uni-saarland.de/edu/seminare/2005/advanced-fp/docs/huet-zipper.pdf)
  paper and Clojure's `clojure.zip` API.

  A zipper is a data structure that represents a location in a tree from the
  perspective of the current node, also called *focus*. It is represented by a
  2-tuple where the first element is the focus and the second element is the
  metadata/context. When the focus is the topmost node, the metadata is `nil`,
  or `:end` after the end of a traversal.
  """

  # Remove once we figure out why these functions cause a "pattern can never
  # match" error:
  #
  # The pattern can never match the type.
  #
  # Pattern: _child = {_, _}
  #
  # Type: nil
  @dialyzer {:nowarn_function, do_prev: 1, prev_after_remove: 1}

  import Kernel, except: [node: 1]

  @type tree :: Macro.t()
  @type path :: %{
          l: [tree],
          ptree: zipper,
          r: [tree]
        }
  @type zipper :: {tree, path | nil | :end}

  @doc """
  Returns true if the node is a branch.
  """
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
  @spec zip(tree) :: zipper
  def zip(term), do: {term, nil}

  @doc """
  Walks the zipper all the way up and returns the top zipper.
  """
  @spec top(zipper) :: zipper
  def top({tree, :end}), do: {tree, :end}

  def top(zipper) do
    if parent = up(zipper) do
      top(parent)
    else
      zipper
    end
  end

  @doc """
  Walks the zipper all the way up and returns the root node.
  """
  @spec root(zipper) :: tree
  def root(zipper), do: zipper |> top() |> node()

  @doc """
  Returns the node at the zipper.
  """
  @spec node(zipper) :: tree
  def node({tree, _}), do: tree

  @doc """
  Returns the zipper of the leftmost child of the node at this zipper, or
  nil if no there's no children.
  """
  @spec down(zipper) :: zipper | nil
  def down({tree, meta}) do
    with true <- branch?(tree), [first | rest] <- children(tree) do
      rest =
        if rest == [] do
          nil
        else
          rest
        end

      {first, %{ptree: {tree, meta}, l: nil, r: rest}}
    else
      _ -> nil
    end
  end

  @doc """
  Returns the zipper of the parent of the node at this zipper, or nil if at the
  top.
  """
  @spec up(zipper) :: zipper | nil
  def up({_, nil}), do: nil

  def up({tree, meta}) do
    children = Enum.reverse(meta.l || []) ++ [tree] ++ (meta.r || [])
    {parent, parent_meta} = meta.ptree
    {make_node(parent, children), parent_meta}
  end

  @doc """
  Returns the zipper of the left sibling of the node at this zipper, or nil.
  """
  @spec left(zipper) :: zipper | nil
  def left({_, nil}), do: nil
  def left({_, %{l: nil}}), do: nil

  def left({tree, meta}) do
    r = [tree | meta.r || []]

    case meta.l do
      [tree | l] ->
        {tree, %{meta | l: l, r: r}}

      [] ->
        nil
    end
  end

  @doc """
  Returns the leftmost sibling of the node at this zipper, or itself.
  """
  @spec leftmost(zipper) :: zipper
  def leftmost({_, nil} = zipper), do: zipper
  def leftmost({_, %{l: nil}} = zipper), do: zipper

  def leftmost({tree, meta}) do
    [left | rest] = Enum.reverse(meta.l)
    r = rest ++ [tree] ++ (meta.r || [])

    {left, %{meta | l: nil, r: r}}
  end

  @doc """
  "Returns the zipper of the right sibling of the node at this zipper, or nil.
  """
  @spec right(zipper) :: zipper | nil
  def right({_, nil}), do: nil
  def right({_, %{r: nil}}), do: nil

  def right({tree, meta}) do
    l = [tree | meta.l || []]

    case meta.r do
      [tree | r] ->
        {tree, %{meta | l: l, r: r}}

      [] ->
        nil
    end
  end

  @doc """
  Returns the rightmost sibling of the node at this zipper, or itself.
  """
  @spec rightmost(zipper) :: zipper
  def rightmost({_, nil} = zipper), do: zipper
  def rightmost({_, %{r: nil}} = zipper), do: zipper

  def rightmost({tree, meta}) do
    [right | rest] = Enum.reverse(meta.r)
    l = rest ++ [tree] ++ (meta.l || [])

    {right, %{meta | l: l, r: nil}}
  end

  @doc """
  Replaces the current node in the zipper with a new node.
  """
  @spec replace(zipper, tree) :: zipper
  def replace({_, meta}, tree), do: {tree, meta}

  @doc """
  Replaces the current node in the zipper with the result of applying `fun` to
  the node.
  """
  @spec update(zipper, (tree -> tree)) :: zipper
  def update({tree, meta}, fun), do: {fun.(tree), meta}

  @doc """
  Removes the node at the zipper, returning the zipper that would have preceded
  it in a depth-first walk.
  """
  @spec remove(zipper) :: zipper
  def remove({_, nil}), do: raise(ArgumentError, message: "Cannot remove the top level node.")

  def remove({_, meta}) do
    case meta.l do
      [left | rest] ->
        prev_after_remove({left, %{meta | l: rest}})

      _ ->
        children = meta.r || []
        {parent, parent_meta} = meta.ptree
        {make_node(parent, children), parent_meta}
    end
  end

  defp prev_after_remove(zipper) do
    with true <- branch?(node(zipper)),
         {_, _} = child <- down(zipper) do
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
  @spec insert_left(zipper, tree) :: zipper
  def insert_left({_, nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_left({tree, meta}, child) do
    {tree, %{meta | l: [child | meta.l || []]}}
  end

  @doc """
  Inserts the item as the right sibling of the node at this zipper, without
  moving. Raises an `ArgumentError` when attempting to insert a sibling at the
  top level.
  """
  @spec insert_right(zipper, tree) :: zipper
  def insert_right({_, nil}, _),
    do: raise(ArgumentError, message: "Can't insert siblings at the top level.")

  def insert_right({tree, meta}, child) do
    {tree, %{meta | r: [child | meta.r || []]}}
  end

  @doc """
  Inserts the item as the leftmost child of the node at this zipper,
  without moving.
  """
  def insert_child({tree, meta}, child) do
    {do_insert_child(tree, child), meta}
  end

  @doc """
  Inserts the item as the rightmost child of the node at this zipper,
  without moving.
  """
  def append_child({tree, meta}, child) do
    {do_append_child(tree, child), meta}
  end

  @doc """
  Returns true if the zipper represents the end of a depth-first walk.
  """
  @spec end?(zipper) :: boolean
  def end?({_, meta}), do: meta == :end

  @doc """
  Returns the following zipper in depth-first pre-order. When reaching the end,
  returns a distinguished zipper detectable via `end?/1`. If it's already at
  the end, it stays there.
  """
  def next({_, :end} = zipper), do: zipper

  def next({tree, _} = zipper) do
    cond do
      branch?(tree) && down(zipper) ->
        down(zipper)

      next = right(zipper) ->
        next

      true ->
        next_up(zipper)
    end
  end

  defp next_up(zipper) do
    parent = up(zipper)

    if parent do
      right(parent) || next_up(parent)
    else
      {node(zipper), :end}
    end
  end

  @doc """
  Returns the previous zipper in depth-first pre-order. If it's already at
  the end, it returns nil.
  """
  @spec prev(zipper) :: zipper
  def prev(zipper) do
    if left = left(zipper) do
      do_prev(left)
    else
      up(zipper)
    end
  end

  defp do_prev(zipper) do
    with true <- branch?(node(zipper)),
         {_, _} = child <- down(zipper) do
      do_prev(rightmost(child))
    else
      _ -> zipper
    end
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node. Returns a zipper to the root node.

  The function must return a zipper.
  """
  @spec traverse(zipper, (zipper -> zipper)) :: zipper
  def traverse({tree, :end}, _), do: {tree, :end}

  def traverse(zipper, fun) do
    fun.(zipper)
    |> next()
    |> traverse(fun)
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node with an accumulator. Returns a zipper to the root node and the
  accumulator.
  """
  @spec traverse(zipper, term, (zipper, term -> {zipper, term})) :: {zipper, term}
  def traverse({tree, :end}, acc, _), do: {{tree, :end}, acc}

  def traverse(zipper, acc, fun) do
    {zipper, acc} = fun.(zipper, acc)

    traverse(next(zipper), acc, fun)
  end

  @doc """
  Returns a zipper to the node that satisfies the predicate function, or `nil`
  if none is found.
  """
  def find({_, :end}, _), do: nil

  def find({tree, _} = zipper, predicate) do
    if predicate.(tree) do
      zipper
    else
      find(next(zipper), predicate)
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
end
