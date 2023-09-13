## empty

%{}

## from keywords

%{a: 1, b: 2}

## from arrow entries

%{:a => 1, "b" => 2, c => 3}

## from both arrow entries and keywords

%{"a" => 1, b: 2, c: 3}

## trailing separator

%{"a" => 1,}

## update syntax

%{user | name: "Jane", email: "jane@example.com"}
%{user | "name" => "Jane"}
