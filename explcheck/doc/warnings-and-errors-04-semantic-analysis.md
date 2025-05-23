# Semantic analysis
In the semantic analysis step, the expl3 analysis tool determines the meaning of the different function calls.

## Functions and conditional functions

### Expanding an unexpandable variable or constant {.t}
A function with a `V`-type argument is called with a variable or constant that does not support `V`-type expansion [@latexteam2024interfaces, Section 1.1].

``` tex
\cs_new:Nn
  \module_foo:n
  { #1 }
\cs_generate_variant:Nn
  \module_foo:n
  { V }
\module_foo:V  % error on this line
  \c_false_bool
```

### Unused private function {.w label=w401 #unused-private-function}
A private function or conditional function is defined but unused.

 /w401-01.tex
 /w401-02.tex

### Unused private function variant {.w label=w402 #unused-private-function-variant}
A private function or conditional function variant is defined but unused.

 /w402-01.tex
 /w402-02.tex

### Function variant of incompatible type {.t label=t403}
A function or conditional function variant is generated from an incompatible argument type [@latexteam2024interfaces, Section 5.2, documentation of function `\cs_generate_variant:Nn`].

 /t403-01.tex

Deprecated variants, such as `N` or `c` variants of an `n` parent, are not included in this issue. Instead, they produce <#deprecated-variant>.

Higher-order variants can be created from existing variants as long as only `n` and `N` arguments are changed to other types:

 /t403-02.tex

### Protected predicate function {.e label=e404}
A protected predicate function is defined.

 /e404.tex

### Function variant for an undefined function {.e label=e405}
A variant is defined for an undefined function.

 /e405-01.tex
 /e405-02.tex

### Multiply defined function {.e}
TODO

### Multiply defined function variant {.w label=w407}
A function or conditional function variant is defined multiple times.

 /w407-01.tex
 /w407-02.tex

### Calling an undefined function {.e #calling-undefined-function}
A function is used but undefined.

``` tex
\module_foo:  % error on this line
```

### Calling an undefined function variant {.e #calling-undefined-function-variant}
A function or conditional function variant is used but undefined.

``` tex
\cs_new:Nn
  \module_foo:n
  { bar~#1 }
\tl_set:Nn
  \l_tmpa_tl
  { baz }
\module_foo:V  % error on this line
  \l_tmpa_tl
```

``` tex
\prg_new_conditional:Nnn
  \module_foo:n
  { p, T, F, TF }
  { \prg_return_true: }
\prg_generate_conditional_variant:Nnn
  \module_foo:n
  { TF }
  { V }
\module_foo:VTF  % error on this line
  \l_tmpa_tl
  { foo }
  { bar }
```

### Function variant of deprecated type {.w label=w410 #deprecated-variant}
A function or conditional function variant is generated from a deprecated argument type [@latexteam2024interfaces, Section 5.2, documentation of function `\cs_generate_variant:Nn`].

 /w410.tex

## Variables and constants

### Unused variable or constant {.w #unused-variable-or-constant}
A variable or a constant is declared and perhaps defined but unused.

``` tex
\tl_new:N  % warning on this line
  \g_declared_but_undefined_tl
```

``` tex
\tl_new:N  % warning on this line
  \g_defined_but_unused_tl
\tl_gset:Nn
  \g_defined_but_unused_tl
  { foo }
```

``` tex
\tl_new:N
  \g_defined_but_unused_tl
\tl_gset:Nn
  \g_defined_but_unused_tl
  { foo }
\tl_use:N
  \g_defined_but_unused_tl
```

``` tex
\tl_const:Nn  % warning on this line
  \c_defined_but_unused_tl
  { foo }
```

``` tex
\tl_const:Nn
  \c_defined_but_unused_tl
  { foo }
\tl_use:N
  \c_defined_but_unused_tl
```

### Setting an undeclared variable {.w #setting-undeclared-variable}
An undeclared variable is set.

``` tex
\tl_gset:Nn  % warning on this line
  \g_example_tl
  { bar }
```

### Setting a constant {.e}
A constant is set.

``` tex
\tl_gset:Nn  % error on this line
  \c_example_tl
  { bar }
```

### Using a token list variable or constant without an accessor {.w}
A token list variable or constant is used without an accessor function.

``` tex
\tl_set:Nn
  \l_tmpa_tl
  { world }
Hello,~\l_tmpa_tl!  % warning on this line
Hello,~\tl_use:N \l_tmpa_tl !
```

This also applies to subtypes of token lists such as strings
and comma-lists:

``` tex
\str_set:Nn
  \l_tmpa_str
  { world }
Hello,~\l_tmpa_str!  % warning on this line
Hello,~\str_use:N \l_tmpa_str !
```

