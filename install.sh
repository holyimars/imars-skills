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
  # clean up pre-0.0.27 layout (two separate hook scripts, since merged into one)
  rm -f ~/.claude/hooks/cbm-augment.sh ~/.claude/hooks/codegraph-augment.sh
  cp "$HERE/optional/hooks/code-navigator-augment.sh" ~/.claude/hooks/
  chmod +x ~/.claude/hooks/code-navigator-augment.sh
  echo "hook script installed: ~/.claude/hooks/code-navigator-augment.sh"
  echo "NOTE: queries whichever index product(s) are present (.codebase-memory/ and/or .codegraph/), silently"
  echo "      no-ops on either side that's absent, and merges both tools' results into one injection when both hit."
  echo "      user-level -> merge optional/settings-hook-user.json into ~/.claude/settings.json (backup first);"
  echo "      project-level -> copy the script to <repo>/.claude/hooks/ and merge optional/settings-hook-project.json"
  echo "      (project-level MUST use \$CLAUDE_PROJECT_DIR in the command path)."
  echo "      If you previously wired the two old hook entries by hand in settings.json, replace them with the"
  echo "      single new entry above — this installer only manages the script files, not your settings.json."
fi

echo "Done. Restart Claude Code, then run the verification checklist in README.md."
