# Changes

## expltools 2025-MM-DD

### explcheck v0.7.0-dev

#### Development

- Add command-line option `--error-format` and Lua option `error_format` for
  specifying Vim's quickfix errorformat used for the machine-readable output
  when the command-line option `--porcelain` is enabled.
  (discussed with @koppor in koppor/errorformat-to-html#2, added in #40 and
  5034639)

#### Fixes

- In machine-readable output, report the line and column number 1 for file-wide
  issues. (reported by @koppor in #39, fixed in #40)

- Always accept both lower- and upper-case issue identifiers. (reported by
  @muzimuzhi in #26, fixed in #44)

  This includes Lua options and configuration files, in addition to
  command-line options and inline TeX comments.

#### Artwork

- Add artwork by https://fiverr.com/quickcartoon to directory `artwork/`.
  (566769b)

## expltools 2025-01-20

### explcheck v0.6.1

#### Fixes

- Correctly read option `warnings_are_errors` from file `.explcheckrc`.
  (e351fdd)

## expltools 2025-01-16

### explcheck v0.6.0

#### Development

- Add support for TOML configuration files. (#24)

  You may configure the tool by placing a configuration file named
  `.explcheckrc` in the current working directory.

  For example, the following configuration file would increase the maximum line
  length before the warning S103 (Line too long) is produced from 80 to 120
  characters and also disable the warnings W100 (No standard delimiters) and
  S204 (Missing stylistic whitespaces):

  ``` toml
  [options]
  max_line_length = 120
  ignored_issues = ["w100", "s204"]
  ```

#### Fixes

- Do not require lower-case identifiers in the command-line option
  `--ignored-issues`. (f394d38c)

#### Distribution

- Add Lua library `lfs` to Docker image `ghcr.io/witiko/expltools/explcheck`.
  (4f9f26f)

  This enables additional functionality, such as suggesting which `.ins` file
  the user should process with TeX to extract expl3 code from a `.dtx` archive.

## expltools 2025-01-15

### explcheck v0.5.0

#### Development

- Add support for ignoring file-wide issues and issues on a single line using
  TeX comments. (#23)

  For example, a comment `% noqa` will ignore any issues on the current line,
  whereas a comment `% noqa: W100, S204` will ignore the file-wide warning W100
  (No standard delimiters) and the warning S204 (Missing stylistic whitespaces)
  on the current line.

- Add command-line option `--ignored-issues` and Lua option `ignored_issues`
  for ignoring issues. (#23)

  For example, `--ignored-issues=w100,s204` will ignore the file-wide warning
  W100 (No standard delimiters) and all warnings S204 (Missing stylistic
  whitespaces).

#### Fixes

- Correctly shorten long names of files from the current working directory in
  the command-line output. (#23)

- Correctly parenthesize and order LPEG parsers in the file
  `explcheck-obsolete.lua`. (#23)

- Do not produce warning S204 (Missing stylistic whitespaces) for non-expl3,
  empty, or one-character names of control sequences. (#23)

- Do not produce warning S204 (Missing stylistic whitespaces) for an empty
  grouping (`{}`). (#23)

- Do not produce warning S204 (Missing stylistic whitespaces) for a parameter
  before begin grouping (`#1{`). (#23)

- Do not produce S204 (Missing stylistic whitespaces) for a comma immediately
  after a control sequence. (505608f9)

- Do not produce warnings S205 (Malformed function name) and S206 (Malformed
  variable or constant name) for non-expl3 functions, variables, and constants.
  (#23)

- Do not produce warnings S206 (Malformed variable or constant name) for
  variable and constant names that contain names of built-in types such as
  `\c_module_constant_clist_tl` containing `clist`. (#23)

## expltools 2025-01-14

### explcheck v0.4.0

#### Development

- Add lexical analysis. (#21)

#### Fixes

- Do not detect error E102 (expl3 material in non-expl3 parts) when the
  command-line option `--expect-expl3-everywhere` has been specified. (#21)

## expltools 2024-12-23

### explcheck v0.3.0

#### Development

- Add option `--expect-expl3-everywhere` to ignore \ExplSyntaxOn and Off.
  (discussed with @muzimuzhi in #17, added in #19)

- Add short-hand command-line option `-p` for `--porcelain`.
  (suggested by @FrankMittelbach in #8, added in #19)

- Add file `explcheck-config.lua` with the default configuration of explcheck. (#19)

  You may place a file named `explcheck-config.lua` with your own configuration
  in your repository to control the behavior of explcheck.

  Note that the configuration options are provisional and may be changed or
  removed before version 1.0.0. Furthermore, support for configuration YAML
  files that will allow you to specify different configuration for different
  .tex files is envisioned for a future release and will be the recommended way
  to configure explcheck.

#### Fixes

- Make the detection of error E102 (expl3 material in non-expl3 parts) more precise.
  (discussed with @cfr42 in #18, fixed in #19)

- Use a less naïve parser of TeX comments to improve the detection of issues
  W100 and E102. (reported by @FrankMittelbach in #8, fixed in #16)

#### Documentation

- State in the output of `explcheck --help` that command-line options are
  provisional and subject to change. (discussed with @FrankMittelbach and
  @muzimuzhi in #8 and #17, added in #19)

- Display the default maximum line length in the output of `explcheck --help`. (#19)

- Rename E102 to "expl3 material in non-expl3 parts".
  (discussed with @cfr42 in #18, added in #19)

## expltools 2024-12-13

### explcheck v0.2.0

#### Development

- Add a command-line option `--porcelain` for machine-readable output.
  (suggested by @FrankMittelbach in #8, added in #15)

  See <https://github.com/Witiko/expltools/pull/15#issuecomment-2542418484>
  and below for a demonstration of how you might set up your text editor, so
  that it automatically navigates you to lines with warnings and errors.

#### Fixes

- In the command-line interface, forbid the checking of .ins and .dtx files.
  Display messages that direct users to check the generated files instead.
  (reported by @josephwright and @FrankMittelbach in #8, fixed in #14)

- Expect both backslashes and forward slashes when shortening pathnames. (#14)

- Correctly pluralize "1 file" on the first line of command-line output. (#14)

#### Documentation

- Normalize the behavior and documentation of functions `get_*()` across files
  `explcheck/build.lua`, `explcheck/test.lua`, and `explcheck-cli.lua`. (#14)

## expltools 2024-12-09

### explcheck v0.1.1

#### Fixes

- In LuaTeX, initialize Kpathsea Lua module searchers first.
  (reported by @josephwright, Lars Madsen, and Philip Taylor on
  [tex-live@tug.org][tex-live-02] and by @muzimuzhi in #9,
  fixed on [tex-live@tug.org][tex-live-03] by @gucci-on-fleek)

- Allow spaces between arguments of `\ProvidesExpl*` commands.
  (reported by @u-fischer and @josephwright in #7, fixed in #13)

 [tex-live-02]: https://tug.org/pipermail/tex-live/2024-December/050958.html
 [tex-live-03]: https://tug.org/pipermail/tex-live/2024-December/050968.html

#### Documentation

- Include explcheck version in the command-line interface.
  (reported in #10, fixed in #13)

- Hint in the file `README.md` that .dtx files are not well-supported.
  (reported by @josephwright in #8, added in #13)

- Show in the file `README.md` how explcheck can be used from Lua code. (#13)

- Include instructions about using l3build in the file `README.md`.
  (reported in #11, added in #13)

#### Continuous integration

- Add `Dockerfile`, create Docker image, and mention it in the file `README.md`.
  (discussed in #12, added in #13)

## expltools 2024-12-04

### explcheck v0.1

#### Development

- Implement preprocessing. (#5)

#### Documentation

- Add `README.md`. (suggested by @Skillmon in #1, fixed in #2)
- Update to Markdown 3. (#3)
- Use the expl3 prefix `expltools`. (#3)
- Add project proposal. (#4)

#### Continuous integration

- Use small Docker image. (#3)

#### Distribution

- Make changes to the CTAN archive following a discussion with TeX Live developers
  on [tex-live@tug.org][tex-live-01] and with CTAN maintainers. Many thanks
  specifically to Petra Rübe-Pugliese, Reinhard Kotucha, and Zdeněk Wagner.

 [tex-live-01]: https://tug.org/pipermail/tex-live/2024-December/050952.html
