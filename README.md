# Expltools: Development tools for expl3 programmers

This repository contains the code and documentation of an expl3 static analysis tool `explcheck` outlined in the following devlog posts:

1. [Introduction][1]
2. [Requirements][2]
3. [Related work][3]
4. [Design][4]

On September 6, 2024, the tool has been [accepted for funding][5] by [the TeX Development Fund][6].
The full text of the project proposal, which summarizes devlog posts 1–4 is available [here][7].

In the future, this repository may also contain the code of other useful development tools for expl3 programmers, such as a command-line utility similar to `grep` that will ignore whitespaces and newlines as well as other tools.

 [1]: https://witiko.github.io/Expl3-Linter-1/
 [2]: https://witiko.github.io/Expl3-Linter-2/
 [3]: https://witiko.github.io/Expl3-Linter-3/
 [4]: https://witiko.github.io/Expl3-Linter-4/
 [5]: https://tug.org/tc/devfund/grants.html
 [6]: https://tug.org/tc/devfund/application.html
 [7]: https://tug.org/tc/devfund/documents/2024-09-expltools.pdf

## Usage

You can use the tool from command-line as follows:

```
$ explcheck [options] [filenames]
```

## License

This material is dual-licensed under GNU GPL 2.0 or later and LPPL 1.3c or later.
