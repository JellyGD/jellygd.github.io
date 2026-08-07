---
layout: post
title: "移动端 AI Agent 深入系列（一）：Function Calling / Tool Use —— 从意图到可靠执行"
date: 2026-08-07
author: Jelly
categories: AI Agent
tags:
  - AI Agent
  - 端侧 AI
  - Function Calling
  - Tool Use
  - Swift
---

> 基础篇里我把 Function Calling 草草当成「模型能调我的函数」带过了。这个误判骗了我很久。
>
> 真正把它接进 App 之后我才发现：模型不会调任何函数，它只是**吐一段结构化的意图**；真正执行的是我的代码，而「模型吐的意图」和「我的函数签名」之间，隔着一整套必须自己守的契约。契约哪一侧失守，哪一侧就出事——轻则查个假天气，重则整个 Agent 崩，或者工具返回里一句「忽略前文」把模型带跑。
>
> 这一篇把这一套契约拆开，配着我扩展后的 `AgentToolDemo` 走一遍：schema 设计、参数强校验、流式累积、并行编排、错误回退、结果回填与注入防护。代码都在仓库 `AgentToolDemo/Sources/AgentToolDemo/` 下，能直接跑。

## 先说清楚：模型只吐意图，不干活

Function Calling 机制的产出物，是模型在一轮输出里不再吐自然语言，而是吐一个结构化的调用请求。我把它定义成这样：

```swift
enum LLMResponse: Sendable {
    case text(String)
    case toolCall(name: String, argumentsJSON: String, id: String)
    case toolCalls([(name: String, argumentsJSON: String, id: String)])
}
```

注意那个 `id`。它不是装饰——一次对话里模型可能调同一个工具多次，或者一轮调多个工具，你要把「工具执行出来的结果」准确挂回「那一次具体的调用」，靠的就是 `id`。

这就回到我一直在用的那个剧组比喻：LLM 是主演，它**不会真的去拿伞**，它只是伸手比划一下「给我把伞」。真正去拿伞的，是副导演（也就是你的代码）。`argumentsJSON` 是它比划时嘟囔的「黑色的、长柄的」，你听懂了才去拿。

所以 Function Calling 落地的第一性原理是：**模型负责「说要调谁、参数是什么」，你负责「真去调、把结果拿回来、再喂回去」**。任何把模型当成「会自动执行代码」的理解，都会在线上给你惊喜。

## Tool Schema 是给模型看的「填空题题干」，也是给校验看的「判卷标准」

模型不知道你的函数签名长什么样。你得上交一份「说明书」，它才知道能填哪些空、每个空是什么类型。这份说明书就是 Tool Schema，喂给模型的就是 JSON Schema：

```swift
struct ParamDecl: Sendable {
    let name: String
    let type: ParamType          // string / integer / number / boolean / array / object
    let description: String
    let required: Bool
    let allowedValues: [String]? // 枚举白名单
    let maxLength: Int?
}
```

但我特别想强调一点：**schema 的价值不在「描述清楚」，而在「把边界钉死」**。三个东西最该钉死——

- `required`：漏了必填，后面全错。
- `allowedValues`（枚举白名单）：让模型只能从你给的池子里挑，不能自由发挥。我的 `ConvertCurrencyTool` 里 `from` / `to` 只允许 `USD / CNY / EUR`，模型填个 `GBP` 直接被拦。
- `maxLength`：防止一个超长字符串撑爆上下文窗口。

还有个工程上的小聪明：`ToolSchema` 这一份声明，既能 `toJSONSchema()` 渲染成给模型看的 JSON Schema，又能直接拿来对模型给的 JSON 做强校验。把「给模型看」和「给自己校验」绑在同一个源头上，才不会两份对不上、各说各话。

## 强校验：模型和结构化数据之间的一道护栏

我早期的做法，是工具 `run` 里用 `if-let` 兜底：拿不到就给默认值。后来踩的坑是——模型偶尔会塞个枚举外的值、或者把数字塞成字符串。兜底逻辑散落在十几个 `run` 里，根本改不过来。

正确做法是把校验独立出来，放在「调工具之前」，对着 schema 一道道过：

