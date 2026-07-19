#!/usr/bin/env bash
# Optional non-blocking PreToolUse hook: augments Grep/Glob AND Bash-run
# grep/git-grep/rg/ag calls with knowledge-graph symbol matches as
# additionalContext. Replaces the old cbm-augment.sh + codegraph-augment.sh
# pair (0.0.27) -- this is now ONE process querying both index products
# (whichever are present) and merging their results into a single
# injection, tagged by which tool(s) found each hit. Self-contained except
# for jq (plus mktemp/git, both near-universal on any dev box). EVERY
# failure path exits 0.
#
# Field-verified fixes carried over from the two predecessor scripts:
# no --raw flag on codebase-memory-mcp v0.9.0; its results use file_path
# (no line); codegraph query on an unindexed dir prints an ANSI "[ERR] ..."
# line to STDOUT with exit 0 (the .codegraph/ existence check below keeps
# normal operation off that path); macOS has no `timeout` (gtimeout probed).
#
# Regexes are kept in variables, never inlined into `[[ =~ ]]` -- macOS's
# bundled bash 3.2 silently treats an inline quoted regex as a literal
# string instead of a pattern.

INPUT=$(cat) || exit 0

# Step 0 -- zero-subprocess coarse filter, before any jq call. Must let
# through BOTH native Grep/Glob calls (tool_name is capitalized JSON text,
# e.g. "tool_name":"Grep") and Bash commands that mention a target command
# in lowercase. Checking only the lowercase forms here would silently drop
# every native Grep/Glob call (case-sensitive match), which is why both
# cases are listed explicitly.
case "$INPUT" in
  *'"Grep"'*|*'"Glob"'*|*grep*|*'rg '*|*'ag '*) ;;
  *) exit 0 ;;
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0

