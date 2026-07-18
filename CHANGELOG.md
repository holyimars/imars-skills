# Changelog

## 0.0.18 (2026-07-18)
- **Merged `cbm-navigator` and `codegraph-navigator` into a single unified skill, `code-navigator`, plus a single `deep-analyst` subagent, a single CLAUDE.md snippet, and a new LSP collaboration protocol — a user-requested architectural change, motivated by a real bug an audit of every file in this repo turned up this same session:**
  - **The bug: the two CLAUDE.md snippets were the only ALWAYS-loaded guidance layer, and each unconditionally said "invoke [my skill] FIRST" for structural questions with zero cross-reference to the other.** That is a literal contradiction at the layer read before either skill is even invoked. The actual arbitration logic (accuracy > tokens > speed; prefer codegraph for single-symbol questions; prefer cbm for whole-graph aggregate questions codegraph has no equivalent for) only existed inside each SKILL.md's own "both present" gate-check step — reachable only after a skill was already invoked. The fix is structural: one skill, one decision table, one CLAUDE.md snippet, so there is nothing left to contradict.
  - **New: a `code-navigator` decision table organized by QUESTION SHAPE rather than by tool** — each row names a priority-ordered fallback chain across whatever is actually installed (codegraph script > cbm script > native grep, or the reverse, depending on the row), with the "both installed" arbitration baked directly into the table instead of living one layer deeper than the always-loaded snippet. Several rows are new splits that the two old, separate decision tables didn't have: symbol-anchored vs. diff-anchored impact analysis (`cg-impact.sh` vs. `cbm-impact.sh`, genuinely complementary, not alternatives), and dead-code/hubs/cross-layer pulled apart into three rows each with its own false-positive/false-negative caveat instead of one blended "aggregate questions" row.
  - **New, field-verified this session: Claude Code's own LSP tool (`findReferences`, `goToDefinition`, etc.) was tested against both dogfood repos and found to have NO language server configured for either language** — `findReferences` on a `.java` file returned `"No LSP server available for file type: .java"`; `documentSymbol` on a `.ts` file returned `"typescript-language-server not found or is in an unsafe location"`. Because of this, LSP is deliberately placed nowhere near the head of any decision-table row — it is documented (`references/lsp-and-native-fallbacks.md`) purely as an opportunistic corroboration layer for single-symbol questions, tried once when relevant and silently dropped on any "not available"/"not found" error. What LSP would provide if a server were configured (expected: compiler-level receiver-type accuracy, no Lombok-getter collision) is explicitly labeled untested design speculation, not a field-verified finding, until a future session actually has a working language server to test against.
  - **`SpringUtils.getBean(X.class)` — a deterministic single-target Spring bean lookup — was re-characterized more precisely while merging the two tools' blindspots pages**: codegraph is confirmed fully blind to this call shape (0/2 recall on two real call sites); codebase-memory-mcp's name-only edge resolution can incidentally surface these same call sites, but mixed into unrelated noise, so its apparent "catch" cannot be relied on either. The decision table's "who calls X" row now states this asymmetry explicitly instead of the old, less precise "shared blind spot" framing, and makes the standing `grep SpringUtils.getBean(<Interface>.class)` spot-check mandatory regardless of which graph tool produced the count being reported.
  - **File structure**: `skills/cbm-navigator/` and `skills/codegraph-navigator/` are gone, replaced by `skills/code-navigator/` — the same 16 query scripts (`cbm-*.sh` ×8, `cg-*.sh` ×8, plus `_project.sh`/`_gate.sh`) moved in with zero logic changes, only text-level redirects in comments/hints/warnings that pointed at the old skill names or the old `references/blindspots.md` path (now `cbm-blindspots.md` / `codegraph-blindspots.md`, siblings under one skill, cross-references between them updated to match); a new `references/lsp-and-native-fallbacks.md` holds the LSP protocol plus the consolidated "blind on both tools, native grep only" list (MyBatis XML binding, Vue/React dynamic `import()`, computed Spring bean names, `extends` direction). `agents/cbm-deep-analyst.md` + `agents/codegraph-deep-analyst.md` are gone, replaced by `agents/deep-analyst.md`. `optional/CLAUDE.md.codegraph.snippet` is gone; `optional/CLAUDE.md.snippet` is now the one unified snippet (still carries the `<PROJECT_NAME>` line, needed only when the cbm-side index is present). No backward-compatible aliases for any of the old names — this is a personal/small-team repo with no third-party consumers of the old skill/agent names.
  - **Hooks were deliberately NOT merged.** `optional/hooks/cbm-augment.sh` and `codegraph-augment.sh` remain two independent, non-blocking PreToolUse scripts — each still gates on its own index product and coexists with the other exactly as before; only their `additionalContext` closing sentence was retargeted to say "consider the `code-navigator` skill" (previously two different names, now byte-identical). Cross-hook deduplication would need shared state between two isolated processes for a best-effort, ≤5-row, non-blocking hint — judged as over-engineering. The real cost of keeping them separate (up to two symbol-match injections per Grep/Glob on a dual-indexed repo) is now stated plainly in README, along with the option to wire only `codegraph-augment.sh` for token-sensitive setups.
  - `install.sh`/`uninstall.sh` updated to the single `skills/code-navigator` + `agents/deep-analyst.md` layout, with an added cleanup step removing any pre-0.0.18 `cbm-navigator`/`codegraph-navigator`/`cbm-deep-analyst`/`codegraph-deep-analyst` leftovers from a prior install. `README.md` restructured around the one skill (component table, install self-test checklist, known-boundaries sections, and the tool-comparison table all updated); the comparison table gained an LSP row stating plainly that it's untested in this environment.
  - This plan was independently reviewed by a second model (Fable 5) before implementation, which caught and fixed three problems in the original draft: LSP had been placed at the head of the "who calls X" chain with an unearned "no false positives" claim (moved to corroboration-only); several scripts' comments/hints referencing the old skill names and the old shared `references/blindspots.md` path had been missed entirely (now covered); and the `SpringUtils.getBean(X.class)` characterization above was tightened from "both tools blind" to the more accurate asymmetric description.

