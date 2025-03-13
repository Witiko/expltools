# Syntactic analysis
In the syntactic analysis step, the expl3 analysis tool converts the list of `\TeX`{=tex} tokens into a tree of function calls.

## Unexpected function call argument {.e label=e300}
A function is called with an unexpected argument.

 /e300-02.tex
 /e300-03.tex
 /e300-04.tex

Partial applications are detected by analysing closing braces (`}`) and do not produce an error:

 /e300-01.tex

## End of expl3 part within function call {.e label=e301}
A function call is cut off by the end of a file or an expl3 part of a file:

 /e301.tex
