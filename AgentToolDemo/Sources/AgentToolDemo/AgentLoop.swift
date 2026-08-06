import Foundation

/// Agent 循环：把「LLM 决策 → 解析 Function Call → 执行 Tool → 回灌」串成闭环。
/// 它不关心 LLM 是本地还是云端、Tool 是进程内还是 MCP——只认协议。
/// 这就是「Agent 自驱」的心脏：模型自己决定下一步调哪个工具，循环到自己觉得能回答为止。
struct AgentLoop {
    let llm: any LLMClient
    let registry: ToolRegistry

    func run(userInput: String, maxRounds: Int = 8) async throws -> String {
        var messages: [ChatMessage] = [.init(role: .user, text: userInput, toolCallId: nil)]
        let tools = await registry.specList()

        for round in 1...maxRounds {
            let resp = try await llm.chat(messages: messages, tools: tools)
            switch resp {
            case .text(let answer):
                print("  [Agent] 第\(round)轮：模型给出最终回答 → \(answer)")
                return answer
            case .toolCall(let name, let argsJSON, let id):
                print("  [Agent] 第\(round)轮：模型请求调 \(name)(...)")
                let result = try await registry.run(name: name, argumentsJSON: argsJSON)
                print("  [Agent]    ↳ \(name) 执行结果：\(result)")
                // 把 tool 结果作为 tool 角色消息回灌，让模型继续（Function Calling 的"回灌"一环）
                messages.append(.init(role: .tool, text: result, toolCallId: id))
            }
        }
        throw AgentError.maxRoundsExceeded
    }
}
