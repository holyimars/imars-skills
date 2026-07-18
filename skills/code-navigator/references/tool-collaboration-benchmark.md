# Tool-collaboration benchmark (field-verified 2026-07-18, post-0.0.18 merge)

This is NOT a codegraph-vs-codebase-memory-mcp shootout — that ground is already covered by the sibling `cbm-blindspots.md`/`codegraph-blindspots.md`.
This file records what was learned by testing **collaboration strategies**: graph tool + graph tool, graph tool + native Grep/Glob/Read, cheap-first escalation, multi-signal consensus, and Claude Code's own LSP tool as a (currently non-functional) third source.
Method: 8 independent `imars-skills:deep-analyst` sub-agent runs (effort: high), 4 test phases × 2 repos (`RuoYi-Vue-Plus` Java backend, `plus-ui` Vue/TS frontend), each phase building on the prior phase's numbers.
Every accuracy claim below was cross-checked against real source (grep/Read), not taken from a tool's JSON at face value — that discipline is what "effort: high" bought here, and it is what surfaced several findings that plain single-tool testing missed.
Raw per-call latency/byte tables from all 8 runs are in the Appendix; the sections above it are the distilled, actionable findings.

## New blind spots discovered (not in the existing blindspots.md files)

- **Vue `app.config.globalProperties` injected calls — confirmed as a repo-wide CLASS of blind spot, not a per-function quirk.**
  Three independent functions registered this way in `plus-ui/src/plugins/index.ts` (`parseTime`, `handleTree`, `addDateRange`) were each tested separately; all three reproduced the identical failure: both `cg-trace.sh` and `cbm-trace.sh` recalled 0-1 out of 10-19 real call sites, because the real call shape is `proxy.parseTime(...)`/`proxy?.addDateRange(...)` through the injected property, which neither tool's static call-graph model resolves back to the plugin registration.
  A single native `grep -rn "proxy\.<name>\|\.<name>("` call recovered 10/10, 19/19, and 10/10 respectively, each in under 100ms.
  Recommend adding this to `lsp-and-native-fallbacks.md`'s shared-blind-spot list alongside dynamic `import()`: any function registered via `app.config.globalProperties.X = fn` (grep `src/plugins/index.ts` or equivalent to enumerate the full registered set before trusting a graph tool's call-chain answer for ANY of them).

- **Spring AOP self-invocation via `SpringUtils.getAopProxy(this).<method>(...)` — a new sibling of the documented `getBean(X.class)` blind spot.**
  Found while cross-verifying a `dead-code-methods` candidate (`SysDictTypeServiceImpl.selectDictTypeByType`, cached via `@Cacheable`): the real call site invokes the method through `SpringUtils.getAopProxy(this)` rather than a direct `this.method()` call, specifically to route through the Spring AOP proxy and trigger the cache annotation.
  Both `cbm-cypher.sh dead-code-methods` AND `cg-trace.sh`/`cg-node.sh` independently missed this call site and agreed the method looked dead — a case where two "independent" signals shared the exact same blind spot and their agreement was worthless (see the consensus-is-not-majority-vote finding below).
  Recommend a standing mandatory grep — `SpringUtils.getAopProxy(this).<method>(` — anywhere a service-impl method carries `@Cacheable`/`@CachePut`/`@CacheEvict` or another AOP-relevant annotation and looks like a dead-code candidate.

- **`cg-node`'s file-level dependency aggregation is vulnerable to coincidental shared function/variable names across unrelated Vue SFCs.**
  `cg-node.sh` reported `RoleSelect/index.vue` as "used by 29 files" — but manual grep found ZERO genuine references to the component anywhere; the false "29" came from other CRUD pages sharing generic boilerplate names (`handleQuery`, `queryParams`) that happened to also live in files codegraph's file-level heuristic associated with `RoleSelect`.
  This is a distinct failure mode from the documented method-level `CALLS` edge accuracy (which IS receiver-typed and does not collide) — it is specifically the **file-summary/dependency-count heuristic** that is not immune to boilerplate-name collision.
  Fallback: never trust a bare "used by N files" count for a Vue component as evidence of real usage — grep the kebab-case template tag (`<role-select`) and check `vite/plugins/components.ts` / global-registration entry points for auto-import resolvers (see next finding) before concluding used-or-unused either way.

- **Cross-layer violation misattribution can point outside the repo entirely, not just to an in-repo Lombok-getter collision.**
  One of `cbm-cypher.sh cross-layer`'s 4 reported violations (`FlwDefinitionController` → `DefService.updateById`) turned out, on Read, to likely be a call into a third-party workflow-engine library's own `DefService` interface, not this repo's Mapper layer — the bare-name collision class of bug (already documented for Lombok getters) extends to external dependencies too.
  Fallback: for any cross-layer violation report, Read the actual import statement at the top of the flagged file before treating it as a real in-repo violation.

## Corrections to previously-assumed-safe decision-table guidance

- **Chinese business-term search is NOT "either tool is fine" — it's repo/context-dependent, and currently wrong for plus-ui.**
  The existing decision table's guidance was validated only on the Java backend (`cg-find.sh` and `cbm-grep.sh` both worked there).
  On plus-ui, `cg-find.sh` failed systematically: 0/6 distinct real Chinese terms found across two test rounds ("字典管理", "客户端管理", "系统管理", "配置管理", "登录日志", plus a re-confirm) — this reproduced regardless of whether the term sat next to a Latin-script identifier, so it looks like a CJK-tokenizer gap in codegraph's FTS layer on this repo/build, not a query-shape issue.
  `cbm-grep.sh` found all 6/6 correctly, byte-for-byte matching independent manual grep counts every time.
  **Recommend a hard decision-table swap for Vue/TS repos**: use `cbm-grep.sh` (or native grep) unconditionally for pure-Chinese literal-text search, don't offer `cg-find.sh` as an equal alternative there — keep the existing "either is fine" guidance only for the Java backend shape until another frontend repo is tested.

