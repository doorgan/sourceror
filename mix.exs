defmodule Sourceror.MixProject do
  use Mix.Project

  @repo_url "https://github.com/doorgan/sourceror"
  @version "1.12.0"

  def project do
    [
      app: :sourceror,
      name: "Sourceror",
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_paths: erlc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls]
    ]
    |> maybe_add_preferred_cli_env()
  end

  # `:preferred_cli_env` in `def project` is deprecated since Elixir v1.19
  # in favor of `def cli` with `:preferred_envs`. `def cli` is available
  # from Elixir v1.14 onwards, so on v1.12/v1.13 we still set the legacy
  # option in `def project` to avoid breaking the build.
  defp maybe_add_preferred_cli_env(project) do
    if Version.match?(System.version(), "< 1.14.0") do
      Keyword.put(project, :preferred_cli_env, preferred_envs())
    else
      project
    end
  end

  if Version.match?(System.version(), ">= 1.14.0") do
    def cli do
      [preferred_envs: preferred_envs()]
    end
  end

  defp preferred_envs do
    [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  if Version.match?(System.version(), ">= 1.13.0") do
    defp elixirc_paths(:dev), do: ["lib"]
    defp elixirc_paths(:test), do: ["lib", "test/support"]
    defp elixirc_paths(_), do: ["lib"]
  else
    defp elixirc_paths(:dev), do: ["lib", "lib_vendored"]
    defp elixirc_paths(:test), do: ["lib", "lib_vendored", "test/support"]
    defp elixirc_paths(_), do: ["lib", "lib_vendored"]
  end

  defp erlc_paths(_) do
    if Version.match?(System.version(), ">= 1.13.0") do
      ["src"]
    else
      ["src", "src_vendored"]
    end
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :erts, :kernel, :stdlib],
      flags: ["-Wunmatched_returns", "-Werror_handling", "-Wno_opaque"],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.3", only: [:dev], runtime: false},
      {:benchee_html, "~> 1.0", only: :dev},
      {:credo, "~> 1.7.13", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.2", only: [:dev], runtime: false},
      {:ex_check, "~> 0.15.0", only: [:dev], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.15", only: [:test]},
      {:sobelow, "~> 0.11", only: :dev}
    ]
  end

  defp package do
    [
      description: "Utilities to work with Elixir source code.",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @repo_url
      }
    ]
  end

  defp docs do
    [
      extras: [
        "notebooks/zippers.livemd",
        "notebooks/expand_multi_alias.livemd",
        "CHANGELOG.md": [title: "Changelog"],
        "CONTRIBUTING.md": [title: "Contributing"],
        LICENSE: [title: "License"],
        "README.md": [title: "Overview"]
      ],
      groups_for_extras: [
        Guides: ~r/notebooks/
      ],
      main: "readme",
      homepage_url: @repo_url,
      source_ref: "v#{@version}",
      source_url: @repo_url,
      formatters: ["html"]
    ]
  end
end
