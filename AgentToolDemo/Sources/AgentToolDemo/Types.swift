import Foundation

/// 消息角色。.tool 是 Function Calling 回灌结果时用的角色。
enum Role: String, Sendable { case system, user, assistant, tool }

/// 一条对话消息。toolCallId 用于把"工具结果"挂回对应的那次 tool_call。
struct ChatMessage: Sendable {
    let role: Role
    let text: String
    let toolCallId: String?
}

/// 模型一轮的输出：要么是文本，要么是一次或多次 Function Call 请求。
/// 这正是 Function Calling 机制的"产出物"——模型不再吐自然语言，而吐结构化调用。
/// 同一轮可能一次吐多个 tool_call（无依赖时），循环应当并行执行。
enum LLMResponse: Sendable {
    case text(String)
    case toolCall(name: String, argumentsJSON: String, id: String)
    case toolCalls([(name: String, argumentsJSON: String, id: String)])
}

/// 一个 Tool 对外暴露的"说明书"——喂给模型的 schema。
/// 真实项目里应为 JSON Schema（见 ToolSchema），这里保留字符串入口兼容旧写法，
/// 也新增从结构化 schema 直接构造的入口，让"给模型看"和"给自己校验"同源。
struct ToolSpec: Sendable {
    let name: String
    let description: String
    let parametersJSONSchema: String
    /// 可选：结构化参数表，循环据此做强校验与枚举约束。
    let schema: ToolSchema?
    /// 是否允许在同一轮里被并行执行。
    /// 默认 false（保守串行）：凡有副作用、非幂等、或会抢同一外部资源的工具都应标 false。
    /// 只有纯只读、幂等、彼此无共享状态的工具才标 true。
    /// 编排引擎据此在"同一轮多个 tool_call"时决定并行还是串行（见 AgentLoop）。
    let parallelSafe: Bool
    /// 风险等级——权限管理的策略表。执行前编排引擎据此决定是否要用户确认（见 Permission）。
    /// 默认 .auto（纯只读、无副作用，直接跑）。有副作用/联网/不可逆的应标更高等级。
    let riskLevel: RiskLevel

    init(name: String, description: String, parametersJSONSchema: String,
         schema: ToolSchema? = nil, parallelSafe: Bool = false, riskLevel: RiskLevel = .auto) {
        self.name = name
        self.description = description
        self.parametersJSONSchema = parametersJSONSchema
        self.schema = schema
        self.parallelSafe = parallelSafe
        self.riskLevel = riskLevel
    }

    /// 从结构化 schema 构造：schema 同时驱动"给模型看"和"给自己校验"两份用途。
    init(name: String, description: String, schema: ToolSchema,
         parallelSafe: Bool = false, riskLevel: RiskLevel = .auto) {
        self.init(name: name, description: description,
                  parametersJSONSchema: schema.toJSONSchema(), schema: schema,
                  parallelSafe: parallelSafe, riskLevel: riskLevel)
    }
}
