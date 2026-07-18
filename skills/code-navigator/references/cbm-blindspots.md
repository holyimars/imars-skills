# Framework blind spots & native fallbacks

The graph is built by tree-sitter + Hybrid LSP static analysis.
The constructs below bind at RUNTIME or in non-code files — the graph cannot see them.
Use the native fallback instead; do not report graph emptiness here as "no usage / dead code".

## Java interface → implementation calls (field-verified 2026-07-16, MANDATORY protocol — not an edge case)
- Blind: a call through an interface-typed variable (`@Autowired`/`@Resource`/constructor-injected field, a method param, ANY variable whose static type is the interface) attaches its `CALLS` edge to the **interface method node**, never to the implementation method node — because tree-sitter has no runtime type info and resolves by static/declared type only.
  This is **not limited to multi-impl interfaces with `@Primary`/`@Qualifier`** — it reproduces on a plain single-implementation `IFooService` → `FooServiceImpl` pair, i.e. the single most common pattern in a layered Spring codebase.
- Confirmed by direct A/B query on RuoYi-Vue-Plus (v0.9.0, field-verified, reproduced twice with different interface/impl pairs).
  `cbm-trace.sh` on `ISysDeptService.selectDeptList` (interface method) → 2 real callers (`SysDeptController.list`, `.excludeChild`).
  `cbm-trace.sh` on `SysDeptServiceImpl.selectDeptList` (the exact same logical method, impl side) → **0 callers**, no error, no warning.
  Repeated with `ISysUserService.selectUserListByDept` / `SysUserServiceImpl.selectUserListByDept` — identical result (1 real caller on the interface node, 0 on the impl node).
- **Consequence for dead-code detection specifically**: any Cypher/query that looks for "Method nodes with no inbound CALLS" will flag EVERY implementation method of EVERY interface-implementing service class as dead code, even when it is the single most-called method in the codebase.
  This is a false-positive generator, not a rare corner case, in any interface-heavy Spring/Java repo.
- Why this can't be fixed in the query itself: the obvious fix (walk `Class -[:INHERITS]-> Interface -[:DEFINES_METHOD]-> Method` and OR the two calls together) requires a 2-hop nested `EXISTS`, which this CLI's Cypher engine rejects (`unsupported EXISTS pattern — only the single-hop form '(var)-[:TYPE]->()' is supported`, tested directly).
  There is no query-side workaround.
- **Mandatory fallback (protocol, not optional)**: before reporting ANY caller count, impact result, or dead-code verdict for a method defined in a class name ending in `Impl` (or any class you know `implements` an interface), ALSO run the same query against the interface's copy of that method (same short name, defined in the `I*`/interface file) and take the union.
  A "0 callers" result on an Impl-suffixed class is not evidence of anything by itself.
- Outbound direction (impl → what it calls) is NOT affected — only inbound/callers/impact queries anchored on the impl method are blind.

## Java + MyBatis / MyBatis Plus
- Blind: XML mapper binding (`namespace` + statement id → Mapper interface method), `<if>/<foreach>` dynamic SQL, `@Select/@Update` SQL semantics.
- Fallback: Grep the mapper interface FQN as XML `namespace=`, then Read the mapper XML directly.
  For "which SQL does method X run": grep the method name inside `src/main/resources/**/ *Mapper.xml`.
- Note: LambdaQueryWrapper call chains DO resolve in the graph; only the SQL/XML semantics behind them are invisible.
- Field-tested on RuoYi-Vue-Plus (2026-07-16): this repo's `*Mapper.xml` files are empty namespace shells (MyBatis-Plus auto-registration only) — zero hand-written `<select>`/`<if>`/`<foreach>` statements found anywhere in the tree.
  On a pure MyBatis-Plus repo like this one, this blind spot simply does not trigger.
  The structural inference above still holds for repos that DO hand-write dynamic SQL, but don't assume every RuoYi-style repo has any — grep for `<if\|<foreach` first to check before treating this as a live concern.

