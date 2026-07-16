#!/usr/bin/env bash
# Script uninstall path (reverses install.sh). Optional: --with-hook also
# removes the hook script — mirrors install.sh's own --with-hook flag.
# Without it, the hook script is left in place: it is wired via a manual
# settings.json entry independent of which install method (script or
# /plugin) delivers the skill/agent, so switching methods or reinstalling
# must not silently break an already-configured hook.
set -euo pipefail
WITH_HOOK=0
[ "${1:-}" = "--with-hook" ] && WITH_HOOK=1

rm -rf ~/.claude/skills/cbm-navigator ~/.claude/skills/codegraph-navigator
rm -f ~/.claude/agents/cbm-deep-analyst.md ~/.claude/agents/codegraph-deep-analyst.md
echo "removed: ~/.claude/skills/cbm-navigator + codegraph-navigator (skills), ~/.claude/agents/cbm-deep-analyst.md + codegraph-deep-analyst.md (subagents)"
echo "note: this only reverses a script install (install.sh); a /plugin install is untouched — use 'claude plugin uninstall imars-skills@<marketplace>' for that."

if [ "$WITH_HOOK" = 1 ]; then
  rm -f ~/.claude/hooks/cbm-augment.sh
  echo "removed: ~/.claude/hooks/cbm-augment.sh"
  echo "if you added the PreToolUse entry to ~/.claude/settings.json, remove that entry manually."
else
  echo "hook script left in place (~/.claude/hooks/cbm-augment.sh) since it isn't tied to the skill/agent install method — pass --with-hook to remove it too."
fi
