# Changelog

## 0.0.22 (2026-07-20)
- **Systematic audit: cross-checked every `cg-*.sh`/`cbm-*.sh` script's assumptions against a fresh dump of its underlying CLI's own `--help` output, prompted by the realization that 0.0.21's `cg-trace.sh` bug was found by accident, not by design.** No new dogfood repo this pass — verification used the still-indexed `RuoYi-Vue-Plus`/`plus-ui` projects and the still-on-disk `hi.events` codegraph index from 0.0.21. Found and fixed 4 more real defects, all on the `cbm-*` side; the `cg-*` side came back clean except for one positive confirmation. Full repro in `cbm-blindspots.md`'s two new sections; methodology and scope in `tool-collaboration-benchmark.md`'s new "Round 4" section.
  - **`cbm-find.sh` hardcoded `limit:20` — LOWER than `search_graph`'s own documented default of 200 — and discarded the `total`/`has_more` fields the CLI ships specifically to detect truncation.** Confirmed live: `-l Route '.*'` returned exactly 20 of a real 303 routes with zero signal, the identical failure shape to 0.0.21's `cg-trace.sh` bug, just on the sibling tool. **Fix**: default raised to 200, a new `-n LIMIT` override added, `total`/`hasMore` now flow into the hint.
  - **`cbm-trace.sh`'s own "0 results" hint checked field names (`.paths`/`.results`) that don't exist in `trace_path`'s real response (`.callers`/`.callees`) — it reported "0 results" on EVERY call, real results or not.** Confirmed live: a query with 83 real callers still produced the "0 paths — the name must be EXACT" hint. 100% reproduction rate, not a truncation-dependent edge case. **Fix**: hint now counts the real fields; also exposes (and documents) `trace_path`'s own `include_tests=false` default, since a hand-derived grep ground truth that counts test files would otherwise look like a recall gap that isn't the tool's fault.
  - **The shared `_project.sh::cbm_call()` helper had no safety net for tools that fail with their error JSON on stderr instead of stdout — under `set -e`, this silently killed the whole calling script with zero output.** This exact gap was flagged as a known followup in 0.0.19's `cbm-cypher.sh` review but never fixed until now. Confirmed live: `trace_path` on an unknown function name exits 1 with a well-formed `{"error","hint"}` object on stderr and nothing on stdout; the caller saw nothing at all. **Fix**: `cbm_call()` now mirrors `cg_call()`'s (`scripts/_gate.sh`) tempfile+`jq empty` safety net, recovering the CLI's own error/hint from stderr when possible. Side finding: `jq empty` on an empty string exits 0 (success) — both `cbm_call()` and `cg_call()` now also require non-empty stdout before treating it as valid, since the naive check would silently treat an empty-output failure as a blank success (no live repro found on the codegraph side, fixed for consistency anyway).
  - **`cbm-impact.sh`/`cbm-arch.sh` both referenced fields (`summary`/`risk`, `entry_points`) that don't exist in `detect_changes`/`get_architecture`'s real responses — always null.** **Fix**: both scripts now report only real fields; `cbm-arch.sh` also now surfaces `layers`/`boundaries` (real, useful, never surfaced before) and its hint now states plainly that `routes`/`hotspots`/`clusters` are an overview slice, not exhaustive (confirmed live: 20/303 real routes shown).
  - **Positive finding, not a bug: `cg-node.sh`'s caller/callee trail has no limit flag for symbol mode, but its own `+N more` truncation marker is honest and exact** — confirmed on `hi.events`: 12 shown callers + "+31 more" = 43, matching 0.0.21's already-verified ground truth for the same symbol. Unlike `callers`/`callees` before the 0.0.21 fix, this command was never silently truncating.
  - **Unlike 0.0.21's correction, no previously-published finding's NUMBERS needed retracting this pass** — every past caller/recall count in this skill's docs was read directly off the raw array, never off a hint field, so these bugs misled in isolation without corrupting any conclusion already on record.
  - `SKILL.md`'s Quality rules/Token discipline, `cbm-blindspots.md`, `tool-collaboration-benchmark.md`, and `README.md`'s known-boundaries sections synced with all of the above.

