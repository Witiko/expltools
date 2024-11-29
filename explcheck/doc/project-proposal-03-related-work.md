# Related work

In this section, I review the related work in the analysis of `\TeX`{=tex} programs and documents. This related work should be considered in the design of the linter and reused whenever it is appropriate and compatible with the license of the linter.

## Unravel

[The unravel package][11] by Bruno Le Floch analyses of expl3 programs as well as `\TeX`{=tex} programs and documents in general. The package was suggested to me as related work by Joseph Wright in personal correspondence.

Unlike a linter, which performs _static_ analysis by leafing through the code and makes suggestions, unravel is a _debugger_ that is used for _dynamic_ analysis. It allows the user to step through the execution of code while providing extra information about the state of `\TeX`{=tex}. Unravel is written in expl3 and emulates `\TeX`{=tex} primitives using expl3 functions. It has been released under the `\LaTeX`{=tex} Project Public License (LPPL) 1.3c.

While both linters and debuggers are valuable in producing bug-free software, linters prevent bugs by proactively pointing out potential bugs without any user interaction, whereas debuggers are typically used interactively to determine the cause of a bug after it has already manifested.

## Chktex, chklref, cmdtrack, lacheck, match_parens, nag, and tex2tok

The Comprehensive `\TeX`{=tex} Archive Network (CTAN) lists related software projects on the topics of [debuging support][12] and [`\LaTeX`{=tex} quality][13], some of which I list in this section.

[The chktex package][14] by Jens T. Berger Thielemann is a linter for the static analysis of `\LaTeX`{=tex} documents. It has been written in ANSI C and released under the GNU GPL 2.0 license. The types of issues with the input files and how they are reported to the user can be configured to some extent from the command-line and using configuration files to a larger extent. Chktex is extensible and, in addition to the configuration of existing issues, it allows the definition of new types of issues using regular expressions.

[The lacheck package][17] by Kresten Krab Thorup is a linter for the static analysis of `\LaTeX`{=tex} documents. Similarly to chktex, lacheck has been written in ANSI C and released under the GNU GPL 1.0 license. Unlike chktex, lacheck cannot be configured either from the command-line or using configuration files.

[The chklref package][15] by Jérôme Lelong is a linter for the static analysis of `\LaTeX`{=tex} documents. It has been written in Perl and released under the GNU GPL 3.0 license. Unlike chktex, chklref focuses just on the detection of unused labels, which often accumulate over the lifetime of a `\LaTeX`{=tex} document.

[The match_parens package][18] by Wybo Dekker is a linter for the static analysis of expl3 programs as well as `\TeX`{=tex} programs and documents in general. It has been written in Ruby and released under the GNU GPL 1.0 license. Unlike chktex, match_parens focuses just on the detection of mismatched paired punctuation, such as parentheses, braces, brackets, and quotation marks. As such, it can also be used for the static analysis of natural text as well as programs and documents in programming and markup languages that use paired punctuation in its syntax.

[The cmdtrack package][16] by Michael John Downes is a debugger for the dynamic analysis of `\LaTeX`{=tex} documents. It has been written in `\LaTeX`{=tex} and released under the LPPL 1.0 license. It detects unused user-defined commands, which also often accumulate over the lifetime of a `\LaTeX`{=tex} document, and mentions them in the `.log` file produced during the compilation of a `\LaTeX`{=tex} document.

[The nag package][19] by Ulrich Michael Schwarz is a debugger for the dynamic analysis of `\LaTeX`{=tex} documents. Similarly to cmdtrack, nag has also been written in `\LaTeX`{=tex} and released under the LPPL 1.0 license. It detects the use of obsolete `\LaTeX`{=tex} commands, document classes, and packages and mentions them in the `.log` file produced during the compilation of a `\LaTeX`{=tex} document.

[The tex2tok package][20] by Jonathan Fine is a debugger for the dynamic analysis of expl3 programs as well as `\TeX`{=tex} programs and documents in general. It has been written in `\TeX`{=tex} and released under the GNU GPL 2.0 license. It executes a `\TeX`{=tex} file and produces a new `.tok` file with a list of `\TeX`{=tex} tokens in the file. Compared to static analysis, the dynamic analysis ensures correct category codes. However, it requires the execution of the `\TeX`{=tex} file, which may take long or never complete in the presence of bugs in the code.

## Luacheck and flake8

[Luacheck][21] by Peter Melnichenko and [flake8][22] by Tarek Ziade are linters for the static analysis of Lua and Python programs, respectively. They have been written in Lua and Python, respectively, and released under the MIT license. Both tools are widely used and should inform the design of my linter in terms of architecture, configuration, and extensibility.

Similar to chktex, the types of issues with the input files and how they are reported to the user can be configured from the command-line and using configuration files. Additionally, the reporting can also be enabled or disabled in the code of the analyzed program using inline comments.

Unlike luacheck, which is not extensible at the time of writing and only allows the configuration of existing issues, flake8 supports Python extensions that can add support for new types of issues.

## TeXLab and digestif

[TeXLab][23] by Eric and Patrick Förscher and [digestif][24] by Augusto Stoffel are [language servers][6] for the static analysis of `\TeX`{=tex} programs and documents. They have been written in Rust and Lua, respectively, and released under the GNU GPL 3.0 license.  The language servers were suggested to me as related work by Michal Hoftich at TUG 2024.

Whereas `\TeX`{=tex}Lab focuses on `\LaTeX`{=tex} documents, digestif also supports other formats such as `\Hologo{ConTeXt}`{=tex} and GNU Texinfo. Neither `\TeX`{=tex}Lab nor digestif support expl3 code at the time of writing.

In terms of the programming language, license, and scope, digestif seems like the most related work to my linter. However, its GNU GPL 3.0 license is incompatible with the dual license of the linter, which prohibits code reuse.

 [1]: /Expl3-Linter-2
 [2]: /Expl3-Linter-2#license-terms
 [5]: /Expl3-Linter-2.5
 [6]: https://microsoft.github.io/language-server-protocol/
 [11]: https://ctan.org/pkg/unravel
 [12]: https://ctan.org/topic/debug-supp
 [13]: https://ctan.org/topic/latex-qual
 [14]: https://ctan.org/pkg/chktex
 [15]: https://ctan.org/pkg/chklref
 [16]: https://ctan.org/pkg/cmdtrack
 [17]: https://ctan.org/pkg/lacheck
 [18]: https://ctan.org/pkg/match_parens
 [19]: https://ctan.org/pkg/nag
 [20]: https://ctan.org/pkg/tex2tok
 [21]: https://github.com/mpeterv/luacheck
 [22]: https://github.com/pycqa/flake8
 [23]: https://ctan.org/pkg/texlab
 [24]: https://ctan.org/pkg/digestif