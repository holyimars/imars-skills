# Changelog

## 0.0.13 (2026-07-17)
- **Second round of head-to-head field verification against `cbm-navigator`, this time targeting whole-graph aggregate questions (dead code, hubs/god-classes, routes list) rather than single-symbol lookups** — see `skills/codegraph-navigator/references/blindspots.md` for full repro output.
- **Critical finding: `cg-explore.sh` fails SILENTLY, not loudly, on aggregate questions.** Asked to find dead code, it matched the word "find" in the question against method names like `findFirst`/`findAny` and returned them — each with real callers, formatted with the same confident "Blast radius"/⚠️ styling as a correct answer. Asked for "hubs", it returned near-random low-connectivity symbols. Asked for "list all routes", it matched controller methods literally named `list` and surfaced zero actual route paths. Root cause: `explore` is keyword/semantic retrieval over symbol names + source, not a graph-analytics engine — there is no call-degree, zero-callers, or kind-count-and-sort capability anywhere in the `codegraph` CLI (confirmed against `codegraph --help`: no `stats`/`hubs`/`unused` command exists).
  `SKILL.md`'s decision table and Quality rules now explicitly forbid `cg-explore.sh` for this question shape and route it to `cbm-cypher.sh` (if this repo is also indexed by codebase-memory-mcp) or native grep instead — previously the skill suggested `cg-explore.sh` as a plausible fallback here, which was actively bad advice.
- **Correction: "routes list" was wrongly marked "no direct equivalent" — it has one.** `codegraph query '' -k route -j -l 500` (empty pattern + kind filter) returned exactly 303 results, an EXACT match against `codegraph status -j`'s `nodesByKind.route` — same exact-match verification repeated for `-k class` (482/482) and, on plus-ui, `-k component` (99/99). Each route result's `name` includes the real HTTP verb (`"DELETE /auth/unlock/{socialId}"`), arguably more precise than `cbm-cypher.sh routes`'s path-only Cypher template. `SKILL.md`'s decision table now documents this as the correct tool for exhaustive kind listings, separate from fuzzy-text `cg-find.sh` searches.
- **Two bugs in `cg-find.sh` found and fixed while confirming the above:**
  - Omitting the search pattern entirely (`cg-find.sh -k route`, the natural way to ask "list all routes") crashed with `line 6: $1: unbound variable` under `set -u`. Fixed: `Q="${1:-}"`.
  - Once unblocked, the default limit (20) silently under-returned for empty-pattern kind listings: codegraph's own `-l` behaves like a per-file/group multiplier (not a literal cap) specifically when the search pattern is empty — field-verified `-l 1/3/5` returning `5/15/25` rows on the same repo. `cg-find.sh` now defaults `-l` to 500 when the pattern is empty (still 20 for normal fuzzy search) so "list all X" actually returns everything by default instead of a silently-truncated ~1/15th of it.
- `cbm-navigator`'s own SKILL.md/scripts were NOT modified in this release — only its findings were used as the comparison baseline.

## 0.0.12 (2026-07-16)
- **New: `codegraph-navigator` skill + `codegraph-deep-analyst` subagent** — a second, fully
  independent integration parallel to `cbm-navigator`, wrapping the competing
  [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) CLI (v1.4.1, installed via
  `npm i -g @colbymchenry/codegraph`, never `codegraph install` — that subcommand writes MCP config
  and was deliberately never run). Triggered by a head-to-head field verification against the same
  two repos (RuoYi-Vue-Plus, plus-ui) already used to verify codebase-memory-mcp's blind spots.
- **Verified comparison (see `skills/codegraph-navigator/references/blindspots.md` for full
  evidence)**: codegraph's graph carries an actual interface→impl edge, surfaced by `node`/`explore`
  as `[dynamic: interface → impl @file:line]` labels — `explore` in particular returns both the
  interface's real callers AND the impl's blast radius in one call, something cbm-navigator cannot
  do without a manual mandatory cross-check. The underlying `callers` command is still single-hop
  though: querying an `*Impl` method returns exactly one "caller" that is actually the interface's
  own declaration line, not a real business caller — easy to misread if you skip the labeled tools.
  Dynamic `() => import('...')` route lazy-loading and MyBatis XML mapper `namespace=` binding
  reproduce as blind spots on codegraph IDENTICALLY to codebase-memory-mcp — neither tool models
  these. Spring runtime `getBean(computedName)` strategy dispatch: codegraph fans out to ALL
  implementing classes as dynamic-dispatch candidates (honest but imprecise — it doesn't know it's
  a runtime string selection, it just reuses the same interface/impl heuristic).
