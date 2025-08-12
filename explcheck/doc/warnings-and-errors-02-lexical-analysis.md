# Lexical analysis
In the lexical analysis step, the expl3 analysis tool converts the expl3 parts of the input files into a list of `\TeX`{=tex} tokens.

## “Do not use” argument specifiers {.w label=w200}
Some control sequence tokens correspond to functions with `D` (do not use) argument specifiers.

 /w200.tex

The above example has been taken from @latexteam2024interfaces [Chapter 24].

## Unknown argument specifiers {.e label=e201}
Some control sequence tokens correspond to functions with unknown argument specifiers. [@latexteam2024interfaces, Section 1.1]

 /e201.tex

## Deprecated control sequences {.w label=w202}
Some control sequence tokens correspond to deprecated expl3 control sequences from `l3obsolete.txt` [@josephwright2024obsolete].

 /w202.tex

## Removed control sequences {.e label=e203 removed=2025-02-14}
Some control sequence tokens correspond to removed expl3 control sequences from `l3obsolete.txt` [@josephwright2024obsolete].

 /e203.tex

## Missing stylistic whitespaces {.s label=s204}
Some control sequences and curly braces are not surrounded by whitespaces [@latexteam2024programming, Section 6] [@latexteam2024style, Section 3].

 /s204.tex

## Malformed function name {.s label=s205}
Some function have names that are not in the format `\texttt{\textbackslash\meta{module}\_\meta{description}:\meta{arg-spec}}`{=tex} [@latexteam2024programming, Section 3.2].

 /s205-01.tex
 /s205-02.tex
 /s205-03.tex
 /s205-04.tex

This also extends to conditional functions:

 /s205-05.tex
 /s205-06.tex
 /s205-07.tex

## Malformed quark or scan mark name {.s label=s207}
Some expl3 quarks and scan marks have names that do not start with `\q_` and `\s_`, respectively [@latexteam2024programming, Chapter 19].

 /s207-01.tex
 /s207-02.tex
 /s207-03.tex
 /s207-04.tex

## Too many closing braces {.e label=e208}
An expl3 part of the input file contains too many closing braces.

 /e208.tex

## Invalid characters {.e label=e209}
An expl3 part of the input file contains invalid characters.

 /e209.tex
