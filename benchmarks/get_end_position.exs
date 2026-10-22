definitions = fn name ->
  {_, definitions} =
    ["benchmarks", "data", name]
    |> Path.join()
    |> File.read!()
    |> Sourceror.parse_string!()
    |> Macro.prewalk([], fn
      {form, _, args} = quoted, acc
      when form in [:def, :defp, :defmacro, :defmacrop, :defmodule] and is_list(args) ->
        {quoted, [quoted | acc]}

      quoted, acc ->
        {quoted, acc}
    end)

  definitions
end

Benchee.run(
  %{
    "Sourceror.get_end_position/2" => fn definitions ->
      Enum.each(definitions, &Sourceror.get_end_position/1)
    end
  },
  inputs: %{
    "small" => definitions.("small.ex"),
    "medium" => definitions.("enum.ex"),
    "large" => definitions.("kernel.ex")
  },
  time: 5,
  memory_time: 2,
  formatters: [Benchee.Formatters.Console]
)
