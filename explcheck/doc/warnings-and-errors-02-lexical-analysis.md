# Lexical analysis
In the lexical analysis step, the expl3 analysis tool converts the expl3 parts of the input files into a list of `\TeX`{=tex} tokens.

## “Weird” and “Do not use” argument specifiers {.w label=w200}
Some control sequence tokens correspond to functions with `w` (weird) or `D` (do not use) argument specifiers.

 /w200.tex

The above example has been taken from @latexteam2024interfaces [Chapter 24].

## Unknown argument specifiers {.e label=e201}
Some control sequence tokens correspond to functions with unknown argument specifiers. [@latexteam2024interfaces, Section 1.1]

 /e201.tex

## Deprecated control sequences {.w label=w202}
Some control sequence tokens correspond to deprecated expl3 control sequences from `l3obsolete.txt` [@josephwright2024obsolete].

 /w202.tex

## Removed control sequences {.e label=e203}
Some control sequence tokens correspond to removed expl3 control sequences from `l3obsolete.txt` [@josephwright2024obsolete].

 /e203.tex

## Missing stylistic whitespaces {.s label=s204}
Some control sequences and curly braces are not surrounded by whitespaces [@latexteam2024programming, Section 6] [@latexteam2024style, Section 3].

 /s204.tex

## Malformed function name {.s label=s205}
Some function have names that are not in the format `\texttt{\textbackslash\meta{module}\_\meta{description}:\meta{arg-spec}}`{=tex} [@latexteam2024programming, Section 3.2].

 /s203-01.tex
 /s203-02.tex
 /s203-03.tex
 /s203-04.tex

## Malformed variable or constant name {.s}
Some expl3 variables and constants have names that are not in the format `\texttt{\textbackslash\meta{scope}\_\meta{module}\_\meta{description}\_\meta{type}}`{=tex} [@latexteam2024programming, Section 3.2], where the `\meta{module}`{=tex} part is optional.

``` tex
\tl_new:Nn
  \g_description_box  % warning on this line
\tl_new:Nn
  \l__description_box  % warning on this line
\tl_const:Nn
  \c_description  % warning on this line
  { foo }
```

``` tex
\tl_new:Nn
  \g_module_description_box
\tl_new:Nn
  \l_module_description_box
\tl_const:Nn
  \c__module_description_box
  { foo }
```

An exception is made for scratch variables [@latexteam2024interfaces, Section 1.1.1]:

``` tex
\tl_use:N
  \l_tmpa_tl
\int_use:N
  \l_tmpb_int
\str_use:N
  \l_tmpa_str
```

## Malformed quark or scan mark name {.s}
Some expl3 quarks and scan marks have names that do not start with `\q_` and `\s_`, respectively [@latexteam2024programming, Chapter 19].

``` tex
\quark_new:N
  \foo_bar  % error on this line
```

``` tex
\quark_new:N
  \q_foo_bar
```

``` tex
\scan_new:N
  \foo_bar  % error on this line
```

``` tex
\scan_new:N
  \s_foo_bar
```

## Too many closing braces {.e label=e208}
An expl3 part of the input file contains too many closing braces.

 /e208.tex

## Invalid characters {.e label=e209}
An expl3 part of the input file contains invalid characters.

 /e209.tex
