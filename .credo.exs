%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "src/",
          "test/"
        ],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          ~r"/lib/sourceror/code/",
          ~r"/test/corpus/",
          "lib/sourceror/code.ex"
        ]
      }
    }
  ]
}
