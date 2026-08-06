import Foundation

/// 进程内 Tool 示例 1：查天气（纯本地模拟，不联网）
struct GetWeatherTool: Tool {
    let spec = ToolSpec(
        name: "get_weather",
        description: "查询指定城市的当前天气",
        parametersJSONSchema: #"{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}"#
    )
    func run(argumentsJSON: String) async throws -> String {
        let city = (try parseArgs(argumentsJSON))["city"] as? String ?? "未知"
        return "\(city) 当前 25℃，晴，湿度 40%"   // 真实场景这里调天气 API
    }
}

/// 进程内 Tool 示例 2：计算器
struct CalculatorTool: Tool {
    let spec = ToolSpec(
        name: "calculator",
        description: "计算一个算术表达式，如 \"23*7\"",
        parametersJSONSchema: #"{"type":"object","properties":{"expression":{"type":"string"}},"required":["expression"]}"#
    )
    func run(argumentsJSON: String) async throws -> String {
        let expr = (try parseArgs(argumentsJSON))["expression"] as? String ?? "0"
        // ⚠️ 演示用 NSExpression；生产环境务必用安全的表达式求值，绝不能 eval 外部输入。
        if let val = NSExpression(format: expr).expressionValue(with: nil, context: nil) as? NSNumber {
            return "\(expr) = \(val)"
        }
        return "无法计算：\(expr)"
    }
}

/// 进程内 Tool 示例 3：设提醒（呼应你 BabyFood 的 ReminderTool 思路）
struct ReminderTool: Tool {
    let spec = ToolSpec(
        name: "create_reminder",
        description: "创建一个本地提醒",
        parametersJSONSchema: #"{"type":"object","properties":{"text":{"type":"string"},"when":{"type":"string"}},"required":["text","when"]}"#
    )
    func run(argumentsJSON: String) async throws -> String {
        let args = try parseArgs(argumentsJSON)
        let text = args["text"] as? String ?? ""
        let when = args["when"] as? String ?? "稍后"
        return "已创建提醒[\(when)]：\(text)"
    }
}
