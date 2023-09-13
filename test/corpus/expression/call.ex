## local call / no arguments

fun()

## local call / arguments in parentheses

fun(a)
fun([1, 2], option: true, other: 5)

## local call / arguments without parentheses

fun a
fun {}
fun [1, 2], option: true, other: 5
fun +: 1

## local call / arguments without parentheses / multiline

fun [1, 2],
  option: true,
  other: 5

## local call / nested with parentheses

outer_fun(inner_fun(a))

## local call / nested without parentheses (right associativity)

outer_fun inner_fun a, b
outer_fun inner_fun do: 1

## local call / precedence with operator

outer_fun 1 + 1
1 + inner_fun 1
outer_fun 1 + inner_fun 1
fun 1, 2 |> other_fun

## local call / treats nonimmediate parentheses as a block argument

fun (x)

## remote call / no arguments

Mod.fun()

## remote call / no arguments without parentheses

Mod.fun

## remote call / arguments in parentheses

Mod.fun(a)
Mod.fun([1, 2], option: true, other: 5)

## remote call / arguments without parentheses

Mod.fun a
Mod.fun [1, 2], option: true, other: 5

## remote call / nested with parentheses

Mod.outer_fun(Mod.inner_fun(a))

## remote call / nested without parentheses (right associativity)

Mod.outer_fun Mod.inner_fun a

## remote call / precedence with operator

Mod.outer_fun 1 + 1
1 + Mod.inner_fun 1
Mod.outer_fun 1 + Mod.inner_fun 1

## remote call / treats nonimmediate parentheses as a block argument

Mod.fun (x)

## remote call / multi-level alias

Mod1.Mod2.Mod3.fun(a)

## remote call / operator

Kernel.+(a, b)

## remote call / quoted function name

Mod."fun"(a)
Mod.'fun'(a)

## remote call / atom literal module

:mod.fun(a)
:"Elixir.Mod".fun(a)

## anonymous call / no arguments

fun.()

## anonymous call / arguments in parentheses

fun.(a)
fun.([1, 2], option: true, other: 5)

## anonymous call / nested with parentheses

outer_fun.(inner_fun.(a))

## mixed call types

Mod.outer_fun mid_fun inner_fun.(a)

## identifier call

mod.fun(a)

## nested identifier call

map.mod.fun(a)

## reserved word call

a.and

## range call

(1..2).step
(1..2//3).step

## multi-expression block call

(
  x
  1..2
).step

## map call

%{}.field

## struct call

%Mod{}.field

## arbitrary term call

1.(1, 2)

## escaped newline call

fun \
a

## keyword list trailing separator

fun(option: true, other: 5,)

## newline before dot

Mod
  .fun(a)

## newline after dot

Mod.
  fun(a)

## access syntax

map[key]
map[:key]

## access syntax / does not allow whitespace

map [key]

## access syntax / precedence with dot call

map.map[:key]
map[:mod].fun

## access syntax / precedence with operators

-x[:key]
@x[:key]
&x[:key]
&1[:key]

## double parenthesised call

fun()()
fun() ()
fun(1)(1)
Mod.fun()()
fun.()()

unquote(name)()

## [field names]

fun()
fun a
Mod.fun a
fun()()
fun.()
map[key]
