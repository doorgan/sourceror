![Github Actions](https://github.com/doorgan/sourceror/actions/workflows/main.yml/badge.svg?branch=main)
[![Coverage Status](https://coveralls.io/repos/github/doorgan/sourceror/badge.svg?branch=main)](https://coveralls.io/github/doorgan/sourceror?branch=main)

# Sourceror 🧙

Utilities to work with Elixir source code.

**NOTICE:** This library is under heavy development. Expect frequent breaking
changes until the first stable v1.0 release is out.

## Documentation

You can find Sourceror documentation on [Hex Docs](https://hexdocs.pm/sourceror/readme.html).

## Examples

You can find usage examples in the `examples` folder. You can run them by
cloning the repo and running `elixir examples/<example_file>.exs`.

You can also find documented examples you can run with [Livebook](https://github.com/elixir-nx/livebook)
in the `notebooks` folder.

## Contributing

If you want to contribute to Sourceror, please check our
[Contributing](https://github.com/doorgan/sourceror/blob/master/CONTRIBUTING.md)
section for pointers.

## Getting assistance

If you have any questions about Sourceror or need assistance, please open a
thread in the [Discussions](https://github.com/doorgan/sourceror/discussions)
section.

<!-- MDOC !-->

## Installation

Add `:sourceror` as a dependency to your project's `mix.exs`:

```elixir
defp deps do
  [
    {:sourceror, "~> 0.7.2"}
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

  * Be as close as possible to the standard Elixir AST.
  * Make working with comments as simple as possible.
  * No runtime dependencies, to simplify integration with other tools.

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
us to work with an AST that is as close to regular elixir AST as possible. It
also allows you to move nodes around without worrying about leaving a comment
behind and ending up with misplaced comments.

Two metadata fields are added to the regular Elixir AST:
  * `:leading_comments` - holds the comments directly above the node or are in
    the same line as it. For example:

    ```elixir
    test "parses leading comments" do
      quoted = """
      # Comment for :a
      :a # Also a comment for :a
      """ |> Sourceror.parse_string!()

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
      end # Not a trailing comment for :foo
      """ |> Sourceror.parse_string!()

      assert {:__block__, block_meta, [{:def, meta, _}]} = quoted
      assert [%{line: 3, text: "# A trailing comment"}] = meta[:trailing_comments]
      assert [%{line: 4, text: "# Not a trailing comment for :foo"}] = block_meta[:trailing_comments]
    end
    ```

Note that Sourceror considers leading comments to the ones that are found in the
same line as a node, and trailing coments to the ones that are found before the
ending line of a node, based on the `end`, `closing` or `end_of_expression`
line. This also makes the Sourceror AST consistent with the way the Elixir
formatter works, making it easier to reason about how a given AST would be
formatted.

## License

Copyright (c) 2021 dorgandash@gmail.com

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
