# 两个工具的能力差异与脚本使用陷阱

两个工具都装的场景下,哪个更准、哪个该用哪种查询方式。完整取证过程存档在 `research/code-navigator/`,这里只保留会改变"选哪个工具"这个决策的结论。

## Java/PHP 接口 → 实现调用桥接

一个通过接口类型的变量/字段/参数发起的调用,静态分析上只会挂在**接口方法节点**上,两个工具的底层原理都是如此,不是实现差异。区别在于两个工具在这之上做了什么:

- **codegraph**:`cg-node.sh`/`cg-explore.sh`/`cg-impact.sh` 自动合成桥接(`[dynamic: interface → impl]`),一次调用就有完整结果。`cg-trace.sh` 的桥接是启发式的(`bridged: true` 标记),出现该标记时仍要用 `cg-node.sh`/`cg-explore.sh` 交叉确认。
- **cbm**:Cypher 引擎完全无法表达这种 2-hop 查询——`cbm-trace.sh` 的接口侧+实现侧手动查询再 union 是**强制步骤,每次都要做**,包括最普通的单实现 `IFoo→FooImpl` 场景,不限于多实现/`@Primary` 场景。

## `CALLS` 边解析精度:codegraph 按接收者类型,cbm 按裸方法名

- **codegraph** 的边是接收者/类型限定的——已验证对 Java(`getDictLabel` 与同名 Lombok getter 零污染)和 PHP(一打同名 `*CreationService->handle()` 类零污染)都成立。当目标方法名是 `get`/`set`/`is` 形状,或者在一批结构相似的类里重复出现,codegraph 是更可信的选择。
  - 例外:`cg-node.sh` 的文件级"used by N files"聚合**不享受**这个接收者类型保证——Vue SFC 之间共享的模板变量名(`handleQuery`/`queryParams`)曾把一个真实 0 使用的组件误判成"被 29 个文件使用"。文件级使用计数永远不能只信这一个信号。
  - PHP 新发现的例外:全局函数和同名类方法(如 Laravel 的 `event()` 助手函数 vs `ActivityLogService::event()` 方法)codegraph 也无法可靠区分——常见动词形状的方法名(`event`/`dispatch`/`handle`)命中后要抽样读源码确认。
- **cbm** 按裸方法名匹配,不检查参数、接收者类型——实测在 Lombok getter 碰撞场景下 60% 假阳性。任何 `get`/`set`/`is` 形状或 MyBatis-Plus `BaseMapper` 继承来的方法名(`updateById`/`selectList`),cbm 结果都要抽样核对源码再报数。

## PHP 链式调用尾部:codegraph 的一个真实解析缺口

codegraph 只解析接收者是**同一行简单表达式**的调用(`$this->prop->findById(...)`),完全解析不到链式调用的尾部方法(`$this->prop->loadRelation(...)->findById(...)`)——这是 codegraph 核心提取器的限制,不是 wrapper 脚本 bug(已用裸 CLI 绕过 wrapper 直接验证过)。实测:一个被 15 个兄弟接口共享继承、未覆写的方法,cbm 找到 92 个真实调用者,codegraph 同一符号只找到 43+7=50 个(约 54%)——全部差值都来自链式调用尾部。**只要查询的符号可能通过 builder 链式调用触达(Laravel 仓储/查询构造器模式常见),优先用 cbm。**

## Go:cbm 的限定名方案有一个未彻底查清的命名碰撞疑点

cbm 的 Go 限定名格式是 `<package路径>.<方法名>`,不含接收者/struct 类型名(不同于 Java 的 `Class.method`、PHP 的 `Class::method`)——同包内接口方法和具体 wrapper 方法如果同名,可能被合并成一个可查询身份,或者其中一个根本没被单独提取成节点。这一点未彻底追查到底,遇到 Go 仓库同名碰撞时留意。不影响本轮的核心结论:两个工具在跨包 struct 字段方法调用上都是干净的完全miss(见 `fallback-cookbook.md`)。

## 只有一个工具有的能力(装了两个也不能互相替代)

| 能力 | 谁有 |
|---|---|
| 死代码检测 | 只有 cbm(`cbm-cypher.sh dead-code`/`dead-code-methods`)——但极不可靠,任何"死"的结论都要用原生 grep+读源码反证,不能只看图谱结果,更不能"两个工具都说死"就当作印证(它们常常共享同一个盲区) |
| Hub/god-class 检测 | 只有 cbm(`cbm-cypher.sh hubs`),且只对 class/OOP 型仓库有信号,函数式 JS/TS/Vue 仓库返回空 |
| 跨层违规检测 | 只有 cbm(`cbm-cypher.sh cross-layer`) |
| 符号锚定的多跳影响面 | 只有 codegraph(`cg-impact.sh`) |
| 哪些测试覆盖这次改动 | 只有 codegraph(`cg-affected.sh`) |
| 一次调用返回穷举列表(全部路由/类/组件) | codegraph 更准更省——`cg-find.sh -k <kind>` 空 pattern 实测精确穷举(303/303 路由、482/482 类、99/99 组件),还带 HTTP 动词;cbm 的 `routes` 模板会自报截断且不含动词 |

## 业务词搜索,按语言拆分(不是"哪个工具更好",是特定组合会直接失败)

