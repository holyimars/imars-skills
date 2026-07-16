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

## General
- Reflection / dynamic dispatch / DI decided by config: graph edges may be missing or land on interfaces (see the dedicated Java interface section above for the specific, verified failure mode).
- **Methodology note (2026-07-16):** do not carry forward blind-spot claims sourced from a GitHub issue number without opening the issue and confirming it says what you think it says.
  Of 5 issue numbers cited in an earlier research pass on this tool (#281, #500, #734, #1033, #1187), only **#734** (`Java/Spring: class-level @RequestMapping prefix dropped from Route nodes`, open, milestone 0.9.1-rc) actually matched its claimed subject when checked directly against the tracker; the other four pointed at unrelated or nonexistent issues.
  Treat any issue-sourced claim as unverified until read firsthand.