- **Config-binding (`.yml`/`.env`) is NOT uniformly "zero graph-tool value" — it's per-script, and one assumption in this benchmark's own test design was wrong.**
  `cg-find.sh` unexpectedly indexes `application.yml` keys as `constant`-kind nodes and links them to `@Value` reference sites in Java code — a real capability, not the assumed "codegraph doesn't see YAML at all."
  `cbm-find.sh` (regex/symbol-oriented) has zero `.yml`/`.env` visibility, but `cbm-grep.sh` (literal-text-oriented) partially does — it modeled `plus-ui/.env.development` as a Module node and found the defining line for a `VITE_APP_CLIENT_ID`-style key.
  Net effect for daily work is still "grep the config file directly if you need certainty" (native grep is faster and complete either way, and remains the only path for `.properties` files and env-var files that no script here modeled), but do not write a decision-table row claiming graph tools have literally zero config-file awareness — say instead "unreliable/inconsistent, verify with native grep."

## Validated / re-quantified existing guidance

- **Querying the wrong side of an interface/impl pair is silently ~100% false-positive, reproduced twice more.**
  `cbm-trace.sh` on `SysDictTypeServiceImpl.getDictLabel` (the impl side, a bare-name collision with `SysDictData`'s Lombok getter) again returned 4 confidently-formatted callers, 100% of which were false positives — indistinguishable in output shape from a correct answer, no warning emitted.
  This justifies promoting "query the INTERFACE side, not the impl side" from a preference to an explicit mandatory guard in the decision table, since the failure mode is silent and equally plausible-looking as success.

- **Dead-code raw signal vs. full cross-check chain can INVERT the conclusion entirely, not just refine it.**
  3 Java interface/impl methods flagged by `cbm-cypher.sh dead-code-methods` were run through the full mandatory cross-check chain (graph trace + native grep + Read); 0/3 were actually dead — all 3 had real callers the raw dead-code query's Function/Method dual-registration blind spot hid.
  This is stronger than the documented warning implied: the chain doesn't just add confidence, it can flip "3 dead" to "0 dead."

- **`SpringUtils.getBean(X.class)` blind spot reconfirmed identically on a fresh run** — both graph tools 0/2 recall on the two reflection-only callers, native grep recovered both in <200ms, consistent with the existing `codegraph-blindspots.md`/`cbm-blindspots.md` entries.

## Collaboration-pattern findings (the core ask: how should multiple tools work together)

- **Graph + graph union added far less value than graph + native grep.**
  For `DictService.getDictLabel`, `cg-trace.sh` and `cbm-trace.sh` (correct/interface side) returned IDENTICAL callers — running both graph tools cost double with zero recall gain.
  The recall gain from 2/4 to 4/4 came entirely from the mandatory native `SpringUtils.getBean` grep, not from combining two graph tools.
  **Implication**: when the decision table says "run both if both are installed," that default should be reconsidered per question-shape — for interface-method call-chain questions specifically, one graph tool + the standing native-grep fallback reaches the same recall as running both graph tools, at 2/3 the cost.

- **Grep-first-then-selectively-escalate beats "graph tool cold" for two distinct question shapes.**
  Plain-text-shaped constructs (e.g. `new ServiceException(`, 140 real hits): native grep alone (168ms, complete enumeration) vastly outperformed `cg-trace.sh`, which returned import/namespace-level noise and could not answer "who constructs this" at all for this shape.
  Fuzzy business-shaped questions with an available keyword anchor (e.g. "where is login lockout handled", "where is menu permission filtering applied"): a cheap `Glob` (candidate files) → scoped `grep` (keyword) pipeline resolved BOTH test questions completely, faster and with less noise than a cold `cg-explore.sh` call, whose top-ranked "relevant" hit was off-target in both repos tested.
  Escalating only the genuinely ambiguous grep hits (2-3 out of many) to a graph tool for structural disambiguation was far cheaper than either "grep only, no verification" or "always run the graph tool" — this adaptive 2-stage pattern is the strongest general recommendation from this whole benchmark.

- **Glob alone strictly dominates both graph tools when the exact file/class/component name is already known.**
  Tested on 2 backend classes and 2 frontend files: `Glob` was faster (up to 18x), cheaper (near-zero bytes), and equally or more precise (single exact hit vs. the target buried among 11-20 fuzzy near-misses) in every case.
  **Recommend an explicit fast-path row**: "exact name already known → Glob, do not invoke either graph tool."

- **Precise-range `Read` after a graph tool narrows to file+line beats whole-file `Read`, and the savings scale with file size.**
  Backend cross-layer violations: 4629 bytes (4 precise-range reads) vs. 15944 bytes (4 whole-file reads) — a 3.9x reduction.
  Frontend hotspot files: savings ranged from 74-97% on files over ~150 lines down to negligible on files already under ~100 lines — this is a real but size-dependent win, not a flat multiplier.

- **"Graph locates, native tool completes" vs. "graph tool's own all-in-one call" is genuinely context-dependent — this benchmark produced a direct disagreement between the two repos, which is itself the finding.**
  On plus-ui, for understanding a single Vue component, the locate(`cg-find`)+Read relay (4155 bytes, 2 calls) beat both `cg-node.sh`'s all-in-one file dump (21365 bytes, 5x) and `cg-explore.sh`'s flagship call (16796 bytes, ~4x).
  On RuoYi-Vue-Plus, for understanding a single already-named Java method, `cg-node.sh`'s all-in-one call (1776 bytes, 1 call) actually beat the locate+Read relay (2887 bytes, 2 calls).
  The difference: `cg-node.sh` already embeds full method source + bidirectional callers in one shot when it has a clean single-symbol target, so a follow-up Read is redundant overhead; the Vue case needed Read because the all-in-one call's embedded content didn't include everything the question needed.
  **Rule of thumb, not a fixed table row**: prefer the graph tool's own all-in-one/embedded-source command (`cg-node.sh`) first for a single, already-exactly-named symbol; only add a Read/relay step if that output visibly doesn't cover what's needed — don't default to "always relay" or "always trust the embedded output," check the specific tool's actual embedded-content shape.
  `cg-explore.sh` (the flagship compound-question command) was consistently 4-14x more bytes than the targeted single-symbol commands in both repos for a question that didn't actually need blast-radius/relationship context — reserve it for genuinely compound questions, not "explain this one method."

- **Multi-signal consensus is not majority-vote-safe when the signals share a common blind spot — this is the single most important methodological finding.**
  Backend: a dead-code candidate had 2 of 3 independent-looking signals (the `dead-code-methods` query AND `cg-trace`/`cg-node`) agree it was dead — both were blind to the same `SpringUtils.getAopProxy(this)` self-invocation pattern, so their agreement was not corroboration, it was the same mistake counted twice.
  Frontend: a 3-signal "is this component unused" check flipped verdicts in BOTH directions on different components — a graph "0 usages" verdict was a false negative (missed `unplugin-vue-components` auto-registration by folder name), while a graph "used by 29 files" verdict was a false positive (boilerplate variable-name collision inflating a file-level heuristic).
  **Implication for the skill**: when documenting a "cross-check with another signal" step, name signals that fail for DIFFERENT underlying reasons (e.g. a structural graph query + a native grep + a check of the framework's own auto-registration/DI mechanism), not just "run a second tool" — two tools built on the same underlying static-analysis limitation will agree with each other and both be wrong.

## Cost/speed characterization (aggregate, from ~180 individual measured calls across 8 runs)

- **Per-call latency**: `cbm-*` scripts consistently 300-700ms; `cg-*` scripts consistently 1200-2700ms (roughly 3-4x slower per call, both repos, both phases). This held throughout — it appears to be a stable characteristic of the two CLIs' startup/query cost, not noise.
- **Token cost for exhaustive/flagship output**: `cg-find.sh -k route` (303 rows) cost ~30.4k tokens vs. `cbm-cypher.sh routes`' ~6.5k tokens (which self-reports truncation at 200/303 shown, honestly, rather than silently under- or over-stating). `cg-explore.sh` cost 4-14x the tokens of a targeted single-symbol call across every test where both were tried.
- **Total wall-clock for a multi-call chain is NOT always worse than one heavier call**: cbm's 3-4 call chains sometimes finished in comparable or less total time than codegraph's single heavier call, because cbm's per-call latency is low enough that 3-4 calls can still undercut one 1300-2700ms codegraph call.
- **Cheap-first escalation policies save latency reliably but do not always save tokens** — on one 5-symbol mixed batch, "always cg-find alone" was actually the cheapest strategy overall on calls+bytes, because escalating cbm's noisy substring-match payloads after a failed cheap attempt meant paying for both.

## Concrete decision-table / skill changes recommended

**Status: all 10 shipped (0.0.19)** — every item below is already reflected in `SKILL.md`'s decision table/Quality rules and the reference files cited inline. Kept as a record of what prompted each change and why, not a pending list; re-check an item here only if a future version bump of either CLI changes the underlying behavior it describes.

1. Add "Vue/React `app.config.globalProperties`-injected method calls" as a new documented shared blind spot in `lsp-and-native-fallbacks.md`, next to dynamic `import()` — mandatory native grep, not graph-tool trust, for any function found registered this way.
2. Add "`SpringUtils.getAopProxy(this).<method>(...)`" as a standing mandatory grep alongside the existing `SpringUtils.getBean(X.class)` check, specifically before trusting any dead-code verdict on a `@Cacheable`/AOP-annotated service method.
3. Promote "query the interface side, not the impl side" from guidance to an explicit mandatory guard in the interface/impl call-chain decision-table row — the wrong-side failure mode is silent and 100% false-positive.
4. Correct the Chinese-business-term decision-table row: split it by repo/language context — backend Java: either tool; Vue/TS frontend: `cbm-grep.sh` only, `cg-find.sh` is currently unreliable there (0/6 field-verified).
5. Soften the config-binding blind-spot claim from "zero graph value" to "inconsistent, verify with native grep" — `cg-find.sh` has partial `.yml` visibility, `cbm-grep.sh` has partial `.env` visibility, neither is complete or dependable enough to skip a native check.
6. Add a new decision-table row for cross-repo consistency questions (e.g. "does this frontend API call have a matching backend route") — today NEITHER tool has any cross-repo capability; the answer is native grep on both trees, optionally cross-checked with `cg-find.sh -k route` on the backend side.
7. Add an explicit Glob-first fast path: "exact file/class/component name already known → Glob, skip both graph tools."
8. Add explicit guidance for interface-method call-chain questions: running one graph tool + the mandatory native fallback grep reaches the same recall as running both graph tools together, at lower cost — don't default to "run both" for this shape specifically.
9. Add a caveat to any "cross-check with another signal" instruction: signals must fail for different underlying reasons, not just be "a different tool" — call out the AOP self-invocation and auto-registration (`unplugin-vue-components`)-style cases as examples of correlated blind spots that produce false consensus.
10. Note in `codegraph-blindspots.md` that `cg-node`'s file-level "used by N files" aggregation for Vue SFCs is vulnerable to boilerplate-name collision distinct from its (still accurate) receiver-typed method-level `CALLS` edges — don't extend the "no collision" guarantee to this file-summary heuristic.

## Round 2 — `pterodactyl/panel` (closing the Laravel+PHP / React+TS evidence gap, 2026-07-18)

Round 1 above (and every dated finding in the sibling `cbm-blindspots.md`/`codegraph-blindspots.md` prior to this round) came from exactly two repos, both Java/Vue (`RuoYi-Vue-Plus`, `plus-ui`). This round targeted the two stacks with zero prior field evidence in this skill: Laravel+PHP (fully untested) and React+TS (only indirectly covered via Vue). Repo chosen: `pterodactyl/panel` v1.14.1 (shallow clone, 1,289 files, PHP 64.8% / TS 20.9% / Blade 11.7%, ~9k stars) — a single repo with both a real Laravel backend (`app/`) and a real React+TS frontend (`resources/scripts/`), reducing setup cost versus finding two separate repos.

**Methodology, two tracks, deliberately different from each other and from Round 1's single deep-analyst methodology:**
- **Track A** — the skill-creator plugin's FORMAL eval loop (with-skill / baseline subagent pairs, `eval_metadata.json` assertions decomposed one-fact-per-assertion rather than one lump "lists all callers" assertion, grading against pre-established ground truth, `aggregate_benchmark.py`, an HTML eval-viewer) run on 2 test questions chosen specifically to exercise cases where the skill's routing has genuine value (a PHP receiver-type-disambiguation question, a React hook recall question) — NOT the framework-magic questions, because a compliant with-skill agent routes those to native grep by the skill's own decision table and would never touch a graph tool on them, so that shape can't be tested this way (see the plan review that caught this before the round started).
- **Track B** — direct probes run by the orchestrating session itself (no subagents), against symbols pinned and hand-verified BEFORE any indexing happened, for the actual framework-magic questions Track A structurally cannot answer: a Laravel Facade call chain, an Eloquent local scope invocation, a React `lazy()` dynamic-import route.
- Only `codegraph` was actually available for either track — `codebase-memory-mcp`'s `index_repository` had to be force-killed after driving host memory to within ~1GB of a 64GB machine's full capacity (see below); no cbm-side data exists for this repo as a result.

**Track A result — an honest tie, not a skill win, and a useful lesson about test-case selection:**
- Both eval questions scored 100% pass rate for BOTH with-skill and without-skill configurations. The PHP question (`UserCreationService::handle()` callers, with ~15 textually-identical decoy calls to unrelated `*CreationService` classes in the same codebase) and the React question (`useFlash()` hook, 30 real call sites) were both answered completely and correctly by a baseline agent using nothing but Grep/Read, because the class/hook name in question was distinctive enough for careful literal-text search plus manual cross-checking to substitute for graph traversal.
- The with-skill runs took noticeably longer (+88s mean) and used more tokens (+27.6k mean) for the identical pass rate — largely because the with-skill agent, per the skill's own cross-check discipline, queried the graph tool AND THEN verified with native grep, i.e. did strictly more work for parity rather than less.
- **Lesson for future rounds, not a negative finding about the skill**: a sufficiently careful baseline agent can match graph-tool accuracy through diligence alone when native grep is cheap and unambiguous for the specific symbol chosen. A future iteration should pick eval questions where grep alone is expensive or noisy at scale (a common one-word name colliding across dozens of classes, or a question requiring aggregation across hundreds of sites) to actually surface a discriminating recall gap in pass_rate, rather than relying on a raw single-tool-call comparison (which Track B's direct probes below did surface real gaps in — the eval-loop's pass/fail framing just wasn't the instrument that caught them this round).

**Track B result — real, concrete evidence closing the evidence gap (full repro in the per-tool blindspots files):**
- **Laravel Facade resolution — CORRECTED 2026-07-19 (see Round 3 below): actually 100% file recall, not the ~29% reported here originally.** `Activity::event()` (an app-defined Facade resolving to `ActivityLogService::event()`) has 58 real call sites across 24 files; the ORIGINAL `cg-trace.sh` run found 20 callers across 7 files (~29% file-level recall) and was reported as a genuine partial-recall capability. Round 3 traced this to a silent 20-result cap in `cg-trace.sh` itself (now fixed) — re-run with the fix, the same query found all 24 files (75 records across 28 files, 4 of which are a distinct, genuine false-positive class also documented in Round 3). See `codegraph-blindspots.md`'s Facade section for the current, correct numbers.
- **Eloquent local scopes are a confirmed CLEAN miss** (this one holds, unaffected by the Round 3 correction — ground truth was 1 real caller, well under any result cap): `scopeWhereIdentifier` (declared with the `scope` prefix, invoked without it — `->whereIdentifier(...)`) has exactly 1 real caller; codegraph found 0/1, because it indexes the declared name and has no rule connecting it to the un-prefixed invocation form. See `codegraph-blindspots.md`'s Eloquent section.
- **React `lazy(() => import(...))` reproduces the exact same blind spot already documented for Vue Router, now confirmed cross-framework rather than assumed**: a `FileEditContainer` route component declared via `lazy()` in `routers/routes.ts` has zero graph edge connecting the declaration to the real component file, same failure shape as Vue's dynamic `import()`.
- **The `useFlash()` React hook recall — CORRECTED 2026-07-19 (see Round 3 below): actually 30/30 (100%), not 20/30.** The original report characterized a single raw `cg-trace.sh` call as under-recalling by a third on a completely ordinary hook with no runtime injection or aliasing; Round 3 identified this as the SAME 20-result-cap bug as the Facade finding above, not an independent capability gap — the "20" in both findings was the cap, not a measurement. With the fix, the same query returns 30/30 directly, no cross-check needed to reach the true count (cross-checking remains good general practice, just not load-bearing for this specific number any more).
- **The PHP receiver-type-disambiguation finding (Track A's A1 eval, also directly probed) extends the existing Java-only "codegraph resolves by receiver type, no same-name-across-classes collision" finding to a second language** (this one also holds — ground truth was 4 real callers, well under any result cap): `UserCreationService::handle()` has 4 real callers among ~19 textually-identical `*CreationService->handle(...)` call sites across a dozen-plus unrelated classes; `cg-trace.sh` found exactly the 4 real ones, zero false positives.

**Operational finding, unrelated to query accuracy — a real, cross-platform risk worth knowing before installing cbm on an unfamiliar repo:**
- Indexing this same 1,289-file repo with `codebase-memory-mcp cli index_repository --mode fast` drove host memory usage from ~58GB free to ~6GB free (on a 64GB Windows machine) before the process was force-killed as a safety measure, roughly 30 minutes in with no sign of completing. Free memory returned to ~58GB immediately after the kill, confirming this process was the cause.
- This matches multiple currently-OPEN upstream issues, confirmed by directly reading the tracker rather than assumed: Windows (`DeusData/codebase-memory-mcp#581`, `#832`, `#775`, `#1084`), macOS (`#580` — a `--max-memory` flag request, still unshipped; `#765`; `#317`), Linux (`#363`, `#1070`), plus the umbrella issue `#593`. This is a known, cross-platform, currently-unmitigated risk class for this specific binary, not an artifact of this session's environment.
- `codegraph` indexed the identical repo in 2.6 seconds with no memory concern. See `cbm-blindspots.md`'s "`index_repository` memory usage" section and `SKILL.md`'s Gate check item 4 for the operational guidance this produced.

**Status: findings 1-5 above (Facade, Eloquent scope, React `lazy()`, `useFlash` recall, PHP receiver-type extension, and the memory-usage risk) were reflected in `SKILL.md`, `codegraph-blindspots.md`, `cbm-blindspots.md`, and `lsp-and-native-fallbacks.md` as of this pass (0.0.19 → 0.0.20). Two of them (Facade recall, `useFlash` recall) were subsequently corrected in Round 3 below (0.0.20 → 0.0.21) after a root-cause was found in this skill's own tooling, not in codegraph or the target repos. Track A's test-case-selection lesson is recorded here as methodology guidance, not something that changes any current decision-table row.**

### Methodology note for Round 2 (distinct from Round 1's methodology above)

- Track A used the `skill-creator` plugin's actual eval machinery (general-purpose subagents at default effort, not `deep-analyst` at high effort) — 4 subagent spawns total (2 evals × with-skill/baseline), graded by the orchestrating session directly against pre-established ground truth rather than a separate grader subagent, given the small scope (2 evals).
- Track B's ground truth for all 5 symbols (Facade call count, Eloquent scope caller, React `lazy()` wiring, `UserCreationService::handle()` callers, `useFlash()` callers) was established by direct grep/Read BEFORE building any index, specifically to avoid the index-then-discover-the-question-was-badly-chosen failure mode a prior plan review flagged as a risk.
- `pterodactyl/panel` is NOT added to this skill's permanent dogfood-repo set the way `RuoYi-Vue-Plus`/`plus-ui` are — it was a one-time local clone (`D:/data/pterodactyl-panel-bench`, outside this repo's git tree) used only to generate this round's evidence, and can be deleted without affecting anything documented here.
- Go/Python were deliberately out of scope this round (lowest priority in the target environment's repo-stack distribution — 10% share, only 1-2 repos) — left as a candidate for a future round using the same direct-probe-first methodology.

## Round 3 — `hi.events` (a second Laravel+React data point — and a correction to two Round 2 findings, 2026-07-19)

**Why a second repo, and how it was chosen:** the user asked to continue closing the Laravel+PHP/React+TS evidence gap, specifically requesting a React+TS frontend (not Vue) paired with Laravel. Three candidates were scouted via the GitHub search API before committing to a clone: `koel/koel` (17.2k stars, genuinely clean Laravel+Vue separation, ~87k lines) was rejected because its frontend is Vue, not React; `bagisto/bagisto` (27.7k stars, Laravel e-commerce) was rejected after cloning and inspecting it — its only `.ts` files turned out to be Playwright e2e tests, and `package.json` has no `vue`/`react`/`alpine` dependency at all, meaning it has no real separated frontend to test against despite the language-byte stats suggesting otherwise. `HiEventsDev/hi.events` (3,928 stars, event-ticketing platform) was selected: `backend/` (Laravel, Repository/DTO architecture) and `frontend/` (React 18 + TypeScript, React Router v6.4 data router) are genuinely separate directories with independent `composer.json`/`package.json`, ~2,200 files, well over the 10k-line threshold the user set.

**A critical discovery while probing, not a planned test:** while establishing ground truth for a constructor-injected-interface probe (see below), a `cg-trace.sh` query that should have matched 43 independently-grep-confirmed callers returned exactly 20 — the same round number that, in hindsight, appears in TWO of Round 2's headline findings (Facade: "20 caller records"; `useFlash`: "20/30"). Investigating this traced to a real bug: `codegraph callers`/`codegraph callees` (the raw CLI) default their own `-l` to 20 with no total/hasMore field in their JSON response, and `cg-trace.sh` — this skill's own wrapper script — called both with no `-l` override at all, silently inheriting that cap on every invocation since the script existed.

**Fix and re-verification:**
- `cg-trace.sh` now defaults to `-l 200` (was: uncapped, i.e. the CLI's silent default of 20), accepts an optional 3rd positional arg to go higher, and surfaces a `possiblyTruncated: true` flag plus a hint whenever a fetch returns exactly the limit in use.
- Re-ran BOTH of Round 2's affected queries against the still-available `pterodactyl-panel-bench` clone with the fixed script: Facade file recall corrected from 7/24 (~29%) to **24/24 (100%)**; `useFlash` hook recall corrected from 20/30 (~67%) to **30/30 (100%)**. Both corrections are already reflected in place in Round 2's write-up above and in `codegraph-blindspots.md`.

**New findings from `hi.events` itself, beyond the bug fix:**
- **A genuine (if narrower) false-positive class, found while re-verifying the Facade query**: the corrected 24/24-file result actually returned 28 files; the 4 extra were confirmed to be false positives, not extra real recall — `ForgotPasswordController.php` and 3 `Observer` classes call Laravel's global `event(new SomeEvent(...))` HELPER FUNCTION (dispatches a framework event, no receiver), which codegraph's PHP extractor conflates with the `ActivityLogService::event()` METHOD purely on bare-name match. This is a PHP-specific gap (global functions vs. methods sharing a name) that the earlier "receiver-typed, no collision" Java findings could never have surfaced, since Java has no free-floating functions.
- **Constructor-injected interface binding, a different Laravel DI mechanism from Facades, confirmed to work well**: `EventRepositoryInterface::findById()` (declared on the interface, implemented via inheritance from `BaseRepository`, bound to `EventRepository` in a `ServiceProvider`) — codegraph resolves real callers correctly by querying the INTERFACE method node directly, no understanding of the container binding required, because PHP attaches interface-typed calls to the interface's own node (matching the existing Java interface/impl behavior). 43 real callers found this way, cross-checked 100% against grep ground truth, once the result-cap fix was in place.
- **A third syntactic variant of the dynamic-`import()` blind spot**: React Router v6.4's data-router `async lazy() { await import(...) }` route property (distinct AST shape from both classic `React.lazy()` and Vue Router's callback form) reproduces the identical zero-edge blind spot — same root cause, third confirmed syntax.
- **A methodology self-correction, recorded because it's instructive**: an initial grep-based ground truth for a second hook cross-check (`useIsCurrentUserAdmin`) included a false 5th file, caught only because codegraph's (correct) 4-caller result didn't match — the extra file imports a different, same-file sibling hook (`useIsCurrentUserSuperAdmin`), and the grep had matched the IMPORT PATH string, not a real call to the queried hook. Worth remembering: when a tool's output disagrees with hand-derived ground truth, re-verify the ground truth too, not just the tool.

**Track A (formal eval loop) deliberately not re-run this round:** Round 2 already validated the with-skill/baseline/grading/aggregate_benchmark/eval-viewer machinery works end-to-end and produced a non-discriminating tie (see Round 2's Track A section above, including the lesson about picking harder test cases). Given this round's direct-probe track had already surfaced a real script bug, two corrected findings, one new false-positive class, and one new confirmed-good capability by the time that would have started, re-running the same formal-eval mechanism on similarly-shaped questions had low expected marginal value compared to continuing the probe line that was actively producing results — a deliberate scope call, not an oversight.

### Methodology note for Round 3

- All numeric corrections above were re-derived by directly re-running the exact same `cg-trace.sh` queries from Round 2 against the same still-on-disk `pterodactyl-panel-bench` clone, not estimated or inferred — this is a live repro of the fix, not a theoretical read of the bug.
- `hi.events` ground truth (the 18-call `eventRepository->findById()` scope, the 5 candidate hook callers before the substring-match correction, the React Router lazy-route wiring) was established by direct grep/Read before any codegraph query, same discipline as Round 2.
- `hi.events` is a second one-time local clone (`D:/data/hievents-bench`, outside this repo's git tree), not added to this skill's permanent dogfood set — deletable without affecting anything documented here. `pterodactyl-panel-bench` was kept on disk from Round 2 specifically because Round 3 needed to re-run its exact queries; both can now be deleted.
- cbm was deliberately not indexed against `hi.events` — a precaution given Round 2's memory incident on a similarly-sized repo, not a retry of that failure.

## Round 4 — systematic `--help`-vs-wrapper audit of every `cg-*.sh`/`cbm-*.sh` script (2026-07-20)

**Why this round is shaped differently from Rounds 1-3:** every prior round found bugs by accident, while probing a new repo for a specific question. Round 3's `cg-trace.sh` discovery raised an obvious follow-up question this skill hadn't yet asked systematically: if one wrapper script silently disagreed with its own CLI's documented behavior, do any of the others? This round answered that directly — no new dogfood repo, no new probe questions, just a full cross-reference of every script in `skills/code-navigator/scripts/` against a fresh dump of its underlying CLI's own `--help` output (`codegraph <subcommand> --help`, `codebase-memory-mcp cli <tool> --help`), followed by live verification of anything that looked suspicious, using the still-indexed `RuoYi-Vue-Plus`/`plus-ui` projects and the still-on-disk `hi.events` codegraph index from Round 3.

**Findings, all on the `cbm-*` side (the `cg-*` side was already hardened by Round 3's fix and came back clean except for one positive confirmation):**
1. `cbm-find.sh` hardcoded `limit:20`, lower than `search_graph`'s own documented default of 200, and discarded the `total`/`has_more` fields the CLI ships specifically to detect truncation — confirmed live, `-l Route '.*'` returned 20 of a real 303 routes with zero signal. Same failure shape as Round 3's `cg-trace.sh` bug, on the sibling tool.
2. `cbm-trace.sh`'s "0 results" hint tested field names (`.paths`/`.results`) that don't exist in `trace_path`'s real response (`.callers`/`.callees`) — it reported "0 results" on every single call, confirmed even against a query with 83 real callers. 100% reproduction rate, not a truncation-dependent edge case.
3. The shared `cbm_call()` helper had no safety net for a tool (`trace_path`) that fails with its error JSON on stderr instead of stdout — under `set -e`, this silently killed the whole calling script with zero output on an unknown symbol name, a gap already flagged as a followup in the `cbm-cypher.sh` section of `cbm-blindspots.md` but never fixed until now.
4. `cbm-impact.sh`/`cbm-arch.sh` both referenced fields (`summary`/`risk`, `entry_points`) that don't exist in `detect_changes`/`get_architecture`'s real responses — always null.
5. (Positive finding, not a bug) `cg-node.sh`'s caller/callee trail has no limit flag at all in symbol mode, but confirmed its own `+N more` truncation marker is honest and exact: 12 shown + "+31 more" = 43 on `hi.events`'s `findById`, matching Round 3's already-verified ground truth. Unlike `callers`/`callees` before the Round 3 fix, this command was never silently truncating.

All five items are detailed with full live reproductions in `references/cbm-blindspots.md`'s two new sections (the wrapper-defects section and the `cg-node.sh` truncation-honesty section); fixes 1-4 are live in `scripts/cbm-find.sh`, `scripts/cbm-trace.sh`, `scripts/_project.sh`, `scripts/cbm-impact.sh`, `scripts/cbm-arch.sh`, and (a related fix found while implementing #3) `scripts/_gate.sh`.

**Explicitly NOT a repeat of Round 3's retraction pattern:** Round 3 had to correct two previously-published NUMBERS (Facade 29%→100%, `useFlash` 67%→100%) because those numbers had been read through the buggy cap. This round's bugs are different in kind — items 1-2 are signal/hint defects, not silent data loss in a way any past finding actually relied on. Checked directly: every caller/recall count already on record in this skill's docs was read off the raw `.callers`/`.results` array by whoever ran the query, never off a `hint` field — so nothing published before this round needs a numeric correction. The value here is forward-looking (these scripts now tell the truth going forward), not retroactive.

**Track A/B split not applicable this round:** there was no new probe question requiring ground truth or subagent comparison — this was a code-review-style audit of this skill's own scripts against reference documentation, closer in spirit to the same-day code-review pass already documented in `cbm-blindspots.md`'s `cbm-cypher.sh` section than to Rounds 1-3's field-testing methodology.

## Appendix: raw per-scenario data tables

### Phase 1 — single-tool baseline (backend, RuoYi-Vue-Plus)

| Test | Tool(s) | Calls | Latency (ms) | Output (bytes/~tok) | Accuracy |
|---|---|---|---|---|---|
| B1a interface/impl bridge | `cg-trace` | 1 | 2714 | 1012/253 | bridged:true, both controllers found |
| B1b interface/impl bridge | `cbm-trace` iface+impl | 3 | 1115 | 4596/1149 | iface finds both, impl finds 0 (why cbm needs 2 queries) |
| B2a name-collision+reflection | `cg-trace` | 1 | 1477 | 614/154 | 2/4 recall |
| B2b name-collision+reflection | `cbm-trace` (interface) | 3 | 1126 | 3097/774 | 2/4 recall, 0% FP |
| B2c native fallback | grep getBean | 1 | 174 | 897/224 | recovers other 2/4 |
| B3a exhaustive routes | `cg-find -k route` | 1 | 1516 | 121626/30407 | exact 303/303 |
| B3b exhaustive routes | `cbm-cypher routes` | 1 | 694 | 25878/6470 | 200/303 shown, honest truncation warning |
| B4a hubs (cbm-exclusive) | `cbm-cypher hubs` | 1 | 442 | 2328/582 | sane top 5 |
| B4b cross-layer (cbm-exclusive) | `cbm-cypher cross-layer` | 1 | 538 | 564/141 | 4 violations |
| B5a Chinese term | `cg-find` | 1 | 1342 | 3965/991 | confirmed 12 hits |
| B5b Chinese term | `cbm-grep` | 1 | 678 | 4759/1190 | confirmed |
| B5c Chinese compound | `cg-explore` | 1 | 1305 | 60/15 | confirmed blind (empty) |
| B6a flagship | `cg-explore` | 1 | 1389 | 25383/6346 | correct, 1 call |
| B6b manual chain | `cbm-find`+`trace`+`snippet` | 3-4 | 1164 | 3897/974 | correct, converged same symbol |

### Phase 1 — single-tool baseline (frontend, plus-ui)

| Test | Tool(s) | Calls | Latency (ms) | Output (bytes/~tok) | Accuracy |
|---|---|---|---|---|---|
| F1a dynamic import | `cg-find`+`cg-node` | 2 | 2678 | 13131/3283 | correct, 0 router edge (blind spot confirmed) |
| F1b dynamic import | `cbm-find`+`cbm-trace` | 2 | 660 | 1058/265 | same, 0 callers |
| F2a symbol+usage | `cg-find` | 1 | 1377 | 1170/293 | 2/2 usage recall |
| F2b symbol+usage | `cbm-find` | 1 | 328 | 457/114 | 0/2 usage recall (def only) |
| F3a call chain | `cg-trace` | 1 | 1613 | 827/207 | 1/19 recall + 3 FP noise |
| F3b call chain | `cbm-trace` | 1 | 368 | 330/83 | 1/19 recall, 0 noise |
| F4a arch | `cg-arch` | 1 | 2054 | 8890/2223 | plausible |
| F4b arch | `cbm-arch` | 1 | 297 | 7651/1913 | plausible |
| F5a Chinese term | `cg-find` | 1 | 1355 | 131/33 | FAILED, 0 results |
| F5b Chinese term | `cbm-grep` | 1 | 541 | 571/143 | 2/2 exact |
| F5c Chinese compound | `cg-explore` | 1 | 1225 | 60/15 | confirmed blind (empty) |

### Phase 2 — combination strategies (backend)

| Scenario | Strategy | Calls | Latency (ms) | Output (bytes/~tok) | Result |
|---|---|---|---|---|---|
| C1 union | cg-trace+cbm-trace+grep | 4 | 2493 | 3293/823 | 4/4 recall, 0% FP; gain was 100% from grep |
| C1 wrong-side | cbm-trace impl side | +1 | 398 | 1231/308 | 4/4 = 100% FALSE POSITIVE |
| C2 cheap-first | cbm-find→escalate | 8 | 6056 | 43745/10936 | 2/5 cheap, 3/5 escalated |
| C2 always-cg | cg-find only | 5 | 6956 | 24087/6022 | cheapest overall for this batch |
| C2 always-both | both unconditional | 10 | 8832 | 47543/11886 | worst on every axis |
| C3 raw signal | `dead-code-methods` | 1 | 782 | 22958/5740 | 3 candidates flagged dead |
| C3 full chain | trace+find+trace×3+grep | 10 | 7363 | 6066/1517 | 0/3 actually dead (inverted) |
| C4 raw | `cross-layer` | 1 | 614 | 564/141 | 4 violations |
| C4 +Read check | native Read ×4 | +8 | +~1500 | — | 3/4 real, 1/4 FP (external lib) |
| C5 | `cg-affected` on real commit | 1 | 1273 | 332/83 | affectedTests:[], high traversal, corroborated gap real |
| C5 | `cbm-impact` on committed diff | n/a | n/a | n/a | no capability (live-diff only) |
| C6 cross-repo | native grep both trees | ~7 | ~700 | ~2500/625 | 3/3 matched |
| C6 cross-repo | `cg-find -k route` check | 1 | 1367 | 6489/1622 | confirmed independently |

### Phase 2 — combination strategies (frontend)

| Scenario | Strategy | Calls | Latency (ms, avg) | Output (bytes/~tok) | Result |
|---|---|---|---|---|---|
| D1 Chinese ×5 terms | `cg-find` | 5 | 1347 | 129 each/32 | 0/5 — systematic fail |
| D1 Chinese ×5 terms | `cbm-grep` | 5 | 522 | varies | 5/5 exact |
| D2 globalProperties | native grep | 1 | 75 | 2137/534 | 19/19 vs graph's 1/19 |
| D3 hubs | `cbm-cypher hubs` | 1 | 418 | 541/135 | empty, confirmed useless here |
| D4 union test | cg-find vs cbm-find | 2 | 1420+431 | 1139/504 | codegraph dominates, union adds nothing |

### Phase 3 — relay pattern (backend)

| Scenario | Approach | Calls | Latency (ms) | Output (bytes/~tok) | Verdict |
|---|---|---|---|---|---|
| R1a relay | cbm-find→Read | 2 | ~3674 | 2887/720 | correct, more calls |
| R1b all-in-one | `cg-node` | 1 | 1258 | 1776/444 | correct, WINS here (smaller) |
| R1c flagship | `cg-explore` | 1 | 1427 | 25318/6330 | correct, 14x bytes of R1b |
| R2a grep-first | native grep | 1 | 168 | 25605/6401 | 140/140 hits |
| R2b selective escalate | `cg-trace` on 2 ambiguous | 2 | 6890 | 5546/1387 | both resolved correctly |
| R3 | grep vs full trace on FP candidates | 3 vs 1 | 522 vs 3460 | 641/160 vs 1473 | grep equally correct, 6-9x cheaper |
| R4 | LSP recheck | 0 | n/a | n/a | still unavailable |
| R5 | precise-range Read vs whole-file | 1+4 | 552+reads | 4629 vs 15944 | 3.9x savings |

### Phase 3 — relay pattern (frontend)

| Scenario | Approach | Calls | Latency (ms) | Output (bytes/~tok) | Verdict |
|---|---|---|---|---|---|
| R1a relay | cg-find→Read | 2 | ~1590 | 4155/1039 | WINS here (smallest) |
| R1b all-in-one | `cg-node -f` | 1 | 1268 | 21365/5341 | correct, 5x bytes of relay |
| R1c flagship | `cg-explore` | 1 | 1342 | 16796/4199 | correct, ~4x bytes of relay |
| R2a grep-first | native grep | 1 | 60 | 1907/477 | 12/12 hits instantly |
| R2b verify | `cg-find` component check | 1 | 1472 total | 6770/1693 total | adds certainty, 23x latency |
| R3 | 3rd globalProperties instance (`addDateRange`) | 1+1 | 2088 vs 58 | graph 0/10 vs grep 10/10 | pattern generalizes, 3/3 confirmed |
| R4 | LSP recheck | 1 | negligible | n/a | binary exists, no tool exposed |
| R5 | precise-slice vs whole-file (3 hotspots) | 6 | negligible | 2.7-26.1% of full-file size | savings scale with file size |

### Phase 4 — broad collaboration patterns (backend)

| Scenario | Pattern | Calls | Latency (ms) | Output (bytes/~tok) | Verdict |
|---|---|---|---|---|---|
| G1 rename confidence | trace→reflection-grep→string-grep→Read×4 | 7 | ~1966+reads | ~1427+snippets | full 4/4; graph line number off by 9 (annotation not call) |
| G2 fuzzy question | Glob→grep vs cold `cg-explore` | 3 vs 1 | 43(grep) vs 1402 | 1068 vs 17188 | pre-filter wins, 16x smaller, more precise |
| G3 consensus (2 candidates) | dead-code+grep+cg-trace/node+Read | 6 | ~5580 | ~22958+small | BOTH flip dead→not-dead; one flip exposed shared-blind-spot false consensus |
| G4 config-binding | grep+yml+Read+graph spot-check | 6 | mixed | small+~900/~500 | confirmed present; cg-find has partial yml visibility (surprise) |
| G5 Glob fast path | Glob vs cg-find vs cbm-find | 6 | 139 vs 1328 vs 340 | ~90 vs ~7000 vs ~2400 | Glob wins every axis |

### Phase 4 — broad collaboration patterns (frontend)

| Scenario | Pattern | Calls | Latency (ms) | Output (bytes/~tok) | Verdict |
|---|---|---|---|---|---|
| G1 rename confidence (`addDateRange`) | trace→grep→Read×3 | 9 | ~3500 | ~5200/1300 | graph stage alone 0/10; full chain 10/10 |
| G2 fuzzy question | Glob→grep vs cold `cg-explore` | 3 vs 1 | 148 vs 1341 | 7100 vs 12009 | cheap path cheaper AND more precise |
| G3 consensus (3 components) | graph count+grep+registration check | ~23 | ~7400 | ~13000 | 2/3 flip unused→used (false neg), 1/3 flip used→unused (false pos) |
| G4 env-binding | grep .env vs graph (zero visibility) | 5 | ~2300 | ~2500 | native grep is the whole answer; cbm-grep partially sees .env |
| G5 Glob fast path | Glob vs cg-find vs cbm-find | 6 | 73 vs 1324 vs 338 | 25 vs 4011 vs 500-900 | Glob wins every axis, 18x latency |

## Methodology note (for reproducing or extending this benchmark)

- All 8 runs used `imars-skills:deep-analyst` (effort: high) as the sub-agent type, launched via the Agent tool in background mode, so raw JSON dumps never entered the orchestrating session's context — only the structured markdown tables above did.
- Every agent was instructed to time each call via `date +%s%N` wrapping, measure output via `wc -c` (reported as bytes/4 ≈ tokens, consistent with this repo's own `est.` convention elsewhere), and — critically — to independently verify accuracy claims against real source (grep/Read) rather than trust a tool's own JSON output, since several of the most important findings here (the AOP self-invocation blind spot, the wrong-direction consensus flip, the file-level aggregation collision) were only caught by that verification step.
- Environment: Windows, Git Bash: `codebase-memory-mcp` CLI + `codegraph` (`@colbymchenry/codegraph@1.4.1`) both installed and indexed on both repos; TypeScript LSP plugin installed but its binary invocation fails in this session ("not found or is in an unsafe location") despite `typescript-language-server@5.3.0` being present on PATH; Java has no LSP server installed at all — LSP was therefore excluded as an empirical arm throughout and is noted only where the skill's existing LSP protocol doc already describes its intended role.
- This is a snapshot as of the 0.0.18 plugin release and the index states current on 2026-07-18 — re-verify before trusting a specific number if the underlying CLI versions, index freshness, or repo content have since changed materially.
