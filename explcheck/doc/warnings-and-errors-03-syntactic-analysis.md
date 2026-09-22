# Syntactic analysis
In the syntactic analysis step, the expl3 analysis tool converts the list of `\TeX`{=tex} tokens into a tree of function calls.

## Unexpected function call argument {.e label=e300}
A function is called with an unexpected argument.

 /e300-02.tex

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

## Unexpected parameter number {.e label=e304}
A parameter or replacement text contains parameter tokens (`#`) followed by unexpected numbers:

 /e304-01.tex
 /e304-02.tex

## Expanding an unexpandable variable or constant {.t label=t305}
A function with a `V`-type argument is called with a variable or constant that does not support `V`-type expansion [@latexteam2024interfaces, Section 1.1].

 /t305.tex

## LaTeX3 command too recent {.w label=w306 .work-in-progress}
A standard-library LaTeX3 command is used that was introduced after the date specified by the Lua option `latex3_definitions_max_added_date`.

``` tex
\use:c
  { tl_if_regex_match:nnTF }  % warning on this line if
  % latex3_definitions_max_added_date < 2024-12-08
  { foo~bar }
  { foo }
  { bar }
  { baz }
\tl_count:v
  { tl_if_regex_match:nnTF }  % warning on this line if
  % latex3_definitions_max_added_date < 2024-12-08
  { foo~bar }
  { foo }
  { bar }
  { baz }
\str_show:c  % warning on the following line if
  % latex3_definitions_max_added_date < 2020-08-20
  { c_sys_engine_format_str }
\str_show:v  % warning on the following line if
  % latex3_definitions_max_added_date < 2020-08-20
  { c_sys_engine_format_str }
```

This check is a stronger version of <#latex-command-too-recent> and the issue should only be emitted if <#latex-command-too-recent> has not previously been emitted for this function.
