# Syntactic analysis
In the syntactic analysis step, the expl3 analysis tool converts the list of `\TeX`{=tex} tokens into a tree of function calls.

## Unexpected function call argument {.e}
A function is called with an unexpected argument. Partial applications are detected by analysing closing braces (`}`) and do not produce an error.

``` tex
\cs_new:Nn
  \example_foo:n
  { foo~#1 }
\cs_new:Nn
  \example_bar:
  { \example_foo:n }
\cs_new:Nn
  \example_baz:
  {
    \example_bar:
      { bar }
  }
```

``` tex
\cs_new:Nn
  { unexpected }  % error on this line
  \l_tmpa_tl  % error on this line
```