PATTERN=""
case "$TOOL" in
  Grep|Glob)
    PATTERN=$(printf '%s' "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null) || exit 0
    ;;
  Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
    [ -z "$CMD" ] && exit 0

    # Single regex doing three jobs at once: (a) confirm one of the target
    # command names occurs at a real command boundary -- start of string,
    # or right after `;`/`&`/`|` plus optional whitespace -- so a bare word
    # like "grep" inside an unrelated sentence ("ls my grep folder && ...")
    # can't be mistaken for an invocation; (b) skip zero-or-more leading
    # `-flag` tokens; (c) capture the first positional argument, quoted or
    # bare, in left-to-right order. Doing this as ONE combined regex (rather
    # than a separate boundary check + a separate extraction search) matters:
    # two independent regexes can each report success while anchoring to
    # DIFFERENT occurrences of the command name in the string, which would
    # silently extract from an invalid occurrence even though a valid one
    # exists elsewhere in the same command line.
    RE="(^|[;&|])[[:space:]]*(git[[:space:]]+grep|grep|rg|ag)[[:space:]]+((-[^[:space:]]+[[:space:]]+)*)(\"[^\"]*\"|'[^']*'|[^[:space:]\"'-][^[:space:]]*)"
    if [[ "$CMD" =~ $RE ]]; then
      CANDIDATE="${BASH_REMATCH[5]}"
      case "$CANDIDATE" in
        \"*\") CANDIDATE="${CANDIDATE#\"}"; CANDIDATE="${CANDIDATE%\"}" ;;
        \'*\') CANDIDATE="${CANDIDATE#\'}"; CANDIDATE="${CANDIDATE%\'}" ;;
      esac
      # Quality guard: flags that consume a separate value (rg -t ts, grep
      # -m 1) can still be misparsed as the pattern above -- a short and/or
      # all-numeric result is the cheap tell. This doesn't catch every case
      # (e.g. `-t typescript`), which is a documented, accepted gap: worst
      # case is a wrong symbol lookup that degrades to a clean empty result,
      # same cost as the existing "nothing found" path.
      if [ "${#CANDIDATE}" -ge 3 ] && [[ "$CANDIDATE" == *[A-Za-z]* ]]; then
        PATTERN="$CANDIDATE"
      fi
    fi
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$PATTERN" ] && exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

TMO=""
command -v timeout  >/dev/null 2>&1 && TMO="timeout 2"
command -v gtimeout >/dev/null 2>&1 && TMO="gtimeout 2"

# codegraph branch: kicked off in the background first since it has no
# dependency on cbm's project-name resolution, so it runs concurrently
# with cbm's two sequential calls below instead of adding its own time on
# top of them (merging two previously-parallel hook processes into one
# sequential script would otherwise roughly double the worst-case wall
# time against the same hook-level timeout).
# Requires $TMO to be non-empty (a real `timeout`/`gtimeout` wrapper) --
# unlike the old two-script layout, where the single CLI call was the
# whole script's foreground blocking work (so an external hook-timeout
# kill of the parent basically took it down too), this call is now
# backgrounded: with no internal time bound of its own, a hang could in
# theory outlive a killed parent as an orphaned process. Skipping this
# branch entirely when neither timeout binary is available -- rather than
# running it unbounded -- avoids introducing that risk; the repo already
# treats a missing `codegraph` binary or missing `.codegraph/` dir as "this
# side just doesn't run," so treating "can't bound its runtime" the same
# way is consistent, not a loss of coverage beyond what those cases already
# accept.
CGTMP=""
CG_PID=""
if [ -d "$ROOT/.codegraph" ] && command -v codegraph >/dev/null 2>&1 && [ -n "$TMO" ]; then
  CGTMP=$(mktemp 2>/dev/null) || CGTMP=""
  if [ -n "$CGTMP" ]; then
    trap 'rm -f "$CGTMP"' EXIT
    (
      RAW=$($TMO codegraph query "$PATTERN" -j -l 5 -p "$ROOT" 2>/dev/null)
      printf '%s' "$RAW" | jq -c '[.[] | {name: .node.name, kind: .node.kind, file: .node.filePath}]' 2>/dev/null > "$CGTMP"
    ) &
    CG_PID=$!
  fi
fi

# cbm branch: runs in the foreground, unchanged two-step shape (project
# name resolution, then search_graph) -- these two steps are sequentially
# dependent and can't be parallelized against each other.
# Deliberately NOT `|| exit 0` after PROJECT=/MATCH= like the old standalone
# cbm-augment.sh did: an empty PROJECT/MATCH just falls through the `if
# [ -n ... ]` guards below and leaves CBM_JSON at its "[]" default -- no
# `set -e` in this script, so that's safe. An early `exit 0` here would be a
# real bug in the merged script: it would abandon the codegraph query
# already running in the background (CG_PID never waited/merged) even
# though it may already have a usable result. Keep it this way even if it
# looks less "defensive" than the old per-branch fail-fast style.
CBM_JSON="[]"
if command -v codebase-memory-mcp >/dev/null 2>&1; then
  BASE=$(basename "$ROOT")
  FLAT=$(printf '%s' "$ROOT" | sed 's|^[/\\]||; s|[/\\]|-|g')
  PROJECT=$($TMO codebase-memory-mcp cli list_projects 2>/dev/null \
    | jq -r --arg f "$FLAT" --arg b "$BASE" '
        [.projects[]?.name // empty] as $n
        | ( ([$n[] | select(.==$f)] + [$n[] | select(.==$b)])[0]
          // ([$n[] | select(endswith($b))] | first)
          // empty )' 2>/dev/null)
  if [ -n "$PROJECT" ]; then
    MATCH=$(jq -n --arg p "$PROJECT" --arg q "$PATTERN" '{project:$p, name_pattern:$q, limit:5}' \
      | $TMO codebase-memory-mcp cli search_graph 2>/dev/null \
      | jq -c '[.results[]? | {name, file: (.file_path // .file // null)}]' 2>/dev/null)
    [ -n "$MATCH" ] && CBM_JSON="$MATCH"
  fi
fi

CG_JSON="[]"
if [ -n "$CG_PID" ]; then
  wait "$CG_PID" 2>/dev/null
  FROM_FILE=$(cat "$CGTMP" 2>/dev/null)
  [ -n "$FROM_FILE" ] && CG_JSON="$FROM_FILE"
fi

{ [ "$CBM_JSON" = "[]" ] || [ -z "$CBM_JSON" ]; } && { [ "$CG_JSON" = "[]" ] || [ -z "$CG_JSON" ]; } && exit 0

# Merge: dedupe on (name, file), tag each hit with which tool(s) found it.
# A "both" tag -- codegraph's fuzzy full-text match and cbm's exact/regex
# name match independently agreeing on the same symbol -- is a stronger
# signal than either tool alone can produce, and only exists because this
# is now one process able to compare both result sets directly. Ordering:
# "both" first, then codegraph-only and cbm-only interleaved preserving
# each side's own original order, capped at 8 total (below today's worst-
# case 10-row two-injection total, above either tool's solo 5-row cap so
# genuinely complementary recall isn't clipped).
MERGED=$(jq -n --argjson cbm "$CBM_JSON" --argjson cg "$CG_JSON" '
  def key: [.name, .file];
  ($cbm // []) as $cbm |
  ($cg  // []) as $cg  |
  ($cbm | map(key)) as $cbmKeys |
  ($cg  | map(key)) as $cgKeys  |
  ($cg  | map(. + {src: (if (key | IN($cbmKeys[])) then "both" else "cg" end)})) as $cgTagged |
  ($cbm | map(. + {src: "cbm"}) | map(select((key | IN($cgKeys[])) | not))) as $cbmOnly |
  ([$cgTagged[] | select(.src=="both")]) as $both |
  ([$cgTagged[] | select(.src=="cg")]) as $cgOnly |
  ( [range(0; ([$cgOnly, $cbmOnly] | map(length) | max))]
    | map( [ $cgOnly[.], $cbmOnly[.] ] | map(select(. != null)) )
    | add // []
  ) as $interleaved |
  ($both + $interleaved)[0:8]
' 2>/dev/null)

{ [ -z "$MERGED" ] || [ "$MERGED" = "[]" ]; } && exit 0

jq -n --argjson m "$MERGED" '{hookSpecificOutput: {hookEventName: "PreToolUse",
  additionalContext: ("Knowledge-graph symbol matches for this pattern: " + ($m|tostring) + " (src: both = confirmed by exact-name AND full-text matching independently, cg = codegraph only, cbm = codebase-memory-mcp only) — consider the code-navigator skill for structural follow-ups.")}}'
exit 0
