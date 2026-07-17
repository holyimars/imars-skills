#!/usr/bin/env bash
# Optional non-blocking PreToolUse hook: augments Grep/Glob with codegraph
# symbol matches as additionalContext. Self-contained. EVERY failure path
# exits 0. Parallel counterpart to cbm-augment.sh, targeting the codegraph
# CLI (.codegraph/ index) instead of codebase-memory-mcp (.codebase-memory/)
# -- the two are meant to be wired as separate entries in the same
# PreToolUse hooks array (see optional/settings-hook-*.json), each silently
# no-op'ing when its own index product is absent, so a repo indexed by only
# one of the two tools still works with both hooks installed.
# Field-verified (2026-07-17, RuoYi-Vue-Plus): `codegraph query` on an
# unindexed dir prints an ANSI-colored "[ERR] CodeGraph not initialized"
# line to STDOUT with exit code 0 (not stderr, not JSON) -- the upfront
# .codegraph/ existence check below is what keeps this hook off that path
# in normal (dual-hook) operation; the jq-parse `|| exit 0` is the backstop.
# Also field-verified: no-match and regex-special-char patterns both return
# a clean `[]` (query does fuzzy text matching, not regex parsing), and
# `-p "$ROOT"` resolves the target repo explicitly regardless of hook cwd.
INPUT=$(cat) || exit 0
PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null) || exit 0
[ -z "$PATTERN" ] && exit 0
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -d "$ROOT/.codegraph" ] || exit 0
command -v codegraph >/dev/null 2>&1 || exit 0
TMO=""
command -v timeout  >/dev/null 2>&1 && TMO="timeout 2"
command -v gtimeout >/dev/null 2>&1 && TMO="gtimeout 2"
MATCH=$($TMO codegraph query "$PATTERN" -j -l 5 -p "$ROOT" 2>/dev/null \
  | jq -c '[.[] | {name: .node.name, kind: .node.kind, file: .node.filePath}]' 2>/dev/null) || exit 0
{ [ -z "$MATCH" ] || [ "$MATCH" = "[]" ]; } && exit 0
jq -n --argjson m "$MATCH" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  additionalContext: ("Knowledge-graph symbol matches for this pattern: " + ($m|tostring) + " — consider the codegraph-navigator skill for structural follow-ups.")}}'
exit 0