## JS/TS + dynamic `import()` (field-verified 2026-07-16 on plus-ui / Vue Router)
- Blind: components registered via `() => import('@/views/x.vue')` (route-level code splitting — the standard Vue Router / React Router lazy-loading pattern) produce NO edge from the router file to the target component.
  Only statically-imported (`import X from '...'` at the top of the file) components get an `IMPORTS` edge.
- Confirmed on plus-ui's `src/router/index.ts`: it dynamically imports `login.vue`, `register.vue`, `error/404.vue`, `redirect/index.vue` and more — graph query for its outbound edges returns exactly ONE `IMPORTS` edge (the one static `import Layout from '@/layout/index.vue'`) and nothing else.
  Every dynamically-imported route component is invisible.
- Fallback: for "who/what routes to this Vue/React component", grep the component's file path (or its basename) directly inside router config files (`src/router/**`, `*.route.ts`, etc.) rather than trusting `cbm-trace.sh`/graph IMPORTS edges.
  Do not report a dynamically-lazy-loaded component as unused based on 0 inbound graph edges.

## PHP + Laravel
- Blind: Facades (`Cache::get` → container via __callStatic), Eloquent magic methods / dynamic scopes / relationship access, container string bindings (`app('foo')`, `bind/singleton` with string keys), Blade logic, event/listener wiring in providers.
- Fallback: For a facade, grep its accessor in `config/app.php` aliases or the Facade class `getFacadeAccessor()`, then trace the bound service in `app/Providers/*.php`.
  For Eloquent scopes grep `scopeXxx`.
  Read Blade templates directly.
- Not yet field-verified by this team on a real repo (carried over from prior research) — treat as a structural inference, spot-check before relying on it for a decision.

## Python + Django
- Blind: dynamic URLconf composition, signals (`connect()` at runtime), settings-driven imports.
- Fallback: Read `urls.py` chain directly; grep `.connect(` for signals.
- Not yet field-verified by this team on a real repo (carried over from prior research) — treat as a structural inference, spot-check before relying on it for a decision.

## Runtime bean-name lookup (Spring `getBean(dynamicName)`, field-verified 2026-07-16)
- Blind: a call resolved via a runtime-computed string (e.g. `SpringUtils.getBean(grantType + "AuthStrategy")`) has no static target at all — tree-sitter cannot know which of N `@Service("xxxAuthStrategy")` beans gets called, because the answer depends on a request parameter at runtime.
- Confirmed on RuoYi-Vue-Plus's `IAuthStrategy` strategy pattern (`ruoyi-admin/.../service/IAuthStrategy.java`): 5 implementations (`EmailAuthStrategy`, `PasswordAuthStrategy`, `SmsAuthStrategy`, `SocialAuthStrategy`, `XcxAuthStrategy`), each registered under a computed bean name, looked up via `SpringUtils.getBean(beanName)` inside a `static` interface method.
  No amount of graph querying will connect `AuthController` to any specific implementation — this is not a graph gap, it is genuinely undecidable without running the code.
- Fallback: grep the bean-name construction pattern (here `+ IAuthStrategy.BASE_NAME` / `@Service("..." + ...)`) to enumerate all candidate implementations by hand; do not expect `cbm-trace.sh` to find a path from caller to any specific impl.

## Cross-repository analysis (front-end + back-end split, e.g. this monorepo pair)
- Each repo is indexed as its own independent `project` (verified: `plus-ui` and `RuoYi-Vue-Plus` are separate graphs, separate node/edge counts, no shared nodes).
  There is currently no multi-root/aggregated-workspace graph — this is a deliberate, working setup, not a missing feature blocking anything documented here.
- Consequence: a question spanning both repos (e.g. "which frontend page calls this backend API") requires TWO separate graph calls (one per project, via `--name`/`-p` project targeting) plus manual correlation of the Vue API-call string against the backend `Route` node path.
  The graph will not do this join for you.
