defmodule Sourceror.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/dashbitco/nimble_parsec"

  def project do
    [
      app: :sourceror,
      version: @version,
      elixir: "~> 1.13.0-dev",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [docs: &build_docs/1]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false}
    ]
  end

  defp build_docs(_) do
    Mix.Task.run("compile")
    ex_doc = Path.join(Mix.path_for(:escripts), "ex_doc")

    unless File.exists?(ex_doc) do
      raise "cannot build docs because escript for ex_doc is not installed"
    end

    args = ["Sourceror", @version, Mix.Project.compile_path()]
    opts = ~w[--main Sourceror --source-ref v#{@version} --source-url #{@url}]
    System.cmd(ex_doc, args ++ opts)
    Mix.shell().info("Docs built successfully")
  end
end
