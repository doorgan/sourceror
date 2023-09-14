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
  Return paths to Elixir files in the corpus.

  By default, all paths for syntax valid for the current system version
  are returned. To include only some paths, pass a list of strings to be
  compared using `=~`.
  """
  def paths(includes \\ [""]) do
    ommissions = ommissions()

    "test/corpus/**/*.ex"
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to_cwd(&1))
    |> Enum.filter(&contains?(includes, &1))
    |> Enum.reject(&contains?(ommissions, &1))
  end

  defp contains?(ommissions, file) do
    Enum.any?(ommissions, &(file =~ &1))
  end

  defp ommissions do
    version = System.version()

    @version_requirements
    |> Enum.filter(fn {requirement, _file} -> not Version.match?(version, requirement) end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Applies the given function to every syntax node parsed from the included
  paths.

  See `paths/1` for how includes work.

  The function must accept two arguments, the quoted node and the current
  path, and is return value is ignored.
  """
  def walk!(includes \\ [""], fun) when is_list(includes) and is_function(fun, 2) do
    includes
    |> paths()
    |> Enum.each(fn path ->
      path
      |> File.read!()
      |> Sourceror.parse_string!()
      |> walk(fun, path)
    end)
  end

  defp walk(quoted, fun, path) do
    Sourceror.prewalk(quoted, fn quoted, acc ->
      fun.(quoted, path)
      {quoted, acc}
    end)
  end
end
