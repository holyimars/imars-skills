#!/usr/bin/env bash
# Script uninstall path (reverses install.sh). Optional: --with-hook also
# removes the hook scripts — mirrors install.sh's own --with-hook flag.
# Without it, the hook scripts are left in place: they are wired via manual
# settings.json entries independent of which install method (script or
# /plugin) delivers the skill/agent, so switching methods or reinstalling
# must not silently break an already-configured hook.
set -euo pipefail
WITH_HOOK=0
[ "${1:-}" = "--with-hook" ] && WITH_HOOK=1

rm -rf ~/.claude/skills/code-navigator
rm -f ~/.claude/agents/deep-analyst.md
# also clean up any pre-0.0.18 layout left over from an older install
rm -rf ~/.claude/skills/cbm-navigator ~/.claude/skills/codegraph-navigator
rm -f ~/.claude/agents/cbm-deep-analyst.md ~/.claude/agents/codegraph-deep-analyst.md
echo "removed: ~/.claude/skills/code-navigator (skill), ~/.claude/agents/deep-analyst.md (subagent)"
echo "note: this only reverses a script install (install.sh); a /plugin install is untouched — use 'claude plugin uninstall imars-skills@<marketplace>' for that."

if [ "$WITH_HOOK" = 1 ]; then
  # also clean up any pre-0.0.27 layout (two separate hook scripts) left over from an older install
  rm -f ~/.claude/hooks/cbm-augment.sh ~/.claude/hooks/codegraph-augment.sh
  rm -f ~/.claude/hooks/code-navigator-augment.sh
  echo "removed: ~/.claude/hooks/code-navigator-augment.sh"
  echo "if you added the PreToolUse entry to ~/.claude/settings.json, remove it manually."
else
  echo "hook script left in place (~/.claude/hooks/code-navigator-augment.sh) since it isn't tied to the skill/agent install method — pass --with-hook to remove it too."
fi
