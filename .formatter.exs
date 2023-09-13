locals_without_parens = [
  # Typedstruct
  field: 2,
  field: 3
]

[
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ],
  inputs:
    ["{mix,.formatter}.exs"] ++
      (Path.wildcard("{config,lib,test}/**/*.{ex,exs}") -- Path.wildcard("test/corpus/**/*.ex"))
]