## 0.0.21 (2026-07-19)
- **Found and fixed a real bug in this skill's own `cg-trace.sh` script — and it retroactively corrects two of 0.0.20's headline findings.** While adding a second Laravel+React dogfood repo (`hi.events`, see below) to further the Round-2 evidence gap work, a query that should have matched 43 independently-grep-confirmed callers returned exactly 20 through `cg-trace.sh`. Root cause: `codegraph callers`/`callees` (the raw CLI) default their own `-l` to 20 with no total/hasMore field anywhere in their JSON, and `cg-trace.sh` called both with no `-l` override at all, silently inheriting that cap on every invocation since the script was written.
  - **Fix**: `cg-trace.sh` now defaults to `-l 200`, accepts an optional 3rd positional arg to raise it further, and returns a `possiblyTruncated: true` flag (plus a hint) whenever a fetch returns exactly the limit in use — the one observable signal available given the underlying CLI still reports no total count.
  - **Correction, re-verified live against the still-on-disk `pterodactyl-panel-bench` clone from 0.0.20**: the "Laravel Facade resolution ~29% file recall" finding is actually **100% (24/24 files)**; the "`useFlash` React hook ~67% recall" finding is actually **100% (30/30)**. Both were the exact same 20-result cap wearing different repo/language clothes, not independent capability gaps. Corrected in place (not left as stale numbers alongside a separate erratum) in `codegraph-blindspots.md`, `SKILL.md`, `README.md`, and `tool-collaboration-benchmark.md`'s Round 2 section.
- **Added a second Laravel+React dogfood repo, `hi.events` (~3,928 stars), after scouting and rejecting two other candidates**: `koel/koel` (clean Laravel+Vue separation, but Vue not React) and `bagisto/bagisto` (27.7k stars, but its only `.ts` files are Playwright e2e tests — no real frontend framework dependency at all despite the language-byte stats suggesting one). `hi.events` has genuinely separate `backend/` (Laravel, Repository/DTO architecture) and `frontend/` (React 18 + TypeScript, React Router v6.4) directories. Full methodology in `tool-collaboration-benchmark.md`'s new "Round 3" section.
  - **New: a global PHP function and a same-named class method are not reliably disambiguated.** Re-verifying the corrected Facade recall above surfaced 4 false-positive files — Laravel's global `event(...)` helper (dispatches a framework event) was conflated with the Facade-backed `ActivityLogService::event()` METHOD purely on bare-name match. PHP-specific: Java has no free-floating functions to collide with a method name, so this couldn't have surfaced in the earlier Java-only "receiver-typed, no collision" testing. New caveat in `SKILL.md`'s Quality rules and `codegraph-blindspots.md`'s Facade section.
  - **New: Laravel's constructor-injected-interface DI pattern (distinct from Facades) is handled well, without codegraph needing to understand the ServiceProvider binding at all.** Querying the INTERFACE method's own node (matching how the codebase actually types its dependencies) surfaces real business callers directly — 43 found, 100% cross-checked against grep ground truth. New section in `codegraph-blindspots.md`; new row in `README.md`'s comparison table.
  - **New: a third syntactic variant of the dynamic-`import()` blind spot** — React Router v6.4's data-router `async lazy() { await import(...) }` route property (a different AST shape from both classic `React.lazy()` and Vue Router's callback form) reproduces the identical zero-edge blind spot. Extended the existing dynamic-import sections in `codegraph-blindspots.md`/`lsp-and-native-fallbacks.md`/`README.md`.
  - **Methodology note recorded, not a tool finding**: a hand-derived ground truth for a secondary hook cross-check (`useIsCurrentUserAdmin`) initially included a false 5th file — the grep had matched an unrelated sibling hook's import PATH string, not a real call. Caught only because codegraph's (correct) result disagreed with it. Recorded in `codegraph-blindspots.md`'s Round-3 methodology note as a reminder to re-verify ground truth, not just tool output, when the two disagree.
  - **Track A (the formal skill-creator with-skill/baseline eval loop) was deliberately not re-run this round** — 0.0.20's Round 2 already validated the loop mechanics and produced a non-discriminating tie; continuing the direct-probe line that was actively producing results (the bug fix, two corrections, two new findings) had higher expected value than repeating a validated-but-low-signal mechanism a third time. Recorded as a scope decision in `tool-collaboration-benchmark.md`'s Round 3 section, not an oversight.
  - cbm was deliberately not indexed against `hi.events` — a precaution given 0.0.20's memory incident on a similarly-sized repo, not a retry. Noted in `cbm-blindspots.md` and `README.md`.

