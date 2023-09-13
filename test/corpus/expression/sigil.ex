## simple literal

~s(content)
~r{content}
~w[content]
~a<content>
~b"content"
~c'content'
~d|content|
~e/content/

## multiple lines

~s"line 1
line 2"

## interpolation

~s"hey #{name}!"
~r/hey #{
  name
}!/
~w{##{name}#}

## nested interpolation

~s{this is #{~s{number #{1}}}!}

## escape sequence

~s{_\}_\n_\t_\r_\e_\\_\1_\x3f_\u0065\u0301_}

## escaped interpolation

~s/\#{1}/

## upper sigil / no interpolation

~S"hey #{name}!"

## upper sigil / no escape sequence

~S"\n"

## upper sigil / escape terminator

~S"content \" content"
~S{content \} content}
~S/content \/ content/

## heredoc delimiter

~s"""
text
with "quotes"
"""

~s'''
text
with 'quotes'
'''

## modifiers

~r/left|right/i
~r/left|right/iUx
