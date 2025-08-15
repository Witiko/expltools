# Semantic analysis
In the semantic analysis step, the expl3 analysis tool determines the meaning of the different function calls.

## Functions and conditional functions

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

Higher-order variants can be created from existing variants as long as only `n` and `N` arguments are changed to other types:

 /t403-02.tex

### Protected predicate function {.e label=e404}
A protected predicate function is defined.

 /e404.tex

### Function variant for an undefined function {.e label=e405 #function-variant-for-undefined-function}
A function or conditional function variant is defined for an undefined function.

 /e405-01.tex
 /e405-02.tex

### Calling an undefined function {.e label=e408 #calling-undefined-function}
A function or conditional function (variant) is called but undefined.

 /e408-01.tex
 /e408-02.tex
 /e408-03.tex

### Function variant of deprecated type {.w label=w410}
A function or conditional function variant is generated from a deprecated argument type [@latexteam2024interfaces, Section 5.2, documentation of function `\cs_generate_variant:Nn`].

 /w410.tex

### Indirect function definition from an undefined function {.e label=e411 #indirect-function-definition-from-undefined-function}
A function or conditional function is indirectly defined from an undefined function.

 /e411-01.tex
 /e411-02.tex
 /e411-03.tex
 /e411-04.tex

### Malformed function name {.s label=s412}
Some function have names that are not in the format `\texttt{\textbackslash\meta{module}\_\meta{description}:\meta{arg-spec}}`{=tex} [@latexteam2024programming, Section 3.2].

 /s412-01.tex
 /s412-02.tex
 /s412-03.tex
 /s412-04.tex

This also extends to conditional functions:

 /s412-05.tex
 /s412-06.tex
 /s412-07.tex

## Variables and constants

### Malformed variable or constant name {.s label=s413}
Some expl3 variables and constants have names that are not in the format `\texttt{\textbackslash\meta{scope}\_\meta{module}\_\meta{description}\_\meta{type}}`{=tex} [@latexteam2024programming, Section 3.2], where the `\meta{module}`{=tex} part is optional.

 /s413-01.tex
 /s413-02.tex
 /s413-03.tex

### Malformed quark or scan mark name {.s label=s414}
Some expl3 quarks and scan marks have names that do not start with `\q_` and `\s_`, respectively [@latexteam2024programming, Chapter 19].

 /s414-01.tex
 /s414-02.tex
 /s414-03.tex
 /s414-04.tex

### Unused variable or constant {.w label=w415 #unused-variable-or-constant}
A variable or a constant is declared and perhaps defined but unused.

 /w415-01.tex
 /w415-02.tex
 /w415-03.tex
 /w415-04.tex
 /w415-05.tex

### Setting an undeclared variable {.w label=w416 #setting-undeclared-variable}
An undeclared variable is set.

 /w416.tex

### Setting a variable as a constant {.e label=e417}
A variable is set as though it were a constant.

 /e417.tex

### Setting a constant {.e label=e418}
A constant is set.

 /e418.tex

### Using an undeclared variable or constant {.w label=w419 #using-undeclared-variable-or-constant}
A variable or constant is used but undeclared or undefined.

 /w419-01.tex
 /w419-02.tex
 /w419-03.tex
 /w419-04.tex
 /w419-05.tex

### Locally setting a global variable {.e label=e420}
A global variable is locally set.

 /e420.tex

### Globally setting a local variable {.e label=e421}
A local variable is globally set.

 /e421.tex

### Using a variable of an incompatible type {.t}
A variable of one type is used where a variable of a different type should be used.

``` tex
\tl_new:N
  \l_example_str  % error on this line
```

``` tex
\tl_new:N
  \l_example_tl
\tl_count:N
  \l_example_tl
\str_count:N
  \l_example_tl
\seq_count:N
  \l_example_tl  % error on this line
\clist_count:N
  \l_example_tl  % error on this line
\prop_count:N
  \l_example_tl  % error on this line
\intarray_count:N
  \l_example_tl  % error on this line
\fparray_count:N
  \l_example_tl  % error on this line
```