## 0.0.20 (2026-07-18)
- **Closed the Laravel+PHP and React+TS evidence gap: until this pass, every field-verified finding in this skill came from exactly two repos, both Java/Vue (`RuoYi-Vue-Plus`, `plus-ui`) — no real testing existed for the department's other two stacks (Laravel+PHP ~10% of repos, React+TS ~30%, only indirectly covered via Vue).** Added `pterodactyl/panel` (a real Laravel+React app, ~9k stars) as a third dogfood repo. Full methodology and per-symbol numbers in `references/tool-collaboration-benchmark.md`'s new "Round 2" section.
  - **The original plan (run the `skill-creator` plugin's formal with-skill/baseline eval loop on 6 framework-magic questions) was independently reviewed by Fable 5 (Plan agent) before implementation and found fundamentally unable to produce the intended evidence**: `SKILL.md`'s own decision table already routes Laravel Facade/Eloquent and React dynamic-`import()` questions to native grep, so a compliant with-skill agent would never touch a graph tool on exactly the questions this round existed to test — the eval loop could only confirm routing was followed, not measure tool behavior. The review also caught that `code-navigator` is an installed plugin visible to every subagent (so "baseline, no skill" needed an explicit prohibition to mean anything) and that the plan's pipeline was missing the grading stage entirely (would have produced an empty benchmark). Restructured into two tracks per the review's recommendation.
  - **Track A (skill-creator's actual formal eval machinery — with-skill/baseline subagent pairs, decomposed one-fact-per-assertion grading, `aggregate_benchmark.py`, an HTML eval-viewer)**: run on 2 questions chosen to test genuine skill-routing value (PHP receiver-type disambiguation; a React hook's real callers) rather than framework-magic questions. Result: an honest tie — both configurations scored 100% pass rate on both evals, because the specific symbols chosen were distinctive/searchable enough that careful native grep alone matched graph-tool accuracy, at roughly half the tokens and wall-clock time. Recorded as a methodology lesson (pick less-searchable symbols next round to actually discriminate skill value), not a negative finding about the skill.
  - **Track B (direct probes against hand-verified ground truth, run without subagents)** produced the actual new field evidence:
    - **New: Laravel Facade resolution is a genuine PARTIAL capability for codegraph, not a clean blind spot** — `Activity::event()` (custom Facade → `ActivityLogService::event()`) has 59 real call sites across 24 files; `cg-trace.sh` against the real class found 20 across 7 files (~29% file-level recall). Worth querying (free corroboration) but never trustable alone. New section in `codegraph-blindspots.md`.
    - **New: Eloquent local scopes (`scopeXxx` declared, invoked un-prefixed as `->xxx(...)`) are a confirmed CLEAN miss for codegraph** — the one case tested (`HasRealtimeIdentifier::scopeWhereIdentifier`, 1 real caller) scored 0/1. New section in `codegraph-blindspots.md`.
    - **Confirmed cross-framework: React `lazy(() => import(...))` reproduces the identical dynamic-`import()` blind spot previously documented only for Vue Router.** Updated the existing dynamic-`import()` sections in `codegraph-blindspots.md`/`lsp-and-native-fallbacks.md` from Vue-only-tested to Vue-and-React-tested.
    - **New: a completely ordinary React hook call (`useFlash()`, no aliasing, no runtime injection) under-recalled on a single raw graph-tool call (20/30, ~67%)** — distinct from the already-documented Vue `app.config.globalProperties` near-total-blindness case (0-1/10-19). Unlike that case, this one is fully recoverable by cross-checking (Track A's with-skill run self-corrected to 30/30). New Quality-rules bullet in `SKILL.md` generalizing "cross-check raw call counts" beyond name-collision-prone symbols to ordinary functions in general.
    - **Extended the existing Java-only "codegraph resolves by receiver type, no same-name-across-classes collision" finding to PHP** — `UserCreationService::handle()` has 4 real callers among ~19 textually-identical `*CreationService->handle(...)` call sites across a dozen-plus unrelated classes; codegraph found exactly the 4, zero false positives.
  - **Operational finding, unrelated to query accuracy: `codebase-memory-mcp index_repository` drove host memory usage to within ~1GB of a 64GB machine's full capacity indexing the same 1,289-file repo, and had to be force-killed** — no cbm-side data exists for this round as a result (Laravel/PHP remains genuinely untested for cbm, not just "not gotten around to"). Confirmed via the upstream tracker this is a known, currently-unmitigated, cross-platform issue class (`DeusData/codebase-memory-mcp` #581/#593/#832/#775/#1084 on Windows, #580/#765/#317 on macOS, #363/#1070 on Linux — no shipped `--max-memory` flag). `codegraph` indexed the identical repo in 2.6s with no issue. New "`index_repository` memory usage" section in `cbm-blindspots.md`; new operational warning in `SKILL.md`'s Gate check (Freshness item) and `README.md`'s cbm install-prerequisites section.
  - `SKILL.md`'s "framework magic" decision-table row, `README.md`'s known-boundaries sections and 工具选型对比 table synced with all of the above.

## 0.0.19 (2026-07-18)
- **Post-merge tool-collaboration benchmark: 8 independent `deep-analyst` (effort: high) runs across 4 phases × 2 repos, testing how the two graph tools, native Grep/Glob/Read, and LSP should work TOGETHER — not another codegraph-vs-codebase-memory-mcp shootout, that ground was already covered pre-0.0.18.** Full raw data and methodology in the new `references/tool-collaboration-benchmark.md`. Findings folded into `SKILL.md`'s decision table and the two blindspots reference files:
  - **New blind spot: Vue/React functions registered on `app.config.globalProperties`** (e.g. `app.config.globalProperties.parseTime = parseTime`, called elsewhere as `proxy.parseTime(...)`). Confirmed a repo-wide CLASS of blind spot, not a per-function quirk — 3/3 independently-tested functions (`parseTime`, `handleTree`, `addDateRange`) reproduced identically: both graph tools recalled ~0-1/10-19 real call sites, native grep recovered 10/10, 19/19, 10/10 in under 100ms each. Documented in `references/lsp-and-native-fallbacks.md`'s shared-blind-spot list.
  - **New blind spot: `SpringUtils.getAopProxy(this).<method>(...)` self-invocation**, a sibling of the existing `getBean(X.class)` gap — found while cross-verifying a `dead-code-methods` candidate (`SysDictTypeServiceImpl.selectDictTypeByType`, `@Cacheable`) that turned out to have a real caller reached only through the AOP proxy. Unlike `getBean(X.class)` (asymmetric), this one is a genuinely SHARED miss: both `cbm-cypher.sh dead-code-methods` and `cg-trace.sh`/`cg-node.sh` independently missed the same call site and agreed the method looked dead. New dedicated section in `codegraph-blindspots.md`, cross-referenced from `cbm-blindspots.md`'s dead-code section and `SKILL.md`'s Quality rules (which already held the canonical `getBean(X.class)` statement).
  - **New blind spot: `cg-node.sh`'s file-level "used by N files" dependency aggregation is vulnerable to boilerplate variable-name collision**, distinct from its (still accurate) receiver-typed method-level `CALLS` edges. `RoleSelect/index.vue` was reported "used by 29 files" when manual grep found zero genuine references — the false 29 came from unrelated CRUD pages sharing generic identifiers (`handleQuery`, `queryParams`). New caveat in `codegraph-blindspots.md`'s receiver-typed-edges section and `SKILL.md`'s Quality rules.
  - **Correction: Chinese business-term search is NOT "either tool is fine" on a Vue/TS repo.** The existing guidance was validated only on the Java backend. On plus-ui, `cg-find.sh` failed systematically (0/6 real Chinese terms across two rounds, regardless of Latin-anchor presence) while `cbm-grep.sh` found 6/6. `SKILL.md`'s decision table now splits this row by repo shape: Java/backend keeps "either tool fine", Vue/TS/frontend is `cbm-grep.sh` only.
  - **Correction: config-binding (`.yml`/`.env`) is NOT "zero graph value".** `cg-find.sh` unexpectedly indexes some `application.yml` keys as `constant` nodes linked to `@Value` sites; `cbm-grep.sh` (not `cbm-find.sh`) partially models `.env` files as Module nodes. Neither is complete enough to skip a native grep+Read, but the old "zero visibility" framing was overstated — softened in `SKILL.md`'s new config-binding row and in `lsp-and-native-fallbacks.md`'s new dedicated section.
  - **New decision-table row: cross-repo consistency** (e.g. "does this frontend API call have a matching backend route") — neither tool has any cross-repo capability (each resolves strictly to its own cwd's git-toplevel repo); the answer is native grep on both trees, optionally cross-checked with `cg-find.sh -k route` on the backend side. Field-verified 3/3 real API-to-route matches this way on RuoYi-Vue-Plus/plus-ui. Folded into `cbm-blindspots.md`'s existing "Cross-repository analysis" section rather than duplicated.
  - **New decision-table fast path: exact name already known → native Glob, skip both graph tools.** Field-verified across 4 cases (2 backend classes, 2 frontend files): Glob was faster (up to 18x), cheaper, and equally-or-more precise every time — the graph tools only added fuzzy-match noise and latency when the exact name was already known.
  - **New Quality rule: agreement between signals is not proof when the signals share a blind spot.** Stated as an explicit, standalone principle (not just implied) after this benchmark caught it twice — the `getAopProxy` case above (two tools agreeing a method was dead, both wrong for the same reason) and a Vue "is this component unused" check that flipped in BOTH directions (a false negative from missed `unplugin-vue-components` auto-registration, a false positive from the file-level aggregation collision above). Any "cross-check with another signal" instruction in this skill now implicitly carries this caveat: the second signal must fail for a DIFFERENT underlying reason than the first.
  - **Other collaboration-pattern findings, not table changes but documented in the new reference file**: graph+graph union adds little beyond graph+native-grep for interface-method call chains (one graph tool + the mandatory grep reaches the same recall as running both, at lower cost); grep-first-then-selectively-escalate beats "graph cold" for plain-text-shaped and fuzzy-anchored questions; precise-range Read after a graph tool narrows location beats whole-file Read (savings scale with file size); "graph locates + native Read completes" vs. a graph tool's own all-in-one embedded-source call is genuinely context-dependent (documented a direct disagreement between the two repos on this exact question) — none of these are safe to bake into a fixed table row, so they're recorded as documented judgment calls instead.
  - `cbm-*` scripts measured consistently 300-700ms per call across all 8 runs; `cg-*` scripts consistently 1200-2700ms (~3-4x slower) — a stable characteristic of the two CLIs, not noise.
- **Housekeeping surfaced during a full re-read of this skill and its related files, done in the same pass as the benchmark write-up:**
  - `SKILL.md`'s decision table "who calls X" row had accumulated a 7-point mandatory-check protocol crammed into one table cell as run-on prose — extracted into a proper numbered-list subsection ("Interface-method call-chain — mandatory checks") right after the table, with the table cell now just a one-line pointer. No content removed; point 4 (Lombok collision) now points at the existing Quality-rules bullet for the evidence figure instead of restating it.
  - `references/lsp-and-native-fallbacks.md`'s shared-blind-spot bullets were inconsistent about citing back to the fuller per-tool repro in `cbm-blindspots.md`/`codegraph-blindspots.md` — some (the newly-added `getAopProxy`/config-binding entries) did, the older ones (MyBatis XML, dynamic `import()`, computed bean name, `extends`, Laravel/Django) didn't. Added the missing pointers for consistency.
  - `references/tool-collaboration-benchmark.md`'s "10 concrete changes recommended" list is now marked as shipped (it previously read like an open TODO even though every item had already landed in `SKILL.md`/the reference files by the time this entry was written).
  - `README.md`'s "已知边界" sections and "工具选型对比" table — explicitly described in the file as the evidence appendix for `SKILL.md`'s decision table — had not been updated since 0.0.18 and were missing every finding in this entry (Vue `globalProperties`, `getAopProxy`, the `cg-node` aggregation collision, the Chinese/Vue-repo correction, the config-binding correction, the cross-repo row, the Glob-first row). Updated, and added a pointer to `references/tool-collaboration-benchmark.md` (previously never referenced from `README.md` at all).

## 0.0.18 (2026-07-18)
- **Merged `cbm-navigator` and `codegraph-navigator` into a single unified skill, `code-navigator`, plus a single `deep-analyst` subagent, a single CLAUDE.md snippet, and a new LSP collaboration protocol — a user-requested architectural change, motivated by a real bug an audit of every file in this repo turned up this same session:**
  - **The bug: the two CLAUDE.md snippets were the only ALWAYS-loaded guidance layer, and each unconditionally said "invoke [my skill] FIRST" for structural questions with zero cross-reference to the other.** That is a literal contradiction at the layer read before either skill is even invoked. The actual arbitration logic (accuracy > tokens > speed; prefer codegraph for single-symbol questions; prefer cbm for whole-graph aggregate questions codegraph has no equivalent for) only existed inside each SKILL.md's own "both present" gate-check step — reachable only after a skill was already invoked. The fix is structural: one skill, one decision table, one CLAUDE.md snippet, so there is nothing left to contradict.
  - **New: a `code-navigator` decision table organized by QUESTION SHAPE rather than by tool** — each row names a priority-ordered fallback chain across whatever is actually installed (codegraph script > cbm script > native grep, or the reverse, depending on the row), with the "both installed" arbitration baked directly into the table instead of living one layer deeper than the always-loaded snippet. Several rows are new splits that the two old, separate decision tables didn't have: symbol-anchored vs. diff-anchored impact analysis (`cg-impact.sh` vs. `cbm-impact.sh`, genuinely complementary, not alternatives), and dead-code/hubs/cross-layer pulled apart into three rows each with its own false-positive/false-negative caveat instead of one blended "aggregate questions" row.
  - **New, field-verified this session: Claude Code's own LSP tool (`findReferences`, `goToDefinition`, etc.) was tested against both dogfood repos and found to have NO language server configured for either language** — `findReferences` on a `.java` file returned `"No LSP server available for file type: .java"`; `documentSymbol` on a `.ts` file returned `"typescript-language-server not found or is in an unsafe location"`. Because of this, LSP is deliberately placed nowhere near the head of any decision-table row — it is documented (`references/lsp-and-native-fallbacks.md`) purely as an opportunistic corroboration layer for single-symbol questions, tried once when relevant and silently dropped on any "not available"/"not found" error. What LSP would provide if a server were configured (expected: compiler-level receiver-type accuracy, no Lombok-getter collision) is explicitly labeled untested design speculation, not a field-verified finding, until a future session actually has a working language server to test against.
  - **`SpringUtils.getBean(X.class)` — a deterministic single-target Spring bean lookup — was re-characterized more precisely while merging the two tools' blindspots pages**: codegraph is confirmed fully blind to this call shape (0/2 recall on two real call sites); codebase-memory-mcp's name-only edge resolution can incidentally surface these same call sites, but mixed into unrelated noise, so its apparent "catch" cannot be relied on either. The decision table's "who calls X" row now states this asymmetry explicitly instead of the old, less precise "shared blind spot" framing, and makes the standing `grep SpringUtils.getBean(<Interface>.class)` spot-check mandatory regardless of which graph tool produced the count being reported.
  - **File structure**: `skills/cbm-navigator/` and `skills/codegraph-navigator/` are gone, replaced by `skills/code-navigator/` — the same 16 query scripts (`cbm-*.sh` ×8, `cg-*.sh` ×8, plus `_project.sh`/`_gate.sh`) moved in with zero logic changes, only text-level redirects in comments/hints/warnings that pointed at the old skill names or the old `references/blindspots.md` path (now `cbm-blindspots.md` / `codegraph-blindspots.md`, siblings under one skill, cross-references between them updated to match); a new `references/lsp-and-native-fallbacks.md` holds the LSP protocol plus the consolidated "blind on both tools, native grep only" list (MyBatis XML binding, Vue/React dynamic `import()`, computed Spring bean names, `extends` direction). `agents/cbm-deep-analyst.md` + `agents/codegraph-deep-analyst.md` are gone, replaced by `agents/deep-analyst.md`. `optional/CLAUDE.md.codegraph.snippet` is gone; `optional/CLAUDE.md.snippet` is now the one unified snippet (still carries the `<PROJECT_NAME>` line, needed only when the cbm-side index is present). No backward-compatible aliases for any of the old names — this is a personal/small-team repo with no third-party consumers of the old skill/agent names.
  - **Script-by-script text redirects** (11 of the 16 migrated scripts are byte-identical pure renames; the other 5 got ONLY the following comment/string edits, zero logic changes, confirmed via `git diff`):
    - `_gate.sh`: comment "every codegraph-navigator script" → "every cg-* script"; error hint `"...use the cbm-navigator skill"` → `"...use this skill's cbm-* scripts instead (same skill, different index)"`; comment `references/blindspots.md` → `references/codegraph-blindspots.md`.
    - `cbm-cypher.sh`: comment path fixes (`references/blindspots.md` → `references/cbm-blindspots.md`, ×2 in warning strings + comments); "unlike codegraph-navigator's" → "unlike this skill's codegraph-side"; "cbm-navigator scripts" → "cbm-* scripts".
    - `cbm-find.sh`: comment path fix to `references/cbm-blindspots.md`.
    - `cg-find.sh`: comment path fix to `references/codegraph-blindspots.md`.
    - `cg-trace.sh`: comment path fix to `references/codegraph-blindspots.md`.
    - Unchanged (pure `git mv`, 100% similarity): `_project.sh`, `cbm-arch.sh`, `cbm-grep.sh`, `cbm-impact.sh`, `cbm-snippet.sh`, `cbm-trace.sh`, `cg-affected.sh`, `cg-arch.sh`, `cg-explore.sh`, `cg-impact.sh`, `cg-node.sh`.
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
