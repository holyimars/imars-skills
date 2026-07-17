#!/usr/bin/env bash
# Usage: cbm-find.sh [-s] [-l LABEL] [-o OFFSET] '<regex-or-question>'
set -euo pipefail; source "$(dirname "$0")/_project.sh"
SEMANTIC=0; LABEL=""; OFFSET=0
while getopts "sl:o:" f; do case $f in s) SEMANTIC=1;; l) LABEL=$OPTARG;; o) OFFSET=$OPTARG;; esac; done
shift $((OPTIND-1)); Q="$1"
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
  ARGS=$(jq -n --arg p "$PROJECT" --argjson kws "$KWS" --argjson o "$OFFSET" '{project:$p, semantic_query:$kws, limit:20, offset:$o}')
else
  ARGS=$(jq -n --arg p "$PROJECT" --arg q "$Q" --argjson o "$OFFSET" '{project:$p, name_pattern:$q, limit:20, offset:$o}')
fi
[ -n "$LABEL" ] && ARGS=$(echo "$ARGS" | jq --arg l "$LABEL" '. + {label:$l}')
OUT=$(cbm_call search_graph "$ARGS")
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
  # the correct tool instead, see SKILL.md / references/blindspots.md.
  echo "$OUT" | jq '{count: (.semantic_results|length),
    results: [.semantic_results[] | {name, qualified_name: (.qualified_name // null), label, file: (.file_path // .file // null), score}],
    hint: (if (.semantic_results|length)==0 then "no match — broaden the query, or fall back to native grep"
      elif (.semantic_results[0].score // 0) < 0.3 then "top score below 0.3 — likely an unreliable/near-random match (field-verified: this happens on ANY Chinese-language query, and on some under-specified English ones); do not trust this result, use cbm-grep.sh (literal text search, handles Chinese Javadoc/comments fine) instead"
      else null end)}'
else
  echo "$OUT" | jq '{count: (.results|length),
    results: [.results[] | {name, qualified_name: (.qualified_name // null), label, file: (.file_path // .file // null), degree: (.degree // null)}],
    hint: (if (.results|length)==0 then "no match — broaden the regex (e.g. .*Name.*), try -s semantic mode (English queries only, see hint above for why), or fall back to native grep" else null end)}'
fi
