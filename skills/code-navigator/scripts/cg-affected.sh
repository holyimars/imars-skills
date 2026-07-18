#!/usr/bin/env bash
# Usage: cg-affected.sh [file1 file2 ...]
# No args -> defaults to the current uncommitted git diff (like cbm-impact.sh
# on the other skill). Capability codebase-memory-mcp does NOT have: maps
# changed source files -> the test files that actually cover them.
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
if [ "$#" -eq 0 ]; then
  mapfile -t FILES < <(git -C "$CG_ROOT" diff --name-only HEAD 2>/dev/null || true)
else
  FILES=("$@")
fi
if [ "${#FILES[@]}" -eq 0 ]; then
  echo '{"changedFiles":[],"affectedTests":[],"hint":"no uncommitted changes and no files given — pass file paths explicitly"}'
  exit 0
fi
codegraph affected "${FILES[@]}" -j 2>/dev/null | jq '. + {hint: (if ((.affectedTests // [])|length)==0
  then "no covering test files found by dependency traversal — grep for the source file basename in test dirs as a fallback" else null end)}'
