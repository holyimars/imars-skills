#!/usr/bin/env bash
set -euo pipefail
rm -rf ~/.claude/skills/cbm-navigator
rm -f ~/.claude/agents/cbm-deep-analyst.md ~/.claude/hooks/cbm-augment.sh
echo "removed skill, subagent, and hook script. If you added the hook to ~/.claude/settings.json, remove that entry manually."
