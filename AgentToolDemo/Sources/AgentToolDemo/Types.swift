import Foundation

/// 消息角色。.tool 是 Function Calling 回灌结果时用的角色。
enum Role: String, Sendable { case system, user, assistant, tool }

/// 一条对话消息。toolCallId 用于把"工具结果"挂回对应的那次 tool_call。
struct ChatMessage: Sendable {
    let role: Role
    let text: String
    let toolCallId: String?
}

/// 模型一轮的输出：要么是直接回答，要么是一次 Function Call 请求。
/// 这正是 Function Calling 机制的"产出物"——模型不再吐自然语言，而吐结构化调用。
enum LLMResponse: Sendable {
    case text(String)
    case toolCall(name: String, argumentsJSON: String, id: String)
}

/// 一个 Tool 对外暴露的"说明书"——喂给模型的 schema。
/// 真实项目里应为 JSON Schema；demo 用字符串简化。
struct ToolSpec: Sendable {
    let name: String
    let description: String
    let parametersJSONSchema: String
}