``` tex
\str_new:N
  \l_example_str
\tl_count:N
  \l_example_str
\str_count:N
  \l_example_str
\seq_count:N
  \l_example_str  % error on this line
\clist_count:N
  \l_example_str  % error on this line
\prop_count:N
  \l_example_str  % error on this line
\intarray_count:N
  \l_example_str  % error on this line
\fparray_count:N
  \l_example_str  % error on this line
```

``` tex
\int_new:N
  \l_example_int
\tl_count:N
  \l_example_int  % error on this line
\str_count:N
  \l_example_int  % error on this line
\seq_count:N
  \l_example_int  % error on this line
\clist_count:N
  \l_example_int  % error on this line
\prop_count:N
  \l_example_int  % error on this line
\intarray_count:N
  \l_example_int  % error on this line
\fparray_count:N
  \l_example_int  % error on this line
```

``` tex
\seq_new:N
  \l_example_seq
\tl_count:N
  \l_example_seq  % error on this line
\str_count:N
  \l_example_seq  % error on this line
\seq_count:N
  \l_example_seq
\clist_count:N
  \l_example_seq  % error on this line
\prop_count:N
  \l_example_seq  % error on this line
\intarray_count:N
  \l_example_seq  % error on this line
\fparray_count:N
  \l_example_seq  % error on this line
```

``` tex
\clist_new:N
  \l_example_clist
\tl_count:N
  \l_example_clist  % error on this line
\str_count:N
  \l_example_clist  % error on this line
\seq_count:N
  \l_example_clist  % error on this line
\clist_count:N
  \l_example_clist
\prop_count:N
  \l_example_clist  % error on this line
\intarray_count:N
  \l_example_clist  % error on this line
\fparray_count:N
  \l_example_clist  % error on this line
```

``` tex
\clist_new:N
  \l_example_prop
\tl_count:N
  \l_example_prop  % error on this line
\str_count:N
  \l_example_prop  % error on this line
\seq_count:N
  \l_example_prop  % error on this line
\clist_count:N
  \l_example_prop  % error on this line
\prop_count:N
  \l_example_prop
\intarray_count:N
  \l_example_prop  % error on this line
\fparray_count:N
  \l_example_prop  % error on this line
```

``` tex
\intarray_new:Nn
  \g_example_intarray
  { 5 }
\tl_count:N
  \g_example_intarray  % error on this line
\str_count:N
  \g_example_intarray  % error on this line
\seq_count:N
  \g_example_intarray  % error on this line
\clist_count:N
  \g_example_intarray  % error on this line
\prop_count:N
  \g_example_intarray  % error on this line
\intarray_count:N
  \g_example_intarray
\fparray_count:N
  \g_example_intarray  % error on this line
```

``` tex
\fparray_new:Nn
  \g_example_fparray
  { 5 }
\tl_count:N
  \g_example_fparray  % error on this line
\str_count:N
  \g_example_fparray  % error on this line
\seq_count:N
  \g_example_fparray  % error on this line
\clist_count:N
  \g_example_fparray  % error on this line
\prop_count:N
  \g_example_fparray  % error on this line
\intarray_count:N
  \g_example_fparray  % error on this line
\fparray_count:N
  \g_example_fparray
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

### Too few arguments supplied to message {.e #too-few-arguments-supplied-to-message}
A message was supplied fewer arguments than there are parameters in the message text.

``` tex
\msg_new:nnn
  { foo }
  { bar }
  { #1~#2 }
\msg_info:nn  % error on this line
  { foo }
  { bar }
\msg_info:nnn  % error on this line
  { foo }
  { bar }
  { baz }
\msg_info:nnnn
  { foo }
  { bar }
  { baz }
  { baz }
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
