# Flow analysis
In the flow analysis step, the expl3 analysis tool determines compiler-theoretic properties of functions, such as expandability, and variables, such as reaching definitions.

## Functions and conditional functions

### Multiply defined function {.e label=e500}
A function or conditional function is defined multiple times.

 /e500-01.tex
 /e500-02.tex
 /e500-03.tex
 /e500-04.tex
 /e500-05.tex
 /e500-06.tex

<!--

  We can't really report this issue from the `FUNCTION_CALL` edges alone.

  Instead, we will need to report this issue either inside the inner loop
  of reaching definitions whenever we are processing a function definition
  statement or after the outer loop at the end of the function
  `draw_group_wide_dynamic_edges()`.

  We need to take into account the `maybe_redefinition` attribute of
  `FUNCTION_DEFINITION` statements to differentiate between `new` and `set`.

-->

### Multiply defined function variant {.w label=w501}
A function or conditional function variant is defined multiple times.

 /w501-01.tex
 /w501-02.tex
 /w501-03.tex
 /w501-04.tex

<!--

  The same considerations apply as for the previous issue (E500).

-->

### Unused private function {.w label=w502}
A private function or conditional function is defined but unused.

 /w502.tex

<!--

  We can't really report this issue from the `FUNCTION_CALL` edges alone
  either, as is the case for the previous two issues. Furthermore, this
  issue will require a live variable analysis, in addition to the reaching
  definitions analysis. However, since liveness likely won't affect our ability
  to determine reaching definitions, it might make sense to make it into a
  separate substep.

-->

This check is a stronger version of <#unused-private-function> and should only be emitted if <#unused-private-function> has not previously been emitted for this function.

### Unused private function variant {.w label=w503}
A private function or conditional function variant is defined but unused.

 /w503.tex

<!--

  The same considerations apply as for the previous issue (W502).

-->

This check is a stronger version of <#unused-private-function-variant> and should only be emitted if <#unused-private-function-variant> has not previously been emitted for this function variant.

### Function variant for an undefined function {.e label=e504}
A function or conditional function variant is defined before the base function has been defined or after it has been undefined.

 /e504-01.tex
 /e504-02.tex
 /e504-03.tex
 /e504-04.tex
 /e504-05.tex
 /e504-06.tex

<!--

  As with all the previous issues, we can't report this issue from the
  `FUNCTION_CALL` edges alone.

  Instead, we will need to report this issue either inside the inner loop
  of reaching definitions whenever we are processing a function variant
  definition statement or after the outer loop at the end of the function
  `draw_group_wide_dynamic_edges()`.

-->

This check is a stronger version of <#function-variant-for-undefined-function> and should only be emitted if <#function-variant-for-undefined-function> has not previously been emitted for this function variant.

### Calling an undefined function {.e label=e505}
A function or conditional function (variant) is called before it has been defined or after it has been undefined.

 /e505-01.tex
 /e505-02.tex
 /e505-03.tex

<!--

  This is the first issue in this section that we can determine and report this
  issue from the `FUNCTION_CALL` edges alone.

-->

This check is a stronger version of <#calling-undefined-function> and should only be emitted if <#calling-undefined-function> has not previously been emitted for this function.

### Indirect function definition from an undefined function {.e label=e506}
A function or conditional function is indirectly defined from a function that has yet to be defined or after it has been undefined.

 /e506-01.tex
 /e506-02.tex
 /e506-03.tex
 /e506-04.tex

<!--

  The same considerations apply as for the issue E504.

-->

This check is a stronger version of <#indirect-function-definition-from-undefined-function> and should only be emitted if <#indirect-function-definition-from-undefined-function> has not previously been emitted for this function.

### Setting a function before definition {.w label=w507}
A function is set before it has been defined or after it has been undefined.

 /e507-01.tex
 /e507-02.tex

<!--

  The same considerations apply as for the issues E504 and E506.

-->

### Unexpandable or restricted-expandable boolean expression {.e label=e508}
A boolean expression [@latexteam2024interfaces, Section 9.2] is not fully-expandable.

 /e508.tex

