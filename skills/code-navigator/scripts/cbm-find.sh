#!/usr/bin/env bash
# Usage: cbm-find.sh [-s] [-l LABEL] [-o OFFSET] [-n LIMIT] '<regex-or-question>'
#
# Field-verified 2026-07-20 on RuoYi-Vue-Plus: `search_graph`'s own --help
# documents a default limit of 200 and ships `total`/`has_more` specifically
# so callers can detect truncation and page through results. This script
# used to hardcode limit:20 (LOWER than the CLI's own default) and then
# rebuilt its output object without ever passing `total`/`has_more` through
# -- so a query with more real matches than 20 was silently capped with zero
# signal, the identical failure shape to the cg-trace.sh silent-cap bug
# fixed in code-navigator 0.0.21. Confirmed live: `cbm-find.sh -l Route
# '.*'` returned exactly 20 results with no indication that the real total
# is 303. Fixed: default limit raised to 200 (still overridable with -n),
# and has_more/total now flow into the hint.
set -euo pipefail; source "$(dirname "$0")/_project.sh"
SEMANTIC=0; LABEL=""; OFFSET=0; LIMIT=200
while getopts "sl:o:n:" f; do case $f in s) SEMANTIC=1;; l) LABEL=$OPTARG;; o) OFFSET=$OPTARG;; n) LIMIT=$OPTARG;; esac; done
shift $((OPTIND-1))
[ "$#" -ge 1 ] || { echo '{"error":"query (positional arg) is required","hint":"usage: cbm-find.sh [-s] [-l LABEL] [-o OFFSET] [-n LIMIT] <regex-or-question>"}'; exit 2; }
Q="$1"
_require_positive_int "$LIMIT" "-n/LIMIT"
_require_positive_int "$OFFSET" "-o/OFFSET"
if [ "$SEMANTIC" = 1 ]; then
  # Field-verified 2026-07-17: `search_graph`'s `semantic_query` MUST be a JSON
  # array of keyword strings (CLI help: "MUST be an ARRAY ... NOT a single
  # string"). Sending it as a plain string (the old behavior here) does NOT
  # error — it silently returns near-random results indistinguishable from a
  # real answer: a single English string ("dict label") scored ~0.03 with
  # irrelevant hits, the equivalent array (["dict","label"]) scored ~0.97 with
  # exactly-right hits, same repo, same query text. Fix: split on whitespace
  # into keywords, matching the CLI's own example shape.
  KWS=$(printf '%s' "$Q" | jq -R '[splits("[ \t]+")] | map(select(length>0))')
  ARGS=$(jq -n --arg p "$PROJECT" --argjson kws "$KWS" --argjson o "$OFFSET" --argjson n "$LIMIT" '{project:$p, semantic_query:$kws, limit:$n, offset:$o}')
else
  ARGS=$(jq -n --arg p "$PROJECT" --arg q "$Q" --argjson o "$OFFSET" --argjson n "$LIMIT" '{project:$p, name_pattern:$q, limit:$n, offset:$o}')
fi
[ -n "$LABEL" ] && ARGS=$(echo "$ARGS" | jq --arg l "$LABEL" '. + {label:$l}')
OUT=$(cbm_call search_graph "$ARGS")
# Code-review finding (2026-07-21): both branches below used to reconstruct a
# brand-new output object unconditionally and iterate `.results[]` /
# `.semantic_results[]` with no `// []` guard. On a `cbm_call()` error object
# (missing both keys entirely) that iteration crashes jq ("Cannot iterate
# over null"), which under `set -euo pipefail` killed the whole script with
# zero output — reintroducing, one layer downstream, the exact "silent
# crash" defect this same round's cbm_call() fix was built to eliminate.
# Every branch now passes `.error` straight through untouched instead of
# reshaping it away, and guards the iteration regardless.
if [ "$SEMANTIC" = 1 ]; then
  # Semantic hits live in `.semantic_results` (with a `score`), a SEPARATE
  # field from `.results` — reading `.results` here (the old behavior) shows
  # an unrelated, unranked dump of arbitrary graph nodes instead.
  # Field-verified 2026-07-17: even with the array fix above, the underlying
  # embedding model does not support Chinese query text — a Chinese phrase,
  # split or not, scores ~0.02-0.03 (same near-random range as the string bug)
  # regardless of relevance, while English keyword arrays reliably score
  # ~0.9+ on a true match. This is a model limitation, not fixable here — the
  # low-score hint below is the only mitigation; for Chinese business terms,
  # `cbm-grep.sh` (literal text search over source incl. Chinese Javadoc) is
  # the correct tool instead, see SKILL.md / references/tool-divergence.md.
  # The score-too-low and hit-the-limit conditions are NOT mutually
  # exclusive (a truncated result can also score badly) — collect whichever
  # apply via join_warnings() (_hint.jq, shared with cg-trace.sh) instead of
  # an elif chain that silently drops one.
  HINTDEFS=$(cat "$(dirname "$0")/_hint.jq")
  echo "$OUT" | jq --arg limit "$LIMIT" "$HINTDEFS"'if (.error != null) then . else {
    count: ((.semantic_results // [])|length), total: (.total // null), hasMore: (.has_more // false),
    results: [(.semantic_results // [])[] | {name, qualified_name: (.qualified_name // null), label, file: (.file_path // .file // null), score}],
    hint: (if ((.semantic_results // [])|length)==0 then "no match — broaden the query, or fall back to native grep"
      else join_warnings([
          (if ((.semantic_results[0].score // 0) < 0.3) then "top score below 0.3 — likely an unreliable/near-random match (field-verified: this happens on ANY Chinese-language query, and on some under-specified English ones); do not trust this result, use cbm-grep.sh (literal text search, handles Chinese Javadoc/comments fine) instead" else empty end),
          (if (.has_more // false) then "hit the query limit (\($limit)) — total real matches: \(.total // "unknown"); re-run with -n <higher> (e.g. cbm-find.sh -s -n 500 ...) or page with -o, before treating this as a complete list" else empty end)
        ]) end) } end'
else
  echo "$OUT" | jq --arg limit "$LIMIT" 'if (.error != null) then . else {
    count: ((.results // [])|length), total: (.total // null), hasMore: (.has_more // false),
    results: [(.results // [])[] | {name, qualified_name: (.qualified_name // null), label, file: (.file_path // .file // null), degree: (.degree // null)}],
    hint: (if ((.results // [])|length)==0 then "no match — broaden the regex (e.g. .*Name.*), try -s semantic mode (English queries only, see hint above for why), or fall back to native grep"
      elif (.has_more // false) then "hit the query limit (\($limit)) — total real matches: \(.total // "unknown"); re-run with -n <higher> (e.g. cbm-find.sh -n 500 ...) or page with -o, before treating this as a complete list"
      else null end) } end'
fi
