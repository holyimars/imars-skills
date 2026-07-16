#!/usr/bin/env bash
# Usage: cbm-find.sh [-s] [-l LABEL] [-o OFFSET] '<regex-or-question>'
set -euo pipefail; source "$(dirname "$0")/_project.sh"
SEMANTIC=0; LABEL=""; OFFSET=0
while getopts "sl:o:" f; do case $f in s) SEMANTIC=1;; l) LABEL=$OPTARG;; o) OFFSET=$OPTARG;; esac; done
shift $((OPTIND-1)); Q="$1"
if [ "$SEMANTIC" = 1 ]; then
  ARGS=$(jq -n --arg p "$PROJECT" --arg q "$Q" --argjson o "$OFFSET" '{project:$p, semantic_query:$q, limit:20, offset:$o}')
else
  ARGS=$(jq -n --arg p "$PROJECT" --arg q "$Q" --argjson o "$OFFSET" '{project:$p, name_pattern:$q, limit:20, offset:$o}')
fi
[ -n "$LABEL" ] && ARGS=$(echo "$ARGS" | jq --arg l "$LABEL" '. + {label:$l}')
OUT=$(cbm_call search_graph "$ARGS")
echo "$OUT" | jq '{count: (.results|length),
  results: [.results[] | {name, qualified_name: (.qualified_name // null), label, file: (.file_path // .file // null), degree: (.degree // null)}],
  hint: (if (.results|length)==0 then "no match — broaden the regex (e.g. .*Name.*), try -s semantic mode, or fall back to native grep" else null end)}'
