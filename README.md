# imars-skills

让 Claude Code 通过 **纯 CLI(零 MCP)** 使用预建代码知识图谱的 Skill 套件——一次图谱调用替代几十轮 grep/read。

一套统一 skill `code-navigator`,内部可对接两种互不依赖的底层 CLI,按问题形状自动选用其中最合适的一个(或两个都用):

| 底层 CLI | 索引产物 |
|---|---|
| [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | `.codebase-memory/` |
| [codegraph](https://github.com/colbymchenry/codegraph) | `.codegraph/` |

推荐两个都装:`code-navigator` 会按 SKILL.md 里的决策表自动选择准确度最高、成本最低的那一个;只装一个也完整可用,对应能力会降级到只用那一个工具能做到的程度(见文末"工具选型对比")。0.0.18 之前这里是 `cbm-navigator`/`codegraph-navigator` 两个完全并行的 skill,各自的 CLAUDE.md 片段常驻层会同时写"invoke 我 FIRST"、互相矛盾——已合并为一个统一入口,详见 CHANGELOG 0.0.18。

内含五个组件:
| 组件 | 位置 | 作用 |
|---|---|---|
| `code-navigator` skill | `skills/code-navigator/` | 统一触发协议 + 14 个查询脚本(`cbm-*.sh` 7 个 + `cg-*.sh` 7 个)+ 两份盲区参考 + LSP 协作协议 |
| `deep-analyst` subagent | `agents/` | 高风险问题(影响面/改造决策)以 `effort: high` 在独立上下文运行并回传已验证结论 |
| PreToolUse hook(可选,单脚本) | `optional/hooks/` | `code-navigator-augment.sh` 一个脚本统一处理:原生 `Grep`/`Glob` 调用,以及 `Bash` 里直接跑的 `grep`/`git grep`/`rg`/`ag`,自动注入图谱符号匹配作为 additionalContext,非阻断;按各自索引产物(`.codebase-memory/`/`.codegraph/`)是否存在独立判否,只建了其中一种索引的仓库照常工作;两边都命中同一符号时合并成一条并标注 `src:both`,详见下方"PreToolUse hook 的合并策略" |
| CLAUDE.md 片段(可选) | `optional/` | 一份统一片段,强化触发,同时兼容只建了一种索引的仓库 |
| settings 模板 | `optional/` | hook 接线,project/user 两个作用域各一份 |

## 安装(两种方式,选其一)

**方式 A:Claude Code plugin(推荐,自动获得更新)**
```
/plugin marketplace add holyimars/imars-skills
/plugin install imars-skills@imars-skills
```

**方式 B:脚本安装(拷贝到 ~/.claude/)**
```bash
git clone https://github.com/holyimars/imars-skills && cd imars-skills
./install.sh              # 或 ./install.sh --with-hook
```

两种方式都会装上统一的 `code-navigator` skill 和 `deep-analyst` agent;具体哪半能力能用,取决于对应的 CLI 有没有装、目标仓库有没有建对应的索引(见下面各自的"前提")——不需要也不应该只为了"用全部能力"而在没有对应仓库场景的机器上强装两个 CLI。

---

## codebase-memory-mcp 前提(code-navigator 的 cbm 侧)

1. 已安装 codebase-memory-mcp 二进制(**务必 `--skip-config`,不写任何 MCP 配置**):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash -s -- --skip-config
   ```
2. 目标仓库已建索引(**团队标准命令**,实机验证的 flags 形式):
   ```bash
   codebase-memory-mcp cli index_repository \
     --repo-path "$(git rev-parse --show-toplevel)" \
     --name "$(basename "$(git rev-parse --show-toplevel)")" \
     --persistence true
   ```
   三个 flag 的原因:`--name` 固定项目短名(默认名是绝对路径扁平化,因人而异,跨机器不可移植);`--persistence true` 才会写团队共享工件 `.codebase-memory/graph.db.zst`(**默认不写**);语义检索(`cbm-find.sh -s`)依赖 similarity/semantic 边,仅 `--mode full|moderate` 构建,若语义检索无结果用 `--mode full` 重建——**语义检索只对英文关键词可靠,中文查询得分近随机**,中文业务词请用 `cbm-grep.sh`(纯文本匹配,能命中中文注释),`cbm-find.sh` 会在语义搜索最高分低于 0.3 时自动提示这一点。手动用 `--repo-path` 传相对路径重新索引会静默建出一个同仓库的重复 project 而不是更新原有的,务必配合绝对路径 + 显式 `--name`,复核 `list_projects` 确认没有多出条目。**首次对陌生仓库建索引前,先 `grep` 一下有没有类似 `class Database`/`Cache`/`Config`/`Session`/`Container`/`Storage`/`Log` 这种框架保留字式命名的类,且该类某个方法带 `<Target, $this>` 这种自引用泛型标注**——这个组合已被实测确认是 `index_repository` 内存暴涨的真实触发条件(体量大小、PHP+TS 混合语言都只是巧合共现,不是真正原因),命中就跳过 cbm 只用 codegraph;完整的二分排查过程和证据见 `research/code-navigator/cbm-blindspots.md` 的"`index_repository` memory usage"小节。
3. 本机有 `jq`。

## codegraph 前提(code-navigator 的 cg 侧)

1. 已安装 codegraph(推荐 npm 方式;官方也提供 `install.sh`/`install.ps1` 独立二进制,见其 [README](https://github.com/colbymchenry/codegraph)):
   ```bash
   npm i -g @colbymchenry/codegraph
   codegraph telemetry off   # 可选,默认开启遥测
   ```
   **不要跑 `codegraph install`**——那条命令会往 Claude Code / Cursor / Codex 等写入 MCP server 配置,与本仓库"零 MCP、纯 CLI"的设计相悖。本 skill 全程只用 `codegraph` CLI 子命令。
   **实测(2026-07-18,Windows):不要在 Git Bash 里跑官方 `install.sh`**——读了源码确认它的 OS 判断只有 `Darwin`/`Linux` 两个分支,`uname -s` 在 Git Bash(MINGW64)下的实际输出会落进 `*) unsupported OS; exit 1` 直接退出,对应上游 open issue [#1294](https://github.com/colbymchenry/codegraph/issues/1294);上面的 npm 方式没有这个 OS 判断步骤,不受影响,Windows 上如果确实要用独立二进制,改用 PowerShell 跑 `install.ps1`。
2. 目标仓库已建索引:
   ```bash
   codegraph init "$(git rev-parse --show-toplevel)"
   ```
   索引产物是仓库根目录下的 `.codegraph/`(实测未被自动 gitignore,建议手动加进目标仓库的 `.gitignore`)。无需 `--name`——codegraph 按目录路径解析索引,没有 codebase-memory-mcp 那种全局项目名注册表。改动后跑 `codegraph sync .` 增量更新(秒级),或让其自带的文件监听自动同步。
3. 本机有 `jq`。

## code-navigator 安装后 10 分钟自测

1. `codebase-memory-mcp cli list_projects` 能看到目标项目(若装了 cbm 侧);`codegraph status .` 能看到已索引、`nodeCount`/`fileCount` 非零(若装了 cg 侧);
2. 问"XxxService 的调用链" → 触发 `code-navigator`,单次出链,无连环 Grep;两个索引都建了时应优先走 codegraph(`cg-trace.sh`),若查询目标是 `*Impl` 类方法,确认返回里出现 `bridged: true` 且包含真实业务调用方(而不只是接口声明本身);
3. 问"这个项目的整体架构" → 单次 arch 调用;
4. 问"有哪些死代码" → 只有装了 codebase-memory-mcp 才会给出答案(`cbm-cypher.sh dead-code`);只装了 codegraph 的仓库上,skill 应如实说明这类问题它没有能力回答,不会用 `cg-explore.sh` 冒充答案;
5. 问 MyBatis XML 动态 SQL 问题、或 Vue/React 路由懒加载组件是否被使用 → 不用图谱、直接 grep/read(两个工具的共同盲区,见 `skills/code-navigator/references/fallback-cookbook.md`);在 <1,000 行小仓库问结构问题 → 同样不用图谱;
6. 问不存在的函数调用链 → trace 返回空/0 + hint,Claude 转 find 而非重试;
7. 主会话设为 low(`/effort`)问影响面问题 → 应委派 `deep-analyst`;若所装 Claude Code 版本不支持 agent 的 `effort` frontmatter(以继承档位运行),确认回退话术出现;
8. (可选)问单符号调用链时,确认 skill 只把 LSP 结果当"额外佐证"引用,不作为链头;若要实测 TypeScript LSP,记得目标仓库本地也要装一份 `typescript-language-server`(全局装不够,见 `skills/code-navigator/references/lsp-notes.md`)。

## 内置运行时门槛(团队实测口径,写在 SKILL.md 内)

1. **小仓库不用**:当前仓库 <~1,000 行代码时,skill 指导 Claude 直接用原生 grep/read——全局安装 ≠全局使用;
2. **档位认知**:思考/输出 token 预算过小会限制检索质量,low/medium 档准确度低于 high/xhigh/max,图谱不能抬升该上限;**将被采取行动的结论**(影响面、改造决策)会被委派给 `deep-analyst` subagent(effort 覆盖 + 独立上下文 + 源码复核),该 agent 不可用时回退为建议升档 + 原生复核;
3. **只有实测过的能力才能当决策表的链头**:LSP 即便 TypeScript 侧已实测(见下方"LSP 协作"),按设计仍然永远只作为单符号问题的额外佐证,不参与链序判断。

## PreToolUse hook 的合并策略

0.0.18 曾经明确决定不合并这两个 hook,理由是"跨 hook 去重需要两个独立进程之间共享状态,对一个非阻断、best-effort 的提示注入是过度工程"。0.0.27 把两个脚本合并成一个 `code-navigator-augment.sh` 之后,这条理由本身不再成立——合并成一个进程,去重就只是一段普通的 jq 逻辑,不需要任何共享状态。同时这一版也把 hook 的触发范围从原生 `Grep`/`Glob` 扩大到了 `Bash` 里直接跑的 `grep`/`git grep`/`rg`/`ag`,触发频率显著上升,这让"双份注入 + 双份子进程"这个早先可以容忍的代价变得更值得现在解决。

合并后的规则:两边结果按 `name`+`file` 去重,同时命中同一个符号的合并成一条并标 `src:"both"`(保留 codegraph 一侧的 `kind` 字段),只有一边命中的分别标 `src:"cg"`/`src:"cbm"`。`both` 标签排最前面——两种完全不同的匹配机制(cbm 精确/正则 name_pattern,codegraph 模糊 FTS)独立地同时命中同一个符号,是任何单一工具都给不出的更强信号,这也是合并这件事本身带来的新价值,不只是"少发一次"。合并后的展示上限是 8 条(每个工具查询时的单次上限仍是 5,用于各自的 `-l`/`limit` 参数),比旧版两个脚本最坏情况叠加到 10 条要少,又比单独一个工具的 5 条留出更多互补召回的空间。

**只装了一种索引的仓库继续正常工作**——脚本内部两个分支各自独立判否(codegraph 分支查 `.codegraph/` 目录是否存在,cbm 分支查 `codebase-memory-mcp` 命令是否存在),没有变成"两个都要装"。

**迁移提示**:如果你在旧版本手动把 `cbm-augment.sh`/`codegraph-augment.sh` 两条 hook 配置写进了自己的 `settings.json`,需要手动替换成新的一条(指向 `code-navigator-augment.sh`,`matcher` 改成 `"^(Grep|Glob|Bash)$"`,`timeout` 改成 `5`)——`install.sh --with-hook` 只负责清理/安装脚本文件本身,不会去改你已经手改过的 `settings.json`。

**已修复:极端环境下的后台进程风险**:codegraph 分支为了和 cbm 的两步查询并发而用 `&` 放到后台跑(见上面的超时预算说明)。旧版两个独立脚本时,唯一一次 CLI 调用是前台阻塞执行,外层 hook 超时杀父进程基本等于连带杀掉它;合并后改成后台执行,如果所在环境同时缺 `timeout` 和 `gtimeout`,这个已经脱离前台等待链的后台查询就没有任何内置时间上限,理论上可能在外层超时杀掉父进程之后继续跑一会儿,变成孤儿进程——这是合并这次新引入的边界情况,不是延续旧脚本就有的风险。已经修复:codegraph 分支现在额外要求 `$TMO` 非空(即真的探测到了 `timeout` 或 `gtimeout`)才会执行,两者都探测不到时直接跳过这个分支,而不是无时间上限地跑;这和"没装 codegraph 命令"/"没有 `.codegraph/` 目录"时这个分支本来就会跳过是同一套判否逻辑,不算新增的覆盖率损失。

**已知边界:Bash 命令识别的提取盲区**——这几条对应"控制流程"里"Bash 命令识别 + pattern 提取"那一步,如实记录不强行覆盖:
- 复合/管道命令只识别第一个在合法命令边界上匹配到的命令名,不追踪整条命令链(比如 `fd . | xargs grep foo` 完全不会被识别,因为 `xargs` 不是边界字符);
- 对"管道左边命令输出"做 grep(如 `git log --oneline | grep fix`、`ps aux | grep java`)在语法上和"对代码内容"做 grep 无法区分,依然会触发并注入提示——非阻断软性建议,最坏结果只是一句无关但无害的提示;
- `find`(语义上更接近 Glob)、`ack` 等更少见的工具本轮不做;
- 质量兜底过滤(候选长度 `< 3` 或不含字母则视为空)只挡得住短小/纯数字的误捕获(如 `rg -t ts foo` 误捕获成 `ts`),挡不住 `-t typescript` 这类参数值本身较长的写法——这种情况下拿到的是错误的符号名,代价和"查不到就是干净空结果"相当。

## 维护指引

- **文档换行规范**:SKILL.md、references、agent 定义、CLAUDE.md 片段一律"一句一行"(句末标点处换行,句内不折行),PR diff 即句子粒度;
- **触发调优是持续过程**:观察一周,哪类结构问题仍走原生多轮 grep,就把该类触发短语提 PR 加进 `SKILL.md` 的 description(中英文都收);
- **盲区案例**:发现新的图谱盲区形态(解析不到/答错),提 issue 附最小复现;详细取证过程写入 `research/code-navigator/`(不随 skill 分发,存档用),skill 内 `skills/code-navigator/references/tool-divergence.md`/`fallback-cookbook.md` 只更新会改变"该用哪个工具"的简明结论;
- **上游跟踪**:codebase-memory-mcp、codegraph 均按各自节奏迭代;若某 release 更改工具参数名(如 trace 深度参数),按各自的 schema/help 输出校准脚本中的 jq 投影;
- **发版**:改动合并后 bump `.claude-plugin/plugin.json` 的 version 并更新 CHANGELOG,plugin 用户 `/plugin marketplace update` 获取。

## CLI 调用形式说明(cbm 侧脚本)

上游已弃用 raw JSON 位置参数(`cli <tool> '<json>'` 会打印 deprecation 警告,未来版本移除)。`code-navigator` 的所有 `cbm-*.sh` 脚本统一通过 **stdin 管道**传 JSON,且收敛在 `scripts/_project.sh` 的 `cbm_call()` 单一包装函数中——若未来 CLI 调用形式再次变更(如 flags-only),只需修改该函数一处。`cg-*.sh` 脚本直接透传 flags(codegraph CLI 本身就是 flags-only,没有这层包装需求)。

## 已知边界:codebase-memory-mcp 一侧(上游)

- **官方 README 为 main 分支,可能超前于已发布版本**(main 文档中的 `--raw` flag 在 v0.9.0 上不存在)。任何 CLI 用法以 `cli <tool> --help` 与实际输出为准;
- 查询结果的文件字段为 `file_path` 且**无行号字段**(v0.9.0),脚本投影与 Cypher 模板已按此适配;
- macOS 默认无 `timeout` 命令,hook 已内置 timeout/gtimeout 探测;
- `detect_changes` 在 git worktree 下失效(上游 bug),请在普通 clone 使用;
- `effort` 为 subagent frontmatter 较新字段,部署前按自测第 7 条验证;
- 引用 GitHub issue 编号前必须实际打开确认——历史上核查过的二手引用编号里相当比例对不上号;
- 图谱 Route 节点的类级 `@RequestMapping` 前缀实测(3 个真实 Controller)**完整保留**;上游 issue #734 描述的丢失问题仍 open,不同项目/版本可能不同,不要默认套用;
- 手动重新索引传相对路径又不传 `--name` 会静默建出重复 project 而不是更新原有的——务必用绝对路径 + 显式 `--name`;
- **`cbm-*.sh` 全部脚本现在都会可靠地传递错误和截断信号**(经过多轮 code review 修复:`cbm-cypher.sh` 的 5 个 Cypher 模板里 2 个曾静默答错、3 个曾静默截断或崩溃;`cbm_call()` 曾吞掉 stderr 里的真实报错;`cbm-find.sh`/`cbm-impact.sh`/`cbm-arch.sh` 都曾引用不存在或被静默丢弃的字段)——现在看到 `hint`/`warning` 字段可以直接信,一个脚本返回意外的空结果而不带任何提示,本身就是"出问题了"的信号。
- Java 接口/实现调用桥接、`CALLS` 边名字碰撞、`getAopProxy(this)` 自调用坑、跨仓库一致性、Laravel/PHP 全部魔法构造、Go 跨包字段调用、配置键绑定、Django URLconf 路由(cbm 干净 0 召回,codegraph 侧正面结果见下)、Python 自定义 Manager 方法(正面结果)、Python 装饰器应用关系(共享盲区)等具体发现——当前结论已烘进 `skills/code-navigator/references/tool-divergence.md`/`fallback-cookbook.md`,完整实测过程和历史 bug 修复记录存档在 `research/code-navigator/cbm-blindspots.md`,不在此重复。

## 已知边界:codegraph 一侧(上游)

- Java 接口/实现盲区**明显好于** cbm 侧:`node`/`explore` 会给出 `[dynamic: interface → impl]` 双向标注,`cg-trace.sh` 已内置自动桥接;但底层 `callers` 命令本身仍是单跳,查 `*Impl` 类方法只会返回 1 个"caller"——那其实是接口声明本身,不是真实调用方,必须靠 `cg-trace.sh`/`cg-node.sh`/`cg-explore.sh` 而非裸 CLI 调用;
- **CALLS 边是接收者类型感知的,不会有 cbm 侧那种 Lombok getter/setter 同名碰撞问题(实测 2026-07-18,Java;2026-07-18 追加实测 PHP 上同样成立)**:用同一个"getDictLabel"名字(业务接口方法 + 4 个不相关 DTO/VO/Entity 的 Lombok getter)测试,codegraph 完全正确区分,零污染——这是相对 cbm(name-only 解析,实测 60% 假阳性)的明确优势;PHP 上用 `pterodactyl/panel` 的 `UserCreationService::handle()` 复测(仓库里有十几个不相关的 `*CreationService` 类都调用同名 `handle()`,共 19 处文本相同的调用形状,真实属于 `UserCreationService` 的只有 4 处)同样零假阳性,说明这个"按接收者类型而非纯方法名"的保证不是 Java 专属;**但这个"接收者类型限定"的保证只覆盖方法级 CALLS 边,不适用于 `cg-node.sh` 的文件级"used by N files"依赖聚合**(field-verified 2026-07-18):`RoleSelect/index.vue` 被报"used by 29 files",人工 grep 找到的真实引用是 0——假 29 来自其他不相关 CRUD 页面共用的通用标识符(`handleQuery`/`queryParams`)恰好被这个文件级启发式关联到了 `RoleSelect`。文件级"used by N files"计数不管数字大小都不能直接当结论,查 kebab-case 模板标签 + 检查 auto-import 注册入口才是可靠判断;
- **`cg-trace.sh` 曾经默默把 `callers`/`callees` 截断在 20 条,没有任何提示,已修复(field-verified 2026-07-19)**:底层 `codegraph callers`/`callees` 命令本身默认 `-l 20`,JSON 返回体里也没有 total/hasMore 字段——超过 20 条真实调用者时,结果和"正好 20 条"完全无法区分。`cg-trace.sh` 一直没有显式传 `-l`,默默继承了这个上限。这直接导致下面两条结论曾经测错:一个 Laravel Facade 方法报"7/24 文件(~29%)"、一个普通 React hook 报"20/30(~67%)",两个数字里的"20"都不是巧合。已修复:`cg-trace.sh` 现在默认 `-l 200`,并在结果卡满上限时返回 `possiblyTruncated: true` 提示——看到这个字段就该提高上限重查,不要直接采信数字;
- **`cg-node.sh`/`cg-explore.sh`/`cg-impact.sh` 自动合成 Java/PHP 接口→实现桥接**,底层 `callers` 单跳命令本身仍会把接口声明误当成调用者,`cg-trace.sh` 的桥接是启发式的(`bridged: true`);
- **PHP 链式调用尾部是 codegraph 一个真实的核心提取器限制**(根因已定位,非 wrapper 脚本 bug):只解析同一行简单接收者表达式的调用,解析不了 `->loadRelation(...)->findById(...)` 这种链式尾部——查询的符号可能通过 builder 链触达时优先用 cbm;
- **`cg-node.sh` 的调用链展示没有 `-l` 可调,但截断是诚实的**——链断掉的地方会显式打 `+N more` 标记,看到这个标记就该换 `cg-trace.sh` 提高上限查全量;没有这个标记的短链不需要怀疑被静默截断;
- Vue/React 动态 `import()`(经典 `lazy()`、React Router v6.4 `async lazy()`)、MyBatis XML mapper 绑定、Eloquent 本地 scope:**跟 cbm 一样是干净盲区**,直接 grep/read;
- Spring `getBean(运行时拼接名)`:诚实列出全部实现类作为候选,不代表"全部被调用"或"已解析";`SpringUtils.getBean(X.class)` 这种确定性单目标查找**完全解析不到**(0/2 召回),会直接传导进 `cg-impact.sh` 的影响面分析造成漏报,查任何接口方法前建议顺手 grep 一下;
- `SpringUtils.getAopProxy(this).<method>(...)` 自调用是两个工具真正共同的盲区,"两个工具都同意是死代码"在这里没有印证价值;
- 类的 `extends` 关系单向:查父类能看到子类列表(标签是 `Called by`,略有误导),反过来查子类完全看不到父类,复现上游 open issue [#1328](https://github.com/colbymchenry/codegraph/issues/1328);
- **`cg-explore.sh`(官方旗舰单一命令)纯中文查询完全失效**(需要至少一个拉丁字母锚点词),纯中文业务问题请直接用 `cg-find.sh`(FTS);但在 Vue/TS 前端仓库上 `cg-find.sh` 本身也会系统性失效(0/6)——这类仓库的中文业务词查询请只用 `cbm-grep.sh`;
- 没有裸图查询能力(无 Cypher 等价物),死代码/hubs/跨层这类全图模式问题**明确不要用 `cg-explore.sh` 兜底**——它对这类问题做的是关键词/语义检索而非图分析,会给出**看似合理实则文不对题**的结果且不报错;这几类问题只有装了 codebase-memory-mcp 才能回答;
- "列出所有 routes/classes/interfaces/components" 这类**穷举**反而有直接等价物:`cg-find.sh -k <kind>`(pattern 留空),实测数量与 `codegraph status` 的 `nodesByKind` 完全一致,还比 `cbm-cypher.sh` 的 routes 模板多带 HTTP 方法;
- `codegraph index` 全量重建时若有任何其他 codegraph 进程并发持有数据库文件会直接硬失败(`EPERM`,范围比上游 issue #1325 描述的更广),不会损坏现有索引;日常增量更新用 `codegraph sync .`,`index --force` 不要和其他调用并发;
- `codegraph install` 会写 MCP 配置,本套件明确不使用它。
- **Django 动态 URLconf 路由(多层 `include()` 嵌套)是 codegraph 的一个真实强项**:三层嵌套全部正确穿透,cbm 在同一符号上是干净的 0 召回——这类问题装了两个工具时应该专门走 codegraph,不要指望 cbm 给出等价结果;
- Python 自定义 Django Manager 方法(`Model.objects.custom_method()`,命名不改)召回完整,和 PHP Eloquent 的 `scopeXxx()` 魔法改名盲区形成对照——判断力在于"是否改名",不是笼统的"ORM 魔法";Python 装饰器应用关系(`@decorator` 包裹了哪些函数)是共享盲区,codegraph 在这里比 cbm 更差,还会给出噪音假线索;
- 完整实测过程和历史数字存档在 `research/code-navigator/codegraph-blindspots.md`。

## LSP 协作

Claude Code 自带的 LSP 工具是第三个独立信息源,**选装,从不是决策表链头**——完整协议、安装坑、TypeScript/Java 实测结论见 `skills/code-navigator/references/lsp-notes.md`。简述:

- TypeScript 需要在目标仓库**本地**装 `typescript-language-server` devDependency 才能用(全局装不够);装好后能正确区分同名不相关函数,但对 `.vue` 文件完全不支持,且从 `.ts` 侧发起的 `findReferences` 碰到真实调用点落在 `.vue` 里时会**静默漏掉、不报错**——比直接查 `.vue` 文件的报错更危险,也补不上 `app.config.globalProperties` 这个共同盲区;
- Java 在当前 Claude Code 安装里**结构性不可用**(没有对应插件把 `.java` 接到语言服务器命令上),装了能用的 server 也无济于事;
- 任一语言可用时,只作为单符号问题的机会性额外佐证(试一次、失败静默降级、不重试),从不参与链序判断,也不能替代原生 grep 交叉核实。

## 工具选型对比

两个工具没有绝对的谁更好,互补大于替代,**推荐都装**:

- **codegraph 通常更准更省**:接口→实现调用桥接一次调用搞定、`CALLS` 边按接收者类型解析(get/set/is 形状或大量同名方法更可信,Java/PHP 均验证过)、穷举类查询(routes/classes/components)精确且带 HTTP 动词、多跳影响面(`cg-impact.sh`)、覆盖测试查询(`cg-affected.sh`)——这几类只有它有,或它明显更省 token;
- **cbm 有几项独有能力,以及一个真实的精度优势**:死代码/hub/跨层违规的全图 Cypher 查询;PHP 方法被多个兄弟接口共用同一份基类实现、或需要穿过链式调用触达时,cbm 召回明显更完整(codegraph 在这里有已定位根因的真实缺口);
- **两者共享的局限,换工具解决不了,只能 grep**:Vue/React 动态 `import()`、MyBatis XML 绑定、`app.config.globalProperties` 挂载函数、`SpringUtils.getAopProxy(this)` 自调用、Go 跨包 struct 字段调用、Laravel 内置 Facade/Eloquent 魔法方法;
- 符号名已确切知道时,原生 `Glob` 应该跳过两个图谱工具直接用——实测更快(最多 18x)更准。

逐场景的当前结论见 `skills/code-navigator/references/tool-divergence.md`(工具差异)和 `fallback-cookbook.md`(原生兜底速查);完整实测数据、按轮次记录的验证过程存档在 `research/code-navigator/tool-collaboration-benchmark.md`。

## License

MIT
