## single line

'Hello, 123!'

## multiple lines

'line 1
line 2'

## interpolation

'hey #{name}!'
'hey #{
  name
}!'
'##{name}#'

## nested interpolation

'this is #{'number #{1}'}!'

## escape sequence

'_\'_\n_\t_\r_\e_\\_\1_\x3f_\u0065\u0301_'

## escaped interpolation

'\#{1}'

## heredoc / charlist

'''
text
with 'quotes'
'''

## heredoc / interpolation

'''
hey #{name}!
'''

## heredoc / nested interpolation

'''
this is #{
  '''
  number #{1}
  '''
}!
'''

## heredoc / escaped delimiter

'''
\'''
'''

'''
\'\'\'
'''

## heredoc / escaped interpolation

'''
\#{1}
'''