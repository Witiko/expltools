# Changes

## expltools 2024-12-13

### explcheck v0.2.0

#### Development

- Add a command-line option `--porcelain` for machine-readable output.
  (suggested by @FrankMittelbach in #8, added in #14)

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
