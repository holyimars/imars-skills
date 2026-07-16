# Changelog

## 0.0.11 (2026-07-16)
- Field-verified a full pass of previously-secondhand blind-spot claims against two real indexed
  repos (RuoYi-Vue-Plus backend, plus-ui frontend), triggered by a review of an external chat log
  making limitation claims about codebase-memory-mcp. Verified each claim directly rather than
  trusting the log; results below.
- **Major finding (references/blindspots.md, SKILL.md quality rules — MANDATORY protocol, not an
  edge case)**: Java interface method calls attach their CALLS edge to the interface method node,
  never the implementation method node — reproduced on plain single-impl `IFoo`→`FooImpl` pairs
  (`ISysDeptService`/`SysDeptServiceImpl`, `ISysUserService`/`SysUserServiceImpl`), not just
  multi-impl+`@Primary` cases as previously assumed. Direct A/B trace: interface method returns
  real callers, the exact same logical method queried via the impl class returns 0, silently, no
  error. This is the single most common pattern in a layered Spring codebase, so it is now
  documented as a mandatory cross-check (query both interface and impl method, union the results)
  rather than a soft "may undercount" note. Confirmed the underlying query-side fix is impossible
  with this CLI's Cypher engine (`unsupported EXISTS pattern — only the single-hop form supported`,
  tested directly) — this must be handled by protocol, not by a smarter query.
- **Fixed a real bug in our own `cbm-cypher.sh`**: the `dead-code` template only ever matched the
  `Function` label (449 nodes) and completely skipped `Method` (2163 nodes — i.e. almost every Java
  class method, including every Controller and ServiceImpl method). Added a separate
  `dead-code-methods` subcommand that queries `Method`, with a mandatory stderr warning that
  results for interface-implementing classes are unreliable per the finding above (verified: without
  the warning, running it directly flags `SysMenuController.list/add/edit/remove` and multiple real
  `*ServiceImpl` methods as "dead code" — all false positives, all actively called through their
  interface). Kept the original `dead-code` template unchanged for backward compatibility.
- **Route prefix claim (upstream issue #734) re-tested and NOT reproduced**: class-level
  `@RequestMapping` prefixes were field-verified fully intact across 3 real controllers with nested
  paths and inter-controller path sharing (`SysUserController`/`SysProfileController` both under
  `/system/user`). SKILL.md's blanket "route paths may lack prefixes" warning was overstated —
  updated to state the verified-present result while still noting #734 is genuinely open upstream
  (milestone 0.9.1-rc), so this can vary by project/version.
- **New blind spot found (not previously documented)**: JS/TS dynamic `() => import('...')` route
  lazy-loading (the standard Vue Router / React Router code-splitting pattern) produces NO graph
  edge — verified on plus-ui's `src/router/index.ts`, which dynamically imports 4+ page components
  and shows exactly one `IMPORTS` edge total (the one static import). Added to blindspots.md with a
  grep-the-router-config fallback.
- **New blind spot found**: Spring runtime bean-name lookup (`SpringUtils.getBean(computedName)`,
  e.g. RuoYi-Vue-Plus's `IAuthStrategy` 5-way strategy pattern) is genuinely undecidable statically,
  not a graph gap — documented as its own category with a grep-the-bean-name-pattern fallback.
- **MyBatis XML blind spot**: confirmed as a valid structural inference in general, but this specific
  repo (RuoYi-Vue-Plus) has zero hand-written dynamic SQL — every `*Mapper.xml` is an empty
  namespace shell for MyBatis-Plus auto-registration. Documented that pure MyBatis-Plus repos don't
  actually trigger this blind spot; grep `<if\|<foreach` first before treating it as live.
- **Cross-repo (frontend+backend) analysis**: confirmed the current one-project-per-repo setup
  (verified via `list_projects`: `plus-ui` and `RuoYi-Vue-Plus` are fully independent graphs) is a
  working, deliberate design, not a gap blocking anything — documented that a question spanning both
  repos needs two separate graph calls plus manual correlation, since there's no aggregated
  multi-root graph.
- **Methodology correction**: an earlier research pass cited 5 GitHub issue numbers for
  codebase-memory-mcp limitations (#281, #500, #734, #1033, #1187). Checked all 5 directly: only
  **#734** actually matched its claimed subject (open, milestone 0.9.1-rc). #281 and #1033 pointed
  at unrelated PRs, #500 was an unrelated closed feature request, and #1187 doesn't exist (404).
  Added a standing rule to blindspots.md: never carry forward an issue-sourced claim without opening
  the issue and confirming it says what's claimed.

## 0.0.10 (2026-07-16)
- Fix uninstall.sh (field-verified, hit in practice while switching a real
  install from script mode to `/plugin` mode): it unconditionally deleted
  `~/.claude/hooks/cbm-augment.sh`, even though the hook is wired via a
  manual `settings.json` entry that is independent of which install method
  (script or `/plugin`) delivers the skill/agent. Running the old
  uninstall.sh to clean up a superseded script install silently broke an
  already-configured hook, leaving settings.json pointing at a deleted
  file. Uninstall now mirrors install.sh's own `--with-hook` flag: the hook
  script is left in place by default and only removed when `--with-hook`
  is passed. Output also now clarifies that this script never touches a
  `/plugin`-managed install (use `claude plugin uninstall` for that).

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
