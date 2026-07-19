# LSP 协作协议(选装,永远不是链条起点)

Claude Code 自带的 LSP 工具(`findReferences`/`goToDefinition`/`hover`/`documentSymbol`/`goToImplementation`/`prepareCallHierarchy`/`incomingCalls`/`outgoingCalls`/`workspaceSymbol`)是独立于两个图谱工具的第三个结构信息来源。**它是可选的锦上添花,不是决策表里任何一行的首选路径**——即便可用,也只在单符号问题、图谱工具/原生 grep 已经给出答案之后,顺手再验证一次,从不作为起点,也不用于探索性问题、聚合问题或继承方向问题。

## 安装前提(容易踩的坑)

TypeScript LSP 需要在**目标仓库本地**装 devDependency(`npm i -D typescript-language-server typescript`)——全局 `npm i -g` 不够,会报 `"Command 'typescript-language-server' not found or is in an unsafe location"`。官方插件文档只写了全局安装路径,这一步没写但实测是必须的。

Java LSP 在当前 Claude Code 安装里**结构性不可用**——没有任何插件把 `.java` 接到 LSP server 上(不同于 TypeScript 有专门的 `typescript-lsp@claude-plugins-official` 插件)。装了能正常工作的 `jdtls` 封装包作为本地依赖也没用,说明缺的是插件接线,不是服务器本身。除非确认市场上出现了 Java 版的等效插件,否则不要重复尝试。

## 已验证的结果(TypeScript,Vue+TS 仓库)

- **正面**:能正确区分两个同名但互不相关的导出函数,各自只返回真实调用者,零串号——这是 import/类型感知的解析,不是 cbm 那种纯名字匹配。
- **负面,而且是更危险的失败方式**:对 `.vue` 文件本身查询会诚实报错("No LSP server available for file type: .vue");但从 `.ts` 文件发起 `findReferences` 时,会**静默丢弃**任何落在 `.vue` 文件里的真实调用点,不报任何错误——看起来像一个干净完整的结果,实际上漏了东西。**在 Vue+TS 技术栈里,不要在没有原生 grep 交叉验证的情况下相信一个"看起来完整"的 `findReferences` 结果。**
- **不能补上两个图谱工具已有的共同盲区**:专门测过 `app.config.globalProperties` 挂载函数的场景(见 `fallback-cookbook.md`),LSP 同样漏掉了几乎全部真实调用点——原因是这些调用点都在 `.vue` 模板里,加上类型层面的全局属性声明也不构成"对该符号的引用"。

## 失败语义

任何 `"No LSP server available for file type: X"` 或类似"not found"的报错,当作该文件类型在当前会话里没有 LSP 支持——不重试,不建议用户装语言服务器,不要因此拖慢已经在走的图谱工具/原生 grep 链条。已有的答案不需要 LSP 佐证才算数。
