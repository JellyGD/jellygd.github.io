# AgentToolDemo —— Function Calling 完整调用链 Demo（Swift）

对应博客文章《AI Agent 基础概念全景》里「能力原语」一节：把
**Function Calling（机制）→ Tool（被调函数）→ Agent 循环 → 回灌**，以及
**MCP（跨进程/云端那一下）** 串成一条能直接跑的链路。

本 demo **不依赖任何模型文件**，用脚本化 Mock 假装模型在发 Function Call，
所以 `swift run` 即可看完整链路。

## 跑起来

```bash
cd AgentToolDemo
swift run          # 或 swift build && ./.build/debug/AgentToolDemo
```

> ⚠️ 在部分受限沙箱环境里 SwiftPM 的 `sandbox-exec` 会被禁用导致 `swift build`
> 报 `sandbox_apply: Operation not permitted`。此时可直接用 `swiftc` 绕过：
> ```bash
> swiftc -parse-as-library -o /tmp/atd Sources/AgentToolDemo/*.swift && /tmp/atd
> ```

你会看到两个场景：

- **场景一：本地 Tool（进程内 Function Calling）** —— 模型依次请求
  `get_weather` → `calculator` → `create_reminder`，循环 4 轮后给出自然语言答案。
- **场景二：MCP Tool（手机当 Client 连云端）** —— 模型请求 `get_server_price`，
  App 向云端 MCP Server 发 JSON-RPC `tools/call`，拿到结果后作答。

## 文件地图（对应文章里的概念）

| 文件 | 对应概念 |
| --- | --- |
| `Types.swift` | `ChatMessage` / `LLMResponse`（文本或一次 Function Call）/ `ToolSpec`（给模型的说明书） |
| `Tool.swift` | `Tool` 协议 + `ToolRegistry`（进程内函数注册表）+ `parseArgs` |
| `Tools.swift` | 三个**本地 Tool**：`GetWeatherTool` / `CalculatorTool` / `ReminderTool` |
| `LLMClient.swift` | `LLMClient` 协议 + `ScriptedLLM`（Mock）+ `LocalLLMClient`（接 llama.cpp 的骨架） |
| `MCPClient.swift` | `MCPBackedTool`（**手机=Client，向云端 MCP Server 发 `tools/call`**）+ 本地拦截的 `MockMCPURLProtocol` |
| `AgentLoop.swift` | **Agent 循环**：LLM 决策 → 解析 Function Call → 执行 Tool → 回灌，直到模型给最终答案 |
| `main.swift` | 组装注册表、跑两个场景 |

## 核心结论（也是文章的结论）

- **Function Calling 是机制（动词），Tool 是被调的函数（名词）**：没有机制，Tool 只是死定义。
- **Skill = 用多个 Tool 编排成的成品能力**；**MCP = 当 Tool 不住在本进程时，跨进程/跨网络接进来的标准接口**。
- 从 Agent 循环视角，**本地 Tool 与 MCP Tool 完全无差别**——MCP 只是「函数住哪」的另一种答案。
- **MCP 在移动端**：适合「手机当 MCP Client 连云端 Server」，不适合「在手机里跑 MCP Server」（iOS/Android 沙盒限制多进程 + 会废掉离线/弱网降级）。本地活儿交给原生 Function Calling，跨网络的活儿才交给 MCP。

## 接入真实本地模型

把 `LocalLLMClient` 的 `chat` 实现补全即可：

1. 把 `registry.specList()` 的 Tool schema 拼进 system prompt（或走模型自带的 tool-calling 格式）；
2. 让 `LocalLLM.generate` 吐出 JSON 形式的 `function_call`；
3. 用 `JSONSerialization` 解析出 `name` + `arguments`，返回 `.toolCall(...)` 交回 `AgentLoop`。

真实工程见仓库里的 `LocalLLMDemo/`（已集成 llama.cpp）。
