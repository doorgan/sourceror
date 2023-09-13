## single item

<<>>
<<10>>
<<10.0>>
<<"string">>

## multiple items

<<
  10,
  10.0,
  "string"
>>

## size modifiers

<<10::4>>
<<10::size(4)>>

## multiple modifiers

<<"string"::utf8-big>>
<<"string"::utf16-big>>
<<"string"::utf32-big>>
<<10::32-little-unsigned>>
<<10::integer-signed-big>>
<<10.10::float-signed-native>>

## multiple components with modifiers

<<10::8-native, "string", 3.14::float, a::8, b::binary-size(known_size)>>

## spacing

<<
  10 :: 8-native,
  b :: binary - size(known_size)
>>

## trailing separator

<<1,>>