<!--

  We can't really report this issue at this moment at all.

  Here's what we'll need to do before we can report this issue:

  First, in the semantic analysis, we'll need to determine in a flow-unaware
  fashion which user-defined functions are definitely not fully-expandable. We
  should be able to achieve this by looking at whether any built-in functions
  within the top segments of the replacement texts of these functions are not
  fully-expandable, likely by parsing l3kernel .dtx files and distilling this
  information in `explcheck-latex3.lua`.

  Incidentally, this should allow us to report a weaker version of this issue
  during the semantic analysis.

  Then, in the flow analysis, we'll need to determine in a flow-aware
  fashion which user-defined functions are definitely not fully-expandable. We
  should be able to achieve this as follows

  1. Functions that were already determined to be definitely not
     fully-expandable during the semantic analysis are considered as such.

  2. Other functions are considered definitely not fully-expandable if any
     user-defined functions they call are definitely not fully-expandable.

  To determine the latter, we should be able to use a "backwards may" data-flow
  analysis, similar to the live variable analysis that we'll need for the previous
  issue W502.

-->

### Expanding an unexpandable function {.e label=e509}
An unexpandable function or conditional function is called within an `x`-type, `e`-type, or `f`-type argument.

 /e509.tex

<!--

  The same considerations apply as for the previous issue (E508).

-->

### Fully-expanding a restricted-expandable function {.e label=e510}
An restricted-expadable function or conditional function is called within an `f`-type argument.

 /e510.tex

<!--

  The same considerations apply as for the previous two issues (E508 and E509).

-->

### Defined an expandable function as protected {.w label=w511}
A fully-expandable function or conditional function is defined using a creator function `\cs_new_protected:*` or `\prg_new_protected_conditional:*`. [@latexteam2024style, Section 4]

 /w511-01.tex
 /w511-02.tex

<!--

  We can't really report this issue at this moment at all, similar to the
  previous issues E508 through E510.

  Here's what we'll need to do before we can report this issue:

  First, in the semantic analysis, we'll need to determine which user-defined
  functions are definitely fully-expandable, ignoring nested function calls:

  1. A function that contains any statements of type `OTHER_TOKENS_COMPLEX`
     might not be fully-expandable.
  
  2. All calls to built-in functions within the top segment of a
     fully-expandable function's replacement text must be fully-expandable.
  
  To determine the latter, we may need to parse l3kernel .dtx files and
  distill this information in `explcheck-latex3.lua`.

  Then, in the flow analysis, we'll need to determine which user-defined
  functions are definitely fully-expandable: A function is definitely
  fully-expandable if all of the following conditions apply:

  1. It is definitely fully-expandable, ignoring nested function calls.
  2. All functions from nested calls are either built-in or user-defined.
  3. All user-defined functions they call are definitely fully-expandable.

  To determine the third condition, we should be able to use a "backwards may"
  data-flow analysis, similar to the live variable analysis that we'll need for
  the previous issue W502, as well as the expandability analysis that we'll
  need for the previous issues E508 through E510.

-->

### Defined an unexpandable function as unprotected {.w label=w512}
An unexpandable or restricted-expandable function or conditional function is defined using a creator function `\cs_new:*` or `\prg_new_conditional:*`. [@latexteam2024style, Section 4]

 /w512-01.tex
 /w512-02.tex

<!--

  The same considerations apply as for the previous issues E508 through E510.

-->

### Conditional function with no return value {.e label=e513}
A conditional functions has no return value.

 /e513-01.tex
 /e513-02.tex

<!--

  We can't really report this issue at this moment at all.

  Here's what we'll need to do before we can report this issue:

  First, in the semantic analysis, we'll need to determine which user-defined
  functions definitely have no return value, ignoring nested function calls:

  1. A function that contains any statements of type `OTHER_TOKENS_COMPLEX`
     might have a return value.
  
  2. A function that contains either `\prg_return_true:` or `\prg_return_false:`
     within the top segment definitely has a return value.

  Then, in the flow analysis, we'll need to determine which user-defined
  functions definitely have no return value: A function definitely has no
  return value if all of the following conditions apply:

  1. It definitely has no return value, ignoring nested function calls.
  2. All functions from nested calls are user-defined.
  3. All user-defined functions they call definitely have no return value.

  To determine the third condition, we should be able to use a "backwards may"
  data-flow analysis, similar to the live variable analysis that we'll need for
  issue W502, as well as the expandability analysis that we'll need for the
  previous issues E508 through E510, and W511 and W512.

-->

### Conditional function with no return value {.e label=e514}
A conditional functions has no return value.

 /e514-01.tex
 /e514-02.tex

