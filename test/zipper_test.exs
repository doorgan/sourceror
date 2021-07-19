defmodule SourcerorTest.ZipperTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Zipper

  alias Sourceror.Zipper, as: Z

  describe "zip/1" do
    test "creates a zipper from a term" do
      assert Z.zip(42) == {42, nil}
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

      assert Z.children({{:<<>>, :string}, [], ["foo"]}) == ["foo"]

      assert Z.children({{:., [], [:left, :right]}, [], [:arg]}) == [
               {:., [], [:left, :right]},
               :arg
             ]

      assert Z.children({:left, :right}) == [:left, :right]

      assert Z.children({[], [], [1, 2, 3]}) == [1, 2, 3]
      assert Z.children({:"~", [], ["w", "foo", 'a']}) == ["w", "foo", 'a']
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

    test "bare lists" do
      assert Z.make_node([1, 2, 3], [:a, :b, :c]) == [:a, :b, :c]
    end

    test "list nodes" do
      assert Z.make_node({[], [], [1, 2, 3]}, [:a, :b, :c]) == {[], [], [:a, :b, :c]}
    end

    test "interpolation" do
      assert Z.make_node({{:<<>>, :atom}, [], ["foo"]}, ["foo", "bar"]) ==
               {{:<<>>, :atom}, [], ["foo", "bar"]}
    end

    test "sigils" do
      assert Z.make_node({:"~", [], ["w", "foo", 'a']}, ["S", "bar", []]) ==
               {:"~", [], ["S", "bar", []]}
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
      assert Z.zip([1, 2]) |> Z.down() == {1, %{l: nil, r: [2], ptree: {[1, 2], nil}}}
      assert Z.zip({1, 2}) |> Z.down() == {1, %{l: nil, r: [2], ptree: {{1, 2}, nil}}}

      assert Z.zip({:foo, [], [1, 2]}) |> Z.down() ==
               {1, %{l: nil, r: [2], ptree: {{:foo, [], [1, 2]}, nil}}}

      assert Z.zip({{:., [], [:a, :b]}, [], [1, 2]}) |> Z.down() ==
               {{:., [], [:a, :b]},
                %{l: nil, r: [1, 2], ptree: {{{:., [], [:a, :b]}, [], [1, 2]}, nil}}}
    end
  end

  describe "up/1" do
    test "reconstructs the previous parent" do
      assert Z.zip([1, 2]) |> Z.down() |> Z.up() == {[1, 2], nil}
      assert Z.zip({1, 2}) |> Z.down() |> Z.up() == {{1, 2}, nil}
      assert Z.zip({:foo, [], [1, 2]}) |> Z.down() |> Z.up() == {{:foo, [], [1, 2]}, nil}

      assert Z.zip({{:., [], [:a, :b]}, [], [1, 2]}) |> Z.down() |> Z.up() ==
               {{{:., [], [:a, :b]}, [], [1, 2]}, nil}
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

    test "sets meta to :end when finishes" do
      zipper = Z.zip([1, [2, [3, 4]], 5])

      assert {_, :end} =
               zipper
               |> Z.next()
               |> Z.next()
               |> Z.next()
               |> Z.next()
               |> Z.next()
               |> Z.next()
               |> Z.next()
               |> Z.next()

      assert {42, :end} |> Z.next() == {42, :end}
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

  describe "end?/1" do
    test "returns true if it's an end zipper" do
      assert Z.end?({42, nil}) == false
      assert Z.end?({42, :end}) == true
    end
  end

  describe "traverse/2" do
    test "traverses in depth-first pre-order" do
      zipper = Z.zip([1, [2, [3, 4], 5], [6, 7]])

      assert Z.traverse(zipper, fn
               {x, m} when is_integer(x) -> {x * 2, m}
               z -> z
             end)
             |> Z.node() == [2, [4, [6, 8], 10], [12, 14]]
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
  end

  describe "top/1" do
    test "returns the top zipper" do
      assert Z.zip([1, [2, [3, 4]]]) |> Z.next() |> Z.next() |> Z.next() |> Z.top() ==
               {[1, [2, [3, 4]]], nil}

      assert Z.zip(42) |> Z.top() |> Z.top() |> Z.top() == {42, nil}
      assert {42, :end} |> Z.top() |> Z.top() |> Z.top() == {42, :end}
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

  describe "find/2" do
    test "finds a zipper with a predicate" do
      zipper = Z.zip([1, [2, [3, 4], 5]])

      assert Z.find(zipper, fn x -> x == 4 end) |> Z.node() == 4
    end
  end
end
