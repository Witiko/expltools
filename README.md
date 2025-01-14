# Expltools: Development tools for expl3 programmers

This repository contains the code and documentation of an expl3 static analysis tool `explcheck` outlined in the following devlog posts:

1. [Introduction][1]
2. [Requirements][2]
3. [Related work][3]
4. [Design][4]

On September 6, 2024, the tool has been [accepted for funding][5] by [the TeX Development Fund][6].
The full text of the project proposal, which summarizes devlog posts 1–4 is available [here][7].

These devlog posts chronicle the latest updates and progress in the ongoing development of the tool:

5. [Frank Mittelbach in Brno, the first public release of explcheck, and expl3 usage statistics][8] from December 5, 2024
6. [A flurry of releases, CSTUG talk, and what's next][9] from December 19, 2024

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

## Usage

You can use the tool from the command line as follows:

```
$ explcheck [options] [.tex, .cls, and .sty files]
```

You can also use the tool from your own Lua code by importing the corresponding files `explcheck-*.lua`.
For example, here is Lua code that applies the preprocessing step to the code from a file named `code.tex`:

``` lua
local new_issues = require("explcheck-issues")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")

-- LuaTeX users must initialize Kpathsea Lua module searchers first.
local using_luatex, kpse = pcall(require, "kpse")
if using_luatex then
  kpse.set_program_name("texlua", "explcheck")
end

-- Apply the preprocessing step to a file "code.tex".
local filename = "code.tex"
local issues = new_issues()

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())

local _, expl_ranges = preprocessing(issues, content)
lexical_analysis(issues, content, expl_ranges)

print(
  "There were " .. #issues.warnings .. " warnings, "
  .. "and " .. #issues.errors .. " errors "
  .. "in the file " .. filename .. "."
)
```

You can also use the tool from continuous integration workflows using the Docker image `ghcr.io/witiko/expltools/explcheck`.
For example, here is a GitHub Actions workflow file that applies the tool to all .tex file in a Git repository:

``` yaml
name: Check expl3 code
on:
  push:
jobs:
  typeset:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/witiko/expltools/explcheck
    steps:
      - uses: actions/checkout@v4
      - run: explcheck *.tex
```

## Notes to distributors

You can prepare the expltools bundle for distribution with the following two commands:

1. `l3build tag`: Add the current version numbers to the file `explcheck-lua.cli`.
2. `l3build ctan`: Run tests, build the documentation, and create a CTAN archive `expltools-ctan.zip`.

The file `explcheck.lua` should be installed in the TDS directory `scripts/expltools/explcheck`. Furthermore, it should be made executable and either symlinked to system directories as `explcheck` on Unix or have a wrapper `explcheck.exe` installed on Windows.

## Authors

- Vít Starý Novotný (<witiko@mail.muni.cz>)

## License

This material is dual-licensed under GNU GPL 2.0 or later and LPPL 1.3c or later.
