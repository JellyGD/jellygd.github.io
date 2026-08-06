import Foundation

/// Tool：Function Calling 落地时真正被调用的那个函数。
/// spec 是给模型看的"说明书"，run 是给程序执行的"实现"。
protocol Tool: Sendable {
    var spec: ToolSpec { get }
    /// 入参是模型给的 JSON 字符串，返回值是喂回模型的文本结果。
    func run(argumentsJSON: String) async throws -> String
}

/// 进程内的 Tool 注册表——Agent 循环靠它把"函数名"映射到"实现"。
/// 从循环视角看，本地 Tool 与 MCP Tool 都登记在这里，无差别。
actor ToolRegistry {
    private var tools: [String: any Tool] = [:]
    func register(_ tool: some Tool) { tools[tool.spec.name] = tool }
    func specList() -> [ToolSpec] { Array(tools.values.map { $0.spec }) }
    func run(name: String, argumentsJSON: String) async throws -> String {
        guard let tool = tools[name] else { throw AgentError.unknownTool(name) }
        return try await tool.run(argumentsJSON: argumentsJSON)
    }
}

enum AgentError: Error, LocalizedError {
    case unknownTool(String)
    case maxRoundsExceeded
    case badJSON(String)
    var errorDescription: String? {
        switch self {
        case .unknownTool(let n): return "未知工具：\(n)"
        case .maxRoundsExceeded:  return "超出最大轮数"
        case .badJSON(let j):     return "参数 JSON 解析失败：\(j)"
        }
    }
}

/// 把模型给的 JSON 参数解析成字典（demo 用；生产请用 Codable 做类型安全）。
func parseArgs(_ json: String) throws -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AgentError.badJSON(json)
    }
    return obj
}
