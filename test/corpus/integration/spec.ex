## without type parentheses

@spec fun(atom, integer, keyword) :: string

## with type parentheses

@spec fun(atom(), integer(), keyword()) :: string()

## with literals

@spec fun(%{key: atom}) :: {:ok, atom} | {:error, binary}

## with function reference

@spec fun((-> atom), (atom -> integer)) :: integer

## with remote type

@spec fun(Keyword.t()) :: String.t()

## with type guard

@spec fun(arg1, arg2) :: {arg1, arg2} when arg1: atom, arg2: integer

## with named arguments

@spec days_since_epoch(year :: integer, month :: integer, day :: integer) :: integer

## nonempty list

@spec fun() :: [integer, ...]