``` tex
\clist_set:Nn
  \l_tmpa_clist
  { world }
Hello,~\l_tmpa_clist!  % warning on this line
Hello,~\clist_use:Nn \l_tmpa_clist { and } !
```

### Using non-token-list variable or constant without an accessor {.e #using-variables-without-accessors}
A non-token-list variable or constant is used without an accessor function.

``` tex
Hello,~\l_tmpa_seq!  % error on this line
Hello,~\seq_use:Nn \l_tmpa_seq { and } !
```

Note that boolean and integer variables may be used without accessor functions in boolean and integer expressions, respectively. Therefore, we may want to initially exclude them from this check to prevent false positives.

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

### Using an undefined variable or constant {.e #using-undefined-variable-or-constant}
A variable or constant is used but undeclared or undefined.

``` tex
\tl_use:N  % error on this line
  \g_undeclared_tl
```

``` tex
\tl_new:N
  \g_declared_but_undefined_tl
\tl_use:N  % error on this line
  \g_declared_but_undefined_tl
```

``` tex
\tl_new:N
  \g_defined_tl
\tl_gset:Nn
  \g_defined_tl
  { foo }
\tl_use:N
  \g_defined_tl
```

``` tex
\tl_use:N  % error on this line
  \c_undefined_tl
```

``` tex
\tl_const:Nn
  \c_defined_tl
  { foo }
\tl_use:N
  \c_defined_tl
```

### Locally setting a global variable {.e}
A global variable is locally set.

``` tex
\tl_new:N
  \g_example_tl
\tl_set:Nn  % error on this line
  \g_example_tl
  { foo }
```

### Globally setting a local variable {.e}
A local variable is globally set.

``` tex
\tl_new:N
  \l_example_tl
\tl_gset:Nn  % error on this line
  \l_example_tl
  { foo }
```

### Using a variable of an incompatible type {.t}
A variable of one type is used where a variable of a different type should be used.

``` tex
\tl_new:N
  \l_example_str  % error on this line
```

``` tex
\ior_new:N
  \l_example_ior
\iow_open:Nn
  \l_example_ior  % error on this line
  { example }
```

``` tex
\clist_new:N
  \l_example_clist
\tl_set:Nn
  \l_tmpa_tl
  { foo }
\clist_set_eq:NN
  \l_example_clist
  \l_tmpa_tl  % error on this line
```

``` tex
\tl_set:Nn
  \l_tmpa_tl
  { foo }
\seq_set_from_clist:NN
  \l_tmpa_seq
  \l_tmpa_tl  % error on this line
```

``` tex
\tl_set:Nn
  \l_tmpa_tl
  { foo }
\regex_set:Nn
  \l_tmpa_regex
  { foo }
\int_set:Nn
  \l_tmpa_int
  { 1 + 2 }
\regex_show:N
  \l_tmpa_tl
\regex_show:N
  \l_tmpa_regex
\regex_show:N
  \l_tmpa_int  % error on this line
```

``` tex
\tl_set:Nn
  \l_tmpa_tl
  { foo }
\int_set_eq:NN
  \l_tmpa_int
  \l_tmpa_tl  % error on this line
```

## Messages

### Unused message {.w #unused-message}
A message is defined but unused.

``` tex
\msg_new:nnn  % warning on this line
  { foo }
  { bar }
  { baz }
```

``` tex
\msg_new:nnn
  { bar }
  { bar }
  { baz }
\msg_info:nn
  { bar }
  { bar }
```

### Setting an undefined message {.w #setting-undefined-message}
A message is set but undefined.

``` tex
\msg_set:nnn  % error on this line
  { foo }
  { bar }
  { baz }
```

``` tex
\msg_new:nnn
  { foo }
  { bar }
  { baz }
\msg_set:nnn
  { foo }
  { bar }
  { baz }
```

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

### Using an undefined message {.e #using-undefined-message}
A message is used but undefined.

``` tex
\msg_info:nn
  { foo }
  { bar }
```

### Incorrect parameters in message text {.e #invalid-parameters-in-message-text}
Parameter tokens other than `#1`, `#2`, `#3`, and `#4` are specified in a message text.

``` tex
\msg_new:nnn
  { foo }
  { bar }
  { #5 }  % error on this line
```

``` tex
\msg_new:nnnn
  { foo }
  { bar }
  { #4 }
  { #5 }  % error on this line
```

## Sorting
### Comparison conditional without signature `:nnTF` {.e}
A sorting function is called with a conditional that has a signature different than `:nnTF` [@latexteam2024interfaces, Section 15.5.4].

``` tex
\cs_new:Nn
  \example_foo:
  { \prg_return_true: }
\tl_sort:nN
  { { foo } { bar } }
  \example_foo:TF
```
