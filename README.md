# Expltools: Development tools for expl3 programmers

This repository contains the code and documentation of an expl3 static analysis tool `explcheck` outlined in the following devlog posts:

1. [Introduction][1]
2. [Requirements][2]
3. [Related work][3]
4. [Design][4]

On September 6, 2024, the tool has been [accepted for funding][5] by [the TeX Development Fund][6].
The full text of the project proposal, which summarizes devlog posts 1–4 is available [here][7].

These devlog posts chronicle the latest updates and progress in the ongoing development of the tool:

5. [Frank Mittelbach in Brno, first public release of explcheck, and expl3 usage statistics][8] from Dec 5, 2024
6. [A flurry of releases, CSTUG talk, and what's next][9] from December 19, 2024
7. [Lexical analysis and a public website listing issues in current TeX Live][12] from February 24, 2025

In the future, this repository may also contain the code of other useful development tools for expl3 programmers, such as a command-line utility similar to `grep` that will ignore whitespaces and newlines as well as other tools.

 [1]: https://witiko.github.io/Expl3-Linter-1/
 [2]: https://witiko.github.io/Expl3-Linter-2/
 [3]: https://witiko.github.io/Expl3-Linter-3/
 [4]: https://witiko.github.io/Expl3-Linter-4/
 [5]: https://tug.org/tc/devfund/grants.html
 [6]: https://tug.org/tc/devfund/application.html
 [7]: https://tug.org/tc/devfund/documents/2024-09-expltools.pdf
 [8]: https://witiko.github.io/Expl3-Linter-5/
 [9]: https://witiko.github.io/Expl3-Linter-6/
 [10]: https://github.com/witiko/expltools/releases/download/latest/warnings-and-errors.pdf
 [11]: https://koppor.github.io/explcheck-issues/
 [12]: https://witiko.github.io/Expl3-Linter-7/

## Usage

You may browse the results of the tool on all packages in current TeX Live [here][11].

You may also use the tool from the command line as follows:

```
$ explcheck [options] [.tex, .cls, and .sty files]
```

Furthermore, you may also use the tool from your own Lua code by importing the corresponding files `explcheck-*.lua`.
For example, here is Lua code that applies the preprocessing step to the code from a file named `code.tex`:

``` lua
-- LuaTeX users must initialize Kpathsea Lua module searchers first.
local using_luatex, kpse = pcall(require, "kpse")
if using_luatex then
  kpse.set_program_name("texlua", "explcheck")
end

-- Import explcheck.
local new_issues = require("explcheck-issues")

local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")

-- Process file "code.tex" and print warnings and errors.
local filename = "code.tex"
local issues = new_issues()
local results = {}

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())

preprocessing(filename, content, issues, results)
lexical_analysis(filename, content, issues, results)
syntactic_analysis(filename, content, issues, results)

print(
  "There were " .. #issues.warnings .. " warnings, "
  .. "and " .. #issues.errors .. " errors "
  .. "in the file " .. filename .. "."
)
```

Next, you may also use the tool from continuous integration workflows using the Docker image `ghcr.io/witiko/expltools/explcheck`.
For example, here is a GitHub Actions workflow file that applies the tool to all .tex files in a Git repository:

``` yaml
name: Check expl3 code
on:
  push:
jobs:
  check-code:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/witiko/expltools/explcheck
    steps:
      - uses: actions/checkout@v4
      - run: explcheck *.tex
```

## Configuration

You may configure the tool using command-line options.

For example, the following command-line options would increase the maximum line length before the warning S103 (Line too long) is produced from 80 to 120 characters and also disable the warnings W100 (No standard delimiters) and S204 (Missing stylistic whitespaces).

``` sh
$ explcheck --max-line-length=120 --ignored-issues=w100,S204 *.tex
```

Use the command `explcheck --help` to list the available options.

You may also configure the tool by placing a configuration file named `.explcheckrc` in the current working directory.
For example, here is a configuration file that applies the same configuration as the above command-line options:

``` toml
[defaults]
max_line_length = 120
ignored_issues = ["w100", "S204"]
```

You may also configure the tool from within your Lua code.
For example, here is how you would apply the same configuration in the Lua example from the previous section:

``` lua
local options = { max_line_length = 120 }

issues:ignore("w100")
issues:ignore("S204")

preprocessing(filename, content, issues, results, options)
lexical_analysis(filename, content, issues, results, options)
syntactic_analysis(filename, content, issues, results, options)
```

Command-line options, configuration files, and Lua code allow you to ignore certain warnings and errors everywhere.
To ignore them in just some of your expl3 code, you may use TeX comments.

For example, a comment `% noqa` will ignore any issues on the current line.
As another example, a comment `% noqa: w100, S204` will ignore the file-wide warning W100 and also the warning S204 on the current line.

A list of all currently supported issues is available [here][10].

## Notes to distributors

You can prepare the expltools bundle for distribution with the following two commands:

1. `l3build tag`: Add version numbers to file `explcheck-cli.lua` and create `explcheck-obsolete.lua`.
2. `l3build ctan`: Run tests, build the documentation, and create a CTAN archive `expltools-ctan.zip`.

The file `explcheck.lua` should be installed in the TDS directory `scripts/expltools/explcheck`. Furthermore, it should be made executable and either symlinked to system directories as `explcheck` on Unix or have a wrapper `explcheck.exe` installed on Windows.

## Authors

- Vít Starý Novotný (<witiko@mail.muni.cz>)
- Oliver Kopp (<kopp.dev@gmail.com>)

## License

This material is dual-licensed under GNU GPL 2.0 or later and LPPL 1.3c or later.

``` yaml
SPDX-License-Identifier: GPL-2.0-or-later OR LPPL-1.3c
```
