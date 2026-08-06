import Foundation

@main
struct DemoRunner {
    static func main() async throws {
        print("===== AgentToolDemo：一次完整的 Function Calling 调用链 =====\n")

        let registry = ToolRegistry()
        await registry.register(GetWeatherTool())
        await registry.register(CalculatorTool())
        await registry.register(ReminderTool())
        // MCP Tool：从 Agent 循环视角，它和本地 Tool 完全一样——区别只在 run 跨了网络。
        await registry.register(MCPBackedTool(
            spec: ToolSpec(
                name: "get_server_price",
                description: "向云端 MCP Server 查询商品价格",
                parametersJSONSchema: #"{"type":"object","properties":{},"required":[]}"#),
            serverURL: URL(string: "http://mcp.local/tools/call")!))

        // 场景一：本地 Tool 链（进程内 Function Calling）
        print("----- 场景一：本地 Tool（天气 + 计算器 + 提醒）-----")
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
        print("----- 场景二：MCP Tool（手机 → 云端 MCP Server）-----")
        let mcpLLM = ScriptedLLM([
            .toolCall(name: "get_server_price", argumentsJSON: "{}", id: "m1"),
            .text("已通过云端 MCP 查到：iPhone 16 Pro 售价 7999 元。")
        ])
        let ans2 = try await AgentLoop(llm: mcpLLM, registry: registry)
            .run(userInput: "查下 iPhone 16 Pro 的价格")
        print("  ✅ 用户最终收到：\(ans2)\n")

        print("===== 链路说明 =====")
        print("· 本地 Tool：函数就在 App 进程内，直接调（Function Calling 落地）。")
        print("· MCP Tool：函数住在云端 MCP Server，App 发 JSON-RPC tools/call（手机 = Client）。")
        print("· 对 Agent 循环来说两者无差别——MCP 只是『函数住哪』的另一种答案。")
    }
}
