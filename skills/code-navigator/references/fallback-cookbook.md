# 原生 grep/Read 兜底速查表

以下构造对两个图谱工具(codebase-memory-mcp / codegraph)都是盲区或不完整覆盖——不要在这些构造上花一次图谱工具调用,直接用对应的 grep 配方。每条结论背后的完整实机验证过程存档在 `research/code-navigator/`(不随 skill 分发,仅供复核)。

| 构造 | 两个工具的表现 | grep 配方 |
|---|---|---|
| MyBatis XML `namespace=` 绑定、`<if>/<foreach>` 动态 SQL | 两者都把 `.xml` 当文件节点,提取 0 个符号,不建绑定 | grep mapper 接口全限定名作为 `namespace="..."`,再 Read 该 XML |
| Vue Router `() => import('@/views/x.vue')` / React `lazy(() => import(...))` / React Router v6.4+ `async lazy(){ await import(...) }` | 三种写法、Vue 和 React 两个框架都实测复现(不是 Vue 特有),两者都产生不出路由文件→组件的边。注意一个假象:`cg-find` 会同时返回路由文件里的懒加载常量和目标文件——那只是两边同名(懒加载变量习惯上就叫目标文件名),不是解析成功,`cg-impact.sh` 实测 `edgeCount: 0` | grep 组件文件路径/文件名,直接在路由配置文件里搜 |
| 挂在 `app.config.globalProperties` 上的函数(如 `parseTime`),调用形态是 `proxy.parseTime(...)` | 两个图谱工具 + TypeScript LSP 三者全部只能召回 0-1/10-19,是三方共享盲区,不是图谱工具特有 | `grep -rn "proxy\.<name>\|\.<name>("`,先 grep `src/plugins/index.ts` 之类的注册文件列出全部注册函数 |
| `SpringUtils.getBean(computedString)`(运行时字符串拼出 bean 名) | 静态分析原理上无法确定,codegraph 会诚实列出所有实现候选("有一个会被调用,但不知道是哪个"),不是"已解析" | grep bean 名拼接逻辑本身(如 `+ IAuthStrategy.BASE_NAME`),手动枚举候选 |
| `SpringUtils.getBean(X.class)`(单目标确定性查找) | codegraph 完全看不到(0/2 实测);cbm 靠名字匹配可能碰巧看到但不可信 | 每次报告接口方法的调用者数/影响面之前,标准巡检:grep `SpringUtils.getBean(<Interface>.class)` |
| `SpringUtils.getAopProxy(this).<method>(...)` 自调用(通常伴随 `@Cacheable`/`@CachePut`/`@CacheEvict`) | 两个工具都看不到——"两个工具都说这是死代码"在这里不能当作互相印证,因为它们共享同一个盲区 | grep `SpringUtils.getAopProxy(this).<method>(` |
| `class X extends Y` 继承方向 | codegraph 只能从父类反向看到子类列表(还被误标成 `Called by ←`,容易误读成调用关系);cbm 完全不建模这个关系 | 直接 grep 类声明行 `class X extends Y` |
| Laravel 容器字符串绑定 `app('foo')`(目标在 vendor 代码里) | 两者都看不到,没有可查的目标节点 | grep `app('<string>')` / `::make('<string>')` |
| Laravel Blade 视图路径字符串绑定(`markdown: 'emails.orders.x'`) | 两者都是干净的 0 召回 | grep 视图路径字符串,再 Read 对应 `.blade.php` |
| Laravel `ServiceProvider` 里的 `Event::listen()` 事件监听器注册 | 两者都是干净的 0 召回,和 Spring 计算 bean 名一样是运行时才能确定的 | grep `Event::listen(` 所在的 ServiceProvider,再读监听器类的 `handle` 方法 |
| Laravel **内置** Facade(`Cache::`/`Auth::`/`DB::`,目标是 vendor 代码) | 两者都完全看不到——根本没有可查的目标节点(区别于下面"应用自定义 Facade"的情况,见 `tool-divergence.md`) | 直接 grep Facade 调用点,不要查图谱 |
| Eloquent 本地 scope(`scopeXxx` 声明,调用时去掉 `scope` 前缀 `->xxx(...)`) | 两者都是干净的 0 召回(命名和真实声明对不上);已排除"文件没被索引"这种粗解释——调用点所在文件的其它节点都查得到,缺的就是这条边 | grep 去掉前缀的调用形态 `->xxx(` / `::xxx(` |
| Eloquent 关系方法通过魔术属性访问(`$model->relation`,不带括号) | cbm 确认干净 0 召回;codegraph 同构造理论上一样(魔术 `__get`,没有可提取的调用形态) | grep 魔术属性访问形态,不加括号 |
| Go 跨包 struct 字段方法调用(`type Foo struct{ Store *store.Store }`,调用 `s.Store.Method(...)`) | **两个工具最严重的共同盲区**——不是接口/实现拆分或链式调用,是 Go 最普通的依赖模式,实测 0/13 真实跨包调用者 | `grep -rn "\.<FieldName>\.<MethodName>("`,当作 Go 仓库这类问题的**主路径**,不是兜底 |
| 配置键绑定(`@Value("${key}")` ↔ `application.yml`/`application-{profile}.yml`;`import.meta.env.VITE_X` ↔ `.env.*`) | 两者都只是部分可见,不是干净盲区也不能只信图谱结果;`.env.*` 各变体覆盖不均匀(同一项目里 `.env.production` 可能零索引,`.env.development` 却完整) | grep 注解/引用侧 + 逐个 Read 配置文件确认取值;`.env.*` 系列每个文件单独检查,不能因为看到一个变体被索引就假设其它变体也是 |
| 跨仓库一致性(前端 API 调用 ↔ 后端路由) | 两者都严格限定在自己 cwd 的 git 仓库内,零跨仓库能力 | 在前端侧 grep 出 URL 片段,再去后端仓库 grep 同一片段;`cg-find.sh -k route` 交叉确认(如果两边都装了 codegraph) |
| Django `signal.connect()`/`@receiver` 事件监听器注册(收到信号触发,不是直接调用) | 尚未实机验证(测试仓库里没找到实际用例),仅作结构性推断,使用前先抽查 | grep `.connect(`/`@receiver(`,确认信号处理函数的挂载点 |
| Python 装饰器应用关系(`@decorator_name` 用在哪些函数上,常见于 Django/Flask 的鉴权/CORS/权限装饰器) | 两者都看不到"装饰器名 → 被装饰函数"这条边——codegraph 按名字模糊匹配还会返回噪音(如查 `authorize` 装饰器混进一批同名前缀但完全无关的 `authorize_xxx` 方法),cbm 精确匹配后是干净的 0,不返回噪音但也没有真实结果。装饰器内部靠闭包参数(`f(request, *args)`)转发调用被装饰函数原始函数体的这一跳,同样两个工具都看不到。注意:装饰器**本身没有改名**(`@wraps` 保留 `__name__`)的场景下,别的代码按名字直接调用被装饰函数(如 `single()` 里 `delete_check(request, code)`)这条普通调用两个工具都能正常解析——真正的盲区只在"谁应用了这个装饰器"这一层 | grep 字面量 `@<decorator_name>` 找出所有装饰点,再逐个确认它装饰了哪个函数 |
| Django 动态 URLconf(`include()` 多层嵌套) | **不是共享盲区,两个工具结果分裂**——codegraph 正面,cbm 零召回,不要当成两者都盲区处理,见 `tool-divergence.md` | 见 `tool-divergence.md` 里的工具选择结论 |

## 不是盲区,但该用原生工具而非图谱工具

- **精确名字已知的符号定位** → 直接 `Glob("**/<ExactName>.*")`,实测比任一图谱工具快 3-18 倍且同等或更精确;图谱工具在这里只引入模糊匹配噪音。仅当 Glob 找不到或有多个歧义命中时,才退回图谱工具的模糊查找。
- **仓库小于约 1000 行代码** → grep/Read 一样快一样准,图谱工具的架构开销不值得。
