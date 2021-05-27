[
  parallel: true,
  skipped: true,

  tools: [
    {:unused_deps, command: "mix deps.unlock --check-unused"},
    {:credo, "mix credo --strict --format oneline"},
    {:compiler, "mix compile --warnings-as-errors"},
    {:sobelow, false}
  ]
]
