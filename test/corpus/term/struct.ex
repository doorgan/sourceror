## empty

%User{}

## from keywords

%User{a: 1, b: 2}

## from arrow entries

%User{:a => 1, "b" => 2, c => 3}

## from both arrow entries and keywords

%User{"a" => 1, b: 2, c: 3}

## trailing separator

%User{"a" => 1,}

## update syntax

%User{user | name: "Jane", email: "jane@example.com"}
%User{user | "name" => "Jane"}

## unused struct identifier

%_{}

## matching struct identifier

%name{}

## pinned struct identifier

%^name{}

## with special identifier

%__MODULE__{}
%__MODULE__.Child{}

## with atom

%:"Elixir.Mod"{}

## with call

%fun(){}
%Mod.fun(){}
%fun.(){}