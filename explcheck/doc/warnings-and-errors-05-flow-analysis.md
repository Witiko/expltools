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

### Calling an undefined function {.e}
A function or conditional function (variant) is called before it has been defined or after it has been undefined.

``` tex
\module_foo:  % error on this line
\cs_new:Nn
  \module_foo:
  { bar }
```

``` tex
\cs_new:Nn
  \module_foo:
  { bar }
\cs_undefine:N
  \module_foo:
\module_foo:  % error on this line
```

``` tex
\cs_new:Nn
  \module_foo:n
  { bar~#1 }
\tl_set:Nn
  \l_tmpa_tl
  { baz }
\module_foo:V  % error on this line
  \l_tmpa_tl
\cs_generate_variant:Nn
  \module_foo:n
  { V }
```

This check is a stronger version of <#calling-undefined-function> and should only be emitted if <#calling-undefined-function> has not previously been emitted for this function.

### Indirect function definition from an undefined function {.e}
A function or conditional function is indirectly defined from a function that has yet to be defined or after it has been undefined.

``` tex
\cs_new:Nn
  \module_foo:n
  { bar~#1 }
\cs_new_eq:NN  % error on this line
  \module_baz:n
  \module_bar:n
\cs_new_eq:NN
  \module_bar:n
  \module_foo:n
\module_baz:n
  { foo }
```

``` tex
\cs_new:Nn
  \module_foo:n
  { bar~#1 }
\cs_new_eq:NN
  \module_bar:n
  \module_foo:n
\cs_undefine:N
  \module_bar:n
\cs_new_eq:NN  % error on this line
  \module_baz:n
  \module_bar:n
\module_baz:n
  { foo }
```

``` tex
\prg_new_conditional:Nnn
  \module_foo:n
  { p, T, F, TF }
  { \prg_return_true: }
\cs_new_eq:NN  % error on this line
  \module_baz:nTF
  \module_bar:nTF
\cs_new_eq:NN
  \module_bar:nTF
  \module_foo:nTF
\module_baz:nTF
  { foo }
  { bar }
  { baz }
```

``` tex
\prg_new_conditional:Nnn
  \module_foo:n
  { p, T, F, TF }
  { \prg_return_true: }
\cs_new_eq:NN
  \module_bar:nTF
  \module_foo:nTF
\cs_undefine:N
  \module_bar:nTF
\cs_new_eq:NN  % error on this line
  \module_baz:nTF
  \module_bar:nTF
\module_baz:nTF
  { foo }
  { bar }
  { baz }
```

This check is a stronger version of <#indirect-function-definition-from-undefined-function> and should only be emitted if <#indirect-function-definition-from-undefined-function> has not previously been emitted for this function.

### Setting a function before definition {.w}
A function is set before it has been defined or after it has been undefined.

``` tex
\cs_gset:N  % warning on this line
  \module_foo:
  { foo }
\cs_new:Nn
  \module_foo:
  { bar }
```

``` tex
\cs_new:Nn
  \module_foo:
  { bar }
\cs_undefine:N
  \module_foo:
\cs_gset:N  % warning on this line
  \module_foo:
  { foo }
```

### Unexpandable or restricted-expandable boolean expression {.e}
A boolean expression [@latexteam2024interfaces, Section 9.2] is not fully-expandable.

``` tex
\cs_new_protected:N
  \example_unexpandable:
  {
    \tl_set:Nn
      \l_tmpa_tl
      { bar }
    \c_true_bool
  }
\cs_new:N
  \example_restricted_expandable:
  {
    \bool_do_while:Nn
      \c_false_bool
      { }
    \c_true_bool
  }
\cs_new_protected:N
  \example_expandable:
  { \c_true_bool }
\bool_set:Nn
  \l_tmpa_bool
  { \example_unexpandable: }  % error on this line
\bool_set:Nn
  \l_tmpa_bool
  { \example_restricted_expandable: }  % error on this line
\bool_set:Nn
  \l_tmpa_bool
  { \example_expandable: }
```

