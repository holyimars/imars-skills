#!/usr/bin/env bash
# Optional non-blocking PreToolUse hook: augments Grep/Glob with graph symbol
# matches as additionalContext. Self-contained. EVERY failure path exits 0.
# Field-verified fixes: no --raw flag on v0.9.0; results use file_path (no
# line); macOS has no `timeout` (coreutils gtimeout probed, else no timeout —
# the settings-level hook timeout is the backstop).
INPUT=$(cat) || exit 0
PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null) || exit 0
[ -z "$PATTERN" ] && exit 0
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
BASE=$(basename "$ROOT")
FLAT=$(printf '%s' "$ROOT" | sed 's|^[/\\]||; s|[/\\]|-|g')
TMO=""
command -v timeout  >/dev/null 2>&1 && TMO="timeout 2"
command -v gtimeout >/dev/null 2>&1 && TMO="gtimeout 2"
PROJECT=$($TMO codebase-memory-mcp cli list_projects 2>/dev/null \
  | jq -r --arg f "$FLAT" --arg b "$BASE" '
      [.projects[]?.name // empty] as $n
      | ( ([$n[] | select(.==$f)] + [$n[] | select(.==$b)])[0]
        // ([$n[] | select(endswith($b))] | first)
        // empty )' 2>/dev/null) || exit 0
[ -z "$PROJECT" ] && exit 0
MATCH=$(jq -n --arg p "$PROJECT" --arg q "$PATTERN" '{project:$p, name_pattern:$q, limit:5}' \
  | $TMO codebase-memory-mcp cli search_graph 2>/dev/null \
  | jq -c '[.results[]? | {name, file: (.file_path // .file // null)}]' 2>/dev/null) || exit 0
{ [ -z "$MATCH" ] || [ "$MATCH" = "[]" ]; } && exit 0
jq -n --argjson m "$MATCH" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  additionalContext: ("Knowledge-graph symbol matches for this pattern: " + ($m|tostring) + " — consider the code-navigator skill for structural follow-ups.")}}'
exit 0
