"""
defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "0.1.0",
      elixir: "~> 1.13.0-dev",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:a, "~> 1.0"},
      {:z, "~> 1.0"},
      {:g, "~> 1.0"},
      # Comment for r
      {:r, "~> 1.0"},
      {:y, "~> 1.0"},
      # Comment for :u
      {:u, "~> 1.0"},
      {:e, "~> 1.0"},
      {:s, "~> 1.0"},
      {:v, "~> 1.0"},
      {:c, "~> 1.0"},
      {:b, "~> 1.0"},
    ]
  end
end
"""
|> Sourceror.parse_string()
|> Sourceror.postwalk(fn
  {:defp, meta, [{:deps, _, _} = fun, body]}, state ->
    [{{_, _, [:do]}, block_ast}] = body
    {:__block__, block_meta, [deps]} = block_ast

    lines = Enum.map(deps, fn {:__block__, meta, _} -> meta[:line] end)

    deps =
      Enum.sort_by(deps, fn {:__block__, _, [{{_, _, [name]}, _}]} ->
        Atom.to_string(name)
      end)

    deps =
      Enum.zip([lines, deps])
      |> Enum.map(fn {old_line, dep} ->
        {_, tuple_meta, [{left, right}]} = dep
        line_correction = old_line - tuple_meta[:line]

        tuple_meta = Sourceror.correct_lines(tuple_meta, line_correction)
        left = Macro.update_meta(left, &Sourceror.correct_lines(&1, line_correction))
        right = Macro.update_meta(right, &Sourceror.correct_lines(&1, line_correction))

        {:__block__, tuple_meta, [{left, right}]}
      end)

    quoted = {:defp, meta, [fun, [do: {:__block__, block_meta, [deps]}]]}
    state = Map.update!(state, :line_correction, & &1)
    {quoted, state}

  quoted, state ->
    {quoted, state}
end)
|> Sourceror.to_string()
|> IO.puts()