### Expanding an unexpandable function {.e}
An unexpandable function or conditional function is called within an `x`-type, `e`-type, or `f`-type argument.

``` tex
\cs_new_protected:N
  \example_unexpandable:
  {
    \tl_set:Nn
      \l_tmpa_tl
      { bar }
  }
\cs_new:N
  \module_foo:n
  { #1 }
\cs_generate_variant:Nn
  \module_foo:n
  { x, e, f }
\module_foo:n
  { \example_unexpandable: }
\module_foo:x
  { \example_unexpandable: }  % error on this line
\module_foo:e
  { \example_unexpandable: }  % error on this line
\module_foo:f
  { \example_unexpandable: }  % error on this line
```

### Fully-expanding a restricted-expandable function {.e}
An restricted-expadable function or conditional function is called within an `f`-type argument.

``` tex
\cs_new:N
  \example_restricted_expandable:
  {
    \int_to_roman:n
      { 1 + 2 }
  }
\cs_new:N
  \module_foo:n
  { #1 }
\cs_generate_variant:Nn
  \module_foo:n
  { x, e, f }
\module_foo:n
  { \example_restricted_expandable: }
\module_foo:x
  { \example_restricted_expandable: }
\module_foo:e
  { \example_restricted_expandable: }
\module_foo:f
  { \example_restricted_expandable: }  % error on this line
```

### Defined an expandable function as protected {.w}
A fully expandable function or conditional function is defined using a creator function `\cs_new_protected:*` or `\prg_new_protected_conditional:*`. [@latexteam2024style, Section 4]

``` tex
\cs_new_protected:Nn  % warning on this line
  \example_expandable:
  { foo }
```

``` tex
\prg_new_protected_conditional:Nnn  % warning on this line
  \example_expandable:
  { T, F, TF }
  { \prg_return_true: }
```

### Defined an unexpandable function as unprotected {.w}
An unexpandable or restricted-expandable function or conditional function is defined using a creator function `\cs_new:*` or `\prg_new_conditional:*`. [@latexteam2024style, Section 4]

``` tex
\cs_new:Nn  % warning on this line
  \example_unexpandable:
  {
    \tl_set:Nn
      \l_tmpa_tl
      { bar }
  }
```

``` tex
\prg_new_conditional:Nnn  % warning on this line
  \example_unexpandable:
  { p, T, F, TF }
  {
    \tl_set:Nn
      \l_tmpa_tl
      { bar }
    \prg_return_true:
  }
```

### Conditional function with no return value {.e}
A conditional functions has no return value.

``` tex
\prg_new_conditional:Nnn  % error on this line
  \example_no_return_value:
  { p, T, F, TF }
  { foo }
```

``` tex
\prg_new_conditional:Nnn
  \example_has_return_value:
  { p, T, F, TF }
  { \example_foo: }
\cs_new:Nn
  \example_foo:
  { \prg_return_true: }
```

### Comparison code with no return value {.e}
A comparison code [@latexteam2024interfaces, Section 6.1] has no return value.

``` tex
\clist_set:Nn
  \l_foo_clist
  { 3 , 01 , -2 , 5 , +1 }
\clist_sort:Nn  % error on this line
  \l_foo_clist
  { foo }
```

``` tex
\clist_set:Nn
  \l_foo_clist
  { 3 , 01 , -2 , 5 , +1 }
\clist_sort:Nn
  \l_foo_clist
  { \example_foo: }
\cs_new:Nn
  \example_foo:
  {
    \int_compare:nNnTF { #1 } > { #2 }
      { \sort_return_swapped: }
      { \sort_return_same: }
  }
```

The above example has been taken from @latexteam2024interfaces [Chapter 6].

### Paragraph token in the parameter of a "nopar" function {.e}
An argument that contains `\par` tokens may reach a function with the "nopar" restriction.

``` tex
\cs_new_nopar:Nn
  \example_foo:n
  { #1 }
\cs_new:nn
  \example_bar:n
  {
    \example_foo:n
      { #1 }
  }
\example_bar:n
  {
    foo
    \par  % error on this line
    bar
  }
```

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