<!--

  The same considerations apply as for the previous issue (E513).

-->

### Comparison code with no return value {.e label=e515}
A comparison code [@latexteam2024interfaces, Section 6.1] has no return value.

 /e515-01.tex
 /e515-02.tex

<!--

  The same considerations apply as for the previous two issues (E513 and E514).

  Unlike these issues, comparison codes use `\sort_return_same:` and
  `\sort_return_swapped:` rather than `prg_return_true:` and
  `\prg_return_false:`.

-->

The above example has been taken from @latexteam2024interfaces [Chapter 6].

### Paragraph token in the parameter of a "nopar" function {.e label=e516}
An argument that contains `\par` tokens may reach a function with the "nopar" restriction.

 /e516.tex

<!--

  We can't really report this issue at this moment at all.

  Here's what we'll need to do before we can report this issue:

  First, in the semantic analysis, we'll need to determine which variables
  and constants, user-defined functions, and user-defined function calls
  definitely contain `\par` tokens in their unexpanded values, replacement
  texts, and arguments, respectively.

  Then, in the flow analysis, we'll need to determine which variables
  and constants, user-defined functions, and user-defined function calls
  definitely contain `\par` tokens in their expanded values, replacement texts,
  and unexpanded arguments, respectively, similar to the previous issue E508.

  Finally, still in the flow analysis, we'll need to determine for every
  user-defined function call argument whether it may reach a user-defined
  "nopar" function. To determine this, we should be able to use a "forward may"
  data-flow analysis, similar to the reaching definitions analysis.

-->

## Variables and constants

### Unused variable or constant {.w}
A variable or a constant is declared and perhaps defined but unused.

``` tex
\tl_new:N  % warning on this line
  \g_defined_but_unreachable_tl
\tl_gset:Nn
  \g_defined_but_unreachable_tl
  { foo }
\cs_new:Nn
  \__module_baz:
  {
    \tl_use:N
      \g_defined_but_unreachable_tl
  }
```

This check is a stronger version of <#unused-variable-or-constant> and should only be emitted if <#unused-variable-or-constant> has not previously been emitted for this variable or constant.

### Setting an undeclared variable {.e}
A variable is set before it has been declared.

``` tex
\tl_gset:Nn  % error on this line
  \g_example_tl
  { bar }
\tl_new:N
  \g_example_tl
```

This check is a stronger version of <#setting-undeclared-variable> and should prevent <#setting-undeclared-variable> from being emitted for this variable.

### Using an undeclared variable or constant {.w}
A variable or constant is used before it has been declared.

``` tex
\tl_use:N  % error on this line
  \g_example_tl
\tl_new:N
  \g_example_tl
```

``` tex
\tl_use:N  % error on this line
  \c_example_tl
\tl_const:N
  \c_example_tl
  { foo }
```

This check is a stronger version of <#using-undeclared-variable-or-constant> and should only be emitted if <#using-undeclared-variable-or-constant> has not previously been emitted for this variable or constant.

### Multiply declared variable or constant {.e}
A variable or constant is declared multiple times.

``` tex
\tl_new:N
  \g_example_tl
\tl_new:N  % error on this line
  \g_example_tl
```

``` tex
\tl_const:Nn
  \c_example_tl
  { foo }
\tl_const:Nn  % error on this line
  \c_example_tl
  { bar }
```

## Messages

### Unused message {.w}
A message is defined but unused.

``` tex
\msg_new:nnn  % warning on this line
  { foo }
  { bar }
  { baz }
\cs_new:Nn
  \__module_baz:
  {
    \msg_info:nn
      { foo }
      { bar }
  }
```

This check is a stronger version of <#unused-message> and should only be emitted if <#unused-message> has not previously been emitted for this message.

### Using an undefined message {.e}
A message is used before it has been defined.

``` tex
\msg_info:nn  % error on this line
  { foo }
  { bar }
\msg_new:nnn
  { foo }
  { bar }
  { baz }
```

This check is a stronger version of <#using-undefined-message> and should only be emitted if <#using-undefined-message> has not previously been emitted for this message.

### Incorrect number of arguments supplied to message {.w}
A message was supplied fewer or more arguments than there are parameters in the message text.

