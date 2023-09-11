## for / enumerable

for n <- [1, 2], do: n * 2

## for / enumerable / with options and block

for line <- IO.stream(), into: IO.stream() do
  String.upcase(line)
end

## for / binary

for <<c <- " hello world ">>, c != ?\s, into: "", do: <<c>>

## for / reduce

for x <- [1, 2, 1], reduce: %{} do
  acc -> Map.update(acc, x, 1, & &1 + 1)
end