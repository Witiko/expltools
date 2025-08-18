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

### Using a variable of an incompatible type {.t label=t422}
A variable of one type is used where a variable of a different type should be used.

 /t422-01.tex
 /t422-02.tex
 /t422-03.tex
 /t422-04.tex
 /t422-05.tex
 /t422-06.tex
 /t422-07.tex
 /t422-08.tex
 /t422-09.tex
 /t422-10.tex
 /t422-11.tex
 /t422-12.tex
 /t422-13.tex
 /t422-14.tex
 /t422-15.tex
 /t422-16.tex
 /t422-17.tex
 /t422-18.tex

## Messages

### Unused message {.w label=w423 #unused-message}
A message is defined but unused.

 /w423-01.tex
 /w423-02.tex

### Using an undefined message {.e label=e424 #using-undefined-message}
A message is used but undefined.

 /e424.tex

### Incorrect parameters in message text {.e label=e425 #invalid-parameters-in-message-text}
Parameter tokens other than `#1`, `#2`, `#3`, and `#4` are specified in a message text.

 /e425-01.tex
 /e425-02.tex
 /e425-03.tex

### Incorrect number of arguments supplied to message {.w #incorrect-number-of-arguments-supplied-to-message}
A message was supplied fewer or more arguments than there are parameters in the message text.

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
  { foo }
\msg_info:nnnn
  { foo }
  { bar }
  { foo }
  { bar }
\msg_info:nnnn  % error on this line
  { foo }
  { bar }
  { foo }
  { bar }
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
