import Foundation

@main
struct DemoRunner {
    static func main() async throws {
        print("===== AgentToolDemo：Function Calling 深入（一）调用链 =====\n")

        let registry = ToolRegistry()
        await registry.register(GetWeatherTool())
        await registry.register(CalculatorTool())
        await registry.register(ReminderTool())
        await registry.register(ConvertCurrencyTool())
        // MCP Tool：从 Agent 循环视角，它和本地 Tool 完全一样——区别只在 run 跨了网络。
        await registry.register(MCPBackedTool(
            spec: ToolSpec(
                name: "get_server_price",
                description: "向云端 MCP Server 查询商品价格",
                parametersJSONSchema: #"{"type":"object","properties":{},"required":[]}"#,
                parallelSafe: true,
                riskLevel: .confirmAlways),   // 联网查询：只读但出设备，每次确认
            serverURL: URL(string: "http://mcp.local/tools/call")!))

        // 场景一：本地 Tool 链（单轮多次调用，串行回填）
        print("----- 场景一：本地 Tool 链 -----")
        let localLLM = ScriptedLLM([
            .toolCall(name: "get_weather",     argumentsJSON: #"{"city":"北京"}"#,       id: "c1"),
            .toolCall(name: "calculator",      argumentsJSON: #"{"expression":"23*7"}"#, id: "c2"),
            .toolCall(name: "create_reminder", argumentsJSON: #"{"text":"明天买菜","when":"明天"}"#, id: "c3"),
            .text("北京今天 25℃ 晴；23×7=161；已帮你设好明天买菜的提醒。")
        ])
        let ans1 = try await AgentLoop(llm: localLLM, registry: registry)
            .run(userInput: "北京天气怎样？顺便算 23*7，再提醒我明天买菜")
        print("  ✅ 用户最终收到：\(ans1)\n")

        // 场景二：MCP Tool（手机当 Client 连云端）
        print("----- 场景二：MCP Tool（手机 → 云端）-----")
        let mcpLLM = ScriptedLLM([
            .toolCall(name: "get_server_price", argumentsJSON: "{}", id: "m1"),
            .text("已通过云端 MCP 查到：iPhone 16 Pro 售价 7999 元。")
        ])
        let ans2 = try await AgentLoop(llm: mcpLLM, registry: registry)
            .run(userInput: "查下 iPhone 16 Pro 的价格")
        print("  ✅ 用户最终收到：\(ans2)\n")

        // 场景三：同一轮多个 tool_call —— 并行执行（天气和计算器无依赖）
        print("----- 场景三：并行工具调用 -----")
        let parallelLLM = ScriptedLLM([
            .toolCalls([
                (name: "get_weather", argumentsJSON: #"{"city":"上海"}"#, id: "p1"),
                (name: "calculator",  argumentsJSON: #"{"expression":"100/8"}"#, id: "p2")
            ]),
            .text("上海 25℃ 晴；100÷8=12.5。")
        ])
        let ans3 = try await AgentLoop(llm: parallelLLM, registry: registry)
            .run(userInput: "上海天气，再算 100/8")
        print("  ✅ 用户最终收到：\(ans3)\n")

        // 场景三补：同一轮同时拿到「只读工具 + 有副作用工具」——策略判串行。
        // get_weather(parallelSafe) + create_reminder(有副作用) → 含非安全调用，按序串行。
        print("----- 场景三补：只读 + 副作用混合并发 → 判串行 -----")
        let mixedLLM = ScriptedLLM([
            .toolCalls([
                (name: "get_weather",     argumentsJSON: #"{"city":"广州"}"#, id: "x1"),
                (name: "create_reminder", argumentsJSON: #"{"text":"取快递","when":"下午"}"#, id: "x2")
            ]),
            .text("广州 25℃ 晴；已帮你设好下午取快递的提醒。")
        ])
        let ans3b = try await AgentLoop(llm: mixedLLM, registry: registry)
            .run(userInput: "广州天气怎样？顺便提醒我下午取快递")
        print("  ✅ 用户最终收到：\(ans3b)\n")

        // 场景六：权限确认——低风险首次询问并记住，高风险每次确认且可被拒绝。
        // create_reminder(.askOnce) 批准并记住；get_server_price(.confirmAlways) 按预设拒绝。
        print("----- 场景六：权限确认（askOnce + confirmAlways + 拒绝）-----")
        let authLLM = ScriptedLLM([
            .toolCalls([
                (name: "create_reminder", argumentsJSON: #"{"text":"取快递","when":"下午"}"#, id: "s1"),
                (name: "get_server_price", argumentsJSON: "{}", id: "s2")   // confirmAlways，按预设拒绝
            ]),
            .text("已帮你设好下午取快递的提醒；但查价格被你拒绝了，我没法告诉你价格。")
        ])
        let authLoop = AgentLoop(llm: authLLM, registry: registry,
                                 approver: ScriptedApprover(["get_server_price": false]))
        let ans6 = try await authLoop
            .run(userInput: "提醒我下午取快递，再查下价格")
        print("  ✅ 用户最终收到：\(ans6)\n")

        // 场景四：参数校验失败 —— 枚举白名单拦下非法币种，把原因回灌给模型
        print("----- 场景四：强校验 + 错误回退 -----")
        let badLLM = ScriptedLLM([
            .toolCall(name: "convert_currency", argumentsJSON: #"{"amount":100,"from":"GBP","to":"CNY"}"#, id: "v1"),
            .text("抱歉，目前只支持 USD / CNY / EUR 三种币种。")
        ])
        let ans4 = try await AgentLoop(llm: badLLM, registry: registry)
            .run(userInput: "把 100 英镑换成人民币")
        print("  ✅ 用户最终收到：\(ans4)\n")

        // 场景五：流式 tool_call 累积（演示累加器，真实流式模型分片吐出时同理）
        print("----- 场景五：流式 tool_call 累积 -----")
        let acc = ToolCallAccumulator()
        await acc.append(index: 0, nameDelta: "get_", argsDelta: #"{"city":"#)
        await acc.append(index: 0, nameDelta: "weather", argsDelta: #"北京"}"#)
        if let first = await acc.collect().first {
            print("  ↳ 累积完成：\(first.name)，参数 \(first.arguments)")
        }
    }
}
