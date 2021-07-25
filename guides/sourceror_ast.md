# The Sourceror AST

Sourceror AST nodes are made of a simple 3-tuple data structure:
```elixir
{type, metadata, value_or_children}
```
The type is what uniquely identifies a kind of AST node, and is what you will
mostly use to pattern match during traversals to stop certain patterns. The
metadata is a map that contains the same metadata as regular Elixir AST nodes(at
the very least it has `:line` and `:column` numbers), plus some extra metadata
specific to Sourceror:

* `:leading_comments` - the comments found in the same line or above the node
* `:trailing_comments` - the comments found before the node ends, for example
  right before the `end` keyword.
* `:token` - In noodes like integers or floats, it holds the original textual
  representation of the value. For example, for the null byte `0x00` it will
  keep it as `"0x00"`.

The last element of the tuple is the value for terminal nodes, or the children
in the case of branching nodes. The following is a complete reference of the
kind Sourceror speficic nodes you will find. The metadata is represented as an
underscore for the sake of brevity, or with a map with the specific metadata
associated with that kind of node:

### Strings
```elixir
"foo"         ->    {:string, _, "foo"}
```
```elixir
"""
foo
"""           ->    {:string, %{delimiter: ~w["""], indentation: 0}, "foo\n"}
```

### Charlists
```elixir
'foo'         ->    {:charlist, _, "foo"}
```
```elixir
'''
foo
'''           ->    {:charlist, %{delimiter: ~w['''], indentation: 0}, "foo\n"}
```

### Atoms
```elixir
:foo          ->    {:atom, _, :foo}
```

### Variables
```elixir
foo           ->    {:var, _, :foo}
```

### Numbers
```elixir
42_000        ->    {:int, %{token: "42_000"}, 42000}
```
```elixir
42_000.42     ->    {:float, %{token: "42_000.42"}, 42000.00}
```

### Interpolated string
```elixir
"a#{:b}c"     ->    {{:<<>>, :string}, _, [
                        {:string, _, "a"},
                        {:"::", _, [{:atom, _, :b}]},
                        {:string, _, "c"}]}
```

### Interpolated atom
```elixir
:"a#{:b}c"    ->    {{:<<>>, :atom}, _, [
                        {:string, _, "a"},
                        {:"::", _, [{:atom, _, :b}]},
                        {:string, _, "c"}]}
```

### Module aliases
```elixir
Foo.Bar       ->    {:__aliases__, _, [{:atom, _, :Foo}, {:atom, _, :Bar}]}
```

### Tuples
```elixir
{1, 2, 3}     ->    {:{}, _, [1, 2, 3]}
```

### Lists
```elixir
[1, 2, 3]     ->    {[], _, [1, 2, 3]}
```

### Keyword lists
```elixir
[a: :b]       ->    {[], _, [
                        {{:atom, %{format: :keyword}, :a}, {:atom, _, :b}}
                      ]}
```

### Sigils
```elixir
~w[a b c]d    ->    {:"~", %{delimiter: "["}, [
                        "w", [{:string, _, "a b c"}], 'd']}
```
```elixir
~S"""
  a b c
  """         ->    {:"~", %{delimiter: ~w["""], indentation: 2}, [
                        "S", [{:string, _, "a b c"}], 'd']}
```

### Keyword blocks
```elixir
foo :bar do 
  :baz
rescue
  :qux
  :quux
end           ->    {:foo, _, [
                        {:atom, _, :bar},
                        [
                          {{:atom, _, :do}, {:atom, _, :bar}}
                          {{:atom, _, :rescue}, {:__block__, _,
                            [{:atom, _, :qux}, {:atom, _, :quux}]
                          }}
                        ]
                      ]}
```

### Qualified calls
```elixir
foo.bar :baz  ->    {{:., _, [{:var, _, :foo}, {:atom, _, :bar}]}, _, [{:atom, _, :baz}]}
```

Every other node is kept as in the regular Elixir AST, except that the metadata
is converted to a map.
