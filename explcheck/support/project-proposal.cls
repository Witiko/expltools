\NeedsTeXFormat{LaTeX2e}
\ProvidesClass%
  {project-proposal}%
  [2024-09-06 0.0.1 Document class for typesetting the project proposal for %
   the expl3 analysis tool]
\LoadClass{article}
\RequirePackage{lua-widow-control}
\RequirePackage{markdown}
\markdownSetup {
  import = {
    witiko/expltools = metadata,
    witiko/expltools/explcheck/project-proposal = body,
  }
}
\RequirePackage{hologo}
\RequirePackage{hyperref}
