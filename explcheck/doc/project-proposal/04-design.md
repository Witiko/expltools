# Design

In this section, I outline the design of the linter and I create a code
repository for the linter.

## Processing steps

As outlined in the requirements, the linter will process input files in a
series of discrete steps, each represented by a single Lua module.

Here are the individual processing steps that should be supported by the linter:

1. Preprocessing: Determine which parts of the input files contain expl3 code.
2. Lexical analysis: Convert expl3 parts of the input files into `\TeX`{=tex} tokens.
3. Syntactic analysis: Convert `\TeX`{=tex} tokens into a tree of function calls.
4. Semantic analysis: Determine the meaning of the different function calls.
5. Flow analysis: Determine additional emergent properties of the code.

## Warnings and errors

As also outlined in the requirements, each processing step should identify
issues with the output and produce either a warning or an error. Furthermore,
the requirements list 16 types of issues that should be recognized by the linter
at a minimum. Lastly, the requirements require that, as a part of the
test-driven development paradigm, all issues identified by a processing step
should have at least one associated test in the code repository of the linter.

In [a document titled "Warnings and errors for the expl3 analysis tool"][6],
I compiled a list of 67 warnings and errors that should be recognized by the
initial version of the linter. For each issue, there is also an example of
expl3 code with and without the issue. These examples can be directly converted
to tests and used during the development of the corresponding processing steps.

## Limitations

Due to the dynamic nature of `\TeX`{=tex}, initial versions of the linter will make some
naïve assumption and simplification during the analysis, such as:

- Assume default expl3 [catcodes][8] everywhere.
- Ignore non-expl3 and third-party code.
- Do not analyze expansion and key–value calls.

As a result, the initial version of the linter may not have a sufficient
understanding of expl3 code to support proper flow analysis. Instead, the
initial version of the linter may need to use pseudo-flow-analysis that would
check for simple cases of the warnings and errors from flow analysis. Future
versions of the linter should improve their code understanding to the point
where proper flow analysis can be performed.

The warnings and errors in this document do not cover the complete expl3
language. The limitations currently include the areas outlined in a section
of [the document with warnings and errors][6] titled "Caveats". Future versions
of the linter should improve the coverage.

## Code repository

I created a repository [`witiko/expltools`][3] titled "Development tools for
expl3 programmers" at GitHub. As outlined in the requirements, I dual-license the code under [GNU GPL 2.0][10] or later and [LPPL 1.3c][11] or later.

Furthermore, I also [registered][7] the expl3 prefix `expltools`, so that it
can be used in the documentation for the linter, in other supporting expl3 code
used in the linter, and also possibly in development tools for expl3
programmers other than the linter.

 [1]: /Expl3-Linter-2
 [2]: /Expl3-Linter-3
 [3]: https://github.com/Witiko/expltools
 [4]: https://github.com/astoff/digestif/blob/7962d25/digestif/Parser.lua
 [5]: https://ctan.org/pkg/digestif
 [6]: https://github.com/Witiko/expltools/releases/download/2024-09-06/warnings-and-errors.pdf
 [7]: https://github.com/latex3/latex3/pull/1556
 [8]: https://en.wikibooks.org/wiki/TeX/catcode
 [9]: /Expl3-Linter-2#license-terms
 [10]: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 [11]: https://www.latex-project.org/lppl/lppl-1-3c/