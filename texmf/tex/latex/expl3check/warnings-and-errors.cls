\LoadClass{article}
\RequirePackage{lua-widow-control}
\RequirePackage{minted}
\setminted{breaklines, linenos}
\PassOptionsToPackage{theme=witiko/expl3check/warnings-and-errors}{markdown}
\RequirePackage{markdown}
\RequirePackage{biblatex}
\addbibresource{warnings-and-errors.bib}
\RequirePackage{embedfile}
\RequirePackage{imakeidx}
\makeindex[columns=3, intoc, options=-s warnings-and-errors.ist]
\RequirePackage{hyperref}
\def\meta#1{$\langle$\textrm{\textit{#1}}$\rangle$}