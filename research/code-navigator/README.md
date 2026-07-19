# code-navigator 取证存档(不随 skill 分发)

这个目录存放 `code-navigator` skill 每一项结论背后的完整实机验证记录——按时间顺序的"field-verified"叙述、原始数字、纠错过程、仓库/符号级 ground truth。

**这里的文件不会被 skill 读取,也不会随 plugin 安装/`install.sh` 脚本安装被带到用户的 `~/.claude/` 目录**——两种安装路径都只拷贝 `skills/code-navigator/`(见仓库根 `install.sh`;plugin 市场路径下 Claude Code 也只加载 `skills/`/`agents/`/`hooks/` 等约定目录,不会主动读取仓库里的其它文件夹)。这个目录只是借 git 仓库本身存档,给以后要复核结论、追溯某个数字怎么来的人看。

`skills/code-navigator/references/` 里的精简版文件才是 skill 触发时会读取的——那些文件只保留"结论+grep 配方",详细取证过程和纠错历史都在这里。精简版里每条结论都可以在这里找到对应的完整过程。

## 目录

- `codegraph-blindspots.md` — codegraph 一侧的全部实测记录(Java 接口桥接、CALLS 边、Spring getBean、Go、Laravel Facade/Eloquent、动态 import 等)
- `cbm-blindspots.md` — codebase-memory-mcp 一侧的全部实测记录(含 5 个 `cbm-cypher.sh` 模板的 bug 修复过程、语义搜索 bug、Laravel/PHP、Go、配置键绑定等)
- `lsp-and-native-fallbacks.md` — Claude Code 内置 LSP 工具的实测记录 + 两个图谱工具共享盲区的汇总
- `tool-collaboration-benchmark.md` — 按轮次(Round 2-10)记录的完整验证历史,含每一轮"为什么测这个、测出了什么、后续怎么用"的叙事