- This limitation is identical for codegraph — its index is likewise scoped to whatever directory it was run in (no `--name` needed, but the same one-index-per-repo boundary), confirmed by direct test, not just inferred from the architecture.
- **Field-verified recipe (2026-07-18, see `references/tool-collaboration-benchmark.md` for the full run)**: picked 3 real frontend API request URLs from `plus-ui/src/api/system/dict/*.ts`, grepped the URL path fragment directly against `RuoYi-Vue-Plus`'s Java controllers (`grep -rn "<path-fragment>" --include=*.java`), and independently cross-checked with `cg-find.sh -k route` on the backend side — 3/3 matched a real endpoint.
  This is the only reliable path for this question shape today; treat any future "cross-repo query" flag on either CLI's changelog as worth re-testing, but do not assume one exists.

## `cbm-cypher.sh`'s officially-relied-on aggregate templates — 2 of 5 were silently broken, now fixed, plus 3 more issues found in a same-day code-review pass (field-verified 2026-07-17)

The decision table has always pointed whole-graph questions (dead code / hubs / cross-layer / routes) at `cbm-cypher.sh` as this skill's flagship advantage over per-symbol tools — that claim had never actually been executed and checked end-to-end before this pass.
Turned out 2 of the 5 templates were broken in ways that produced a confidently-formatted, plausible-looking WRONG answer rather than an honest error — the same dangerous failure shape as `codegraph explore` on aggregate questions, see the sibling `codegraph-blindspots.md` in this same skill.

- **`hubs` was completely non-functional.**
  The shipped query was `MATCH (c:Class) RETURN ... ORDER BY c.degree DESC LIMIT 20`.
  Ran `MATCH (c:Class) RETURN keys(c) LIMIT 3` directly: the schema is `name, qualified_name, label, file_path, start_line, end_line` — **`degree` does not exist as a property on Class nodes at all.**
  `ORDER BY` on an always-null column is a silent no-op, so the "top 20 hubs" was really just native scan order.
  Confirmed the practical damage on RuoYi-Vue-Plus: `TestTree` (a test-only domain class) and `BackProcessBo`/`SysDeptVo` (plain data objects) ranked in the top 20 "god classes," while zero real utility/base classes appeared.
  Fixed in `cbm-cypher.sh` by aggregating real inbound `CALLS` edges across each class's methods (`MATCH (m:Method)<-[:CALLS]-() WHERE m.parent_class IS NOT NULL RETURN m.parent_class, count(*) ... ORDER BY count(*) DESC`) rather than counting direct calls to the Class node itself.
  Tried that naive version first and it undercounts badly, because a `CALLS` edge into a `Class` node is a **constructor call only** (`new Foo()`); ordinary `obj.method()` calls attach to the `Method` node, not the class.
  The fixed query's top results — `StringUtils` (279), `R` (259), `LoginHelper` (230), `BaseMapperPlus` (133), `StreamUtils` (110), `BaseController` (70) — are exactly the utility/base classes a Java engineer would expect to top this list, a dramatic accuracy jump from the broken version.
  Caveat confirmed by testing on plus-ui (the JS/TS/Vue repo): this class-level aggregation returns 0 rows there, because plus-ui has essentially no `Method`-labeled nodes (1 total) — Vue/TS code in this graph is modeled as `Function`, not class methods.
  This is not a bug, it's a real modeling mismatch: **the fixed `hubs` template only works for class/OOP-heavy repos (Java, etc.); it has no signal for a function-oriented JS/TS/Vue codebase**, which would need a `Function`-level equivalent (not built — out of scope for this pass, note it if asked to extend this template).
