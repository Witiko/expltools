# Expltools: Development tools for expl3 programmers

This repository contains the code and documentation of an expl3 static analysis tool `explcheck` outlined in the following devlog posts:

1. [Introduction][1]
2. [Requirements][2]
3. [Related work][3]
4. [Design][4]
5. [First public release][5]

On September 6, 2024, the tool has been [accepted for funding][6] by [the TeX Development Fund][7].
The full text of the project proposal, which summarizes devlog posts 1–4 is available [here][8].

In the future, this repository may also contain the code of other useful development tools for expl3 programmers, such as a command-line utility similar to `grep` that will ignore whitespaces and newlines as well as other tools.

 [1]: https://witiko.github.io/Expl3-Linter-1/
 [2]: https://witiko.github.io/Expl3-Linter-2/
 [3]: https://witiko.github.io/Expl3-Linter-3/
 [4]: https://witiko.github.io/Expl3-Linter-4/
 [5]: https://witiko.github.io/Expl3-Linter-5/
 [6]: https://tug.org/tc/devfund/grants.html
 [7]: https://tug.org/tc/devfund/application.html
 [8]: https://tug.org/tc/devfund/documents/2024-09-expltools.pdf

## Usage

You can use the tool from the command line as follows:

```
$ explcheck [options] [.tex, .cls, and .sty files]
```

You can also use the tool from your own Lua code by importing the corresponding files `explcheck-*.lua`:

``` lua
local new_issues = require("explcheck-issues")
local preprocessing = require("explcheck-preprocessing")

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

local line_starting_byte_numbers = preprocessing(issues, content)

print(
  "There were " .. #issues.warnings .. " warnings "
  .. "and " .. #issues.errors .. " errors "
  .. "in the file " .. filename .. "."
)
```

## Notes to distributors

You can prepare the expltools bundle for distribution with the following two commands:

- `l3build tag`: Add the current version numbers to the file `explcheck-lua.cli`.
- `l3build ctan`: Run tests, build the documentation, and create a CTAN archive `expltools-ctan.zip`.

The file `explcheck.lua` should be installed in the TDS directory `scripts/expltools/explcheck`. Furthermore, it should be made executable and either symlinked to system directories as `explcheck` on Unix or have a wrapper `explcheck.exe` installed on Windows.

## Authors

- Vít Starý Novotný (<witiko@mail.muni.cz>)

## License

This material is dual-licensed under GNU GPL 2.0 or later and LPPL 1.3c or later.
