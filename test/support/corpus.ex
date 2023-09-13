defmodule SourcerorTest.Support.Corpus do
  @moduledoc false

  @version_requirements [
    {">= 1.11.0", "_1_11.ex"},
    {">= 1.12.0", "_1_12.ex"},
    {">= 1.13.0", "_1_13.ex"},
    {">= 1.14.0", "_1_14.ex"},
    {">= 1.15.0", "_1_15.ex"}
  ]

  @doc """
  Return paths to all Elixir files in the corpus.
  """
  def all_paths do
    ommissions = ommissions()

    "test/corpus/**/*.ex"
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to_cwd(&1))
    |> Enum.reject(&omit?(ommissions, &1))
  end

  def omit?(ommissions, file) do
    Enum.any?(ommissions, &(file =~ &1))
  end

  def ommissions do
    version = System.version()

    @version_requirements
    |> Enum.filter(fn {requirement, _file} -> not Version.match?(version, requirement) end)
    |> Enum.map(&elem(&1, 1))
  end
end
