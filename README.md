![Github Actions](https://github.com/doorgan/sourceror/actions/workflows/main.yml/badge.svg?branch=main)
[![Coverage Status](https://coveralls.io/repos/github/doorgan/sourceror/badge.svg?branch=main)](https://coveralls.io/github/doorgan/sourceror?branch=main)

# Sourceror

Utilities to work with Elixir source code.

<!-- MDOC !-->

## Installation

Add `:sourceror` as a dependency to your project's `mix.exs`:

```elixir
defp deps do
  [
    {:sourceror, "~> 0.2.2"}
  ]
end
```

### A note on compatibility

Sourceror is compatible with Elixir versions down to 1.10 and OTP 21. For Elixir
versions prior to 1.13 it uses a vendored version of the Elixir parser and
formatter modules.

## Documentation

[Hex Docs](https://hexdocs.pm/erlex/readme.html).

## Background

There have been several attempts at source code manipulation in the Elixir
community. Thanks to its metaprogramming features, Elixir provides builtin tools
that let us get the AST of any Elixir code, but when it comes to turning
the AST back to code as text, we had limited options. `Macro.to_string/2` is a
thing, but the produced code is generally ugly, mostly because of the extra
parenthesis or because it turns string interpolations into calls to erlang
modules, to name some examples. This meant that, even if we could use
`Macro.to_string/2` to get a string and then give that to the Elixir formatter
`Code.format_string!/2`, the output would still be suboptimal, as the formatter
is not designed to change the semantics of the code, only to pretty print it.
For example, call to erlang modules would be kept as is instead of being turned
back to interpolations.

We also had the additional problem of comments being discarded by the tokenizer,
and literals not having information like line numbers or delimiter characters.
This makes the regular AST too lossy to be useful if what we want is to
manipulate the source code, because we need as much information as possible to
be able to stay as close to the source as possible. There have been several
proposal in the past to bring all this information to the Elixir AST, but they
all meant a change that would either break macros due to the addition of new
types of AST nodes, or making a compromise in core Elixir itself by storing
comments in the nods metadata.

Despite of all these issues, the Elixir formatter is still capable of
manipulating the source code to pretty print it. Under the hood it does some
neat tricks to have all this information available: on one hand, it tells the
tokenizer to extract the comments from the source code and keep it at hand(not
in the AST itself, but as a separate data structure), and on the other hand it
tells the parser to wrap literals in block nodes so metadata can be preserved.
Once it has all it needs, it can start converting the AST and comments into an
algebra document, and ultimately convert that to a string. This functionality
was private, and if we wanted to do it ourselves we would have to replicate or
vendor the Elixir formatter with all its more than 2000 lines of code. This
approach was explored by Wojtek Mach in
[wojtekmach/fix](https://github.com/wojtekmach/fix), but it involved vendoring
the elixir Formatter code, was tightly coupled to the formatting process, and
any change in Elixir would break the code.

Since Elixir 1.13 this functionality from the formatter was finally exposed via
the `Code.string_to_quoted_with_comments/2` and `Code.quoted_to_algebra/2`
functions. The former gives us access to the list of comments in a shape the
Elixir formatter is able to use, and the latter lets us turn *any arbitrary
Elixir AST* into an algebra document. If we also give it the list of comments,
it will merge them together, allowing us to format AST *and* preserve the
comments. Now all we need to care about is of manipulating the AST, and let the
formatter do the rest.

## Sourceror's AST

Having the AST and comments as separate entities allows Elixir to expose the
code formatting utilities without making any changes to it's AST, but also
delegates the task of figuring out what's the most appropiate way to work with
them to us.

Sourceror's take is to use the node metadata to store the comments. This allows
you to move nodes around without worrying about leaving a comment behind and
ending up with misplaced comments. Two fields are required for this:
  * `:leading_comments` - holds the comments directly above the node or are in
    the same line as it. For example:

    ```elixir
    test "parses leading comments" do
      quoted = """
      # Comment for :a
      :a # Also a comment for :a
      """ |> Sourceror.parse_string()
      
      assert {:__block__, meta, [:a]} = quoted
      assert meta[:leading_comments] == [
        %{line: 1, previous_eol_count: 1, next_eol_count: 1, text: "# Comment for :a"},
        %{line: 2, previous_eol_count: 0, next_eol_count: 1, text: "# Also a comment for :a"},
      ]
    end
    ```

  * `:trailing_comments` - holds the comments that are inside of the node, but
    aren't leading any children, for example:

    ```elixir
    test "parses trailing comments" do
      quoted = """
      def foo() do
      :ok
      # A trailing comment
      end # Also a trailing comment for :foo
      """ |> Sourceror.parse_string()
      
      assert {:def, meta, _} = quoted
      assert meta[:trailing_comments] == [
        %{line: 3, previous_eol_count: 1, next_eol_count: 1, text: "# A trailing comment"},
        %{line: 4, previous_eol_count: 0, next_eol_count: 1, text: "# Also a trailing comment for :foo"},
      ]
    end
    ```

Note Sourceror considers leading comments to the ones that are found in the same
line as a node, and trailing coments to the ones that are found in the same line
or before the ending line of a node, based on the `end`, `closing` or
`end_of_expression` line.

## Working with line numbers

The way the Elixir formatter combines AST and comments depends on their line
numbers and the order in which the AST is traversed. This means that whenever
you move a node around, you need to also change the line numbers to reflect
their position in the node. This is best seen with an example. Lets imagine you
have a list of atoms and you want to sort them in alphabetical order:
```elixir
:a
# Comment for :j
:j
:c
# Comment for :b
:b
```
Sorting it is trivial, as you just need to use `Enum.sort_by` with
`Atom.to_string(atom)`. But if we consider the line numbers:
```
1 :a
2 # Comment for :j
3 :j
4 :c
5 # Comment for :b
6 :b
```
If we sort them, we end up with this:
```
1 :a
6 :b
4 :c
3 :j
```
And the comments will be associated to the line number of the node they're leading:
```
6 # Comment for :b
3 # Comment for :j
```
When the formatter traverses the AST, it will find node `:b` with line `6` and
will see comment with line `6`, and it will print that comment. But it will also
see the comment with line `3` and will go like "hey, this comment has a line
number smaller than this node, so this is a trailing comment too!" and will
print that comment as well. That will make it output this code:
```elixir
:a
# Comment for :b
# Comment for :j
:b
:c
:j
```
And that's not what we want at all. To avoid this issue, we need to calculate
how line numbers changed while the sorting and correct them appropiately.
Sourceror provides a `correct_lines(node, line_correction)` that takes care of
correcting all the line numbers associated to a node, so all you have to do is
figure out the line correction numbers. One way to do it in this example is by
getting the line numbers before the change, reorder the nodes, zip the old line
numbers with the nodes, and correct their line numbers by the difference between
the new and the old one. Translated to code, it would look something like this:
```elixir
test "sorts atoms with correct comments placement" do
  {:__block__, meta, atoms} = """
  :a
  # Comment for :j
  :j
  :c
  # Comment for :b
  :b
  """ |> Sourceror.parse_string()

  lines = Enum.map(atoms, fn {:__block__, meta, _} -> meta[:line] end)

  atoms =
    Enum.sort_by(atoms, fn {:__block__, _, [atom]} ->
      Atom.to_string(atom)
    end)
    |> Enum.zip(lines)
    |> Enum.map(fn {{_, meta, _} = atom, old_line} ->
      line_correction = old_line - meta[:line]
      Macro.update_meta(atom, &Sourceror.correct_lines(&1, line_correction))
    end)

  assert Sourceror.to_string({:__block__, meta, atoms}) == """
  :a
  # Comment for :b
  :b
  :c
  # Comment for :j
  :j
  """ |> String.trim()
end
```
Which will produce the code we expect:
```elixir
:a
# Comment for :b
:b
:c
# Comment for :j
:j
```

In other cases, you may want to add lines to the code, which would cause the new
nodes to have higher line numbers than the nodes that come after it, and that
would also mess up the comments placement. For those use cases Sourceror
provides the `Sourceror.postwalk/3` function. It's a wrapper over
`Macro.postwalk/3` that lets you set the line correction that should be applied
to subsequent nodes, and it will automatically correct them for you before
calling your function on each node. You can see this in action in the
`examples/expand_multi_alias.exs` example.

## Examples

You can find usage examples in the `examples` folder. You can run them with
`elixir examples/<example_file>.exs`.

## License

Copyright (c) 2021 dorgandash@gmail.com

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
