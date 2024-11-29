\NeedsTeXFormat{LaTeX2e}
\ProvidesClass%
  {warnings-and-errors}%
  [2024-09-06 0.0.3 Document class for typesetting the documentation of the %
   warnings and errors for the expl3 analysis tool]
\LoadClass{article}
\RequirePackage{lua-widow-control}
\RequirePackage{minted}
\setminted{breaklines, linenos}
\RequirePackage{markdown}
\markdownSetup {
  import = {
    witiko/expltools = metadata,
    witiko/expltools/explcheck/warnings-and-errors = body,
  }
}
\RequirePackage{biblatex}
\addbibresource{warnings-and-errors.bib}
\RequirePackage{embedfile}
\RequirePackage{imakeidx}
\makeindex[columns=3, intoc, options=-s warnings-and-errors.ist]
\RequirePackage{hyperref}
\def\meta#1{$\langle$\textrm{\textit{#1}}$\rangle$}