- **`cross-layer` hard-failed on its own documented default invocation.**
  Running `cbm-cypher.sh cross-layer` with zero args (the way the SKILL.md decision table shows it) returned `unexpected operator at pos 38` on every single call — not a graceful `hint`, a raw Cypher parser error surfaced straight to the caller.
  Isolated the cause by testing 3 query variants directly: `coalesce(a.file_path, a.file) CONTAINS '...'` in a `WHERE` clause breaks the parser, while the same `coalesce(...)` works fine inside `RETURN`, and a plain `a.file_path CONTAINS '...'` (no coalesce) works fine in `WHERE`.
  Also confirmed via `WHERE n.file_path IS NULL` that 0 of 2163 Method nodes in this repo actually lack `file_path`, so coalesce's `.file` fallback was never doing anything useful here anyway.
  Fixed by dropping `coalesce()` from the `WHERE` clause only (kept in `RETURN` for display).
  The fixed query returns exactly 4 real controller→mapper layer violations on RuoYi-Vue-Plus (e.g. `TestBatchController.add` calling `insertBatch` directly on a Mapper) — a small, plausible number for a codebase that mostly routes through its service layer correctly, which is itself a useful signal (the rare violations are worth looking at precisely because they're rare).
- **`dead-code` (the plain `Function`-label template, distinct from `dead-code-methods`) has its own systematic false-positive pattern, not previously documented.**
  Every Java interface method declaration turns out to be double-registered in the graph as BOTH a `Method` node AND a separate `Function` node at the identical file/line — confirmed via `MATCH (n) WHERE n.name = "..." RETURN labels(n), n.file_path` on 5 different interface methods, each producing exactly this Method+Function pair on the interface file, plus a third `Method` node on the impl side.
  Real `CALLS` edges from real callers attach only to the `Method`-labeled twin (consistent with the interface/impl section above) — the `Function`-labeled twin is structurally incapable of ever having an inbound edge, so `dead-code` reports **every single interface method in the codebase as dead**, independent of and in addition to the already-documented impl-side blind spot (which only affects `dead-code-methods`, the `Method`-label template).
  This is NOT a blanket "Function label is broken" finding — confirmed 95 of 449 Function nodes in this repo DO have real inbound CALLS edges, and a genuinely-unused enum method (`FormatsType.getFormatsType`) was correctly flagged with zero grep hits repo-wide to confirm it really is dead.
  The false-positive is specific to interface method declarations; `cbm-cypher.sh` now emits a warning on every `dead-code` call telling the caller to cross-check any `*Service`/`I*`-shaped hit with `cbm-trace.sh` first.
- **`dead-code-methods` has a further false-positive shared with codegraph's own call-chain commands, not fixable by cross-checking with the other tool.**
  A candidate flagged dead by `dead-code-methods` (`SysDictTypeServiceImpl.selectDictTypeByType`, an `@Cacheable` method) turned out to have a real caller reached only through `SpringUtils.getAopProxy(this).selectDictTypeByType(...)` — a self-invocation through the Spring AOP proxy, done specifically to route the call through the proxy so `@Cacheable` actually triggers.
  `cg-trace.sh`/`cg-node.sh` were run as an independent cross-check and ALSO missed this call site — see `codegraph-blindspots.md`'s dedicated section for the full repro on that side.
  The two signals agreeing here is not corroboration: both share the same underlying gap (neither tool's static extractor resolves a call reached through `getAopProxy(this)`), so before trusting any dead-code verdict on an AOP-annotated method (`@Cacheable`/`@CachePut`/`@CacheEvict`), grep `SpringUtils.getAopProxy(this).<method>(` as a standing check, the same discipline as the existing `SpringUtils.getBean(X.class)` spot-check.
- **`routes` was already accurate** — spot-checked its output against real controllers (`/monitor/logininfor/list`, `/demo/sms/sendAliyun`, etc.), all well-formed and traceable to real `@RequestMapping`/`@GetMapping` sites.
  No change needed.
  `Class` nodes were separately found to ALSO represent MyBatis XML `<select>/<update>` statement elements — e.g. a Class node literally named `select` with `qualified_name` ending `TestDemoMapper.select`, `file_path` pointing at the `.xml`.
  This doesn't affect `routes` (different node label) but is why the naive "count calls into Class nodes" hub query above needed the parent_class-aggregation rewrite rather than a simple `.xml`-path filter; noted here in case a future template touches raw `Class` nodes again.
- **Methodology note**: all five templates were executed directly against RuoYi-Vue-Plus's real index this pass (not read from the script source and assumed correct) — the same discipline as the interface/impl and dynamic-`import()` findings above.
  Re-run this spot-check after any `codebase-memory-mcp` version bump; a schema change could silently reintroduce or shift these issues.
- **Same-day code-review follow-up found 3 more issues in this same template set, all now fixed.**
  A structured review of the just-fixed script (SOLID/security/quality pass, not a fresh field test of new query shapes) surfaced these by re-reading the fix with the discipline of "would a wrong answer here look plausible" rather than just "does it run":
  1. **Silent truncation, present on every fixed-LIMIT template, never previously checked.**
     None of the templates compared their returned row count against their own `LIMIT`, so a true result set bigger than the cap was returned looking exactly like a complete one — the same dangerous shape as the `hubs`/`cross-layer` bugs above, just not yet caught.
     Ran a direct `count(*)` against each template's `WHERE` clause with no `LIMIT` and compared: `routes` LIMIT 200 vs true count **303** (103 hidden, 34%); `dead-code` LIMIT 100 vs true count **348** (248 hidden, 71%); `dead-code-methods` LIMIT 100 vs true count **1159** (1059 hidden, 91%).
     This directly contradicts the "`routes` was already accurate — no change needed" line earlier in this section — that check only verified individual row correctness (real controllers, well-formed paths), never verified the total count against the cap, so a third of the real routes were being silently dropped the whole time.
     Fixed generically: `cbm-cypher.sh` now runs a cheap follow-up `count(*)` whenever a template's result count exactly equals its `LIMIT`, and emits a stderr warning with the real total and how many rows are hidden.
     `hubs` is deliberately exempt — a "top 20" ranking has no "true total" to compare against, capping there is the intended behavior, not data loss.
  2. **`cross-layer`'s `layerA`/`layerB` arguments were spliced into the Cypher string with no escaping.**
     Confirmed live: passing an argument containing a single quote (`/controller/' OR '1'='1`) crashes the parser (`expected token type 85, got 86`) instead of being treated as a literal path-fragment filter — an injection-shaped input-handling defect, not merely a crash-on-weird-input bug, even though a full working injection payload for this specific restricted Cypher grammar was not constructed.
     Fixed by stripping `'` and `\` from both arguments before interpolation; re-tested with the same payload above post-fix — returns a normal empty-result JSON instead of crashing.
  3. **This script's underlying `cbm_call` (in `scripts/_project.sh`) has no JSON-validation safety net, unlike this skill's codegraph-side `cg_call()` (see `scripts/_gate.sh`).**
     Before today's fixes, both the `hubs` degree-ordering bug and the `cross-layer` coalesce bug manifested as a *raw, unhandled crash* reaching the caller — not a graceful `{"error", "hint"}` response — because nothing between the Cypher engine and stdout ever validated the output was JSON.
     This violates the "every script returns valid JSON with a hint, never a raw crash" contract both `SKILL.md`s describe as the mandatory-sequence guarantee.
     Fixed LOCALLY inside `cbm-cypher.sh` (a `run_query` wrapper, same tempfile + `jq empty` pattern as `cg_call()`) so this script now upholds that guarantee regardless of future template bugs.
     Not fixed: the shared `_project.sh::cbm_call` itself, which `cbm-find.sh`/`cbm-grep.sh`/`cbm-trace.sh`/`cbm-impact.sh`/`cbm-snippet.sh`/`cbm-arch.sh` all call directly — those 6 scripts still have no equivalent protection.
     Widening the fix to the shared helper would touch every script in this skill in one pass; deliberately left as a follow-up rather than done inside an already-large review, to keep this change reviewable and its regression surface small.

## `cbm-find.sh -s` (semantic business-term search) — 2 real bugs found and fixed, plus a language limitation that is NOT fixable (field-verified 2026-07-17)

This skill's own decision table pointed Chinese business-language questions (业务词) at `cbm-find.sh -s` as the dedicated tool — that path had never been executed and checked end-to-end before this pass, the same gap that produced the `cbm-cypher.sh` bugs above.

- **Bug 1 (fixed): `semantic_query` was sent as a JSON string, not an array.**
  The CLI's own `--help` for `search_graph` is explicit: `--semantic-query <array> ... MUST be an ARRAY of keyword strings ... NOT a single string`. The script was building `{semantic_query:$q}` with `$q` a plain string (`jq --arg`).
  This does NOT error — it silently returns near-random results with no signal that anything is wrong: on this repo, the ENGLISH string `"dict label"` scored top hit ~0.03 with irrelevant results (`AuthTopIamRequest`, `selectDeptLeaderById`, `doFilter` — nothing to do with dictionaries), while the equivalent 2-element array `["dict","label"]` scored ~0.97 on exactly the right hits (`getDictValue`, `getDictLabel`, `getAllDictByDictType`, all in `DictService`/`SysDictTypeServiceImpl`) — same query text, same repo, same index.
  Fixed: the script now splits the query on whitespace into a JSON array before calling (`jq -R '[splits("[ \t]+")] | map(select(length>0))'`), matching the CLI's own documented example shape (`["send","pubsub","publish"]`).
- **Bug 2 (fixed): the script's output formatter read `.results`, but semantic hits live in a separate `.semantic_results` field.**
  Confirmed directly: even after fixing bug 1, `.results` for a `semantic_query` call is an unranked dump of arbitrary graph nodes (e.g. `.codebase-memory/.gitattributes`, `.gitee/ISSUE_TEMPLATE/*.yml` — literally repo config files, nothing to do with the query) — the real ranked hits with `score` were sitting untouched in `.semantic_results` the whole time. Fixed: the script now reads `.semantic_results` when `-s` is set.
- **Limitation (NOT fixable in this script): the embedding model does not support Chinese query text.**
  Even with both bugs fixed, a Chinese business term scores in the same near-random range as the string bug, regardless of whether it's sent as a single-element array (the whole phrase, e.g. `["字典标签"]`) or split into multiple single-character/word elements (`["退款","审核"]`) — top scores observed were 0.02–0.10 with irrelevant hits (rate-limiter config, WebSocket handlers, monitor admin `main()` — no relation to the query), essentially indistinguishable from noise. This reproduces on every Chinese query tried, not an isolated phrase.
  This is a property of the underlying vector model, not something a wrapper script can work around.
  **Correct fallback for Chinese business terms: `cbm-grep.sh` (`search_code`, literal text match), not `cbm-find.sh -s`.** RuoYi-Vue-Plus's Javadoc comments are written in Chinese and contain the business term verbatim (e.g. `/** 根据字典类型和字典值获取字典标签 */` on `DictService.getDictLabel`) — confirmed `cbm-grep.sh '字典标签'` returns 14 correctly-ranked, genuinely relevant results (`DictService`, `SysDictData`, `SysDictDataBo`, the `dictLabel` field, etc.) in 398ms, because it's a literal grep-style match over source text, not an embedding lookup. BM25 full-text search (`search_graph`'s `query` param, NOT currently used by any script in this skill) was also tested and also fails on Chinese — it tokenizes on whitespace/camelCase boundaries per its own `--help`, and Chinese has neither, so a Chinese query degrades to the same unranked full-graph dump. Only the literal-match path (`search_code`) is language-agnostic here.
  `cbm-find.sh` now emits this same guidance as a `hint` whenever a semantic query's top score is below 0.3 (a threshold picked with wide margin: confirmed-good matches score ~0.9+, confirmed-broken ones score ~0.02–0.10).
- **Methodology note**: root-caused by isolating each variable independently rather than accepting the first plausible explanation — tested string-vs-array holding language constant (both English: 0.03 vs 0.97, confirming Bug 1 is real and language-independent) AND array-vs-string holding language constant (both Chinese: ~0.02–0.03 either way, confirming the Chinese limitation survives the Bug-1 fix and is a separate root cause, not the same bug restated).

## CALLS-edge resolution is name-only — same-named methods on UNRELATED classes collide, not just interface/impl pairs (field-verified 2026-07-17)

Distinct from the Java interface→impl blind spot above (that one is about which NODE of a *related* interface/impl pair gets the edge). This one is about the edge landing on the wrong *method entirely*, on a class with no relationship to the real target.

- Traced all inbound `CALLS` edges to `DictService.getDictLabel(String dictType, String dictValue, String separator)` (a 3-arg business method) and verified each one against source by hand. **6 of 10 edges (60%) were false positives**: they were really calls to `getDictLabel()` — a zero-arg Lombok-generated getter on `SysDictDataVo`/`SysDictData` (from a `dictLabel` field under `@Data`), a completely unrelated class with no inheritance/interface relationship to `DictService`. Examples: `SysDictTypeServiceImpl.getAllDictByDictType` line `map.put(vo.getDictValue(), vo.getDictLabel())` — `vo` is a `SysDictDataVo`, so `.getDictLabel()` is the Lombok getter, not the business method; a method reference `SysDictDataVo::getDictLabel` inside `StreamUtils.toMap(...)` produced the same false attachment.
  Only 4 of 10 were real (verified via source: `ExcelDictConvert.convertToExcelData`, `DictPatternValidator.isValid`, `DictTypeTranslationImpl.translation`, `SysNoticeController.add` — all genuinely call `SpringUtils.getBean(DictService.class).getDictLabel(...)` or `dictService.getDictLabel(...)`).
- Root cause: `CALLS` edges resolve by simple method name only — no parameter count, parameter type, or receiver type check. Any business method whose name collides with a same-named getter/setter (the single most common Java naming collision, since `@Data`/`@Getter` on every DTO/VO/BO/Entity generates `getX()`/`setX()`/`isX()` for every field) will have its caller list polluted by every unrelated call to that getter anywhere in the codebase.
  This is NOT rare in a Lombok-heavy codebase — this repo uses `@Data` on essentially every domain/DTO/VO/BO class, so any business method named `getDictLabel`/`getDictValue`/`getName`/`getStatus`/etc. is at risk purely from naming coincidence.
- Consequence for `cbm-trace.sh`: a caller/callee list for a method whose name starts with `get`/`set`/`is` (or otherwise matches a plausible field-accessor shape) cannot be trusted at face value — always spot-check a sample of the returned callers against source (does the receiver's declared type actually have this method as the business method, not a generated accessor?) before reporting a caller count or "who calls X" answer as fact.
  A quick heuristic: business methods on Service/Mapper interfaces almost always take ≥1 parameter (queries need at least a key; commands need a payload) while Lombok getters take 0 — a caller whose call-site has zero arguments is a strong hint it's actually hitting the accessor, not the business method.
- Consequence for `cbm-cypher.sh dead-code`/`dead-code-methods`: the same name-only resolution means a method can look "used" (nonzero inbound `CALLS`) purely because an unrelated getter with the same name is called elsewhere — a false NEGATIVE for dead-code detection, the opposite direction from the interface/impl false-positive already documented above. Both directions of error stem from the same root cause (name-only resolution) and can coexist on the same method.
- Corroborating positive data point: this is a precision problem on ambiguous names, not a blanket failure. Ran the same source-verification against 8 zero-inbound-degree candidates that are NOT interface methods and NOT getter/setter-shaped (`RedisUtils.getCacheMapKeySet`/`.getMultiCacheMapValue`/`.addMapListener`, `StringUtils.containsAnyIgnoreCase`, `SpringUtils.getAliases`, `DateUtils.difference`, `EncryptUtils.encryptBySm3`, `MybatisExceptionHandler.findCause`) — all 8 confirmed genuinely dead via repo-wide grep (zero external references). Concrete utility-class methods with distinctive names are reliable; the risk is specifically name-collision-prone methods (getter/setter shape, or a name repeated across unrelated interfaces like `updateById`/`selectList` inherited from MyBatis-Plus's `BaseMapper`).

## `get_architecture` hotspot ranking — aggregate stats tolerate the name-collision noise, unlike single-target traces (field-verified 2026-07-17)

Spot-checked `cbm-arch.sh`'s top hotspot (`R.ok`, `fan_in: 172`) against a repo-wide grep for `R.ok(` — 179 raw text matches across 49 files, ~4% difference.
Given the CALLS-edge name-collision issue documented above, exact figures from this tool should never be taken as precise, but a ~4% gap is well within "this is clearly the most-used utility in the codebase" territory — aggregate/ranking questions (hotspots, architecture layers, module boundaries) are far more tolerant of per-edge misattribution than a single-target trace, because misattributed edges mostly land within the same broad popularity tier rather than fabricating a top result out of nothing. Trust `cbm-arch.sh` for relative ranking and "what's a big deal here" questions; don't quote its fan-in numbers as exact.

## `index_repository` project-identity resolution is sensitive to how `--repo-path` is given (field-verified 2026-07-17, defensive note — no script in this skill triggers it)

Running `codebase-memory-mcp cli index_repository --repo-path . --mode fast` (relative path, no `--name`) from within `D:/data/RuoYi-Vue-Plus` did NOT update the existing `RuoYi-Vue-Plus` project — it silently created a SECOND, separate project (observed name: `D-data-RuoYi-Vue-Plus`, derived from the resolved absolute path) pointing at the same `root_path`. Queries against the original project name kept returning the old (pre-reindex) data with no warning that a duplicate now existed; `list_projects` was the only way to notice.
No script in this skill is affected: `_project.sh` always resolves off `git rev-parse --show-toplevel` (an absolute path) and its own error hint for an unindexed repo already tells the user to pass an explicit `--name`; `_project.sh`'s exact-match-before-fuzzy-suffix resolution (added after the stale-benchmark-clone collision noted in that file) would also prefer the correctly-named project over a fresh accidental duplicate in most cases.
Flagging this purely as a caution for anyone manually re-indexing outside these scripts: always pass an absolute `--repo-path` and an explicit `--name` matching the existing entry in `list_projects`, and check `list_projects` after re-indexing if the row count looks unexpectedly unchanged.

## `trace_path --direction` accepts exactly 3 values; anything else silently no-ops (field-verified 2026-07-17, correction to a prior over-broad claim)

`--direction` only recognizes `both` (also the default when omitted), `inbound`, and `outbound` — `cbm-trace.sh`'s `in`/`out`/other→`both` mapping already uses the correct underlying values and is unaffected.
Worth recording because the failure mode is dangerous if anyone changes this script or calls the CLI directly with a guessed value: every one of `up/down/in/out/incoming/outgoing/upstream/downstream/ancestors/descendants/callers/callees/callers_only/callees_only/predecessors/successors/reverse/forward/backward` was tested directly against the CLI and every single one returns an empty, no-error result — indistinguishable from "this function truly has zero callers/callees" unless you already know to be suspicious. `cbm-trace.sh`'s existing 0-result hint ("the name must be EXACT...") does not currently cover this case (a bad direction value, not a bad name) — low priority since the script itself never passes a bad value, noted here so a future edit to this script doesn't reintroduce it via a plausible-looking direction string.

## General
- Reflection / dynamic dispatch / DI decided by config: graph edges may be missing or land on interfaces (see the dedicated Java interface section above for the specific, verified failure mode).
- **Methodology note (2026-07-16):** do not carry forward blind-spot claims sourced from a GitHub issue number without opening the issue and confirming it says what you think it says.
  Of 5 issue numbers cited in an earlier research pass on this tool (#281, #500, #734, #1033, #1187), only **#734** (`Java/Spring: class-level @RequestMapping prefix dropped from Route nodes`, open, milestone 0.9.1-rc) actually matched its claimed subject when checked directly against the tracker; the other four pointed at unrelated or nonexistent issues.
  Treat any issue-sourced claim as unverified until read firsthand.
