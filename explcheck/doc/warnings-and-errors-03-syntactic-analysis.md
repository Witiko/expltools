# Syntactic analysis
In the syntactic analysis step, the expl3 analysis tool converts the list of `\TeX`{=tex} tokens into a tree of function calls.

## Unexpected function call argument {.e label=e300}
A function is called with an unexpected argument. Partial applications are detected by analysing closing braces (`}`) and do not produce an error.

 /e300-01.tex
 /e300-02.tex
 /e300-03.tex