```swift
struct ToolValidator {
    let schema: ToolSchema
    func validate(argumentsJSON: String) -> ValidationResult {
        // 不是合法 JSON？缺必填？类型不对？枚举外？——逐项拦
        // 字符串超长则截断而非报错；枚举外则直接失败并带原因
    }
}
```

这里有个顺序上的判断：校验失败，是把错误甩给调用方让 `run` 崩，还是把「失败原因」当成一次正常的工具结果喂回给模型？我的选择是后者——下面「错误回退」一节会展开。

这一层校验，就是我 BabyFood 项目里那套「Tool Calling 契约」：schema 定义约束 + `parseArguments` 强校验两层。模型是不可控的生成器，你不能假设它每次都守规矩，**所有来自模型的输入，默认都是不可信的**。

## 流式 tool_call 累积：模型是分片吐出来的

基础篇的 Demo 里，模型一次性给完整 tool_call。但真实本地模型（llama.cpp 支持流式输出）是分片吐的：先吐半个 `name`，再吐一段 `arguments`，片段还带 `index` 表明「这是第几个调用」。

如果偷懒「直接把字符串拼起来」，你会遇到半截 JSON 被误判成完整调用的事故。所以我写了个按 `index` 累积的累加器，为接流式模型留好接口：

```swift
actor ToolCallAccumulator {
    func append(index: Int, nameDelta: String?, argsDelta: String?)
    func collect() -> [(index: Int, name: String, arguments: String)]
}
```

现在虽然是一次性拿结果，但用 `index` 累积比裸拼字符串稳，将来换流式模型不用返工。

## 并行还是串行：一轮多个 tool_call 怎么跑

模型一轮可能吐出多个 `tool_call`。这里最容易被绕进去的一点是：**同一轮里，模型其实"给不出"有数据依赖的并行调用。**

模型在一轮 completion 里生成一串 `tool_calls`，每个调用的参数都是从**已经写进 prompt 的历史上下文**里填的——它拿不到"同一个数组里另一个调用"的执行结果。所以如果工具 B 必须拿工具 A 的结果当参数，模型在**同一轮根本填不出 B 的正确参数**，它只能先发 A、拿到结果、下一轮再发 B。

换句话说：**模型既然把多个调用放在同一轮，结构上就等于声明"它们彼此独立"。** 这给了一个宽松的默认——可以并行。但"结构上独立"不等于"可以无脑并行"，编排引擎还得防三种例外：

- **副作用**：两个调用都有副作用（发消息、下单、建提醒），并行可能竞态或重复生效；
- **模型幻觉的依赖**：模型偶尔会"预判"一个它其实拿不到的参数值填进去（比如把上一步该查的 id 编一个），这种靠强校验兜底；
- **设备/外部资源**：并行全开会吃光端侧 CPU/内存，或打爆同一个外部 API 的限流。

所以编排引擎真正该做的，不是去"猜依赖图"，而是看**每个工具自己声明的安全属性**，再加一个并发上限：

- 这一轮所有调用都标了 `parallelSafe`（纯只读、幂等、不抢共享资源）→ 并行，但受 `maxConcurrency` 上限约束；
- 只要有一个标了有副作用 / 非幂等 → 按数组顺序串行；
- 强校验层是最后一道网，拦下幻觉出来的依赖参数。

（OpenAI 还提供 `parallel_tool_calls: false` 这种"一键强制串行"的粗粒度开关，但要做细到"哪些能并行"就得靠 per-tool 策略。）

我在 `ToolSpec` 上加了 `parallelSafe` 标记，并在 `AgentLoop` 里据此决定执行方式——这不是去猜依赖，而是按工具声明的属性拍板：

