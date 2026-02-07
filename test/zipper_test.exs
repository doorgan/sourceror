defmodule SourcerorTest.ZipperTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Zipper, import: true

  import SourcerorTest.CursorSupport, only: [pop_cursor: 1, pop_range: 1]

  alias Sourceror.Zipper, as: Z

  describe "zip/1" do
    test "creates a zipper from a term" do
      assert %Z{node: 42} = Z.zip(42)
    end
  end

  describe "branch?/1" do
    test "correctly identifies branch nodes" do
      assert Z.branch?(42) == false
      assert Z.branch?(:foo) == false
      assert Z.branch?([1, 2, 3]) == true
      assert Z.branch?({:left, :right}) == true
      assert Z.branch?({:foo, [], []}) == true
    end
  end

  describe "children/1" do
    test "returns the children for a node" do
      assert Z.children([1, 2, 3]) == [1, 2, 3]
      assert Z.children({:foo, [], [1, 2]}) == [1, 2]

      assert Z.children({{:., [], [:left, :right]}, [], [:arg]}) == [
               {:., [], [:left, :right]},
               :arg
             ]

      assert Z.children({:left, :right}) == [:left, :right]
    end
  end

  describe "make_node/2" do
    test "2-tuples" do
      assert Z.make_node({1, 2}, [3, 4]) == {3, 4}
    end

    test "changing to 2-tuples arity" do
      assert Z.make_node({1, 2}, [3, 4, 5]) == {:{}, [], [3, 4, 5]}
      assert Z.make_node({1, 2}, [3]) == {:{}, [], [3]}
    end

    test "lists" do
      assert Z.make_node([1, 2, 3], [:a, :b, :c]) == [:a, :b, :c]
    end

    test "unqualified calls" do
      assert Z.make_node({:foo, [], [1, 2]}, [:a, :b]) == {:foo, [], [:a, :b]}
    end

    test "qualified calls" do
      assert Z.make_node({{:., [], [1, 2]}, [], [3, 4]}, [:a, :b, :c]) == {:a, [], [:b, :c]}
    end
  end

  describe "node/1" do
    test "returns the node for a zipper" do
      assert Z.node(Z.zip(42)) == 42
    end
  end

  describe "down/1" do
    test "rips and tears the parent node" do
      assert Z.zip([1, 2]) |> Z.down() == %Z{
               node: 1,
               path: %{left: nil, right: [2], parent: %Z{node: [1, 2]}}
             }

      assert Z.zip({1, 2}) |> Z.down() == %Z{
               node: 1,
               path: %{left: nil, right: [2], parent: %Z{node: {1, 2}}}
             }

      assert Z.zip({:foo, [], [1, 2]}) |> Z.down() ==
               %Z{node: 1, path: %{left: nil, right: [2], parent: %Z{node: {:foo, [], [1, 2]}}}}

      assert Z.zip({{:., [], [:a, :b]}, [], [1, 2]}) |> Z.down() ==
               %Z{
                 node: {:., [], [:a, :b]},
                 path: %{
                   left: nil,
                   right: [1, 2],
                   parent: %Z{node: {{:., [], [:a, :b]}, [], [1, 2]}}
                 }
               }
    end
  end

  describe "up/1" do
    test "reconstructs the previous parent" do
      assert Z.zip([1, 2]) |> Z.down() |> Z.up() == %Z{node: [1, 2]}
      assert Z.zip({1, 2}) |> Z.down() |> Z.up() == %Z{node: {1, 2}}
      assert Z.zip({:foo, [], [1, 2]}) |> Z.down() |> Z.up() == %Z{node: {:foo, [], [1, 2]}}

      assert Z.zip({{:., [], [:a, :b]}, [], [1, 2]}) |> Z.down() |> Z.up() ==
               %Z{node: {{:., [], [:a, :b]}, [], [1, 2]}}
    end

    test "returns nil at the top level" do
      assert Z.zip(42) |> Z.up() == nil
    end
  end

  describe "left/1 and right/1" do
    test "correctly navigate horizontally" do
      zipper = Z.zip([1, [2, 3], [[4, 5], 6]])

      assert zipper |> Z.down() |> Z.right() |> Z.right() |> Z.node() == [[4, 5], 6]
      assert zipper |> Z.down() |> Z.right() |> Z.right() |> Z.left() |> Z.node() == [2, 3]
    end

    test "return nil at the boundaries" do
      zipper = Z.zip([1, 2])

      assert zipper |> Z.down() |> Z.left() == nil
      assert zipper |> Z.down() |> Z.right() |> Z.right() == nil
    end
  end

  describe "rightmost/1" do
    test "returns the rightmost child" do
      assert Z.zip([1, 2, 3, 4, 5]) |> Z.down() |> Z.rightmost() |> Z.node() == 5
    end

    test "returns itself it already at the rightmost node" do
      assert Z.zip([1, 2, 3, 4, 5])
             |> Z.down()
             |> Z.rightmost()
             |> Z.rightmost()
             |> Z.rightmost()
             |> Z.node() == 5

      assert Z.zip([1, 2, 3])
             |> Z.rightmost()
             |> Z.rightmost()
             |> Z.node() == [1, 2, 3]
    end
  end

  describe "leftmost/1" do
    test "returns the leftmost child" do
      assert Z.zip([1, 2, 3, 4, 5])
             |> Z.down()
             |> Z.right()
             |> Z.right()
             |> Z.leftmost()
             |> Z.node() == 1
    end

    test "returns itself it already at the leftmost node" do
      assert Z.zip([1, 2, 3, 4, 5])
             |> Z.down()
             |> Z.leftmost()
             |> Z.leftmost()
             |> Z.leftmost()
             |> Z.node() == 1

      assert Z.zip([1, 2, 3])
             |> Z.leftmost()
             |> Z.leftmost()
             |> Z.node() == [1, 2, 3]
    end
  end

  describe "next/1" do
    test "walks forward in depth-first pre-order" do
      zipper = Z.zip([1, [2, [3, 4]], 5])

      assert zipper |> Z.next() |> Z.next() |> Z.next() |> Z.next() |> Z.node() == [3, 4]

      assert zipper
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.node() == 5
    end

    test "returns nil after exhausting the tree" do
      zipper = Z.zip([1, [2, [3, 4]], 5])

      refute zipper
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()

      refute 42 |> Z.zip() |> Z.next()
    end
  end

  describe "prev/1" do
    test "walks backwards in depth-first pre-order" do
      zipper = Z.zip([1, [2, [3, 4]], 5])

      assert zipper
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.prev()
             |> Z.prev()
             |> Z.prev()
             |> Z.node() == [3, 4]
    end

    test "returns nil when it reaches past the top" do
      zipper = Z.zip([1, [2, [3, 4]], 5])

      assert zipper
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.prev()
             |> Z.prev()
             |> Z.prev()
             |> Z.prev() == nil
    end
  end

  describe "skip/2" do
    test "returns a zipper to the next sibling while skipping subtrees" do
      zipper =
        Z.zip([
          {:foo, [], [1, 2, 3]},
          {:bar, [], [1, 2, 3]},
          {:baz, [], [1, 2, 3]}
        ])

      zipper = Z.down(zipper)

      assert Z.node(zipper) == {:foo, [], [1, 2, 3]}
      assert zipper |> Z.skip() |> Z.node() == {:bar, [], [1, 2, 3]}
      assert zipper |> Z.skip(:next) |> Z.node() == {:bar, [], [1, 2, 3]}
      assert zipper |> Z.skip() |> Z.skip(:prev) |> Z.node() == {:foo, [], [1, 2, 3]}
    end

    test "returns nil if no previous sibling is available" do
      zipper =
        Z.zip([
          {:foo, [], [1, 2, 3]}
        ])

      zipper = Z.down(zipper)

      assert Z.skip(zipper, :prev) == nil
      assert [7] |> Z.zip() |> Z.skip(:prev) == nil
    end

    test "returns nil if no next sibling is available" do
      zipper =
        Z.zip([
          {:foo, [], [1, 2, 3]}
        ])

      zipper = Z.down(zipper)

      refute Z.skip(zipper)
    end
  end

  describe "traverse/2" do
    test "traverses in depth-first pre-order" do
      zipper = Z.zip([1, [2, [3, 4], 5], [6, 7]])

      assert Z.traverse(zipper, fn
               %Z{node: x} = z when is_integer(x) -> %{z | node: x * 2}
               z -> z
             end)
             |> Z.node() == [2, [4, [6, 8], 10], [12, 14]]
    end

    test "traverses a subtree in depth-first pre-order" do
      zipper = Z.zip([1, [2, [3, 4], 5], [6, 7]])

      assert zipper
             |> Z.down()
             |> Z.right()
             |> Z.traverse(fn
               %Z{node: x} = z when is_integer(x) -> %{z | node: x + 10}
               z -> z
             end)
             |> Z.root() == [1, [12, [13, 14], 15], [6, 7]]
    end
  end

  describe "traverse/3" do
    test "traverses in depth-first pre-order" do
      zipper = Z.zip([1, [2, [3, 4], 5], [6, 7]])

      {_, acc} = Z.traverse(zipper, [], &{&1, [Z.node(&1) | &2]})

      assert [
               [1, [2, [3, 4], 5], [6, 7]],
               1,
               [2, [3, 4], 5],
               2,
               [3, 4],
               3,
               4,
               5,
               [6, 7],
               6,
               7
             ] == Enum.reverse(acc)
    end

    test "traverses a subtree in depth-first pre-order" do
      zipper = Z.zip([1, [2, [3, 4], 5], [6, 7]])

      {_, acc} =
        zipper
        |> Z.down()
        |> Z.right()
        |> Z.traverse([], &{&1, [Z.node(&1) | &2]})

      assert [[2, [3, 4], 5], 2, [3, 4], 3, 4, 5] == Enum.reverse(acc)
    end
  end

  describe "traverse_while/2" do
    test "traverses in depth-first pre-order and skips branch" do
      zipper = Z.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      assert zipper
             |> Z.traverse_while(fn
               %Z{node: [x | _]} = z when rem(x, 2) != 0 -> {:skip, z}
               %Z{node: [_ | _]} = z -> {:cont, z}
               %Z{node: x} = z -> {:cont, %{z | node: x + 100}}
             end)
             |> Z.node() == [110, [120, [130, 131], [21, [32, 33]], [122, 123]]]
    end

    test "traverses in depth-first pre-order and halts on halt" do
      zipper = Z.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      assert zipper
             |> Z.traverse_while(fn
               %Z{node: [x | _]} = z when rem(x, 2) != 0 -> {:halt, z}
               %Z{node: [_ | _]} = z -> {:cont, z}
               %Z{node: x} = z -> {:cont, %{z | node: x + 100}}
             end)
             |> Z.node() == [110, [120, [130, 131], [21, [32, 33]], [22, 23]]]
    end

    test "traverses until end while always skip" do
      assert %Z{path: nil} = [1] |> Z.zip() |> Z.traverse_while(fn z -> {:skip, z} end)
    end

    test "removes a node during traversal" do
      updated =
        Z.zip([1, 2, 3])
        |> Z.traverse_while(fn
          %Z{node: 2} = z -> {:remove, z}
          z -> {:cont, z}
        end)

      assert Z.node(updated) == [1, 3]
    end

    test "removes the subtree root and returns the parent zipper" do
      zipper =
        Z.zip([1, [2, 3], 4])
        |> Z.down()
        |> Z.right()
        |> Z.subtree()

      updated = Z.traverse_while(zipper, fn z -> {:remove, z} end)

      assert Z.node(updated) == 1
      assert Z.root(updated) == [1, 4]
    end

    test "removes a single-expression do body and keeps keyword block valid" do
      code = """
      defmodule M do
        def my_fun do
          :ok
        end
      end
      """

      updated =
        code
        |> Sourceror.parse_string!()
        |> Z.zip()
        |> Z.find(&match?({:def, _, _}, &1))
        |> Z.traverse_while(fn z -> {:remove, z} end)
        |> Z.root()
        |> Sourceror.to_string()

      assert updated == """
             defmodule M do
             end\
             """
    end

    test "raises when removing the topmost root" do
      assert_raise ArgumentError, fn ->
        Z.traverse_while(Z.zip(42), fn z -> {:remove, z} end)
      end
    end
  end

  describe "traverse_while/3" do
    test "traverses in depth-first pre-order and skips branch" do
      zipper = Z.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      {_zipper, acc} =
        zipper
        |> Z.traverse_while([], fn
          %Z{node: [x | _]} = z, acc when rem(x, 2) != 0 -> {:skip, z, acc}
          %Z{node: [_ | _]} = z, acc -> {:cont, z, acc}
          %Z{node: x} = z, acc -> {:cont, z, [x + 100 | acc]}
        end)

      assert acc == [123, 122, 131, 130, 120, 110]
    end

    test "traverses in depth-first pre-order and halts on halt" do
      zipper = Z.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      {_zipper, acc} =
        zipper
        |> Z.traverse_while([], fn
          %Z{node: [x | _]} = z, acc when rem(x, 2) != 0 -> {:halt, z, acc}
          %Z{node: [_ | _]} = z, acc -> {:cont, z, acc}
          %Z{node: x} = z, acc -> {:cont, z, [x + 100 | acc]}
        end)

      assert acc == [131, 130, 120, 110]
    end

    test "traverses until end while always skip" do
      assert %Z{path: nil} =
               [1]
               |> Z.zip()
               |> Z.traverse_while(nil, fn z, acc -> {:skip, z, acc} end)
               |> elem(0)
    end

    test "removes a node during traversal" do
      {updated, _acc} =
        Z.zip([1, 2, 3])
        |> Z.traverse_while(nil, fn
          %Z{node: 2} = z, acc -> {:remove, z, acc}
          z, acc -> {:cont, z, acc}
        end)

      assert Z.node(updated) == [1, 3]
    end

    test "removes the subtree root and returns the parent zipper" do
      zipper =
        Z.zip([1, [2, 3], 4])
        |> Z.down()
        |> Z.right()
        |> Z.subtree()

      {updated, _acc} = Z.traverse_while(zipper, nil, fn z, acc -> {:remove, z, acc} end)

      assert Z.node(updated) == 1
      assert Z.root(updated) == [1, 4]
    end

    test "raises when removing the topmost root" do
      assert_raise ArgumentError, fn ->
        Z.traverse_while(Z.zip(42), nil, fn z, acc -> {:remove, z, acc} end)
      end
    end
  end

  describe "top/1" do
    test "returns the top zipper" do
      assert Z.zip([1, [2, [3, 4]]]) |> Z.next() |> Z.next() |> Z.next() |> Z.top() ==
               %Z{node: [1, [2, [3, 4]]]}

      assert 42 |> Z.zip() |> Z.top() |> Z.top() |> Z.top() == %Z{node: 42, path: nil}
    end
  end

  describe "topmost/1" do
    test "returns the top zipper, breaking out of subtrees" do
      assert Z.zip([1, [2, [3, 4]]])
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.subtree()
             |> Z.topmost() ==
               %Z{node: [1, [2, [3, 4]]]}
    end
  end

  describe "topmost_root/1" do
    test "returns the top zipper's node, breaking out of subtrees" do
      assert Z.zip([1, [2, [3, 4]]])
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.subtree()
             |> Z.topmost_root() ==
               [1, [2, [3, 4]]]
    end
  end

  describe "root/1" do
    test "returns the root node" do
      assert Z.zip([1, [2, [3, 4]]]) |> Z.next() |> Z.next() |> Z.next() |> Z.root() ==
               [1, [2, [3, 4]]]
    end
  end

  describe "replace/2" do
    test "replaces the current node" do
      assert Z.zip([1, 2]) |> Z.down() |> Z.replace(:a) |> Z.root() == [:a, 2]
    end
  end

  describe "update/2" do
    test "updates the current node" do
      assert Z.zip([1, 2]) |> Z.down() |> Z.update(fn x -> x + 50 end) |> Z.root() ==
               [51, 2]
    end
  end

  describe "remove/1" do
    test "removes the node and goes back to the previous zipper" do
      zipper = Z.zip([1, [2, 3], 4]) |> Z.down() |> Z.rightmost() |> Z.remove()

      assert Z.node(zipper) == 3
      assert Z.root(zipper) == [1, [2, 3]]

      assert Z.zip([1, 2, 3])
             |> Z.next()
             |> Z.rightmost()
             |> Z.remove()
             |> Z.remove()
             |> Z.remove()
             |> Z.node() == []
    end

    test "raises when attempting to remove the root" do
      assert_raise ArgumentError, fn ->
        Z.zip(42) |> Z.remove()
      end
    end
  end

  describe "insert_left/2 and insert_right/2" do
    test "insert a sibling to the left or right" do
      assert Z.zip([1, 2, 3])
             |> Z.down()
             |> Z.right()
             |> Z.insert_left(:left)
             |> Z.insert_right(:right)
             |> Z.root() == [1, :left, 2, :right, 3]
    end

    test "raise when attempting to insert a sibling at the root" do
      assert_raise ArgumentError, fn -> Z.zip(42) |> Z.insert_left(:nope) end
      assert_raise ArgumentError, fn -> Z.zip(42) |> Z.insert_right(:nope) end
    end
  end

  describe "insert_child/2 and append_child/2" do
    test "add child nodes to the leftmost or rightmost side" do
      assert Z.zip([1, 2, 3]) |> Z.insert_child(:first) |> Z.append_child(:last) |> Z.root() == [
               :first,
               1,
               2,
               3,
               :last
             ]

      assert Z.zip({:left, :right}) |> Z.insert_child(:first) |> Z.root() ==
               {:{}, [],
                [
                  :first,
                  :left,
                  :right
                ]}

      assert Z.zip({:left, :right}) |> Z.append_child(:last) |> Z.root() ==
               {:{}, [],
                [
                  :left,
                  :right,
                  :last
                ]}

      assert Z.zip({:foo, [], []}) |> Z.insert_child(:first) |> Z.append_child(:last) |> Z.root() ==
               {:foo, [], [:first, :last]}

      assert Z.zip({{:., [], [:a, :b]}, [], []})
             |> Z.insert_child(:first)
             |> Z.append_child(:last)
             |> Z.root() ==
               {{:., [], [:a, :b]}, [], [:first, :last]}
    end
  end

  describe "find/3" do
    test "finds a zipper with a predicate" do
      zipper = Z.zip([1, [2, [3, 4], 5]])

      assert Z.find(zipper, fn x -> x == 4 end) |> Z.node() == 4
      assert Z.find(zipper, :next, fn x -> x == 4 end) |> Z.node() == 4
    end

    test "returns nil if nothing was found" do
      zipper = Z.zip([1, [2, [3, 4], 5]])

      assert Z.find(zipper, fn x -> x == 9 end) == nil
      assert Z.find(zipper, :prev, fn x -> x == 9 end) == nil
    end

    test "finds a zipper with a predicate in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Z.zip()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()

      assert Z.find(zipper, :prev, fn x -> x == 2 end) |> Z.node() == 2
    end

    test "retruns nil if nothing was found in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Z.zip()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()

      assert Z.find(zipper, :prev, fn x -> x == 9 end) == nil
    end
  end

  describe "find_all/3" do
    test "finds zippers with a predicate" do
      zipper = Z.zip([1, [2, [3, 4], 5]])

      assert Z.find_all(zipper, fn
               x when is_integer(x) -> rem(x, 2) == 0
               _other -> false
             end)
             |> Enum.map(&Z.node(&1)) == [2, 4]

      assert Z.find_all(zipper, :next, fn
               x when is_integer(x) -> rem(x, 2) == 0
               _other -> false
             end)
             |> Enum.map(&Z.node(&1)) == [2, 4]
    end

    test "returns empty list if nothing was found" do
      zipper = Z.zip([1, [2, [3, 4], 5]])

      assert Z.find_all(zipper, fn
               x when is_integer(x) -> x == 9
               _other -> false
             end) == []

      assert Z.find_all(zipper, :prev, fn
               x when is_integer(x) -> x == 9
               _other -> false
             end) == []
    end

    test "finds a zippers with a predicate in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Z.zip()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()

      assert Z.find_all(zipper, :prev, fn
               x when is_integer(x) -> rem(x, 2) == 0
               _other -> false
             end)
             |> Enum.map(&Z.node(&1)) == [4, 2]
    end

    test "retruns empty list if nothing was found in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Z.zip()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()

      assert Z.find_all(zipper, :prev, fn x -> x == 9 end) == []
    end
  end

  describe "find_value/3" do
    test "finds a zipper and returns the value" do
      zipper = Z.zip([1, [2, [3, 4], 5]])

      assert Z.find_value(zipper, fn
               4 -> 4
               _ -> false
             end) == 4

      assert Z.find_value(zipper, :next, fn
               4 -> 4
               _ -> false
             end) == 4
    end

    test "returns nil if nothing was found" do
      zipper = Z.zip([1, [2, [3, 4], 5]])

      assert Z.find_value(zipper, fn
               9 -> 9
               _ -> false
             end) == nil

      assert Z.find_value(zipper, :prev, fn
               9 -> 9
               _ -> false
             end) == nil
    end

    test "finds a zipper with a predicate in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Z.zip()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()

      assert Z.find_value(zipper, :prev, fn
               2 -> 2
               _ -> false
             end) == 2
    end

    test "retruns nil if nothing was found in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Z.zip()
        |> Z.next()
        |> Z.next()
        |> Z.next()
        |> Z.next()

      assert Z.find_value(zipper, :prev, fn
               9 -> 9
               _ -> false
             end) == nil
    end
  end

  describe "subtree/1" do
    test "returns a new zipper isolated on the focused of the parent zipper" do
      zipper =
        [1, [2, 3], 4, 5]
        |> Z.zip()
        |> Z.next()
        |> Z.next()

      assert Z.subtree(zipper) |> Z.root() == [2, 3]
    end
  end

  describe "supertree/1" do
    test "breaks out of a single subtree level" do
      zipper =
        [1, [2, [3, 4, 5]]]
        |> Z.zip()
        |> Z.next()
        |> Z.next()
        |> Z.subtree()
        |> Z.next()
        |> Z.next()
        |> Z.subtree()
        |> Z.next()

      assert zipper.node == 3
      assert zipper |> Z.root() == [3, 4, 5]
      assert zipper |> Z.supertree() |> Z.node() == [3, 4, 5]
      assert zipper |> Z.supertree() |> Z.root() == [2, [3, 4, 5]]
      assert zipper |> Z.supertree() |> Z.supertree() |> Z.node() == [2, [3, 4, 5]]
      assert zipper |> Z.supertree() |> Z.supertree() |> Z.root() == [1, [2, [3, 4, 5]]]
      assert zipper |> Z.supertree() |> Z.supertree() |> Z.supertree() == nil
    end
  end

  describe "Zipper.Inspect" do
    test "inspect/2 defaults to using zippers: :as_ast" do
      zipper = Z.zip([1, [2], 3])

      assert inspect(zipper) == inspect(zipper, custom_options: [zippers: :as_ast])
    end

    test ":as_ast option formats the node as an ast" do
      zipper = "x = 1 + 2" |> Code.string_to_quoted!() |> Z.zip()

      assert zipper |> inspect() == """
             #Sourceror.Zipper<
               #root
               {:=, [line: 1], [{:x, [line: 1], nil}, {:+, [line: 1], [1, 2]}]}
             >\
             """

      assert zipper |> Z.next() |> inspect() == """
             #Sourceror.Zipper<
               {:x, [line: 1], nil}
               #...
             >\
             """

      assert zipper |> Z.next() |> Z.next() |> inspect() == """
             #Sourceror.Zipper<
               #...
               {:+, [line: 1], [1, 2]}
             >\
             """

      assert zipper |> Z.next() |> Z.next() |> Z.next() |> inspect() == """
             #Sourceror.Zipper<
               1
               #...
             >\
             """

      assert zipper |> Z.next() |> Z.next() |> Z.next() |> Z.next() |> inspect() == """
             #Sourceror.Zipper<
               #...
               2
             >\
             """
    end

    test ":as_code option formats the node as code" do
      zipper = "x = 1 + 2" |> Code.string_to_quoted!() |> Z.zip()

      assert zipper |> inspect(custom_options: [zippers: :as_code]) == """
             #Sourceror.Zipper<
               #root
               x = 1 + 2
             >\
             """

      assert zipper |> Z.next() |> inspect(custom_options: [zippers: :as_code]) == """
             #Sourceror.Zipper<
               x
               #...
             >\
             """

      assert zipper |> Z.next() |> Z.next() |> inspect(custom_options: [zippers: :as_code]) == """
             #Sourceror.Zipper<
               #...
               1 + 2
             >\
             """

      assert zipper
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> inspect(custom_options: [zippers: :as_code]) == """
             #Sourceror.Zipper<
               1
               #...
             >\
             """

      assert zipper
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> Z.next()
             |> inspect(custom_options: [zippers: :as_code]) == """
             #Sourceror.Zipper<
               #...
               2
             >\
             """
    end

    test ":as_code option displays subtree root" do
      zipper = "[x = 1 + 2]" |> Code.string_to_quoted!() |> Z.zip()

      assert zipper
             |> Z.down()
             |> Z.subtree()
             |> inspect(custom_options: [zippers: :as_code]) == """
             #Sourceror.Zipper<
               #subtree root
               x = 1 + 2
             >\
             """
    end

    test ":raw option formats the zipper as a struct" do
      zipper = Z.zip([1, [2], 3])

      assert zipper
             |> Z.next()
             |> Z.next()
             |> inspect(custom_options: [zippers: :raw, sort_maps: true]) ==
               "%Sourceror.Zipper{node: [2], path: %{left: [1], parent: %Sourceror.Zipper{node: [1, [2], 3], path: nil, supertree: nil}, right: [3]}, supertree: nil}"
    end

    test "default_inspect_as/1 sets a default" do
      zipper = "x = 1 + 2" |> Code.string_to_quoted!() |> Z.zip()

      assert :as_ast = Z.Inspect.default_inspect_as()

      assert inspect(zipper) == """
             #Sourceror.Zipper<
               #root
               {:=, [line: 1], [{:x, [line: 1], nil}, {:+, [line: 1], [1, 2]}]}
             >\
             """

      assert :ok = Z.Inspect.default_inspect_as(:as_code)

      assert inspect(zipper) == """
             #Sourceror.Zipper<
               #root
               x = 1 + 2
             >\
             """

      assert :ok = Z.Inspect.default_inspect_as(:as_ast)
    end
  end

  describe "within/2" do
    test "executes a function within a zipper" do
      code = """
      config :target, key: :change_me

      config :unrelated, key: :dont_change_me
      """

      updated =
        code
        |> Sourceror.parse_string!()
        |> Z.zip()
        |> Z.find(&match?({:config, _, [{:__block__, _, [:target]} | _]}, &1))
        |> Z.within(fn zipper ->
          zipper
          |> Z.find(&match?({{:__block__, _, [:key]}, _value}, &1))
          |> Z.update(fn {key, _value} -> {key, {:__block__, [], [:changed]}} end)
        end)
        |> Z.root()
        |> Sourceror.to_string()

      assert updated == """
             config :target, key: :changed

             config :unrelated, key: :dont_change_me\
             """
    end

    test "uses any modified supertree" do
      code = """
      config :target, key: :change_me

      config :unrelated, key: :dont_change_me
      """

      updated =
        code
        |> Sourceror.parse_string!()
        |> Z.zip()
        |> Z.find(&match?({:config, _, [{:__block__, _, [:target]} | _]}, &1))
        # This is simulating a "modify and append code" operation (rare, but good for testing this case)
        |> Z.within(fn zipper ->
          zipper
          |> Map.update!(:supertree, fn supertree ->
            upwards = Z.up(supertree)
            {:__block__, _, code} = upwards.node

            upwards
            |> Z.replace(
              {:__block__, [],
               List.insert_at(code, Enum.count(supertree.path.left || []) + 1, :new_code)}
            )
            |> Z.find(&(&1 == zipper.node))
          end)
          |> Z.find(&match?({{:__block__, _, [:key]}, _value}, &1))
          |> Z.update(fn {key, _value} -> {key, {:__block__, [], [:changed]}} end)
        end)
        |> Z.root()
        |> Sourceror.to_string()

      assert updated == """
             config :target, key: :changed

             :new_code
             config :unrelated, key: :dont_change_me\
             """
    end
  end

  describe "search_pattern/2 with cursor" do
    test "matches everything at top level" do
      code =
        """
        if foo == :bar do
          IO.puts("Hello")
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = """
      __cursor__()
      """

      assert code == Z.search_pattern(code, seek)
    end

    test "matches sub-expression with cursor" do
      code =
        """
        if foo == :bar do
          IO.puts("Hello")
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = """
      IO.puts(__cursor__())
      """

      assert ~S["Hello"] ==
               code |> Z.search_pattern(seek) |> Z.node() |> Sourceror.to_string()
    end

    test "matches list sub-expressions with cursor" do
      code =
        "[[:foo, :bar], :baz]"
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = "[__cursor__(), :bar]"

      assert ":foo" == code |> Z.search_pattern(seek) |> Z.node() |> Sourceror.to_string()

      seek = "[__cursor__(), :baz]"

      assert "[:foo, :bar]" == code |> Z.search_pattern(seek) |> Z.node() |> Sourceror.to_string()
    end

    test "matches sub-expression with cursor and ignored elements" do
      code =
        """
        if foo == :bar do
          "Hello" |> IO.puts()
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = """
      __ |> __cursor__()
      """

      assert "IO.puts()" ==
               code |> Z.search_pattern(seek) |> Z.node() |> Sourceror.to_string()
    end

    test "only matches if outer expression still matches" do
      code =
        "[[:foo, :bar], :baz]"
        |> Sourceror.parse_string!()
        |> Z.zip()

      bad_seek = "[__cursor__(), :buzz]"

      assert nil == Z.search_pattern(code, bad_seek)
    end

    test "continues past current zipper focus" do
      code =
        [[[:foo], :bar], :baz]
        |> Z.zip()
        |> Z.next()

      assert [[:foo], :bar] = code.node

      assert %Z{node: :baz} = Z.search_pattern(code, ":baz")
    end

    test "doesn't continue past current zipper focus in subtree" do
      code =
        [[[:foo], :bar], :baz]
        |> Z.zip()
        |> Z.next()
        |> Z.subtree()

      assert [[:foo], :bar] = code.node

      assert nil == Z.search_pattern(code, ":baz")
    end
  end

  describe "search_pattern/2 without cursor" do
    test "matches everything when pattern is exact match" do
      code =
        """
        if foo == :bar do
          IO.puts("Hello")
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = ~S[if(foo == :bar, do: IO.puts("Hello"))]

      assert code == Z.search_pattern(code, seek)
    end

    test "matches sub-expression" do
      code =
        """
        if foo == :bar do
          IO.puts("Hello")
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = ~S[IO.puts("Hello")]

      assert ~S[IO.puts("Hello")] ==
               code |> Z.search_pattern(seek) |> Z.node() |> Sourceror.to_string()
    end
  end

  describe "move_to_cursor/2" do
    test "if the cursor is top level, it matches everything" do
      code =
        """
        if foo == :bar do
          IO.puts("Hello")
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = """
      __cursor__()
      """

      assert code == Z.move_to_cursor(code, seek)
    end

    test "if the cursor is inside of a block" do
      code =
        """
        if foo == :bar do
          IO.puts("Hello")
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = """
      if foo == :bar do
        __cursor__()
      end
      """

      assert new_zipper = Z.move_to_cursor(code, seek)

      assert "IO.puts(\"Hello\")" ==
               new_zipper |> Z.node() |> Sourceror.to_string()
    end

    test "a really complicated example" do
      code =
        """
        defmodule Foo do
          @foo File.read!("foo.txt")

          case @foo do
            "foo" ->
              10

            "bar" ->
              20
          end
        end
        """
        |> Sourceror.parse_string!()
        |> Z.zip()

      seek = """
      defmodule Foo do
        @foo File.read!("foo.txt")

        case @foo do
          __ ->
            __

          "bar" ->
            __cursor__()
        end
      end
      """

      assert new_zipper = Z.move_to_cursor(code, seek)

      assert "20" == new_zipper |> Z.node() |> Sourceror.to_string()
    end

    test "requires that elements after the cursor match" do
      code =
        [[[:foo], :bar], :baz]
        |> Z.zip()

      seek = "[[[:foo], __cursor__()], :NOMATCH]"

      assert nil == Z.move_to_cursor(code, seek)
    end
  end

  describe "at/2" do
    defp zipper_at_cursor(code_with_cursor) do
      {position, code} = pop_cursor(code_with_cursor)
      code |> Sourceror.parse_string!() |> Z.at(position)
    end

    test "creates a zipper focused on an inner literal at the given position" do
      assert {:ok, zipper} =
               zipper_at_cursor("""
               def foo do
                 [1, 2, |3, 4, 5]
               end
               """)

      assert {:__block__, _, [3]} = zipper |> Z.node()

      assert [
               {:__block__, _, [1]},
               {:__block__, _, [2]},
               {:__block__, _, [3]},
               {:__block__, _, [4]},
               {:__block__, _, [5]}
             ] = zipper |> Z.up() |> Z.node()

      assert {:def, _, _} = zipper |> Z.root()
    end

    test "creates a zipper focused on a container if position isn't in any children" do
      assert {:ok, zipper} =
               zipper_at_cursor("""
               def foo do
                 [1|, 2, 3, 4, 5]
               end
               """)

      assert {:__block__, _, [[_, _, _, _, _]]} = zipper |> Z.node()
      assert {:def, _, _} = zipper |> Z.root()
    end

    test "creates a zipper focused on an alias segment" do
      assert {:ok, zipper} = zipper_at_cursor("alias Foo.{Bar, |Baz}")

      assert {:__aliases__, _, [:Baz]} = zipper |> Z.node()
      assert {:__aliases__, _, [:Bar]} = zipper |> Z.left() |> Z.node()
      assert {:alias, _, _} = zipper |> Z.root()
    end

    test "creates a zipper focused on a qualified call" do
      assert {:ok, zipper} = zipper_at_cursor("Foo.|bar(1, 2, 3)")

      assert {:., _, [{:__aliases__, _, _}, :bar]} = zipper |> Z.node()
      assert {:__block__, _, [1]} = zipper |> Z.right() |> Z.node()
    end

    test "returns :error if there is no node containing the given position" do
      assert :error =
               zipper_at_cursor("""
               def foo do
                 [1, 2, 3, 4, 5]
               end|
               """)
    end
  end

  describe "at_range/2" do
    defp zipper_at_range(code_with_range) do
      {range, code} = pop_range(code_with_range)
      code |> Sourceror.parse_string!() |> Z.zip() |> Z.at_range(range)
    end

    test "creates a zipper focused on an inner literal equal to the given range" do
      assert %{node: {:__block__, _, [2]}} =
               zipper_at_range("""
               def foo do
                 [1, «2», 3, 4, 5]
               end
               """)
    end

    test "creates a zipper focused on the last container node if multiple siblings match" do
      assert %{
               node: [
                 {:__block__, _, [1]},
                 {:__block__, _, [2]},
                 {:__block__, _, [3]},
                 {:__block__, _, [4]},
                 {:__block__, _, [5]}
               ]
             } =
               zipper_at_range("""
               def foo do
                 [1, «2, 3», 4, 5]
               end
               """)
    end

    test "creates a zipper focused on the last container node even if range is not a real node" do
      assert %{node: {:foo, _, [{:arg, _, nil}]}} =
               zipper_at_range("""
               def «foo»(arg) do
                 arg
               end
               """)
    end

    test "creates a zipper focused on an alias segment" do
      assert %{node: {:__aliases__, _, [:Baz]}} =
               zipper_at_range("""
               alias Foo.{Bar, «Baz»}
               """)
    end

    test "creates a zipper focused on an alias group" do
      assert %{
               node:
                 {{:., _, [{_, _, [:Foo]}, :{}]}, _,
                  [
                    {:__aliases__, _, [:Bar]},
                    {:__aliases__, _, [:Baz]}
                  ]}
             } =
               zipper_at_range("""
               alias Foo.«{Bar, Baz}»
               """)
    end

    test "creates a zipper focused on the whole alias" do
      assert %{node: {:alias, _, _}} =
               zipper_at_range("""
               «alias» Foo.{Bar, Baz}
               """)
    end

    test "creates a zipper focused on the last container node for a multiline range" do
      assert %{node: {:fn, _, _}} =
               zipper_at_range("""
               Enum.map(filenames, fn «f ->
                 f <> ".txt"
               end»)
               """)
    end

    test "creates a zipper focused on a function call name" do
      assert %{node: {:bar, _, [_, _, _]}} =
               zipper_at_range("""
               def foo do
                 «bar»(1, 2, 3)
               end
               """)
    end

    test "creates a zipper focused on a qualified call when the range covers the call name" do
      assert %{node: {:., _, [{:__aliases__, _, [:Foo]}, :bar]}} =
               zipper_at_range("""
               def foo do
                 Foo.«bar»(1, 2, 3)
               end
               """)
    end

    test "creates a zipper focused on a qualified call alias when the range covers the alias" do
      assert %{node: {:__aliases__, _, [:Foo]}} =
               zipper_at_range("""
               def foo do
                 «Foo».bar(1, 2, 3)
               end
               """)
    end

    test "creates a zipper focused on the whole qualified call" do
      assert %{node: {:., _, [{:__aliases__, _, [:Foo]}, :bar]}} =
               zipper_at_range("""
               def foo do
                 «Foo.bar»(1, 2, 3)
               end
               """)
    end

    test "creates a zipper focused on a qualified call suffix" do
      assert %{node: {:., _, [{:baz, _, _}, :bar]}} =
               zipper_at_range("""
               def foo do
                 «baz.bar»(1, 2, 3)
               end
               """)
    end

    test "creates a zipper focused on a map key usage" do
      assert %{node: {{:., _, [{:baz, _, _}, :bar]}, _, []}} =
               zipper_at_range("""
               def foo do
                 «baz.bar»
               end
               """)
    end

    test "creates a zipper focused on the entire qualified call" do
      assert %{node: {{:., _, [{:__aliases__, _, [:Foo]}, :baz]}, _, [_, _, _]}} =
               zipper_at_range("""
               def foo do
                 «Foo.baz(1, 2, 3)»
               end
               """)
    end

    test "creates a zipper focused on an operand of a binary operator" do
      assert %{node: {:__block__, _, [2]}} =
               zipper_at_range("""
               def foo do
                 1 + «2»
               end
               """)

      assert %{node: {:__block__, _, [1]}} =
               zipper_at_range("""
               def foo do
                 «1» + 2
               end
               """)
    end

    test "creates a zipper focused on the second function header" do
      assert %{node: {:bar, _, nil}} =
               zipper_at_range("""
               defmodule Foo do
                 def foo do
                   1 + 2
                 end

                 def «bar» do
                   1 + 2
                 end
               end
               """)
    end

    test "returns nil if there is no node that contains the range" do
      assert nil ==
               zipper_at_range("""
               def foo(arg) do
                 arg
               end
               « »
               """)
    end
  end
end
