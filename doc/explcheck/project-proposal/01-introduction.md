# Introduction

In 2021, I used [the expl3 programming language][7] for the first time in my life. I had already been eyeing expl3 for some time and, when it came to defining a `\LaTeX`{=tex}-specific interface for processing YAML metadata in [version 2.11.0][1] of [the Markdown package for `\TeX`{=tex}][2], I took the plunge.

After two and a half years, approximately 3.5k out of the 5k lines of `\TeX`{=tex} code in [version 3.5.0][3] of the Markdown package are written in expl3. I also developed several consumer products with it, and I have written [three][4] [journal][5] [articles][6] for my local `\TeX`{=tex} users group about it. Needless to say, expl3 has been a blast for me!

In the Markdown package, each change is reviewed by a number of automated static analysis tools (so-called *linters*), which look for programming errors in the code. While these tools don't catch all programming errors, they have proven extremely useful in catching the typos that inevitably start trickling in after 2AM.

Since the Markdown package contains code in different programming languages, we use many different linters such as [`shellcheck`][8] for shell scripts, [`luacheck`][9] for Lua, and [`flake8`][10] and [`pytype`][11] for Python. However, since no linters for expl3 exist, typos are often only caught by regression tests, human reviewers, and sometimes even by our users after a release. Nobody is happy about this.

Earlier this year, I realized that, unlike `\TeX`{=tex}, expl3 has the following two properties that seem to make it well-suited to static analysis:

1. Simple uniform syntax: (Almost) all operations are expressed as function calls. This Lisp-like quality makes is easy to convert well-behaved expl3 programs that only use high-level interfaces into abstract syntax trees. This is a prerequisite for accurate static analysis.
2. Explicit type and scope: Variables and constants are separate from functions. Each variable is either local or global. Variables and constants are explicitly typed. This information makes it easy to detect common programming errors related to the incorrect use of variables.

For the longest time, I wanted to try my hand at building a linter from the ground up. Therefore, I decided to kill two birds with one stone and improve the tooling for expl3 while learning something new along the way by building a linter for expl3.

 [1]: https://github.com/Witiko/markdown/releases/tag/2.11.0
 [2]: https://ctan.org/pkg/markdown
 [3]: https://github.com/Witiko/markdown/releases/tag/3.5.0
 [4]: http://dx.doi.org/10.5300/2022-1-4/35
 [5]: http://dx.doi.org/10.5300/2023-1-2/3
 [6]: http://dx.doi.org/10.5300/2023-3-4/153
 [7]: http://mirrors.ctan.org/macros/latex/required/l3kernel/expl3.pdf
 [8]: https://www.shellcheck.net/
 [9]: https://github.com/mpeterv/luacheck
 [10]: https://pypi.org/project/flake8/
 [11]: https://pypi.org/project/pytype/