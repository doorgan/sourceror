![Github Actions](https://github.com/doorgan/sourceror/actions/workflows/main.yml/badge.svg?branch=main)

# Sourceror

Utilities to work with Elixir source code.

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

## Installation

Sourceror depends on functionality that is only available in the `master` branch
of Elixir. A hex release will be published once Elixir 1.13 is released, in the
meantime you can add Sourceror via a git dependency:

```elixir
{:sourceror, git: "https://github.com/doorgan/sourceror.git"}
```

## Examples

You can find usage examples in the `examples` folder. You can run them with
`elixir examples/<example_file>.exs`.

## License

Copyright (c) 2021 dorgandash@gmail.com

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
