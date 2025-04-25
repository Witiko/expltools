# Syntactic analysis
In the syntactic analysis step, the expl3 analysis tool converts the list of `\TeX`{=tex} tokens into a tree of function calls.

## Unexpected function call argument {.e label=e300}
A function is called with an unexpected argument.

 /e300-02.tex
 /e300-03.tex

Partial applications are detected by analysing closing braces (`}`) and do not produce an error:

 /e300-01.tex

## End of expl3 part within function call {.e label=e301}
A function call is cut off by the end of a file or an expl3 part of a file:

 /e301.tex

## Unbraced n-type function call argument {.w label=w302}
An n-type function call argument is unbraced:

 /w302.tex

Depending on the specific function, this may or may not be an error.

## Braced N-type function call argument {.w label=w303}
An N-type function call argument is braced:

 /w303.tex

Depending on the specific function, this may or may not be an error.

# Unexpected parameter number {.e label=e304}
A parameter or replacement text contains parameter tokens (`#`) followed by unexpected numbers:

 /e304-01.tex
 /e304-02.tex
