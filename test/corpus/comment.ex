## empty

#

## single line

# single comment

## multiple start symbols

### multiple "#"

## many consecutive lines

# many
# consecutive
1
# lines

## in the same line as regular code

1 # comment

## matches inside a nested structure

[ 1, ## inside a list
  { 2, # and a tuple, too!
    3 }
]

## does not match inside a string

"# string"
"this is #{interpolation}"