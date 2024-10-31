# Preprocessing
In the preprocessing step, the expl3 analysis tool determines which parts of the input files contain expl3 code. Inline `\TeX`{=tex} comments that disable warnings and errors are also analyzed in this step.

## No standard delimiters {.w}
An input file contains no delimiters such as `\ExplSyntaxOn`, `\ExplSyntaxOff`, `\ProvidesExplPackage`, `\ProvidesExplClass`, and `\ProvidesExplFile` [@latexteam2024interfaces, Section 2.1]. The analysis tool should assume that the whole input file is in expl3.

 /../../testfiles/w100.tex

## Unexpected delimiters {.w}
An input file contains extraneous `\ExplSyntaxOn` delimiters [@latexteam2024interfaces, Section 2.1] in expl3 parts or extraneous `\ExplSyntaxOff` delimiters in non-expl3 parts.

``` tex
\input expl3-generic
\ExplSyntaxOff  % warning on this line
\ExplSyntaxOn
\tl_new:N
  \g_example_tl
\tl_gset:Nn
  \g_example_tl
  { Hello,~ }
\ExplSyntaxOn  % warning on this line
\tl_gput_right:Nn
  \g_example_tl
  { world! }
\tl_use:N
  \g_example_tl
```

## Expl3 control sequences in non-expl3 parts {.e}
An input file contains what looks like expl3 control sequences [@latexteam2024interfaces, Section 1.1] in non-expl3 parts.

``` tex
\ProvidesExplFile{example.tex}{2024-04-09}{1.0.0}{An example file}
\tl_new:N
  \g_example_tl
\tl_gset:Nn
  \g_example_tl
  { Hello,~ }
\tl_gput_right:Nn
  \g_example_tl
  { world! }
\ExplSyntaxOff
\tl_use:N  % error on this line
  \g_example_tl  % error on this line
```

## Line too long {.s}
Some lines in expl3 parts are longer than 80 characters [@latexteam2024style, Section 2].
<!-- The maximum line length should be configurable. -->

``` tex
This line is entirely too long. This line is entirely too long. This line is entirely too long.  % warning on this line
```
