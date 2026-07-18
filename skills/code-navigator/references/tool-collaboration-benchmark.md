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