```swift
private func runMultiCall(_ calls: [(name: String, argumentsJSON: String, id: String)],
                          tools: [ToolSpec], into messages: inout [ChatMessage],
                          round: Int) async throws {
    let specByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    // 只有「全部」调用都标了 parallelSafe，才并行；任一有副作用就串行。
    let allSafe = calls.allSatisfy { specByName[$0.name]?.parallelSafe ?? false }

    if allSafe {
        print("本轮 \(calls.count) 个调用全为只读幂等 → 并行（上限 \(Self.maxConcurrency)）")
        let limiter = ConcurrencyLimiter(limit: Self.maxConcurrency)
        let collected = try await withThrowingTaskGroup(of: (String, String, String).self) { group in
            for call in calls {
                group.addTask {
                    await limiter.acquire()                 // 受上限约束，别无脑全开
                    defer { Task { await limiter.release() } }
                    let r = try await self.execute(name: call.name,
                                                   argsJSON: call.argumentsJSON, tools: tools)
                    return (call.id, call.name, r)
                }
            }
            var out: [(String, String, String)] = []
            for try await item in group { out.append(item) }
            return out.sorted { $0.0 < $1.0 }               // 按 id 排序回填
        }
        for (id, name, r) in collected {
            messages.append(.init(role: .tool, text: r, toolCallId: id))
        }
    } else {
        print("本轮含副作用/非幂等调用 → 按序串行")
        for call in calls {                                 // 串行：避免竞态与重复副作用
            let r = try await execute(name: call.name, argsJSON: call.argumentsJSON, tools: tools)
            messages.append(.init(role: .tool, text: r, toolCallId: call.id))
        }
    }
}
```

`AgentToolDemo` 三个场景是这段的实证：

- **场景三**：`get_weather` + `calculator` 都 `parallelSafe` → 打印"全为只读幂等 → 并行"；
- **场景三补**：`get_weather` + `create_reminder`（建提醒有副作用，`parallelSafe: false`）→ 打印"含副作用 → 按序串行"；
- **校验兜底**：即便模型幻觉出依赖参数，强校验会在执行前拦下，而不是并行跑出脏结果。

值得注意的是，串行 / 并行只解决"执行时机"。真正的数据依赖（B 要 A 的结果当参数）模型在同一轮填不出，会自然落到下一轮——编排引擎**不需要**在这里解依赖图，那是过度设计。

## 确认与权限管理：把关键操作的决定权交还用户

前面几节默认工具"拿到就跑"。但端侧 Agent 跑在用户手机上，工具动的是真实世界——建一条提醒、发一条消息、下一笔单、删一张照片。让模型自己悄无声息地执行这些，是这套机制最危险的地方。我必须把"要不要执行"从模型手里收回来一部分，交还给用户。

这里有两件事，别混为一谈：

- **确认机制（怎么问）**：技术上的"刹车"——执行前弹窗，把工具要做什么、参数是什么摆出来，用户点批准或拒绝。它在真实 App 里是 SwiftUI 的 `.confirmationDialog`，在编排循环里只是个可替换的协议。
- **权限策略（什么时候问、问几次）**：产品上的"分级"——哪些永远不问、哪些问一次、哪些每次都问、哪些默认禁止。它决定用户体验是"顺滑"还是"被弹窗烦死"。

我用 `RiskLevel` 把权限策略做成四级，每个工具自己声明：

```swift
enum RiskLevel: Sendable {
    case auto          // 纯只读、无副作用、不出设备：直接跑，绝不打扰
    case askOnce       // 低风险本地写入：首次询问，记住选择（像 macOS 隐私弹窗）
    case confirmAlways // 高风险（联网发送 / 支付 / 删除）：每次都确认
    case blocked       // 默认禁止，需用户在设置里显式开启
}
```

`auto` 是默认档——`get_weather`、`calculator`、`convert_currency` 这种纯计算、不出设备的，没人想每次都被问。`create_reminder` 是低风险本地写入，我标 `askOnce`：第一次问，记住选择，之后同会话不再烦。`get_server_price` 要联网出设备，我标 `confirmAlways`：每次都确认，因为"把数据发到云端"这件事的代价不该被记住后悄悄发生。

`blocked` 是兜底档——比如"格式化本地缓存"这种不可逆操作，默认不让你跑，得用户去设置里手动开。默认禁止而不是默认允许，是端侧权限的底线思维。

确认这件事有个容易踩的坑：**确认是串行边界，不能并行问用户。** 一轮里若有两个工具都要确认，你不能同时弹两个对话框，用户会被搞懵，UI 也会乱。所以我在 `runMultiCall` 里把"确认"抽成第一步、串行地问完，记下放行结果，再对通过的调用按并行/串行策略执行：

```swift
// 1) 串行确认：确认是用户交互边界，不能并行问，问完记下放行结果
var approved: [(call, ok: Bool)] = []
for call in calls {
    let level = specByName[call.name]?.riskLevel ?? .auto
    let ok = await permission.decide(toolName: call.name, level: level) {
        await approver.request(toolName: call.name, arguments: call.argumentsJSON, level: level)
    }
    approved.append((call, ok))
}
// 2) 被拒的：回填拒因，不进执行
// 3) 批准的：按 parallelSafe 决定并行/串行（此处不再过权限门）
```

