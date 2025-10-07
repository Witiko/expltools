# Changes

## expltools 2025-10-XX

### explcheck v0.15.0

#### Development

This version of explcheck has implemented the following new features:

- Support flow analysis. (#141)

## expltools 2025-10-04

### explcheck v0.14.0

#### Fixes

This version of explcheck has fixed the following bugs:

- Do not produce a Lua error when trying to generate all compatible specifiers
  for base specifiers `T`, `F`, `p`, `w`, and `D`. (reported by @muzimuzhi in
  #137, fixed in #138)

- Fix the description of issue S413, which was previously "Malformed variable
  or constant" rather than "Malformed variable or constant _name_".
  (reported in #137 and #139, fixed in #140)

- Reduce the range of semantic analysis issues to the smallest possible code
  region. (reported by @muzimuzhi in #137 and #139, fixed in #140)

  This is to reduce the chance of `% noqa` comments within long statements
  inadvertently silencing issues related to other parts of the statement.
  Specifically, the ranges of the following issues were narrowed from entire
  statements to particular parts of those statements:

  1. **W401 (Unused private function) and E404 (Protected predicate function):**
     From the beginning of the function definition to the beginning of the
     function replacement text (exclusive), if any, or the whole function
     definition otherwise.

  2. **T403 (Function variant of incompatible type) and W410 (Function variant
     of deprecated type):** The argument with the list of variant specifiers.

  3. **E405 (Function variant for an undefined function):** The argument with
     the function name.

  4. **E408 (Calling an undefined function):** The undefined function name.

  5. **S412 (Malformed function name), S413 (Malformed variable or constant
     name), and S414 (Malformed quark or scan mark name):** The argument with
     the malformed name.

  6. **W415 (Unused variable or constant), W416 (Setting an undeclared
     variable), E417 (Setting a variable as a constant), E418 (Setting a
     constant), W419 (Using an undeclared variable or constant), E420 (Locally
     setting a global variable), and E421 (Globally setting a local
     variable):** The argument with the variable or constant name.

  7. **T422 (Using a variable of an incompatible type):** From the beginning
     of the variable/constant declaration/definition/use to the beginning of
     any arguments following the variable/constant names (exclusive).

  8. **W423 (Unused message):** From the beginning of the message definition
     to the beginning of the message text (exclusive).

  9. **E424 (Using an undefined message):** From the beginning of the message use
     to the first text argument (exclusive), if any, or the whole message use
     otherwise.

  10. **E425 (Incorrect parameter in message text):** The incorrect parameter token.

  11. **E427 (Comparison conditional without signature `:nnTF`):** The argument
      with the comparison conditional name.

#### Warnings and errors

This version of explcheck has made the following changes to the document titled
[_Warnings and errors for the expl3 analysis tool_][warnings-and-errors]:

- Fix the documentation of issue S413 (Malformed variable or constant name).
  (reported by @muzimuzhi in #137 and #139, fixed in #140)

  The module name is mandatory in the variable and constant name, as documented
  in Section 3.2 (Formal naming syntax) of the document titled [_The `expl3`
  package and LaTeX3 programming_][expl3].

 [expl3]: https://mirrors.ctan.org/macros/latex/required/l3kernel/expl3.pdf

- Change the description of issue E425 from "Incorrect parameters in message
  text" to "Incorrect parameter in message text". (#140)

#### Continuous integration

This version of explcheck has made the following changes to our continuous
integration:

- Generate the file `explcheck-latex3.lua` from the files `l3obsolete.txt` and
  `l3prefixes.csv` in the package `l3kernel-dev` rather than `l3kernel`. (#140)

## expltools 2025-09-29

### explcheck v0.13.0

#### Fixes

This version of explcheck has fixed the following bugs:

- Do not deduplicate issues with the same identifier and range but different
  context. (#132)

- Do not report issues E420 (Locally setting a global variable) and E421
  (Globally setting a local variable) in top-level code. (21e2023a, 61a40cb7,
  cfa7847b)

- Support message definitions using the deprecated function `\msg_gset:nn...`.
  (3101d9ff)

#### Warnings and errors

This version of explcheck has made the following changes to the document titled
[_Warnings and errors for the expl3 analysis tool_][warnings-and-errors]:

- Plan issue S105 (Needlessly ignored issue). (#130, #132)

#### Development

This version of explcheck has implemented the following new features:

- Support inter-file dependencies. (#129, #131)

  After this change, you may manually _group files_ from the command-line
  interface as follows:

        explcheck first.tex + second.tex , third.tex , fourth.tex

  The above command would cause the files `first.tex` and `second.tex` to be
  processed together and allow explcheck to assume that these files will always
  be used together. As a result, using e.g. a function in the file `first.tex`
  that is only defined in the file `second.tex` would no longer raise the error
  E408 (Calling an undefined function).

  To control how files are grouped by default, you may use the new command-line
  option `--group-files`. To process a group of files in Lua, you may use the
  function `process_files()` from the file `explcheck-utils.lua`:

  ``` lua
  local utils = require("explcheck-utils")
  local first_group_results = utils.process_files({"first.tex", "second.tex"})
  local second_group_results = utils.process_files({"third.tex"})
  local third_group_results = utils.process_files({"fourth.tex"})
  ```

- Add a new command-line option `--files-from`. (#131)

  Use this option to read the list of expl3 files to check from a text file.

- Report a warning for needlessly ignored issues. (#130, #132)

  Needlessly ignored issues produce warning S105 (Needlessly ignored issue).

- Update the representation of segments according to [the work-in-progress TUG
  2025 paper][expltools-tug25-paper]. (#128, #133)

  Previously, calls and statements were tied to expl3 parts, similarly to
  groupings and tokens, and the notion of "nested calls" and "nested
  statements" was tackled ad-hoc. Following this change, syntactic and
  semantic analyses no longer operate on expl3 parts but on segments that
  represent blocks of either top-level or nested code in some expl3 part from
  some file in the current group of files.

  This more general notion of a block of code that may carry calls and
  statements makes it possible to dynamically support new kinds of segments
  without changing the logic of the code. Furthermore, segments can be
  easily referenced regardless of their files and expl3 parts of origin, and
  subdivided into "chunks of well-understood code", which will be the base data
  type for the flow analysis. Therefore, this change lays the groundwork for
  the implementation of the flow analysis, where we'll be working with a
  directed graph with chunks as the nodes.

- Recognize `T`- and `F`-type arguments as code segments. (#92, #136)

  This allows issues to be reported in true- and false-branches of conditional
  functions, even if these functions are unknown or nested.

- Report code coverage in the verbose human-readable output. (#134, #135)

  The code coverage provides an estimate of how well-understood a piece of code
  is. Circa 14% of all expl3 code and 2% of all TeX code in current TeX Live is
  considered well-understood. The cut-off for performing the flow analysis is
  likely going to be circa 95% well-understood expl3 tokens, so most code will
  initially only be analyzed using semantic analysis, not flow analysis.

#### Continuous integration

This version of explcheck has made the following changes to our continuous
integration:

- Compare code coverage on TeX Live 2024 with a baseline. (#134, #135)

  This acts as an extra precaution against regressions. In general, changes
  should only increase the code coverage compared to the baseline.

## expltools 2025-08-18

### explcheck v0.12.0

#### Warnings and errors

This version of explcheck has made the following changes to the document titled
[_Warnings and errors for the expl3 analysis tool_][warnings-and-errors]:

- Postpone planned issue E417 (Multiply declared variable or constant) to flow
  analysis, under the identifier E519 and the same name. (#110, #112)

- Postpone planned issue E242 (Multiply defined message) to flow analysis,
  under the identifier E524 and the same name. (#110, #112)

- Plan for a weaker version of issue E522 (Too few arguments supplied to
  message) to semantic analysis under the identifier E425 and the same name.
  (#110, #112)

- Remove issues S205 (Malformed function name), S206 (Malformed variable or
  constant name), and S207 (Malformed quark or scan mark name) and replan them
  to semantic analysis under the identifiers S412, S413, and S414, respectively,
  and the same names. (reported by @u-fischer in #109, added in #117)

- Plan for a new issue E417 (Setting a variable as a constant). (#119)

- Unplan issues W419 (Using a token list variable or constant without
  an accessor) and E420 (Using non-token-list variable or constant without
  an accessor). (#121)

- Reclassify the planned errors E421 and E518 (Using an undefined variable or
  constant) as warnings W421 and W518, respectively. (#121)

- Unplan issues W424 and E521 (Setting an undefined message). (#127)

- Reclassify and rename the planned errors E426 and E522 (Too few arguments
  supplied to message) to W426 and W522 (Incorrect number of arguments supplied
  to message), respectively. (#127)

#### Development

This version of explcheck has implemented the following new features:

- Include contextual information in human-readable issue descriptions.
  (suggested by @u-fischer at TUG 2025, reported in #110, added in #112)

- Improve autodetection of expl3 for small example files. (c5ad7a4)

  Previously, we added a new Lua option `min_expl3like_material`, which would
  require at least 5 instances of expl3-like material for a file without
  standard expl3 delimiters to be recognized as expl3. However, this penalizes
  small example files, where there are only a few calls.

  After this change, the option has been renamed to
  `min_expl3like_material_count` and a new Lua option
  `min_expl3like_material_ratio` has been added that specifies the minimum
  portion of the file that must be occupied by expl3 material (defaults to 0.5,
  i.e. 50%) before it is automatically recognized as expl3 regardless.

- Make `% noqa` comments at the beginning of a file silence issues everywhere.
  (suggested by @FrankMittelbach at TUG 2025, reported in #111, added in #116)

- Add more support for semantic analysis. (#117..#122, #127)

  This adds support for all remaining issues from Section 4 of the document
  titled [_Warnings and errors for the expl3 analysis tool_][warnings-and-errors]:

   1. S412 (Malformed function name)
   2. S413 (Malformed variable or constant name)
   3. S414 (Malformed quark or scan mark name)
   4. W415 (Unused variable or constant)
   5. W416 (Setting an undeclared variable)
   6. E417 (Setting a variable as a constant)
   7. E418 (Setting a constant)
   8. W419 (Using an undeclared variable or constant)
   9. E420 (Locally setting a global variable)
  10. E421 (Globally setting a local variable)
  11. T422 (Using a variable of an incompatible type)
  12. W423 (Unused message)
  13. E424 (Using an undefined message)
  14. E425 (Incorrect parameters in message text)
  15. W426 (Incorrect number of arguments supplied to message)
  16. E427 (Comparison conditional without signature `:nnTF`)

- Add Lua option `suppressed_issue_map`. (#102, #126)

  This option defines a mapping between issues that suppress one or more
  other issues. At this point, this option only maps issue W200 ("Do not use"
  argument specifiers) to issues S412, S413, and S414, so that defining
  functions, variables, and constants with malformed names and a "do not use"
  specifier (`:D`) only produces issue W200 and not also S412, S413, and S414.

  In the future, this option will be highly used for issues from the flow
  analysis that have a weaker version in the semantic analysis. In these cases,
  the weaker version will always suppress the stronger version of an issue.

- Make the Lua option `ignored_options`, the command-line option
  `--ignored-options`, the TeX comments `% noqa` and the Lua function
  `issues:ignore()` treat the issue identifiers as prefixes. (#123, #125)

  This allows you to e.g. ignore all style warnings on the current line with
  `% noqa: s`, all general warnings that originate from the semantic analysis
  with `--ignored-issues=W4`, etc.

- Add Lua option `stop_after`. (#124, #126)

  This option allows you to specify after which processing step the analysis
  should stop. If an advanced processing step reports false positive issues
  on a complex expl3 file, this option can be used to reduce the number of
  false positive detections.

- Add Lua option `stop_early_when_confused`. (#124, #126)

  This option, which is enabled by default, allows the processing steps to
  indicate that they are confused by the results of the previous processing
  steps and stop any further processing. If an advanced processing step reports
  false positive issues, then this option should stop the step from running
  and reduce the number of false positive detections.

#### Fixes

This version of explcheck has fixed the following bugs:

- Prevent command-line option `--no-config-file` from raising the error
  `Config file "" does not exist`.
  (reported by @muzimuzhi in #107, fixed in 41446d0)

- Do not report issue W401 (Unused private function) for well-known and
  imported prefixes. (#115)

- Correctly parse indirect applications of creator functions via
  `\cs_generate_from_arg_count:NNnn`. (#118)

- Properly use lazy matching and backtracking in control sequence name patterns
  produced during the semantic analysis. (#120)

  Previously, only wildcards at the end of a name would function properly (lazy
  matching) and any partial matches by previous patterns would prevent any
  potential matches by future patterns (backtracking). Both limitations were
  due to parsing expression grammars (PEGs) being greedy and non-backtracking
  by default. As a result, many wildcards would not match even though they
  should have.

#### Continuous integration

This version of explcheck has made the following changes to our continuous
integration:

- Rename GitHub Action `teatimeguest/setup-texlive-action@v3` to `TeX-Live/...`.
  (reported by @pablogonz in markdown#576, fixed in 28ba10b5)

- Bump actions/checkout and actions/download-artifact from 4 to 5.
  (contributed by @dependabot in #113 and #114)

- Check Lua code blocks in `README.md` with luacheck. (1d21b97, 42f7504, 7b97271)

#### Distribution

This version of explcheck has made the following changes to our distribution:

- Install Bash in the Docker image. (e8c4a08)

## expltools 2025-06-24

### explcheck v0.11.0

#### Development

This version of explcheck has implemented the following new features:

- Detect base forms of deprecated conditional function names.
  (#95, c96332f, 3a4dfbf)

- Improve support for low-confidence function variant definitions. (#99)

  Previously, when unexpected material was encountered in variant argument
  specifiers, variants for all possible sets of specifiers were expected to be
  defined with low confidence. However, for base functions with many
  specifiers, this behavior was disabled because it would lead to a
  combinatorial explosion.

  After this change, all possible variants are efficiently encoded using a
  pattern, which allowed us to support arbitrarily many arguments.

- Recognize more argument specifiers in function (variant) definitions. (#99)

  This includes support for c-type csname arguments and non-n-type replacement
  text arguments. In the latter case, the replacement text is not analyzed and
  the function is assumed to be defined with unknown replacement text.

- Add support for detecting function use in c- and v-type arguments. (#99)

  Previously, if a function `\__example_foo:n` was defined and then used as
  `\use:c { __example_foo:n }`, issue W401 (Unused private function) would be
  raised. After this change, issues like W401 and W402 (Unused private function
  variant) are no longer reported in such cases.

  Furthermore, if a c- or v-type argument can only be partially understood,
  such as `\use:c { __example_foo: \unexpected }`, a pattern `__example_foo:*`
  is generated and functions whose name matches the pattern are marked as
  used with low confidence. However, such pattern is only produced when at
  least N tokens from the argument can be recognized, where N is given by a new
  Lua option `min_simple_tokens_in_csname_pattern` (default is 5 tokens).

- Require more context cues to determine that the whole file is in expl3 when
  the Lua option `expl3_detection_strategy` is set to "auto", which it is by
  default. (#99)

  Previously, any expl3-like material, as defined by the LPEG parser
  `expl3like_material`, would have been sufficient. However, several packages
  such as rcs and fontinst would place colons (:) directly after control
  sequences, confusing the detector. Therefore, N separate instances of
  expl3-like material are now required, where N is given by a new Lua option
  `min_expl3like_material` (default is 5 instances).

- Recognize indirect applications of creator functions via
  `\cs_generate_from_arg_count:NNnn` as function definitions. (#99)

- Add module `explcheck-latex3.lua` that includes LPEG parsers and other
  information extraction from LaTeX3 data files. (#99)

  This module was previously named `explcheck-obsolete.lua` and only included
  information about deprecated control sequences extracted from the file
  `l3obsolete.txt`. The new module also contains registered LaTeX module names
  extracted from the file `l3prefixes.csv`. This new information is used to
  determine whether a control sequence is well-known in order to reduce false
  positive detections of issues such as E408 (Calling an undefined function).

- Add more support for semantic analysis. (#99)

  This adds support for the following new issues from Section 4 of the document
  titled [_Warnings and errors for the expl3 analysis tool_][warnings-and-errors]:

  1. T400[^t400] (Expanding an unexpandable variable or constant)
  2. E408[^e408] (Calling an undefined function)
  3. E411 (Indirect function definition from an undefined function)

  This concludes all planned issues from Section 4.1 (Functions and conditional
  functions) from this document.

 [^t400]: This issue has later been moved to Section 3 of the same document and
    renamed to T305, since it can be detected by the syntactic analysis already.

 [^e408]: By default, all standard library prefixes, defined by the parser
    `expl3_standard_library_prefixes`, as well as registered prefixes from the
    file `l3prefixes.csv` are excluded from this error.

    Besides well-known prefixes, you may also declare other imported prefixes
    using a new Lua option `imported_prefixes`. For example, here is how your
    config file `.explcheckrc` might look if you use the function
    `\precattl_exec:n` from the package precattl:

    ``` csv
    [defaults]
    imported_prefixes = ["precattl"]
    ```

- Add command-line options `--config-file` and `--no-config-file`. (suggested
  by @muzimuzhi in #101, implemented in #99)

- Add Lua option `fail_fast` that controls whether the processing of a file
  stops after the first step that produced any errors. The default value is
  `true`, which means that the processing stops after the first error. (#99)

#### Warnings and errors

This version of explcheck has made the following changes to the document titled
[_Warnings and errors for the expl3 analysis tool_][warnings-and-errors]:

- Gray out issues that are only planned and not yet implemented. (#99)

- Remove the planned issue E406 (Multiply defined function). (#99)

  Semantic analysis wouldn't be able to distinguish between multiply defined
  functions and functions that are defined in different code paths that never
  meet.

- Remove issue W407 (Multiply defined function variant) and plan for a
  replacement issue W501 of the same name for the flow analysis. (#99)

  Semantic analysis can't distinguish between multiply defined variants and
  variants that are defined in different code paths that never meet.

- Merge the planned issues E408 (Calling an undefined function) and E409
  (Calling an undefined function variant) into E408. (#99)

- Plan for a flow-aware variant E504 (Function variant for an undefined
  function) of issue E405 of the same name. (#99)

- Add extra examples for planned issue E500 (Multiply defined function). (#99)

- Include functions `\*_count:N` in the planned issue T420 (Using a variable of
  an incompatible type). (suggested by @FrankMittelbach in latex3/latex3#1754,
  fixed in #97 and #99)

- Remove issue T400 (Expanding an unexpandable variable or constant) and create
  a corresponding issue T305 for the syntactic analysis. (#99)

- Plan for a flow-aware variant E506 (Indirect function definition from an
  undefined function) of issue E411 of the same name. (#99)

- Plan for issue E515 (Paragraph token in the parameter of a "nopar" function)
  and remove the item "Verifying the 'nopar' restriction on functions" from
  Section "Caveats". (#99)

#### Fixes

This version of explcheck has fixed the following bugs:

- Do not report issue E405 (Function variant for an undefined function) for
  standard functions from the modules ltmarks, ltpara, ltproperties, and
  ltsockets. (fixed in commit cb0713df, based on [a TeX StackExchange
  post][tse/739823/70941] by @cfr42)

- Do not report issue S206 (Malformed variable or constant name) when issue
  W200 ("Do not use" argument specifiers) is reported for the same control
  sequence. (reported by @muzimuzhi in #100, fixed in #99)

 [tse/739823/70941]: https://tex.stackexchange.com/a/739823/70941

- Mark file `explcheck.lua` as executable in archive `expltools.ctan.zip`.
  (suggested by @manfredlotz and @PetraCTAN in #98, fixed in #99)

## expltools 2025-05-29

### explcheck v0.10.0

#### Development

- Add more support for semantic analysis. (#86, #92)

  This adds support for the following new issues from Section 4 of the document
  titled [_Warnings and errors for the expl3 analysis tool_][warnings-and-errors]:

  1. W401 (Unused private function)
  2. W402 (Unused private function variant)
  3. T403 (Function variant of incompatible type)
  4. E404 (Protected predicate function)
  5. E405 (Function variant for an undefined function)
  6. W407 (Multiply defined function variant)

  After these changes, 6 out of 24 (25%) issues from this section are
  supported. Support for the remaining issues will be added in upcoming releases.

#### Fixes

- Report issue S205 (Malformed function name) also for conditional function
  definitions. (#86)

- In the command-line interface, do not consider arguments starting with `-`
  filenames. (contributed by @muzimuzhi in #83, fixed in #84)

- Fix issues with token mapping in syntactic analysis. (#86, #90)

- Do not report issue E300 (Unexpected function call argument) for potential
  partial applications. (#86)

- Improve the detection of LaTeX style files. (#86)

- Produce tokens for invalid characters if issue E209 (Invalid characters) is
  ignored. (#86)

#### Continuous integration

- Switch to the GitHub Action `softprops/action-gh-release` for automatic
  pre-releases. (added by @muzimuzhi in #82)

- Improve workflows for forked repositories.
  (reported by @muzimuzhi in #85, fixed in #87)

  Specifically, the name of the built docker image is now parametrized with
  `${{ github.repository }}` and the primary workflow now runs on push to any
  Git branch, not just the main branch.

- Split regression test results into files that contain all pathnames for which
  a specific issue was detected. (suggested by @koppor, added in #88)

- Continuously prune sections that correspond to non-existing files in the
  default config file `explcheck-config.toml`. (#86)

## expltools 2025-05-05

### explcheck v0.9.1

#### Fixes

- Do not crash when `% noqa` is used.
  (reported by @muzimuzhi in #79, fixed in #81)

- Allow any number of spaces and percent signs before `noqa`.
  (reported by @muzimuzhi in #80, fixed in #81)

#### Continuous integration

- Continuously prune the default config file `explcheck-config.toml`. (#78)

  The default config file `explcheck-config.toml` preconfigures many
  packages to prevent false positive detections of issues. However, as the
  capabilities of explcheck grow, many of these configurations are outdated
  and no longer necessary.

  This change adds a script `prune-explcheck-config.lua` that reads the default
  configuration and regression test results and then tests which parts of the
  configuration can be removed without affecting the results of the static
  analysis. Then, the script reminds the maintainer to remove these parts.

- Run CI every Monday morning, after the weekly TeX Live Docker image has
  released. (#78)

- Support simple `.tex` test files without associated `.lua` files. (#81)

#### Documentation

- Include the date of generation and the latest obsolete entry in the generated
  file `explcheck-obsolete.lua`. (#78)

## expltools 2025-04-25

### explcheck v0.9.0

#### Development

- Add basic support for semantic analysis and reading (nested) function
  definitions. (#75)

  None of the issues from Section 4 of the document titled [_Warnings and errors
  for the expl3 analysis tool_][warnings-and-errors] are recognized by
  explcheck yet. Support for (some of) these issues will be added in the next
  minor release.

 [warnings-and-errors]: https://github.com/witiko/expltools/releases/download/latest/warnings-and-errors.pdf

- Add error E304 (Unexpected parameter number) for incorrect parameter tokens
  in parameter and replacement texts of function definitions. (#75)

#### Fixes

- Exclude global scratch variables from issue S206 (Malformed variable or
  constant name). (reported by @fpantigny in #76, fixed in #77)

- Do not produce warning S204 (Missing stylistic whitespaces) in Lua code.
  (reported by @zepinglee in #29, fixed in #75)

#### Documentation

- Add a link to [a work-in-progress TUG 2025 paper][expltools-tug25-paper] to
  `README.md`. (8d4177b, 99ef3b9)

 [expltools-tug25-paper]: https://github.com/witiko/expltools-tug25-paper

## expltools 2025-04-01

### explcheck v0.8.1

#### Fixes

- Be more precise in detecting non-expl3 control sequences in expl3 parts.
  (reported by @callegar in #72, fixed in #74)

## expltools 2025-03-27

### explcheck v0.8.0

#### Development

- Add syntactic analysis. (#66)

- Add Lua option `verbose` and a command-line option `--verbose` that
  prints extra information in human-readable output. (#66)

  For example, here is the output of processing the files `markdown.tex` and
  `markdownthemewitiko_markdown_defaults.sty` of the Markdown package for TeX
  with TeX Live 2024:

  ```
  $ explcheck --verbose `kpsewhich markdown.tex markdownthemewitiko_markdown_defaults.sty`
  ```
  ```
  Checking 2 files

  Checking /usr/local/texlive/2024/texmf-dist/tex/generic/markdown/markdown.tex        OK

      File size: 103,972 bytes

      Preprocessing results:
      - Doesn't seem like a LaTeX style file
      - Six expl3 parts spanning 97,657 bytes (94% of file size):
          1. Between 48:14 and 620:11
          2. Between 637:14 and 788:4
          3. Between 791:14 and 2104:8
          4. Between 2108:14 and 3398:4
          5. Between 3413:14 and 4210:4
          6. Between 4287:14 and 4444:4

      Lexical analysis results:
      - 19,344 tokens in expl3 parts
      - 1,598 groupings in expl3 parts

      Syntactic analysis results:
      - 645 top-level expl3 calls spanning all tokens

  Checking /.../tex/latex/markdown/markdownthemewitiko_markdown_defaults.sty           OK

      File size: 34,894 bytes

      Preprocessing results:
      - Seems like a LaTeX style file
      - Seven expl3 parts spanning 18,515 bytes (53% of file size):
          1. Between 47:14 and 349:4
          2. Between 382:14 and 431:2
          3. Between 446:14 and 512:4
          4. Between 523:14 and 564:2
          5. Between 865:14 and 931:2
          6. Between 969:14 and 1003:2
          7. Between 1072:14 and 1328:2

      Lexical analysis results:
      - 3,848 tokens in expl3 parts
      - 366 groupings in expl3 parts

      Syntactic analysis results:
      - 69 top-level expl3 calls spanning 2,082 tokens (54% of tokens, ~29% of file size)

  Total: 0 errors, 0 warnings in 2 files

  Aggregate statistics:
  - 138,866 total bytes
  - 116,172 expl3 bytes (84% of total bytes) containing 23,192 tokens and 1,964 groupings
  - 714 top-level expl3 calls spanning 21,426 tokens (92% of tokens, ~77% of total bytes)
  ```

- Add Lua option `terminal_width` that determines the layout of the
  human-readable command-line output. (#66)

- Stabilize the Lua API of processing steps. (#64)

  All processing steps are now functions that accept the following arguments:
  1. The filename of a processed file
  2. The content of the processed file
  3. A registry of issues with the processed file (write-only)
  4. Intermediate analysis results (read-write)
  5. Options (read-only, optional)

#### Fixes

- During preprocessing, only consider standard delimiters of expl3 parts that
  are either not indented or not in braces. (discussed in #17, fixed in #66)

- During preprocessing, support `\endinput`, `\tex_endinput:D`, and
  `\file_input_stop:` as standard delimiters of expl3 parts. (#66)

- During preprocessing, do not produce warning W101 (Unexpected delimiters) for
  a `\ProvidesExpl*` after `\ExplSyntaxOn`. (#66)

- Prevent newlines from being recognized as catcode 15 (invalid) with Lua 5.2
  due to unreliable order of table keys. (#66)

#### Continuous integration

- Add regression tests for TeX Live 2024. (#66)

- Configure Dependabot version updates for GitHub Actions.
  (contributed by @koppor in #70)

## expltools 2025-02-25

### explcheck v0.7.1

#### Development

- Add support for config file sections `[package.…]` for specifying
  package-specific configuration. (#32, #57, #62, #63)

  For example, here is how you might configure the file `expl3-code.tex` from
  the package `l3kernel` in your configuration file `.explcheckrc`:

  ``` toml
  [package.l3kernel]
  expl3_detection_strategy = "always"
  ignored_issues = ["w200", "w202", "e208", "e209"]
  max_line_length = 140
  ```

- Add value `"never"` for the command-line option `--expl3-detection-strategy`
  and the Lua option `expl3_detection_strategy`. (#63)

- Pre-configure all remaining expl3 files from current TeX Live with more than
  1 error in <https://koppor.github.io/explcheck-issues/>. (#32, #57, #62, #63,
  4bf5597e, d074dbef)

## expltools 2025-02-24

### explcheck v0.7.0

#### Development

- Generate a static web site for the exploration of issues in all expl3 files
  from TeX Live. (discussed with @norbusan and @koppor in #28 and #32,
  implemented in <https://github.com/koppor/explcheck-issues> by @koppor)

  The web side is available here: <https://koppor.github.io/explcheck-issues/>.

- Add support for config file sections `[filename."…"]` for specifying
  file-specific configuration. (#32, #57, #62)

  For example, here is how you might configure a file `expl3-code.tex` from
  your configuration file `.explcheckrc`:

  ``` toml
  [filename."expl3-code.tex"]
  expl3_detection_strategy = "always"
  ignored_issues = ["w200", "w202", "e208", "e209"]
  max_line_length = 140
  ```

- Pre-configure well-known files from current TeX Live with more than 100 error
  detections in <https://koppor.github.io/explcheck-issues/>. (#32, #57, #62)

- Add command-line option `--error-format` and Lua option `error_format`.
  (discussed with @koppor in koppor/errorformat-to-html#2, added in #40,
  5034639, and #43)

  This allows users to specify Vim's quickfix errorformat used for the
  machine-readable output when the command-line option `--porcelain` or the Lua
  option `porcelain` is enabled.

- Add command-line option `--expl3-detection-strategy` and Lua option
  `expl3_detection_strategy`. (drafted and discussed with @koppor in #38,
  added in #49)

- Add command-line option `--make-at-letter` and Lua option `make_at_letter`.
  (discussed with @zepinglee in #30 and #36, added in #61)

  These options determine how the at sign (`@`) should be tokenized. The
  default value `"auto"` automatically determines the category code based on
  context cues.

#### Fixes

- Prevent false positive E102 (Unknown argument specifiers) detections for
  control sequences with multiple colons (`::`). (#62)

- Ensure that whole files are considered to be in expl3 when the Lua option
  `expl3_detection_strategy` is set to `"always"`, even when the files contain
  standard delimiters `\ProvidesExpl*`. (#62)

  This also prevents false positive E102 (expl3 material in non-expl3 parts)
  detections.

- Only report warning S103 (Line too long) in expl3 parts. (#38, #49)

- In machine-readable output, report the line and column number 1 for file-wide
  issues. (reported by @koppor in #39, fixed in #40)

- Exclude comments from maximum line length checks. (reported by @muzimuzhi in
  #27, fixed in #43, #58, and #59)

  This includes spaces before the comments.

- Always accept both lower- and upper-case issue identifiers. (reported by
  @muzimuzhi in #26, fixed in #44)

  This includes Lua options and configuration files, in addition to
  command-line options and inline TeX comments.

- Exclude "weird" argument specifiers (`:w`) from warning W200. (reported by
  @muzimuzhi in #25, fixed in #45)

- Remove error E203 (Removed control sequences). (reported by @koppor in #53,
  fixed in #54)

- Fix two instances of explcheck crashing while processing input files.
  (reported by @koppor in #31, fixed in #52 and #59)

- Do not recognize `@` as a part of an expl3 control sequence.
  (reported by @zepinglee in #30 and #37, fixed in #60)

  This prevents warnings S205 and S206 for LaTeX2e control sequence
  (re)definitions.

#### Deprecation

- Deprecate the command-line option `--expect-expl3-everywhere` and remove the
  Lua option `expect_expl3_everywhere`. (#49)

  Use the command-line option `--expl3-detection-strategy=always` or the
  corresponding Lua option `expl3_detection_stragegy = "always"` instead.

- Deprecate the default config file section `[options]`. (#62)

  Rename the section to `[defaults]` instead.

#### Documentation

- Add SPDX license identifier to `README.md`. (added by @koppor in #50)

- Link a list of all currently supported issues from `README.md`.
  (added by @koppor in #51)

- Link <https://koppor.github.io/explcheck-issues/> from `README.md`.
  (#28, #32, b774ba77)

#### Continuous integration

- Continuously run explcheck on all packages in historical TeX Live Docker
  images. (suggested by @hansonchar in #28 and #31, added in #52 and #56)

- Use ShellCheck to check code style of Bash scripts. (#61)

#### Housekeeping

- Make off-by-one errors less likely when working with byte ranges.
  (#47, #48, 13ebfc6e, a0923d06)

#### Artwork

- Add artwork by https://www.quickcartoons.com/ to directory `artwork/`.
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
