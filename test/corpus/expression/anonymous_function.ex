## no arguments

fn() -> 1 end
fn () -> 1 end

## no arguments without parentheses

fn -> 1 end

## one argument

fn(x) -> x end

## one argument without parentheses

fn x -> x end

## many arguments

fn(x, y, z) -> x + y end

## many arguments without parentheses

fn x, y -> x + y end

## multiline body

fn x, y ->
  y
  x
end

## many clauses

fn
  1 -> :yes
  2 -> :no
  other -> :maybe
end

## with guard / no arguments

fn
  () when node() == :nonode@nohost -> true
end

## with guard / one argument

fn
  x when x == [] -> x
end

## with guard / multiple arguments

fn
  x, y when x == [] -> x
end

## with guard / arguments in parentheses

fn
  (x, y) when y == [] -> y
end

## with guard / multiple guards

fn
  x when x > 10 when x < 5 -> x
end

## pattern matching

fn
  [h | tail] -> {h, tail}
  %{x: x} when x == 1 -> 1
end