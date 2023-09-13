## call without arguments

fun do
  a
end

## call with arguments in parentheses

fun(a, b) do
  c
end

## call with arguments without parentheses

fun a, b do
  c
end

## remote call

Mod.fun do
  a
end

## sticks to the outermost call

outer_fun inner_fun arg do
  a
end

## newline before do

fun x
do
  x
end

fun x
# comment
do
  x
end

fun()
do
  x
end

Mod.fun x
do
  x
end

## stab clause / no arguments

fun do
 () -> x
end

## stab clause / no arguments without parentheses

fun do
  -> x
end

## stab clause / one argument

fun do
  x -> x
end

## stab clause / many arguments

fun do
  x, y, 1 -> :ok
end

## stab clause / arguments in parentheses

fun do
  (x, y) -> :ok
end

## stab clause / many clauses

fun do
  1 -> :yes
  2 -> :no
  other -> :maybe
end

## stab clause / multiline expression

fun do
  x ->
    y
    x
end

## stab clause / with guard / no arguments

fun do
  () when node() == :nonode@nohost -> true
end

## stab clause / with guard / one argument

fun do
  x when x == [] -> x
end

## stab clause / with guard / multiple arguments

fun do
  x, y when x == [] -> x
end

## stab clause / with guard / arguments in parentheses

fun do
  (x, y) when y == [] -> y
end

## stab clause / with guard / multiple guards

fun do
  x when x > 10 when x < 5 -> x
end

## stab clause / edge cases / no stab

foo do
  a when a
end

foo do
  ([])
end

## stab clause / edge cases / "when" in arguments

foo do
  a when b, c when d == e -> 1
  (a, a when b) -> 1
end

## stab clause / edge cases / block argument

foo do
  (x; y) -> 1
  ((x; y)) -> 1
end

## stab clause / edge cases / operator with lower precedence than "when"

foo do
  x <- y when x -> y
end

foo do
  (x <- y) when x -> y
end

## stab clause / edge cases / empty

fun do->end

## stab clause / edge cases / trailing call in multiline clause

fun do
  1 ->
    1
    x

  1 ->
    1
end

fun do
  1 ->
    1
    Mod.fun

  1 ->
    1
end

fun do
  1 ->
    1
    mod.fun

  1 ->
    1
end

fun do
  1 ->
    1

  x 1 ->
    1
end

## stab clause / edge cases / empty right-hand-side

fun do
  x ->
end

## pattern matching

fun do
  [h | tail] -> {h, tail}
end

## child blocks / after

fun do
  x
after
  y
end

## child blocks / catch

fun do
  x
catch
  y
end

## child blocks / else

fun do
  x
else
  y
end

## child blocks / rescue

fun do
  x
rescue
  y
end

## child blocks / duplicated

fun do
  x
after
  y
after
  z
end

## child blocks / mixed

fun do
  x
else
  y
after
  z
end

## child blocks / stab clause

fun do
  x
rescue
  y -> y
end

## child blocks / keyword pattern with child block start token

fun do
  x
after
after
  after: 1 -> y
end

## [field names]

fun do
  x -> x
  x when x == [] -> x
end