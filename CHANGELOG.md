# Changelog

## 0.0.9 (2026-07-16)
- Repo housekeeping (file organization review): renumbered the 0.1.x-era
  entries below (0.1.0-0.1.6) to a consistent 0.0.x sequence matching
  `plugin.json` — those versions were never tagged or released (all
  pre-dated the first commit), so renumbering carries no compatibility cost.
- Removed `docs/design.md`: it embedded full code copies (SKILL.md, scripts,
  agent definition) frozen at design time and had drifted from the shipped
  source (still showed the deprecated `--raw` flag and the pre-fix, buggy
  `_project.sh`) — a duplicated, disagreeing source of truth. README +
  CHANGELOG + the real source files under `skills/`/`agents/` are now the
  only source of truth.
- Fixed README install commands (plugin method and script method): both
  referenced a stale repo/marketplace name (`cbm-navigator@cbm-tools`)
  instead of the actual `holyimars/imars-skills` / `imars-skills@imars-skills`.

## 0.0.8 (2026-07-16)
- Fix project-name resolution collision (field-verified): the fuzzy
  `endswith(basename)` fallback in `_project.sh` and the optional hook could
  outrank an exact basename match when an unrelated indexed project happened
  to end with the same basename (e.g. a stale benchmark clone named
  "...-RuoYi-Vue-Plus" silently outranked the real "RuoYi-Vue-Plus" project,
  so every graph query silently answered from the wrong repo). Both scripts
  now try an exact match against the plain basename (the documented `--name`
  override) before falling back to the suffix heuristic, and `_project.sh`
  prints a `warning:` to stderr when the fallback itself is still ambiguous
  (multiple indexed projects share the suffix) instead of silently picking
  one.

## 0.0.7 (2026-07-16)
- Fix cbm-grep.sh (field-verified): search_code requires `pattern`, not
  `query` — the old name failed every call with "pattern is required".
  (`query` was inferred from the README, which does not document
  search_code's parameter names.)
- End-to-end validation recorded: cbm-deep-analyst preloads the skill,
  follows gate check -> decision table, verifies via Read, and returns
  conclusion + evidence + confidence + unverified items; `effort: high`,
  `skills:` and `model: inherit` frontmatter all accepted on the installed
  Claude Code version.

## 0.0.6 (2026-07-16) — field-verified fixes on v0.9.0
- Remove `--raw` from ALL CLI calls: the flag does not exist on the v0.9.0
  release ("unknown tool: --raw") even though the main-branch README shows
  it. Root cause noted: official README tracks main and can be ahead of the
  installed release — calibrate against `--help` and real output.
- Results carry `file_path` and NO line number: jq projections and Cypher
  templates now use `file_path` with `coalesce(...)` compatibility.
- Hook: probe `timeout`/`gtimeout` (macOS ships neither by default; the
  settings-level hook timeout is the backstop).
- Hook settings split into user-level and project-level snippets; the
  project-level command path uses `$CLAUDE_PROJECT_DIR` (hook cwd is not
  guaranteed to be the repo root).
- SKILL.md / agent wording: "file:line" -> "file path".

## 0.0.5 (2026-07-16)
- Docs formatting convention: SKILL.md, blindspots.md, the agent definition,
  and the CLAUDE.md snippet now use one-sentence-per-line breaks (line ends
  at sentence-final punctuation). Sentence-level git diffs for PR review.

## 0.0.4 (2026-07-16)
- Standard index command (field-verified flags): `--name` to pin a portable
  short project name (default derived name is the flattened absolute path —
  machine-specific), `--persistence true` to actually write the team-shared
  artifact (NOT written by default), and a note that semantic search needs
  `--mode full|moderate` (similarity/semantic edges are skipped in fast).
- `_project.sh` "not indexed" hint now prints the recommended flags form.

## 0.0.3 (2026-07-16)
- Fix project-name resolution (field-verified): the graph names projects by
  FLATTENED absolute path (e.g. Users-me-www-my-service), not by repo
  basename. `_project.sh` and the optional hook now match by flattened path
  first, with basename-suffix fallback. Previous versions would falsely
  report "repo not indexed".
- README: document the naming rule and the CLAUDE.md `<PROJECT_NAME>` fill-in.

## 0.0.2 (2026-07-16)
- Migrate all CLI calls from deprecated raw-JSON positional args to piped
  stdin (upstream deprecation warning). All invocations now go through a
  single `cbm_call()` wrapper in `scripts/_project.sh` — future CLI
  interface changes need a one-line fix there only.

## 0.0.1 (2026-07-16)
- Initial release: cbm-navigator skill (8 scripts + blindspots reference),
  cbm-deep-analyst subagent (effort override), optional PreToolUse hook,
  optional project CLAUDE.md snippet, dual install paths (plugin / install.sh).
