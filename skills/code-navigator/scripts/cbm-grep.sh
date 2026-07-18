#!/usr/bin/env bash
# Graph-scoped text search (indexed files only). Usage: cbm-grep.sh [-n LIMIT] '<text>'
#
# Field-verified 2026-07-19 on RuoYi-Vue-Plus: search_code's own --help documents
# a default limit of 10 and ships `total_grep_matches`/`total_results` specifically
# so callers can detect truncation (there is NO offset param -- the CLI's own
# guidance is "raise limit or narrow with file_pattern/path_filter"). This script
# used to hardcode limit:20 with no override and threw away both total fields
# entirely -- the identical silent-cap defect already fixed once in cbm-find.sh
# (search_graph) and cg-trace.sh (callers/callees), reproduced here unfixed until
# now. Confirmed live: `cbm-grep.sh 'public class'` on RuoYi-Vue-Plus returned
# exactly 10 of 480 real total_results (500 raw grep hits pre-dedup) with zero
# signal that 470 were hidden.
set -euo pipefail; source "$(dirname "$0")/_project.sh"
LIMIT=20
while getopts "n:" f; do case $f in n) LIMIT=$OPTARG;; esac; done
shift $((OPTIND-1))
_require_positive_int "$LIMIT" "-n/LIMIT"
[ "$#" -ge 1 ] || { echo '{"error":"pattern (positional arg) is required","hint":"usage: cbm-grep.sh [-n LIMIT] <pattern>"}'; exit 2; }
OUT=$(cbm_call search_code "$(jq -n --arg p "$PROJECT" --arg q "$1" --argjson n "$LIMIT" '{project:$p, pattern:$q, limit:$n}')")
echo "$OUT" | jq --arg limit "$LIMIT" 'if (.error != null) then . else {
  count: ((.results // [])|length), totalResults: (.total_results // null), totalGrepMatches: (.total_grep_matches // null),
  results: [(.results // [])[] | {name: (.node // null), qualified_name: (.qualified_name // null), label: (.label // null), file: (.file // null), lines: (.match_lines // null)}],
  hint: (if ((.results // [])|length)==0 then "no match — broaden the pattern, or try cbm-find.sh -s for a semantic search instead"
    elif ((.total_results // 0) > ((.results // [])|length)) then "hit the query limit (\($limit)) — total real matches: \(.total_results // "unknown") (of \(.total_grep_matches // "unknown") raw grep hits before dedup); re-run with -n <higher> (e.g. cbm-grep.sh -n 100 ...) before treating this as a complete list — search_code has no offset param, raising -n is the only way to see more"
    else null end) } end'
