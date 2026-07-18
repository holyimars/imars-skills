#!/usr/bin/env bash
# Usage: cg-find.sh [-k kind] [-l limit] ['<name-or-fuzzy-text>']
#
# The query pattern is OPTIONAL when -k is given: an empty pattern + -k
# <kind> lists EVERY symbol of that kind, not a fuzzy-matched subset.
# Field-verified (2026-07-17): `codegraph query '' -k route -l 500` returns
# a count that exactly matches `codegraph status -j`'s nodesByKind.route
# (303/303 on RuoYi-Vue-Plus), same for -k class/interface/component — this
# is the correct, ACCURATE way to answer "list all routes/classes/
# interfaces/components", not cg-explore.sh (see references/codegraph-blindspots.md:
# explore does keyword/semantic retrieval, not a real kind-filtered
# enumeration, and silently returns wrong-but-plausible results here).
#
# CLI quirk (field-verified 2026-07-17): with a NON-empty pattern, -l is a
# literal cap. With an EMPTY pattern, codegraph's own -l behaves like a
# per-file/group multiplier, not a literal cap: -l 1/3/5 returned exactly
# 5/15/25 rows on the same repo (~5x), so a small default would silently
# truncate a "list all" request. We do not depend on that ratio holding —
# instead default to a limit generously above any real per-kind population
# (500) whenever Q is empty and the caller didn't pass -l explicitly, so
# "list all" actually means all (still verify: compare the returned count
# to `codegraph status -j`'s nodesByKind.<kind> if precision matters).
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
KIND=""; LIMIT=""
while getopts "k:l:" f; do case $f in k) KIND=$OPTARG;; l) LIMIT=$OPTARG;; esac; done
shift $((OPTIND-1)); Q="${1:-}"
if [ -z "$LIMIT" ]; then
  if [ -z "$Q" ]; then LIMIT=500; else LIMIT=20; fi
fi

ARGS=(query "$Q" -j -l "$LIMIT")
[ -n "$KIND" ] && ARGS+=(-k "$KIND")

OUT=$(cg_call "${ARGS[@]}")
echo "$OUT" | jq 'if (type=="object" and has("error")) then
    {count: 0, results: [], hint: ("codegraph error: " + .error)}
  else {count: length,
    results: [.[] | {name: .node.name, qualified_name: .node.qualifiedName, kind: .node.kind, file: .node.filePath, line: .node.startLine, score}],
    hint: (if length==0 then "no match — broaden the text, drop the -k filter, or fall back to native grep" else null end)}
  end'
