#!/usr/bin/env bash
# Usage: cg-find.sh [-k kind] [-l limit] '<name-or-fuzzy-text>'
set -euo pipefail; source "$(dirname "$0")/_gate.sh"
KIND=""; LIMIT=20
while getopts "k:l:" f; do case $f in k) KIND=$OPTARG;; l) LIMIT=$OPTARG;; esac; done
shift $((OPTIND-1)); Q="$1"

ARGS=(query "$Q" -j -l "$LIMIT")
[ -n "$KIND" ] && ARGS+=(-k "$KIND")

OUT=$(cg_call "${ARGS[@]}")
echo "$OUT" | jq 'if (type=="object" and has("error")) then
    {count: 0, results: [], hint: ("codegraph error: " + .error)}
  else {count: length,
    results: [.[] | {name: .node.name, qualified_name: .node.qualifiedName, kind: .node.kind, file: .node.filePath, line: .node.startLine, score}],
    hint: (if length==0 then "no match — broaden the text, drop the -k filter, or fall back to native grep" else null end)}
  end'
