# Sourceror

Utilities to work with Elixir source code.

**IMPORTANT**

Sourceror depends on functionality that is only available in the `master` branch
of Elixir. A hex release will be published once Elixir 1.13 is released, in the
meantime you can add Sourceror via a git dependency:

```elixir
{:sourceror, git: "https://github.com/doorgan/sourceror.git"}
```

<!-- MDOC !-->

Sourceror provides various utilities to work with Elixir source code. Elixir now
lets us extract the comments from the source code and combine them with any
quoted expression to produce formatted code. However, how the ast is manipulated
and how changes in line numbers are reconciled between ast and comments is up
to the user.

The approach used by sourceror is to merge the comments into the ast metadata,
and use a custom traversal function to correct line numbers when needed, and
produce a formatted output that respects the placement of comments in the source
code. You can check the `Sourceror.parse_string/1` and `Sourceror.postwalk/2`
functions to learn more about this.
