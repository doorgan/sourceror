## empty

()

## single expression

(1)

## multiple expressions separated by newline

(
  1
  2
)

## multiple expressions separated by semicolon

(1;2)

## multiple expressions separated by mixed separators

(
  1

  ;

  2
)

## leading semicolon

(;1;2)

## trailing semicolon

(1;2;)

## stab clause / multiple clauses

(x -> x; y -> y
 z -> z)

## stab clause / multiple arguments

(x, y, z -> x)
((x, y, z) -> x)

## stab clause / guard

(x, y when x == y -> 1)
((x, y when x == y -> 1))
((x, y when x == y) -> 1)
(x, y when x, z -> 1)
((x, y when x, z -> 1))
((x, y when x, z) -> 1)