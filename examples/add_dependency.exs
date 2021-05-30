Mix.install([{:sourceror, git: "https://github.com/doorgan/sourceror.git"}, :httpoison, :jason])

defmodule Demo do
  def fetch_version(name) do
    url = "https://hex.pm/api/packages/#{Atom.to_string(name)}"

    with {:ok, response} <- HTTPoison.get(url) do
      version =
        response.body
        |> Jason.decode!()
        |> Map.get("latest_stable_version")

      %{major: major, minor: minor} = Version.parse!(version)

      {:ok, "#{major}.#{minor}"}
    end
  end

  def add_dep(source, name, version \\ nil) do
    version =
      with is_nil(version), {:ok, version} <- fetch_version(name) do
        version
      else
        {:error, _} -> raise "Could not find a hex package for #{inspect name}"
        true -> version
      end

    source
    |> Sourceror.parse_string!()
    |> Sourceror.postwalk(fn
      {:defp, meta, [{:deps, _, _} = fun, body]}, state ->
        [{{_, _, [:do]}, block_ast}] = body
        {:__block__, block_meta, [deps]} = block_ast

        dep_line =
          case List.last(deps) do
            {_, meta, _} ->
              meta[:line] || block_meta[:line]

            _ ->
              block_meta[:line]
          end + 1

        deps =
          deps ++
            [
              {:__block__, [line: dep_line],
                [
                  {
                    name,
                    {:__block__, [line: dep_line, delimiter: "\""], ["~> " <> version]}
                  }
                ]}
            ]

        ast = {:defp, meta, [fun, [do: {:__block__, block_meta, [deps]}]]}
        state = Map.update!(state, :line_correction, & &1)
        {ast, state}

      other, state ->
        {other, state}
    end)
    |> Sourceror.to_string()
  end
end

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
      {:a, "~> 1.0"}
    ]
  end
end
"""
|> Demo.add_dep(:jason)
|> IO.puts()
