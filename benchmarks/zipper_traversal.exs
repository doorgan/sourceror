read_code =
  fn name ->
    path =
      [__DIR__, "**", name]
      |> Path.join()
      |> Path.wildcard()
      |> List.first()

    source = File.read!(path)
    Sourceror.parse_string!(source)
  end


Benchee.run(
  %{
    "Macro.postwalk/2" => fn ast ->
      Macro.traverse(ast, nil, fn quoted, _ -> {quoted, nil} end, fn quoted, _ -> {quoted, nil} end)
    end,

    "Styler.Zipper.traverse/2" => fn ast ->
      zipper = Styler.Zipper.zip(ast)
      Styler.Zipper.traverse(zipper, fn quoted -> quoted end)
    end,

    "Styler.FastZipper.traverse/2" => fn ast ->
      zipper = Styler.FastZipper.zip(ast)
      Styler.FastZipper.traverse(zipper, fn quoted -> quoted end)
    end,

    "Sourceror.FastZipper.traverse/2" => fn ast ->
      record_zipper = Sourceror.FastZipper.zip(ast)
      Sourceror.FastZipper.traverse(record_zipper, fn quoted -> quoted end)
    end
  },
  inputs: %{
    "small" => read_code.("small.ex"),
    "medium" => read_code.("enum.ex"),
    "large" => read_code.("kernel.ex")
  },
  time: 5,
  memory_time: 2,
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.Console
  ]
)
