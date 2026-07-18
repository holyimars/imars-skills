#!/usr/bin/env bash
# Script install path (alternative to /plugin install): copies the unified
# skill and subagent to user-global ~/.claude/. Idempotent. Optional: --with-hook
set -euo pipefail
WITH_HOOK=0
[ "${1:-}" = "--with-hook" ] && WITH_HOOK=1
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== imars-skills installer (script mode) =="
command -v jq >/dev/null || { echo "ERROR: jq is required."; exit 1; }
command -v codebase-memory-mcp >/dev/null || echo "WARNING: codebase-memory-mcp binary not found — code-navigator's cbm-side scripts will not work until it's installed (--skip-config): https://github.com/DeusData/codebase-memory-mcp"
command -v codegraph >/dev/null || echo "WARNING: codegraph binary not found — code-navigator's cg-side scripts will not work until it's installed: npm i -g @colbymchenry/codegraph"

mkdir -p ~/.claude/skills ~/.claude/agents
# clean up pre-0.0.18 layout (two separate skills/agents, since merged into one)
rm -rf ~/.claude/skills/cbm-navigator ~/.claude/skills/codegraph-navigator
rm -f ~/.claude/agents/cbm-deep-analyst.md ~/.claude/agents/codegraph-deep-analyst.md
rm -rf ~/.claude/skills/code-navigator
cp -r "$HERE/skills/code-navigator" ~/.claude/skills/
cp "$HERE/agents/deep-analyst.md" ~/.claude/agents/
chmod +x ~/.claude/skills/code-navigator/scripts/*.sh
echo "installed: ~/.claude/skills/code-navigator (skill), ~/.claude/agents/deep-analyst.md (subagent)"

if [ "$WITH_HOOK" = 1 ]; then
  mkdir -p ~/.claude/hooks
  cp "$HERE/optional/hooks/cbm-augment.sh" ~/.claude/hooks/
  cp "$HERE/optional/hooks/codegraph-augment.sh" ~/.claude/hooks/
  chmod +x ~/.claude/hooks/cbm-augment.sh ~/.claude/hooks/codegraph-augment.sh
  echo "hook scripts installed: ~/.claude/hooks/cbm-augment.sh + codegraph-augment.sh"
  echo "NOTE: each hook silently no-ops when its own index product (.codebase-memory/ or .codegraph/) is absent from a repo,"
  echo "      so both can be wired together even in a repo indexed by only one of the two tools."
  echo "      user-level -> merge optional/settings-hook-user.json into ~/.claude/settings.json (backup first);"
  echo "      project-level -> copy both scripts to <repo>/.claude/hooks/ and merge optional/settings-hook-project.json"
  echo "      (project-level MUST use \$CLAUDE_PROJECT_DIR in the command path)."
fi

echo "Done. Restart Claude Code, then run the verification checklist in README.md."
