# Framework blind spots & native fallbacks

The graph is built by tree-sitter + Hybrid LSP static analysis.
The constructs below bind at RUNTIME or in non-code files — the graph cannot see them.
Use the native fallback instead; do not report graph emptiness here as "no usage / dead code".

## Java + MyBatis / MyBatis Plus
- Blind: XML mapper binding (`namespace` + statement id → Mapper interface method), `<if>/<foreach>` dynamic SQL, `@Select/@Update` SQL semantics.
- Fallback: Grep the mapper interface FQN as XML `namespace=`, then Read the mapper XML directly.
  For "which SQL does method X run": grep the method name inside `src/main/resources/**/ *Mapper.xml`.
- Note: LambdaQueryWrapper call chains DO resolve in the graph; only the SQL/XML semantics behind them are invisible.

## PHP + Laravel
- Blind: Facades (`Cache::get` → container via __callStatic), Eloquent magic methods / dynamic scopes / relationship access, container string bindings (`app('foo')`, `bind/singleton` with string keys), Blade logic, event/listener wiring in providers.
- Fallback: For a facade, grep its accessor in `config/app.php` aliases or the Facade class `getFacadeAccessor()`, then trace the bound service in `app/Providers/*.php`.
  For Eloquent scopes grep `scopeXxx`.
  Read Blade templates directly.

## Python + Django
- Blind: dynamic URLconf composition, signals (`connect()` at runtime), settings-driven imports.
- Fallback: Read `urls.py` chain directly; grep `.connect(` for signals.

## General
- Reflection / dynamic dispatch / DI decided by config: graph edges may be missing or land on interfaces.
  Callers/impact counts on IMPLEMENTATION classes of multi-impl interfaces may undercount — check both the interface method and the impl method before concluding.
