# Introduction

In this document, I list the warnings and errors for the different processing steps of the expl3 linter [@starynovotny2024static3]:

Preprocessing

: Determine which parts of the input files contain expl3 code.

Lexical analysis

: Convert expl3 parts of the input files into `\TeX`{=tex} tokens.

Syntactic analysis

: Convert `\TeX`{=tex} tokens into a tree of function calls.

Semantic analysis

: Determine the meaning of the different function calls.

Flow analysis

: Determine additional emergent properties of the code.

For each warning and error, I specify a unique identifier that can be used to disable the warning or error, a description of the condition for the warning or error, and a code example that demonstrates the condition and serves as a test case for the linter.

Warnings and errors have different types that decides the prefix of their idenfitiers:

- Warnings:

    `S`
    :   Style warnings

    `W`
    :   Other warnings

- Errors:

    `T`
    :   Type errors

    `E`
    :   Other errors

Issues that are planned but not yet implemented are grayed out.
