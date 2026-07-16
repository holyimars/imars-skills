#!/usr/bin/env bash
# Script install path (alternative to /plugin install): copies the skill and
# subagent to user-global ~/.claude/. Idempotent. Optional: --with-hook
set -euo pipefail
WITH_HOOK=0
[ "${1:-}" = "--with-hook" ] && WITH_HOOK=1
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== cbm-navigator installer (script mode) =="
command -v codebase-memory-mcp >/dev/null || { echo "ERROR: codebase-memory-mcp binary not found. Install it first (--skip-config): https://github.com/DeusData/codebase-memory-mcp"; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq is required."; exit 1; }

mkdir -p ~/.claude/skills ~/.claude/agents
rm -rf ~/.claude/skills/cbm-navigator
cp -r "$HERE/skills/cbm-navigator" ~/.claude/skills/
cp "$HERE/agents/cbm-deep-analyst.md" ~/.claude/agents/
chmod +x ~/.claude/skills/cbm-navigator/scripts/*.sh
echo "installed: ~/.claude/skills/cbm-navigator (skill), ~/.claude/agents/cbm-deep-analyst.md (subagent)"

if [ "$WITH_HOOK" = 1 ]; then
  mkdir -p ~/.claude/hooks
  cp "$HERE/optional/hooks/cbm-augment.sh" ~/.claude/hooks/
  chmod +x ~/.claude/hooks/cbm-augment.sh
  echo "hook script installed: ~/.claude/hooks/cbm-augment.sh"
  echo "NOTE: user-level -> merge optional/settings-hook-user.json into ~/.claude/settings.json (backup first);"
  echo "      project-level -> copy the script to <repo>/.claude/hooks/ and merge optional/settings-hook-project.json"
  echo "      (project-level MUST use \$CLAUDE_PROJECT_DIR in the command path)."
fi

echo "Done. Restart Claude Code, then run the verification checklist in README.md."