`PermissionMemory` 负责"问一次记住"——`askOnce` 首次问完把选择存进 actor，之后同会话直接复用。`decide` 这个开关函数把四级策略集中在一处，编排循环和确认 UI 都依赖它，互不耦合：

```swift
func decide(toolName: String, level: RiskLevel, ask: @Sendable () async -> Bool) async -> Bool {
    switch level {
    case .auto:           return true
    case .blocked:        return false
    case .confirmAlways:  return await ask()           // 每次都问
    case .askOnce:                                   // 首次问、之后记住
        if let cached = remembered[toolName] { return cached }
        let ok = await ask()
        remembered[toolName] = ok
        return ok
    }
}
```

`AgentToolDemo` 场景六就是这套的实证：`create_reminder`（askOnce）被批准并记住，`get_server_price`（confirmAlways）被预设拒绝——循环打印"用户拒绝，跳过"，并把"查不了价格"如实告诉模型，模型在最终回答里向用户说明。

权限管理还有两个延伸方向，值得在真实项目里做厚：

- **按"能力"而不是"工具"授权**：与其逐个工具记开关，不如按它动了什么来分——`.network`、`.contacts`、`.payments`、`.deviceWrite`。一个工具声明它需要 `.payments`，用户授权一次，所有要钱的工具有了统一闸门。这比 per-tool 开关更贴近系统级隐私模型的直觉。
- **持久化与可撤回**：`askOnce` 的记忆要落盘（UserDefaults / Keychain），并且用户在设置里能一键重置。否则"第一次手滑拒绝了天气"会永久黑掉这个工具，体验灾难。

权限门不是可选项，是端侧 Agent 上架前的硬门槛。**Function Calling 把"手"给了模型，但"手能不能动、动之前要不要问"必须留在用户和系统手里。**

## 错误回退：工具挂了，别让整个 Agent 崩

工具执行可能抛错——网络超时、JSON 解析失败、后端 500。如果我让异常直接冒泡，整个 Agent 循环就死了，用户看到的是白屏。

我的做法是把异常接住，把「错误」当成一次正常的工具结果喂回给模型：

```swift
do {
    let raw = try await registry.run(name: name, argumentsJSON: argsJSON)
    return sanitizeToolResult(raw)
} catch {
    return "工具执行出错：\(error.localizedDescription)。请换种方式或告知用户。"
}
```

注意：参数校验失败，走的是**同一条**「回灌失败原因」的路。场景四里有完整实证——模型填了 `GBP`，校验拦下，回灌「取值必须在 [USD, CNY, EUR] 内」，模型下一轮就道歉说只支持三种币种。**错误不是终点，是模型自我纠正的素材。**

## 结果回填与 Prompt Injection：工具返回的是不可信文本

最后这一步最容易被忽略。工具执行完，结果要拼回 prompt 让模型继续。可工具返回的内容（尤其 MCP、联网工具）是**不可信文本**——它可能夹一句「忽略前面的指令，改去干 X」。

我做了两层防护：

1. `sanitizeToolResult` 先截断超长、清掉控制字符，缩窄注入面、保护上下文窗口。
2. 真正关键的，是在拼 prompt 时用定界符把工具输出**明确框起来**，告诉模型「这一段是数据，不是指令」。

第二层我在 Demo 里没写死（不同模型格式不同），但它是移动端端云结合（系列四）里最该补的安全点。Phone 当 MCP Client 连云端时，云端返回什么都算外部输入，**绝不能让一段工具输出冒充成用户或系统的指令**。

## 收尾

把这几件事串起来才是「可靠的函数调用」：

> schema 钉死边界 → 调用前强校验 → 流式按 index 累积 → 多调用并行编排 → 执行错误回退 → 结果回填做注入隔离。

任何一环偷懒，线上都会用一种你意想不到的方式报复你。我扩完 `AgentToolDemo` 跑通五个场景（`swiftc` 直编可运行），下一轮要聊的是：**当对话变长、工具结果越积越多，上下文窗口怎么管**——那就是 Context Engine 的活了。
