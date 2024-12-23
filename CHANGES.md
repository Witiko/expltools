# Changes

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
