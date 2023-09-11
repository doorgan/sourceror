## unary

@arg

+arg
-arg
!arg
^arg
not arg
~~~arg

&arg

## binary left associative

a ** b ** c

a * b * c
a / b / c

a + b + c
a - b - c

a ^^^ b ^^^ c

a in b in c
a not in b not in c

a |> b |> c
a <<< b <<< c
a >>> b >>> c
a <<~ b <<~ c
a ~>> b ~>> c
a <~ b <~ c
a ~> b ~> c
a <~> b <~> c
a <|> b <|> c

a < b < c
a > b > c
a <= b <= c
a >= b >= c

a == b == c
a != b != c
a =~ b =~ c
a === b === c
a !== b !== c

a && b && c
a &&& b &&& c
a and b and c

a || b || c
a ||| b ||| c
a or b or c

a <- b <- c
a \\ b \\ c

## binary right associative

a ++ b ++ c
a -- b -- c
a +++ b +++ c
a --- b --- c
a .. b .. c
a <> b <> c

a = b = c

a | b | c

a :: b :: c

a when b when c

## precedence on the same level falls back to associativity

a * b / c
a + b - c
a in b not in c
a <<< b >>> c
a < b > c
a == b != c
a &&& b && c
a ||| b || c
a <- b \\ c

a ++ b -- c

## precedence on different levels

& @ a - b
a -- b + c
a - b ++ c
a = b <<< c

a + b * c - d
a ** b + c ** d

## precedence determined by parentheses

(& a) - b

(a + b) * (c - d)

## "not in" spacing

a not    in b

## "not in" boundary

fun not inARG

## multiline / unary

@
arg

+
arg

-
arg

!
arg

^
arg

not
arg

~~~
arg

&
arg

## multiline / unary over binary

a
+
b

a
-
b

## multiline / right operands

x
not in
[y]

x
not in[y]

:a
++:b

:a++
:b

## multiline / unary over binary (precedence)

x
-
y

x
+
y

## plus minus

x+y
x + y
x+ y

x +y
x +y +z


## nullary range

..

## stepped range

1 .. 2 // 3
1..2//3
0..1//-1

## stepped range / multiline

1..2
// 4

## stepped ranges / blocks

foo do end..bar do end//baz do end
1..2//3

## [field names]

a + b
@a