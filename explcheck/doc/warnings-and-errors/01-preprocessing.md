# Preprocessing
In the preprocessing step, the expl3 analysis tool determines which parts of the input files contain expl3 code. Inline `\TeX`{=tex} comments that disable warnings and errors are also analyzed in this step.

## No standard delimiters {.w label=w100}
An input file contains no delimiters such as `\ExplSyntaxOn`, `\ExplSyntaxOff`, `\ProvidesExplPackage`, `\ProvidesExplClass`, and `\ProvidesExplFile` [@latexteam2024interfaces, Section 2.1]. The analysis tool should assume that the whole input file is in expl3.

 /w100.tex

## Unexpected delimiters {.w label=w101}
An input file contains extraneous `\ExplSyntaxOn` delimiters [@latexteam2024interfaces, Section 2.1] in expl3 parts or extraneous `\ExplSyntaxOff` delimiters in non-expl3 parts.

 /w101.tex

## Expl3 control sequences in non-expl3 parts {.e label=e102}
An input file contains what looks like expl3 control sequences [@latexteam2024interfaces, Section 1.1] in non-expl3 parts.

 /e102.tex

## Line too long {.s label=s103}
Some lines in expl3 parts are longer than 80 characters [@latexteam2024style, Section 2].

 /s103.tex