- **`cg-trace.sh` auto-bridges the single-hop `callers` gap** (a capability codebase-memory-mcp's
  Cypher engine cannot support — confirmed in 0.0.11 that its nested-EXISTS query is rejected
  outright): when a direct `callers` result contains an entry whose name matches the queried
  method's own short name (the fingerprint of an interface-declaration bridge hop), the script
  re-resolves that entry to an exact `qualifiedName` via `codegraph query`, re-queries its callers,
  and unions the results with a `bridged: true` flag. Field-verified on two independent
  interface/impl pairs (`ISysDeptService`/`SysDeptServiceImpl`, `ISysUserService`/
  `SysUserServiceImpl`) and confirmed to correctly NOT trigger when querying the interface side
  directly (which already has real callers).
- **Fixed a bug found while building `cg-arch.sh`**: merging `codegraph status -j` and `codegraph
  files -j --max-depth N` via jq `--argjson` crashed with "Argument list too long" on a 709-file
  repo (125KB of JSON exceeds this environment's shell argv limit) — switched to writing both to
  temp files and reading via `--slurpfile`, and capped the returned file tree to 60 entries with a
  `treeTruncated` flag (token-discipline parity with cbm-navigator's existing result-limit rules).
- New scripts (`skills/codegraph-navigator/scripts/`): `_gate.sh` (hard-stops if `.codegraph/` is
  missing, warns on tiny repos and stale index via `pendingChanges`), `cg-find.sh`, `cg-trace.sh`,
  `cg-impact.sh`, `cg-node.sh`, `cg-explore.sh` (the flagship one-shot tool), `cg-arch.sh`,
  `cg-affected.sh` (wraps `codegraph affected` — a capability codebase-memory-mcp does not have:
  changed source files → the test files that cover them).
- `install.sh`/`uninstall.sh` now install/remove both skill+agent pairs; the previous hard
  `command -v codebase-memory-mcp || exit 1` check is now a soft per-CLI warning (for
  `codebase-memory-mcp` and `codegraph` independently) since a user may reasonably want only one of
  the two integrations — `jq` remains a hard requirement for both.
- README restructured around the two independent integrations (shared intro/component table, then
  cbm-navigator-specific and codegraph-navigator-specific prerequisites/self-test/known-boundaries
  sections), plus a new head-to-head "工具选型对比" table summarizing the verified findings above.
- **Code-review fixes to the codegraph-navigator scripts above (found via `/code-review-expert`,
  reproduced against the live `.codegraph/` indices, fixed before this release ever shipped):**
  - `codegraph callers/callees/impact` report "symbol not found" via **exit code 0** plus a
    non-JSON, ANSI-colored message on **stdout** (not stderr) — the opposite of what
    `2>/dev/null || echo '<fallback>'` guards against. `cg-trace.sh`/`cg-impact.sh` were piping that
    raw text straight into `jq`, crashing with `jq: parse error: Invalid numeric literal` instead of
    returning the documented `hint` field, on the single most-anticipated failure mode (a mistyped
    exact symbol name). Fixed by adding a shared `cg_call()` helper in `_gate.sh` that validates
    stdout with `jq empty` (not a `{`/`[` prefix check — codegraph's own message text starts with a
    literal `[i]` icon that would false-positive that check) and synthesizes a structured
    `{"error", "exitCode"}` object on failure; adopted by `cg-find.sh`, `cg-trace.sh`,
    `cg-impact.sh`, and `cg-arch.sh`'s two subcalls.
  - `cg-trace.sh`'s auto-bridge (see above) silently failed to trigger — with `bridged: false` and
    `hint: null`, i.e. no warning at all — when given the exact `qualified_name` that `cg-find.sh`
    itself recommends copying, because its short-name extraction (`${NAME##*.}`) split on the last
    `.` and landed inside the package prefix instead of at the `::` qualifiedName separator. This
    reproduced the exact interface/impl blind spot the whole skill exists to fix, on the documented
    happy path. Fixed to split on `::` first when present, falling back to `.` only for the plain
    `ClassName.methodName` shorthand; re-verified both formats now bridge identically on both
    field-tested pairs.
  - See `skills/codegraph-navigator/references/blindspots.md`'s "Code-review note (2026-07-17)" for
    the full repro.
- `cbm-navigator`'s own SKILL.md/scripts/blindspots.md were NOT modified in this release — this is
  purely additive.

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
