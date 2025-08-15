# Caveats
The warnings and errors in this documents do not cover the complete expl3 language. The caveats currently include the following areas, among others:

- Functions with “weird” (`w`) argument specifiers
- Symbolic evaluation of expansion functions
  [@latexteam2024interfaces, sections 5.4–5.10]
- Validation of parameters in (inline) functions
  (c.f. <#invalid-parameters-in-message-text>
   and <#too-few-arguments-supplied-to-message>)
- Shorthands such as `\~` and `\\` in message texts
  [@latexteam2024interfaces, sections 11.4 and 12.1.3]
- Quotes in shell commands and file names
  [@latexteam2024interfaces, Section 10.7 and Chapter 12]
- Functions used outside their intended context:
    - `\sort_return_*:` outside comparison code
      [@latexteam2024interfaces, Section 6.1]
    - `\prg_return_*:` outside conditional functions
      [@latexteam2024interfaces, Section 9.1]
    - Predicates (`\*_p:*`) outside boolean expressions
      [@latexteam2024interfaces, Section 9.3]
    - `\*_map_break:*` outside a corresponding mapping
      [@latexteam2024interfaces, sections 9.8]
    - `\msg_line_*:`, `\iow_char:N`, and `\iow_newline:`
      outside message text
      [@latexteam2024interfaces, sections 11.3 and 12.1.3]
    - `\iow_wrap_allow_break:` and `\iow_indent:n`
      outside wrapped message text
      [@latexteam2024interfaces, Section 12.1.4]
    - Token list and string variables without accessor
      functions `\tl_use:N` and `\str_use:N`
    - Boolean variable without an accessor function
      `\bool_to_str:N` outside boolean expressions
      [@latexteam2024interfaces, Section 21.4]
    - Integer variable without an accessor function
      `\int_use:N` outside integer or floating point
      expressions [@latexteam2024interfaces, Section 21.4]
    - Dimension variable without an accessor function
      `\dim_use:N` outside dimension or floating point
      expressions [@latexteam2024interfaces, Section 26.7]
    - Skip variable without an accessor function
      `\skip_use:N` outside skip or floating point expressions
      [@latexteam2024interfaces, Section 26.14]
    - Muskip variable without an accessor function
      `\muskip_use:N` outside muskip or floating point
      expressions [@latexteam2024interfaces, Section 26.21]
    - Floating point variable without an accessor function
      `\fp_use:N` outside floating point
      expressions [@latexteam2024interfaces, Section 29.3]
    - Box variable without accessor functions
      `\box_use(_drop)?:N` or `\[hv]box_unpack(_drop)?:N`,
      or without a measuring function
      `\box_(dp|ht|wd|ht_plus_dp):*` outside dimension or
      floating point expressions
      [@latexteam2024interfaces, sections 35.2 and 35.3]
    - Coffin variable without accessor function
      `\coffin_typeset:Nnnnn` outside dimension or
      floating point expressions
      [@latexteam2024interfaces, Section 36.4]
    - Lonely variables of other types that may or may not
      have accessor functions
- Validation of literal expressions:
    - Comparison expressions in functions
      `\*_compare(_p:n|:nT?F?)`
    - Regular expressions and replacement text
      [@latexteam2024interfaces, sections 8.1 and 8.2]
    - Boolean expressions
      [@latexteam2024interfaces, Section 9.3]
    - Integer expressions and bases
      [@latexteam2024interfaces, sections 21.1 and 21.8]
    - Dimension, skip, and muskip expressions
      [@latexteam2024interfaces, Chapter 26]
    - Floating point expressions
      [@latexteam2024interfaces, Section 29.12]
    - Color expressions
      [@latexteam2024interfaces, Chapter 37.3]
- Validation of naming schemes and member access:
    - String encoding and escaping
      [@latexteam2024interfaces, Section 18.1]
    - Key–value interfaces
      [@latexteam2024interfaces, Chapter 27]:
        - Are keys defined at the point of use or is the module
          or its subdivision set up to accept unknown keys?
          [@latexteam2024interfaces, sections 27.2, 27.5,
          and 27.6]
        - Are inheritance parents, choices, multi-choices, and
          groups used in a key definition defined at points of
          use? [@latexteam2024interfaces, sections 27.1, 27.3,
          and 27.7]
    - Floating-point symbolic expressions and user-defined
      functions [@latexteam2024interfaces, sections 29.6
      and 29.7]
    - Names of bitset indexes
      [@latexteam2024interfaces, Section 31.1]
    - BCP-47 language tags
      [@latexteam2024interfaces, Section 34.2]
    - Color support
      [@latexteam2024interfaces, Chapter 37]:
        - Named colors [@latexteam2024interfaces, Section 37.4]
        - Color export targets [@latexteam2024interfaces,
          Section 37.8]
        - Color models and their families and params
          [@latexteam2024interfaces, sections 37.2 and 37.9]
- Function `\file_input_stop:` not used on its own line
  [@latexteam2024interfaces, Section 12.2.3]
- Exhaustively or fully expanding quarks and scan marks
  [@latexteam2024interfaces, Chapter 19]
- Bounds checking for accessing constant sequences and other
  sequences where the number of items can be easily bounded
  such as integer and floating point arrays
  [@latexteam2024interfaces, chapters 28 and 30]:
    - Index checking functions `\*_range*:*` and `\*_item*:*`
    - Endless loop checking in functions `\*_step_*:*`
      [@latexteam2024interfaces, Section 21.7]
    - Number of symbols in a value-to-symbol mapping
      [@latexteam2024interfaces, Section 21.8]
- Applying functions `\clist_remove_duplicates:N` and
  `\clist_if_in:*` to comma lists that contain `{`, `}`, or `*`
  [@latexteam2024interfaces, sections 23.3 and 23.4]
- Incorrect parameters to function `\char_generate:nn`
  [@latexteam2024interfaces, Section 24.1]
- Incorrect parameters to functions `\char_set_*code:nn`
  [@latexteam2024interfaces, Section 24.2]
- Using implicit tokens `\c_catcode_(letter|other)_token` or
  the token list `\c_catcode_active_tl`
  [@latexteam2024interfaces, Section 24.3]
- Validation of key–value interfaces
  [@latexteam2024interfaces, Chapter 27]:
    - Setting a key with some properties `.*_g?(set|put)*:*`
      should be validated similarly to calling the corresponding
      functions directly: Have the variables been declared, do
      they have the correct type, does the value have the
      correct type?
    - Do points of use always set keys with property
      `.value_required:n` and never set keys with
      property `.value_forbidden:n`?
- Horizontal box operation on a vertical box or vice
  versa [@latexteam2024interfaces, Chapter 35]