``` tex
\msg_new:nnn
  { foo }
  { bar }
  { #1 }
\msg_set:nnn
  { foo }
  { bar }
  { baz }
\msg_info:nnn  % error on this line
  { foo }
  { bar }
  { baz }
```

``` tex
\msg_new:nnn
  { foo }
  { bar }
  { #1 }
\msg_info:nnn
  { foo }
  { bar }
  { baz }
\msg_set:nnn
  { foo }
  { bar }
  { baz }
```

This check is a stronger version of <#incorrect-number-of-arguments-supplied-to-message> and should only be emitted if <#incorrect-number-of-arguments-supplied-to-message> has not previously been emitted for this message.

### Multiply defined message {.e}
A message is defined multiple times.

``` tex
\msg_new:nnn
  { foo }
  { bar }
  { baz }
\msg_new:nnn  % error on this line
  { foo }
  { bar }
  { baz }
```

## Input–output streams
### Using an unopened or closed stream {.e}
A stream is used before it has been opened or after it has been closed.

``` tex
\ior_new:N
  \l_example_ior
\ior_str_get:NN  % error on this line
  \l_example_ior
  \l_tmpa_tl
\ior_open:Nn
  \l_example_ior
  { example }
```

``` tex
\ior_new:N
  \l_example_ior
\ior_open:Nn
  \l_example_ior
  { example }
\ior_close:N
  \l_example_ior
\ior_str_get:NN  % error on this line
  \l_example_ior
  \l_tmpa_tl
```

### Multiply opened stream {.e}
A stream is opened a second time without closing the stream first.

``` tex
\iow_new:N
  \l_example_iow
\iow_open:Nn
  \l_example_iow
  { foo }
\iow_open:Nn  % error on this line
  \l_example_iow
  { bar }
\iow_close:N
  \l_example_iow
```

### Unclosed stream {.w}
A stream is opened but not closed.

``` tex
% file-wide warning
\ior_new:N
  \l_example_ior
\ior_open:Nn
  \l_example_ior
  { example }
```

## Piecewise token list construction
### Building on a regular token list {.t}
A token list variable is used with `\tl_build_*` functions before a function `\tl_build_*begin:N` has been called or after a function `\tl_build_*end:N` has been called.

``` tex
\tl_new:N
  \l_example_tl
\tl_build_put_right:Nn  % error on this line
  \l_example_tl
  { foo }
\tl_build_begin:N
  \l_example_tl
\tl_build_end:N
  \l_example_tl
```

``` tex
\tl_new:N
  \l_example_tl
\tl_build_begin:N
  \l_example_tl
\tl_build_put_right:Nn
  \l_example_tl
  { foo }
\tl_build_end:N
  \l_example_tl
```

``` tex
\tl_new:N
  \l_example_tl
\tl_build_begin:N
  \l_example_tl
\tl_build_end:N
  \l_example_tl
\tl_build_put_right:Nn  % error on this line
  \l_example_tl
  { foo }
```

### Using a semi-built token list {.t}
A token list variable is used where a regular token list is expected after a function `\tl_build_*begin:N` has been called and before a function `\tl_build_*end:N` has been called.

``` tex
\tl_new:N
  \l_example_tl
\tl_use:N
  \l_example_tl
\tl_build_begin:N
  \l_example_tl
\tl_build_end:N
  \l_example_tl
```

``` tex
\tl_new:N
  \l_example_tl
\tl_build_begin:N
  \l_example_tl
\tl_use:N
  \l_example_tl  % error on this line
\tl_build_end:N
  \l_example_tl
```

``` tex
\tl_new:N
  \l_example_tl
\tl_build_begin:N
  \l_example_tl
\tl_build_end:N
  \l_example_tl
\tl_use:N
  \l_example_tl
```

### Multiply started building a token list {.e}
A function `\tl_build_*begin:N` is called on a token list variable a second time without calling a function `\tl_build_*end:N` first.

``` tex
\tl_new:N
  \l_example_tl
\tl_build_begin:N
  \l_example_tl
\tl_build_begin:N  % error on this line
  \l_example_tl
\tl_build_end:N
  \l_example_tl
```

### Unfinished semi-built token list {.w}
A function `\tl_build_*begin:N` is called on a token list variable without calling a function `\tl_build_*end:N` later.

``` tex
% file-wide warning
\tl_new:N
  \l_example_tl
\tl_build_begin:N
  \l_example_tl
```
