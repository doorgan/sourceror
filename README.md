# Sourceror 🧙

![Github
Actions](https://github.com/doorgan/sourceror/actions/workflows/main.yml/badge.svg?branch=main)
[![Coverage
Status](https://coveralls.io/repos/github/doorgan/sourceror/badge.svg?branch=main)](https://coveralls.io/github/doorgan/sourceror?branch=main)
[![Module
Version](https://img.shields.io/hexpm/v/sourceror.svg)](https://hex.pm/packages/sourceror)
[![Hex
Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/sourceror/)
[![Total
Download](https://img.shields.io/hexpm/dt/sourceror.svg)](https://hex.pm/packages/sourceror)
[![License](https://img.shields.io/hexpm/l/sourceror.svg)](https://github.com/doorgan/sourceror/blob/master/LICENSE)
[![Last
Updated](https://img.shields.io/github/last-commit/doorgan/sourceror.svg)](https://github.com/doorgan/sourceror/commits/master)

<!-- MDOC !-->

Utilities to work with Elixir source code.

## Installation

Add `:sourceror` as a dependency to your project's `mix.exs`:

```elixir
defp deps do
  [
    {:sourceror, "~> 1.2"}
  ]
end
```

### A note on compatibility

Sourceror is compatible with Elixir versions down to 1.10 and OTP 21. For Elixir
versions prior to 1.13 it uses a vendored version of the Elixir parser and
formatter modules. This means that for Elixir versions prior to 1.12 it will
successfully parse the new syntax for stepped ranges instead of raising a
`SyntaxError`, but everything else should work as expected.

## Goals of the library

- Be as close as possible to the standard Elixir AST.
- Make working with comments as simple as possible.
- No dev/prod dependencies, to simplify integration with other tools.

## Sourceror's AST

Having the AST and comments as separate entities allows Elixir to expose the
code formatting utilities without making any changes to it's AST, but also
delegates the task of figuring out what's the most appropriate way to work with
them to us.

Sourceror's take is to use the node metadata to store the comments. This allows
us to work with an AST that is as close to regular elixir AST as possible. It
also allows you to move nodes around without worrying about leaving a comment
behind and ending up with misplaced comments.

Two metadata fields are added to the regular Elixir AST:

- `:leading_comments` - holds the comments directly above the node or are in the
  same line as it. For example:

  ```elixir
  test "parses leading comments" do
    quoted = """
    # Comment for :a
    :a # Also a comment for :a
    """ |> Sourceror.parse_string!()

    assert {:__block__, meta, [:a]} = quoted
    assert meta[:leading_comments] == [
      %{line: 1, column: 1, previous_eol_count: 1, next_eol_count: 1, text: "# Comment for :a"},
      %{line: 2, column: 4, previous_eol_count: 0, next_eol_count: 1, text: "# Also a comment for :a"},
    ]
  end
  ```

- `:trailing_comments` - holds the comments that are inside of the node, but
  aren't leading any children, for example:

  ```elixir
  test "parses trailing comments" do
    quoted = """
    def foo() do
    :ok
    # A trailing comment
    end # Not a trailing comment for :foo
    """ |> Sourceror.parse_string!()

    assert {:__block__, block_meta, [{:def, meta, _}]} = quoted
    assert [%{line: 3, text: "# A trailing comment"}] = meta[:trailing_comments]
    assert [%{line: 4, text: "# Not a trailing comment for :foo"}] = block_meta[:trailing_comments]
  end
  ```

Note that Sourceror considers leading comments to the ones that are found in the
same line as a node, and trailing comments to the ones that are found before the
ending line of a node, based on the `end`, `closing` or `end_of_expression`
line. This also makes the Sourceror AST consistent with the way the Elixir
formatter works, making it easier to reason about how a given AST would be
formatted.

## Traversing the AST

Elixir provides the `Macro.prewalk`, `Macro.postwalk` and `Macro.traverse`
functions to traverse the AST. You can use the same functions to traverse the
Sourceror AST as well, since it has the same shape as the standard Elixir AST.

Sourceror also provides the `Sourceror.prewalk`, `Sourceror.postwalk` and
`Sourceror.traverse` variants. At the time of writing they are mostly wrappers
around the standard Elixir functions for AST traversal, but they may be enhanced
in the future if more AST formats are introduced.

In addition to these, Sourceror also provides a Zipper implementation for the
Elixir AST. You can learn more about it in the [Zippers
notebook](https://hexdocs.pm/sourceror/zippers.html).

## Patching the source code

You can use Sourceror to manipulate the AST and turn it back into human readable
Elixir code, this is commonly known as writing a "codemod". For example, you can
write a codemod to replace calls to `String.to_atom` to
`String.to_existing_atom`:

```elixir
test "updates the source code" do
  source =
    """
    String.to_atom(foo)\
    """

  new_source =
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk(fn
      {{:., dot_meta, [{:__aliases__, alias_meta, [:String]}, :to_atom]}, call_meta, args} ->
        {{:., dot_meta, [{:__aliases__, alias_meta, [:String]}, :to_existing_atom]}, call_meta, args}

      quoted ->
        quoted
    end)
    |> Sourceror.to_string()

  assert new_source ==
    """
    String.to_existing_atom(foo)\
    """
end
```

However, this will affect the whole source code, as we are working on the full
source AST. Sourceror relies on the Elixir formatter to produce human readable
code, so the original code formatting will be lost by using
`Sourceror.to_string`. If your code is already using the Elixir formatter then
this won't be an issue, but it will be an undesirable effect if you're not using
it.

An alternative to this is to use Patches instead. A patch is a data structure
that specifies the text range that should be replaced, and either a replacement
string or a function that takes the text in that range and produces a string
replacement.

Using patches, we could do the same as above, but produce a patch instead of
modifying the AST. As a result, only the parts that need to be changed will be
affected, and the rest of the code keeps the original formatting:

```elixir
test "patches the source code" do
  source =
    """
    case foo do
      nil ->         :bar
      _ ->

          String.to_atom(foo)

          end\
    """

  {_quoted, patches} =
    source
    |> Sourceror.parse_string!()
    |> Macro.postwalk([], fn
      {{:., dot_meta, [{:__aliases__, alias_meta, [:String]}, :to_atom]}, call_meta, args} = quoted, patches ->
        range = Sourceror.get_range(quoted)
        replacement =
          {{:., dot_meta, [{:__aliases__, alias_meta, [:String]}, :to_existing_atom]}, call_meta, args}
          |> Sourceror.to_string()

        patch = %{range: range, change: replacement}
        {quoted, [patch | patches]}

      quoted, patches ->
        {quoted, patches}
    end)

  assert Sourceror.patch_string(source, patches) ==
    """
    case foo do
      nil ->         :bar
      _ ->

          String.to_existing_atom(foo)

          end\
    """
end
```

You have to keep in mind that:

1. If you patch a node that has inner code, like replacing a full `case`, then
   the contents of the node will be reformatted as well.

2. At the moment, Sourceror won't check for conflicts in the patches ranges, so
   care needs to be taken to not produce conflicting patches. You may need to do
   a number of `parse -> patch -> reparse` if you find yourself generating
   conflicting patches.

Some of the most common patching operations are available in the
[Sourceror.Patch](https://hexdocs.pm/sourceror/Sourceror.Patch.html) module

## Background

There have been several attempts at source code manipulation in the Elixir
community. Thanks to its metaprogramming features, Elixir provides builtin tools
that let us get the AST of any Elixir code, but when it comes to turning the AST
back to code as text, we had limited options. `Macro.to_string/2` is a thing,
but the produced code is generally ugly, mostly because of the extra parenthesis
or because it turns string interpolations into calls to erlang modules, to name
some examples. This meant that, even if we could use `Macro.to_string/2` to get
a string and then give that to the Elixir formatter `Code.format_string!/2`, the
output would still be suboptimal, as the formatter is not designed to change the
semantics of the code, only to pretty print it. For example, call to erlang
modules would be kept as is instead of being turned back to interpolations.

We also had the additional problem of comments being discarded by the tokenizer,
and literals not having information like line numbers or delimiter characters.
This makes the regular AST too lossy to be useful if what we want is to
manipulate the source code, because we need as much information as possible to
be able to stay as close to the source as possible. There have been several
proposal in the past to bring all this information to the Elixir AST, but they
all meant a change that would either break macros due to the addition of new
types of AST nodes, or making a compromise in core Elixir itself by storing
comments in the nods metadata. [This
discussion](https://groups.google.com/u/1/g/elixir-lang-core/c/GM0yM5Su1Zc/m/poIKsiEVDQAJ)
in the Elixir mailing list highlights the various issues faced when deciding if
and how the comments would be preserved. Arjan Scherpenisse also did a
[talk](https://www.youtube.com/watch?v=aM0BLWgr0g4&t=117s) where he discusses
about the problems of using the standard Elixir AST to build refactoring tools.

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
Elixir formatter is able to use, and the latter lets us turn _any arbitrary
Elixir AST_ into an algebra document. If we also give it the list of comments,
it will merge them together, allowing us to format AST _and_ preserve the
comments. Now all we need to care about is of manipulating the AST, and let the
formatter do the rest.

<!-- MDOC !-->

## Documentation

You can find Sourceror documentation on [Hex
Docs](https://hexdocs.pm/sourceror/readme.html).

## Examples

You can find usage examples in the `examples` folder. You can run them by
cloning the repo and running `elixir examples/<example_file>.exs`.

You can also find documented examples you can run with
[Livebook](https://github.com/elixir-nx/livebook) in the `notebooks` folder.

## Contributing

If you want to contribute to Sourceror, please check our
[Contributing](https://github.com/doorgan/sourceror/blob/master/CONTRIBUTING.md)
section for pointers.

## Getting assistance

If you have any questions about Sourceror or need assistance, please open a
thread in the [Discussions](https://github.com/doorgan/sourceror/discussions)
section.

## Copyright and License

Copyright (c) 2021 dorgandash@gmail.com

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at
[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
