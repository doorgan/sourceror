defmodule SourcerorTest.ZipperTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Zipper

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
  end

  describe "top/1" do
    test "returns the top zipper" do
      assert Z.zip([1, [2, [3, 4]]]) |> Z.next() |> Z.next() |> Z.next() |> Z.top() ==
               %Z{node: [1, [2, [3, 4]]]}

      assert 42 |> Z.zip() |> Z.top() |> Z.top() |> Z.top() == %Z{node: 42, path: nil}
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
end
