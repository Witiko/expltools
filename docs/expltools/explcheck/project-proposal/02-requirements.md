# Requirements

In this section, I outline the requirements for the linter. These will form the basis of the design and the implementation.

## Functional requirements

The linter should accept a list of input expl3 files. Then, the linter should process each input file and print out issues it has identified with the file.

Initially, the linter should recognize at least the following types of issues:

- Style:
  - Overly long lines
  - Missing stylistic white-spaces
  - Malformed names of functions, variables, constants, quarks, and scan marks
- Functions:
  - Multiply defined functions and function variants
  - Calling undefined functions and function variants
  - Calling [deprecated and removed][2] functions
  - Unknown argument specifiers
  - Unexpected function call arguments
  - Unused private functions and function variants
- Variables:
  - Multiply declared variables and constants
  - Using undefined variables and constants
  - Using variables of incompatible types
  - Using deprecated and removed variables and constants
  - Setting constants and undeclared variables
  - Unused variables and constants
  - Locally setting global variables and vice versa

## Non-functional requirements

### Issues

The linter should make distinction between two types of issues: warnings and errors. As a rule of thumb, whereas warnings are suggestions about best practices, errors will likely result in runtime errors.

Here are three examples of warnings:

- Missing stylistic white-spaces around curly braces
- Using deprecated functions and variables
- Unused variable or constant

Here are three examples of errors:

- Using an undefined message
- Calling a function with a `V`-type argument with a variable or constant that does not support `V`-type expansion
- Multiply declared variable or constant

The overriding design goal for the initial releases of the linter should be the simplicity of implementation and robustness to unexpected input. For all issues, the linter should prefer [precision over recall][1] and only print them out when it is reasonably certain that it has understood the code, even at the expense of potentially missing some issues.

Each issue should be assigned a unique identifier. Using these identifiers, issues can be disabled globally using a config file, for individual input files from the command-line, and for sections of code or individual lines of code using `\TeX`{=tex} comments.

### Architecture

To make the linter easy to use in continuous integration pipelines, it should be written in Lua 5.3 using just the standard Lua library. One possible exception is checking whether functions, variables, and other symbols from the input files are expl3 build-ins. This may require using the `texlua` interpreter and a minimal `\TeX`{=tex} distribution that includes the `\LaTeX`{=tex}3 kernel, at least initially.

The linter should process input files in a series of discrete steps, which should be represented as Lua modules. Users should be able to import the modules into their Lua code and use them independently on the rest of the linter.

Each step should process the input received from the previous step, identify any issues with the input, and transform the input to an output format appropriate for the next step. The default command-line script for the linter should execute all steps and print out issues from all steps. Users should be able to easily adapt the default script in the following ways:

1. Change how the linter discovers input files.
2. Change or replace processing steps or insert additional steps.
3. Change how the linter reacts to issues with the input files.

The linter should integrate easily with text editors. Therefore, the linter should either directly support the [language server protocol (LSP)][6] or be designed in a way that makes it easy to write an LSP wrapper for it.

### Validation

As a part of the test-driven development paradigm, all issues identified by a processing step should have at least one associated test in the code repository of the linter. All tests should be executed periodically during the development of the linter.

As a part of the dogfooding paradigm, the linter should be used in the continuous integration pipeline of [the Markdown Package for `\TeX`{=tex}][3] since the initial releases of the linter in order to collect early user feedback. Other early adopters are also welcome to try the initial releases of the linter and report issues to its code repository.

At some point, a larger-scale validation should be conducted as an experimental part of a TUGboat article that will introduce the linter to the wider `\TeX`{=tex} community. In this validation, all expl3 packages from current and historical `\TeX`{=tex} Live distributions should be processed with the linter. The results should be evaluated both quantitatively and qualitatively. While the quantitative evaluation should focus mainly on trends in how expl3 is used in packages, the qualitative evaluation should explore the shortcomings of the linter and ideas for future improvements.

### License terms

The linter should be [free software][8] and dual-licensed under [the GNU General Public License (GNU GPL) 2.0][12] or later and [the `\LaTeX`{=tex} Project Public License (LPPL) 1.3c][13] or later.

The option to use GNU GPL 2.0 or later is motivated by the fact that GNU GPL 2.0 and 3.0 are [mutually incompatible][14]. Supporting both GNU GPL 2.0 and 3.0 extends the number of free open-source projects that will be able to alter and redistribute the linter.

The option to use LPPL 1.3c is motivated by the fact that it imposes very few licensing restrictions on `\TeX`{=tex} users. Furthermore, it also preserves the integrity of `\TeX`{=tex} distributions by enforcing its naming and maintenance clauses, which ensure ongoing project stewardship and prevent confusion between modified and official versions.

Admittedly, GNU GPL and LPPL may seem like an unusual combination, since GNU GPL is a copyleft license whereas LPPL is a permissive license. However, there are strategic benefits to offering both.

We would offer LPPL as the primary license for derivative works within the `\TeX`{=tex} ecosystem. One downside of using LPPL is that it could potentially allow bad actors to create proprietary derivative works without contributing back to the original project. However, this trade-off helps maintain the `\TeX`{=tex} ecosystem's consistency and reliability. Incidentally, there is an element of trust in the `\TeX`{=tex} user community to voluntarily contribute improvements back, even though the license itself does not mandate it.

We would offer GNU GPL as an alternative license for derivative works outside the `\TeX`{=tex} ecosystem. The key benefit of including GNU GPL is that it enables the code to be integrated into free open-source projects, especially those with licenses that are incompatible with LPPL's naming requirements. This opens the door for broader collaboration with the free software community.

Notably, GNU GPL creates a one-way licensing situation: Once a derivative work is licensed under GNU GPL, it cannot be legally re-licensed under a less restrictive license like LPPL. As a result, we wouldn't be able to incorporate changes made to GNU GPL-licensed works back into the original project under LPPL without also creating two forks of the project licensed under GNU GPL 2.0 and GNU GPL 3.0, respectively. While this might seem like a downside, I view it as an important counterbalance to the potential for proprietary derivative works under LPPL.

In summary, this dual-licensing approach allows us to maintain the integrity of the `\TeX`{=tex} ecosystem while making the project more accessible to the broader free open-source community. It provides flexibility for different use cases, though we will need to carefully manage contributions to ensure compliance with all licenses.

 [1]: https://developers.google.com/machine-learning/crash-course/classification/precision-and-recall
 [2]: https://github.com/latex3/latex3/blob/main/l3kernel/doc/l3obsolete.txt
 [3]: https://github.com/witiko/markdown
 [4]: /Expl3-Linter-1
 [5]: /Expl3-Linter-2.5
 [6]: https://microsoft.github.io/language-server-protocol/
 [7]: https://www.gnu.org/licenses/lgpl-3.0.en.html
 [8]: https://www.gnu.org/philosophy/free-sw.html
 [9]: https://www.gnu.org/licenses/gpl-3.0.html
 [10]: https://www.gnu.org/licenses/license-list.html#GPLCompatibleLicenses
 [11]: /Expl3-Linter-3
 [12]: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 [13]: https://www.latex-project.org/lppl/lppl-1-3c/
 [14]: https://www.gnu.org/licenses/rms-why-gplv3.en.html