## 0.0.17 (2026-07-18)
- **Fourth round of field verification, this time on `codegraph-navigator` specifically to empirically confirm/refute the suitable-use and limited-use scenarios drafted from web research (official docs, GitHub issues) — direct CLI execution, not codegraph-navigator's own scripts.** Found 3 new, previously undocumented accuracy gaps, 1 new operational gap, 1 new install-environment gap, and confirmed 1 genuine strength relative to `cbm-navigator`:
  - **New: `cg-explore.sh` — the tool's own flagship "ask in plain language, one call" command and the only MCP tool enabled by default per its official README — returns "No relevant code found" on EVERY pure-Chinese-language query tested (4 independent business terms), even though the exact same term hits correctly via the underlying FTS search `cg-find.sh` wraps.** A query mixing one Latin identifier with Chinese words works fine; a pure-Chinese phrase does not, suggesting `explore`'s query parser requires a Latin/identifier-shaped anchor token. Worse than the already-documented aggregate-question failure mode (wrong-shaped but visible output) because there's nothing to sanity-check. `SKILL.md`'s decision table now splits the compound/exploratory-question row by term language, mirroring `cbm-navigator`'s existing Chinese/English split.
  - **New: `SpringUtils.getBean(X.class).method(...)` — a deterministic single-target bean lookup, not the already-documented computed-bean-name fan-out case — is completely invisible to `callers`/`node`/`impact`.** Confirmed 0/2 recall on two real call sites reaching `DictService.getDictLabel` this way; the gap propagates directly into `cg-impact.sh`'s blast radius, producing a false "safe to change" read on a method with real callers the tool didn't count. Distinct from and worse than the existing `getBean(computedName)` finding, which at least surfaces an honest (if imprecise) fan-out — this shape surfaces nothing.
  - **New: class `extends` relationships are one-directional in the graph — querying a subclass never reveals its parent, only the reverse.** `codegraph node <Parent>` lists subclasses (mislabeled under `Called by ←`); `codegraph node <Child>` has no `extends`/`superclass` field anywhere, confirmed at the JSON schema level. Matches open upstream issue [colbymchenry/codegraph#1328](https://github.com/colbymchenry/codegraph/issues/1328) exactly.
  - **New operational finding: on Windows, a full `codegraph index --force` hard-fails (`EPERM: database file is in use`) if literally any other `codegraph` process — even a read-only `query` — has the DB open concurrently**, a broader trigger than upstream issue [#1325](https://github.com/colbymchenry/codegraph/issues/1325)'s "MCP server running" scenario. Confirmed the failure aborts cleanly with no index corruption; `codegraph sync` (the normal incremental path) was not observed to have the same problem.
  - **New install-environment finding: `install.sh` cannot run under Git Bash (MINGW64) on Windows at all — confirmed by reading the script's source, not just citing the issue.** Its OS-detection `case` statement only handles `Darwin`/`Linux`; every other `uname -s` value, including the exact MINGW64 string Git Bash reports, falls into an `unsupported OS; exit 1` branch. Matches open upstream issue [#1294](https://github.com/colbymchenry/codegraph/issues/1294) byte-for-byte against this machine's own `uname -s` output. Not a blocker in practice — `README.md`'s install instructions already use the unaffected `npm i -g` path — but documented so nobody "fixes" a working npm setup by switching to `install.sh` on Windows.
  - **Confirmed strength, direct contrast with `cbm-navigator`'s documented 60% false-positive rate: codegraph's CALLS edges are receiver/type-qualified, with no Lombok getter/setter name-collision problem.** Ran the identical `getDictLabel`-name-collision scenario cbm-navigator's blindspots.md documents (business interface method vs. 4 unrelated Lombok-generated getters) — codegraph resolved all of them correctly with zero cross-pollution in either direction.
  - `README.md`'s codegraph install notes, "已知边界" bullet list, and "工具选型对比" table all updated with the above; `SKILL.md`'s Decision table, Quality rules, and Gate check (Freshness item, re: concurrent `index`) updated to route around the new gaps.

## 0.0.16 (2026-07-17)
- **`cbm-find.sh -s` (this skill's dedicated tool for Chinese business-term questions, per its own decision table) had never been executed end-to-end before this pass — same gap that produced the `cbm-cypher.sh` bugs in 0.0.15/0.0.14. Found and fixed 2 real bugs, plus documented a third issue that is NOT fixable in the script:**
  - **Bug 1: `semantic_query` was sent as a plain JSON string, not the array the CLI's own `--help` requires** (`--semantic-query <array> ... MUST be an ARRAY of keyword strings ... NOT a single string`). This does not error — it silently returns near-random results: the English string `"dict label"` scored top hit ~0.03 with irrelevant results, the equivalent array `["dict","label"]` scored ~0.97 on exactly the right hits, same query text, same repo. Fixed by splitting the query on whitespace into a JSON array before calling.
  - **Bug 2: the script's formatter read `.results`, but semantic hits live in a separate `.semantic_results` field** — `.results` for a `semantic_query` call turned out to be an unranked dump of arbitrary graph nodes (repo config files, `.gitattributes`, etc.), nothing to do with the query; the real ranked hits were sitting untouched in `.semantic_results`. Fixed to read the correct field.
  - **Limitation, not fixable here: the embedding model does not support Chinese query text at all.** Even with both bugs fixed, every Chinese query tested (single-phrase or multi-keyword array) scored in the same 0.02–0.10 near-random range as the string bug — a property of the underlying model, not the wrapper. Correct fallback for Chinese business terms is `cbm-grep.sh` (literal text match): confirmed it returns 14 correctly-ranked, genuinely relevant results for `字典标签` in 398ms, because RuoYi-Vue-Plus's Javadoc comments are written in Chinese and contain the business term verbatim. BM25 full-text search was also tested and also fails on Chinese (whitespace/camelCase tokenization has no Chinese word boundaries to key off). `cbm-find.sh -s` now emits this guidance as a `hint` whenever a semantic query's top score is below 0.3.
  - `SKILL.md`'s decision table now splits the old single "business-language question(业务词)" row into a Chinese-term row (→ `cbm-grep.sh`) and an English-term row (→ `cbm-find.sh -s`, with the score-check caveat).
- **New, previously undocumented accuracy issue found while root-causing the above: `CALLS` edges resolve by method name ONLY, with no parameter-count/type or receiver-type check — distinct from the already-documented Java interface/impl blind spot.** Traced all inbound edges to `DictService.getDictLabel(String,String,String)` and verified each against source: 6 of 10 (60%) were false positives, really calls to `SysDictDataVo.getDictLabel()` — an unrelated 0-arg Lombok-generated getter on a completely different class, no interface/impl relationship involved. Root cause: any business method whose name collides with a same-named `@Data`-generated getter/setter (the single most common Java naming coincidence) gets its caller list polluted by every unrelated call to that accessor anywhere in the repo. Corroborated the flip side is fine: 8/8 zero-inbound-degree candidates that are NOT getter/setter-shaped and NOT interface methods (`RedisUtils`/`StringUtils`/`SpringUtils`/`DateUtils`/`EncryptUtils`/`MybatisExceptionHandler` utility methods) were confirmed genuinely dead via repo-wide grep — the risk is specific to name-collision-prone methods, not a blanket accuracy failure. `SKILL.md`'s Quality rules and `references/blindspots.md` both updated with the mandatory spot-check this implies for any `get`/`set`/`is`-shaped name (or MyBatis-Plus `BaseMapper`-inherited names like `updateById`/`selectList`).
- **Two smaller, defensive-only findings added to `references/blindspots.md`, neither requiring a script change:**
  - `index_repository --repo-path .` (relative path, no `--name`) run manually from a plain shell silently created a SECOND duplicate project instead of updating the existing one — no script in this skill triggers this (`_project.sh` always resolves off an absolute `git rev-parse --show-toplevel` path and its own unindexed-repo hint already includes an explicit `--name`), documented as a caution for anyone re-indexing by hand.
  - `trace_path --direction` only recognizes `both`/`inbound`/`outbound` — every other plausible-looking value (`up`/`down`/`callers`/`callees`/`upstream`/`downstream`/etc., 17 tested) silently returns an empty result with no error. `cbm-trace.sh` already uses the correct values and is unaffected; recorded so a future edit doesn't reintroduce a bad guess.
  - Corroborating data point for `cbm-arch.sh`: spot-checked its top hotspot (`R.ok`, `fan_in: 172`) against a repo-wide grep (`179` raw matches, ~4% difference) — aggregate/ranking questions tolerate the CALLS name-collision noise far better than single-target traces; exact fan-in numbers still shouldn't be quoted as precise, but relative ranking is trustworthy.

## 0.0.15 (2026-07-17)
- **New: `optional/hooks/codegraph-augment.sh`** — the PreToolUse hook that augments Grep/Glob with graph symbol matches existed only for `cbm-navigator` until now; this adds the parallel counterpart for `codegraph-navigator`, closing a gap the README had explicitly flagged ("可选,仅 cbm-navigator").
  Structurally mirrors `cbm-augment.sh` (self-contained, every failure path exits 0), but calls the `codegraph` CLI's `query -j -l 5 -p "$ROOT"` instead.
  Both scripts are designed to coexist as two entries in the same `Grep|Glob` PreToolUse hooks array (`optional/settings-hook-{user,project}.json` now wire both): each checks for its own index product (`.codebase-memory/` vs `.codegraph/`) up front and silently no-ops if absent, so a repo indexed by only one of the two tools still works correctly with both hooks installed.
- **Field-verified (RuoYi-Vue-Plus, already dual-indexed) before writing the script**: `codegraph query` returns a clean `[]` + exit 0 on both a nonexistent symbol and a pattern containing regex metacharacters (it does fuzzy text matching, not regex parsing, so Grep-style patterns can't crash it); `-p <path>` correctly resolves the target repo from any cwd.
  Also found and guarded against a CLI quirk not previously documented for `query` specifically (only for `callers`/`impact` in `codegraph-navigator/scripts/_gate.sh`): running `query` against an *unindexed* directory prints an ANSI-colored `[ERR] CodeGraph not initialized` line to **stdout** with exit code 0 — not stderr, not JSON. The hook's upfront `.codegraph/` existence check is what keeps normal (dual-hook) operation off that path; a jq-parse `|| exit 0` is the fallback.
- `install.sh`/`uninstall.sh` updated to copy/chmod/remove `codegraph-augment.sh` alongside `cbm-augment.sh` under the existing `--with-hook` flag (no new flag added); `README.md`'s component table row for the hook updated to describe both scripts and the coexistence design instead of "仅 cbm-navigator".

## 0.0.14 (2026-07-17)
- **Third round of field verification, this time covering BOTH skills' officially-claimed strengths (not just their known blind spots), plus a direct same-symbol/same-repo comparison between the two tools.** Triggered by explicit user feedback that prior rounds under-verified `cbm-navigator`'s own claims and over-relied on paraphrased web research for one methodological point — this round is 100% live-CLI execution against RuoYi-Vue-Plus/plus-ui, no web research.
- **`cbm-cypher.sh`'s aggregate templates (this skill's flagship advantage over per-symbol tools) had never been executed end-to-end before this pass — 2 of 5 turned out to be silently broken, now fixed:**
  - `hubs`: the shipped query ordered results by `c.degree`, a property confirmed via `keys(c)` to NOT EXIST on Class nodes at all — `ORDER BY` on an always-null column was a silent no-op, so the "top 20 god classes" was really native scan order (a test-only domain class and plain data objects outranked every real utility class). Fixed by aggregating real inbound `CALLS` edges across each class's methods instead of the nonexistent property or a naive constructor-only count (which also undercounts badly) — the fixed query surfaces `StringUtils`/`R`/`LoginHelper`/`BaseMapperPlus`, the genuinely most-used utility/base classes in this codebase. Caveat: Java/class-oriented repos only, returns empty on function-oriented JS/TS/Vue repos (confirmed on plus-ui) — a real modeling gap, not a query bug.
  - `cross-layer`: the documented zero-arg default invocation hard-crashed the Cypher parser (`unexpected operator at pos 38`) on EVERY call — isolated to `coalesce(...)` being used inside a `WHERE ... CONTAINS` clause (works fine in `RETURN`, works fine in `WHERE` without coalesce, fails only combined). Fixed by dropping `coalesce()` from `WHERE` only; the fixed query returns exactly 4 real controller→mapper layer violations on RuoYi-Vue-Plus.
  - `dead-code` (the `Function`-label template, distinct from `dead-code-methods`): newly discovered, previously undocumented — every Java interface method is double-registered as both a `Method` node AND a `Function` node at the same file/line, but real `CALLS` edges only ever attach to the `Method` twin, so this template reports EVERY interface method as dead regardless of real usage. Not a blanket label bug (95/449 Function nodes in this repo do have real callers; a genuinely-unused enum method was correctly flagged). The script now warns on every call to cross-check `*Service`/`I*`-shaped hits with `cbm-trace.sh` first.
  - `routes` was accurate per-row — but see the code-review follow-up below, its completeness had not actually been checked yet.
- **Same-day code-review pass on the just-fixed `cbm-cypher.sh` found 3 more real issues, all fixed:**
  - **Silent truncation on every fixed-`LIMIT` template, never previously checked**: none of the templates compared their returned row count to their own `LIMIT`, so a true result set bigger than the cap looked exactly like a complete one. Verified: `routes` `LIMIT 200` vs true count 303 (103 hidden); `dead-code` `LIMIT 100` vs true count 348 (248 hidden); `dead-code-methods` `LIMIT 100` vs true count 1159 (1059 hidden, over 90%). This retroactively corrects the "`routes` was already accurate — no change needed" line from earlier the same day, which had only checked row-level correctness, not completeness. Fixed generically: the script now runs a follow-up `count(*)` and warns on stderr whenever a template's row count equals its `LIMIT`; `hubs` is exempt (its cap is an intentional top-20 ranking, not truncated "list all" data).
  - **`cross-layer`'s `layerA`/`layerB` args were spliced unescaped into the Cypher string** — an embedded single quote crashed the parser (`expected token type 85, got 86`) instead of being treated as a literal filter, an injection-shaped input-handling defect. Fixed by stripping `'`/`\` before interpolation.
  - **This script's underlying `cbm_call` (`_project.sh`) has no JSON-validation safety net, unlike codegraph-navigator's `cg_call()`** — a raw Cypher-engine crash (both bugs above, before today's fixes) reached the caller as non-JSON output instead of the `{"error","hint"}` shape both `SKILL.md`s promise. Fixed locally inside `cbm-cypher.sh` (a `run_query` wrapper mirroring `cg_call()`'s pattern); the shared `_project.sh::cbm_call` used directly by the other 6 cbm-navigator scripts is intentionally left unfixed this pass, to keep the change's blast radius reviewable — flagged as a followup.
- **Re-confirmed `cg-explore.sh`'s claimed strength on a fresh single-symbol compound question** (not just re-confirming its known aggregate-question failure mode): correctly synthesized the interface/impl bridge in both directions with real blast-radius counts in one call. Caveat found even here: one unrelated symbol was pulled in purely by keyword coincidence with the question's phrasing — a smaller-scale instance of the same retrieval mechanism behind the aggregate-question failures, so a quick relevance skim of `explore` output is still warranted even on its strong-case questions.
- **Direct same-symbol, same-repo comparison between the two tools** (not two separate one-sided tests): both tools independently attach the interface-typed call edge to the interface's method node, never the impl's — same root cause, confirmed on the identical `ISysDeptService`/`SysDeptServiceImpl` and `ISysUserService`/`SysUserServiceImpl` pairs on both tools. They diverge only in what sits above that shared limitation: cbm's Cypher engine cannot express the bridge query at all (mandatory manual 2-call union, every time), while codegraph's higher-level commands synthesize the bridge automatically in one call — same accuracy ceiling, fewer calls/tokens on codegraph's side.
- **Both `SKILL.md`s now state an explicit, identical tool-selection priority: accuracy first, then tokens, then speed** — added as a gate-check point to `cbm-navigator/SKILL.md` (previously only `codegraph-navigator/SKILL.md` had a "both tools present" gate check; now symmetric) and strengthened in `codegraph-navigator/SKILL.md` with the newly-fixed cbm-cypher.sh accuracy status.
- `README.md`'s "已知边界" sections and "工具选型对比" table updated with all of the above; the comparison table's closing note now explicitly separates "switching tools fixes this" (single-symbol lookups, routes list) from "no tool switch fixes this, only grep does" (Vue dynamic import, MyBatis XML, Spring runtime bean lookup) — a distinction the table previously blurred.

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