- 英文 → `cg-explore.sh` 或 `cbm-find.sh -s`(语义搜索)或 `cg-find.sh`(全文检索),都可靠
- 中文,Java/后端仓库 → `cbm-grep.sh`(字面匹配)或 `cg-find.sh`(全文检索),两个都可靠
- 中文,Vue/TS 前端仓库 → **只有** `cbm-grep.sh` 可靠——`cg-find.sh` 在这类仓库上实测系统性失败(两轮共 0/6),疑似 CJK 分词器在这种文件形态上的缺陷
- **无论哪种语言,都不要用 `cg-explore.sh` 查纯中文**(零 Latin 锚点词时直接返回"没找到",哪怕底层 FTS 索引本身是正常的)、**也不要用 `cbm-find.sh -s` 查中文**(嵌入模型对中文近乎随机打分)

## 应用自定义 Facade vs 内置 Facade:同一个"Facade"关键词,结果天差地别

Laravel Facade 的表现取决于访问器目标在哪:
- **应用自己定义的 Facade**(访问器类在 `app/` 里,会被索引)——codegraph 实测高召回(单案例 100% 文件级召回,且在重新克隆、从零重建索引后复现),值得信;但要警惕方法名和 PHP 全局函数同名的假阳性(见上面 CALLS 边一节)。范围限定:目前只验证过 `getFacadeAccessor()` 直接返回具体类名(`XxxService::class`)的写法——访问器返回接口或字符串别名的形态没有实测过,不要把结论外推成"所有自定义 Facade 都能穿透"。
- **内置 Facade**(`Cache::`/`Auth::`/`DB::`,目标在 vendor 代码里)——两个工具都是干净的完全 miss,见 `fallback-cookbook.md`,这种情况不要浪费图谱工具调用。

## Django 动态 URLconf 路由解析:codegraph 正面结果,cbm 干净 0 召回

实测于 `healthchecks/healthchecks`(Django,codegraph + cbm 都已建索引):顶层 `hc/urls.py` 用 `include("hc.front.urls")` 引入子 app 的 urls.py,子 app 内部又用 `include(check_urls)` 二次嵌套(共 3 层 include)。测试符号:`hc/front/views.py:988` 的 `details()`,对应路由 `/checks/<uuid:code>/details/`。

- **codegraph**:`cg-trace.sh details in` 正确穿透全部 3 层 include(),返回一条 `kind: "route"` 的边(`hc/front/urls.py:9`),外加一个真实的普通函数调用边(`status()` 在 `hc/front/views.py:318` 内部直接调用了 `details()`)——两条边都验证为真,没有漏、没有多。
- **cbm**:`cbm-trace.sh` 用 `cbm-find.sh` 确认过的精确限定名(`healthchecks-bench.hc.front.views.details`)查询,`callers` 干净返回空——路由注册这条边对 cbm 的调用图完全不可见,已排除"名字没对上"这个可能。

结论:**Django URLconf 路由追踪该用 codegraph,不要用 cbm**——如果两个工具都装了,这类问题直接走 `cg-trace.sh`/`cg-find.sh -k route`,不要指望 cbm 给出等价结果,也不要因为 cbm 返回 0 就误判成"这个路由没人访问"。

## Python `Model.objects.custom_method()`(自定义 Manager,通过 objects 属性转发):两个工具都是正面结果

实测于 `healthchecks/healthchecks`:`ProfileManager.for_user()`(定义 `hc/accounts/models.py:62`,`Profile.objects = ProfileManager()` 绑定在同文件第 109 行)——命名完全不变(定义和调用都叫 `for_user`),只是要跨"实例属性的运行时类型"做解析,不涉及任何魔法改名。

- **codegraph**:`cg-trace.sh for_user in` 精确找到全部 10 个真实调用点(跨 `hc/accounts/`、`hc/integrations/email/` 两个 app),零遗漏零噪音。
- **cbm**:`cbm-trace.sh for_user in`(深度 3)同样找到全部 10 个直接调用者,外加几个 hop-2/hop-3 的传递调用者——cbm 的深度参数能看到间接调用链,codegraph 的 `in` 查询只返回直接调用者。

和 PHP Eloquent `scopeXxx → ->xxx()` 磁力改名调用(`fallback-cookbook.md` 里的确认盲区)形成清晰对照:同样是"通过 ORM manager/scope 机制发起的调用",Python 这边命名不改所以两个工具都能靠名字匹配解析到,PHP 那边因为 Eloquent 约定要求调用时去掉 `scope` 前缀而彻底失联。**判断力所在:是否涉及运行时改名/魔术方法转发,而不是"是不是 ORM"这个笼统标签——同一类"ORM 便利方法"在不同语言/框架里可能是盲区也可能不是,不能互相外推。**

## 脚本参数陷阱(容易踩,而且两个脚本长得很像)

- **`cbm-trace.sh` 第 3 个位置参数是深度(hop 数),`cg-trace.sh` 第 3 个位置参数是结果条数上限**——两个脚本用法行几乎长得一样,极易搞反。拿 cbm 的数字去对 grep 出来的"直接调用者"时,永远传深度 `1`,传大数字会把间接/传递调用者混进来,数字会莫名其妙偏大。
- **报告任何调用者/callee 数量前,先看截断信号**:`cg-trace.sh` 的 `possiblyTruncated` 字段、`cbm-find.sh` 的 `hasMore`/`total` 字段。数字如果卡在一个整数上限(20/50/100/200)附近,先检查这个字段,不要直接当作真实总数引用。
- **`cg-trace.sh` 报告的调用点行号是调用者方法的起始行,不是调用语句本身那一行**(方法级粒度,PHP 上实测确认)——拿行号去和 grep 结果逐行对照,对不上是正常现象,不代表这个调用者是假阳性;要确认一个调用者真不真,读那个方法的源码,别只对行号。
