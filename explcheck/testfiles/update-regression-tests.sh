#!/bin/bash
# Update regression tests after a failed GitHub Actions run.

set -e -o xtrace

if (( $# != 1 ))
then
  printf 'Usage: %s GITHUB_ACTIONS_RUN_ID\n' "$0" 1>&2
  exit 1
fi

cd "$(dirname "$(readlink -f "$0")")"
gh run download "$1"
for DIRECTORY in TL20*\ issues/
do
  mv "$DIRECTORY"/issues.txt "${DIRECTORY% issues/}-issues.txt"
  rmdir "$DIRECTORY"
done
