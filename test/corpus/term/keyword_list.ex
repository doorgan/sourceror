## simple literal

[a: 1, a_b@12?: 2, A_B@12!: 3, Mod: 4, __struct__: 5]

## trailing separator

[a: 1,]

## with leading items

[1, {:c, 1}, a: 1, b: 2]

## operator key

[~~~: 1, ==: 2, >: 3]

## special atom key

[...: 1, %{}: 2, {}: 3, %: 4, <<>>: 5, ..//: 6]

## reserved token key

[not: 1, and: 2]
[nil: 1, true: 2]

## quoted key

[
  "key1 ?? !! ' \n": 1,
  'key2 ?? !! " \n': 2
]

## key interpolation

[
  "hey #{name}!": 1,
  'hey #{name}!': 2
]