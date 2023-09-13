## def / no arguments

def fun() do
end

## def / no arguments without parentheses

def fun do
end

## def / one argument

def fun(x) do
  x
end

## def / one argument without parentheses

def fun x do
  x
end

## def / many arguments

def fun(x, y) do
  x + y
end

## def / many arguments without parentheses

def fun x, y do
  x + y
end

## def / default arguments

def fun x, y \\ 1 do
  x + y
end

def fun(x, y \\ 1) do
  x + y
end

## def / keyword do block

def fun(), do: 1
def fun(x), do: x

## def / pattern matching

def fun([{x, y} | tail]) do
  x + y
end

## def / with guard

def fun(x) when x == 1 do
  x
end

## def / with guard / multiple guards

def fun(x) when x > 10 when x < 5 do
  x
end

## defp

defp fun(x) do
  x
end

## defmacro

defmacro fun(x) do
  quote do
    [unquote(x)]
  end
end

## defguard

defguard is_even(term) when is_integer(term) and rem(term, 2) == 0

## def in macro

def unquote(name)(unquote_splicing(args)) do
  unquote(compiled)
end