import Foundation

/// 进程内 Tool 示例 1：查天气（纯本地模拟，不联网）
struct GetWeatherTool: Tool {
    static let schema = ToolSchema(params: [
        ParamDecl(name: "city", type: .string, description: "城市名，如 北京", required: true, allowedValues: nil, maxLength: 32)
    ])
    let spec = ToolSpec(name: "get_weather", description: "查询指定城市的当前天气", schema: GetWeatherTool.schema, parallelSafe: true)
    func run(argumentsJSON: String) async throws -> String {
        let city = (try parseArgs(argumentsJSON))["city"] as? String ?? "未知"
        return "\(city) 当前 25℃，晴，湿度 40%"   // 真实场景这里调天气 API
    }
}

/// 进程内 Tool 示例 2：计算器
struct CalculatorTool: Tool {
    static let schema = ToolSchema(params: [
        ParamDecl(name: "expression", type: .string, description: "算术表达式，如 23*7", required: true, allowedValues: nil, maxLength: 64)
    ])
    let spec = ToolSpec(name: "calculator", description: "计算一个算术表达式", schema: CalculatorTool.schema, parallelSafe: true)
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
    static let schema = ToolSchema(params: [
        ParamDecl(name: "text", type: .string, description: "提醒内容", required: true, allowedValues: nil, maxLength: 128),
        ParamDecl(name: "when", type: .string, description: "提醒时间描述", required: true, allowedValues: nil, maxLength: 32)
    ])
    // ⚠️ 有副作用（在设备上真实建一条提醒），绝不能和其他调用盲目并行 → parallelSafe: false
    //     且属于低风险本地写入 → riskLevel: .askOnce（首次询问，记住选择）
    let spec = ToolSpec(name: "create_reminder", description: "创建一个本地提醒",
                        schema: ReminderTool.schema, parallelSafe: false, riskLevel: .askOnce)
    func run(argumentsJSON: String) async throws -> String {
        let args = try parseArgs(argumentsJSON)
        let text = args["text"] as? String ?? ""
        let when = args["when"] as? String ?? "稍后"
        return "已创建提醒[\(when)]：\(text)"
    }
}

/// 进程内 Tool 示例 4：货币换算——专门演示"枚举白名单"：
/// from / to 只允许 USD / CNY / EUR，模型填 GBP 之类会被强校验直接拦下（见场景四）。
struct ConvertCurrencyTool: Tool {
    static let schema = ToolSchema(params: [
        ParamDecl(name: "amount", type: .number, description: "金额", required: true, allowedValues: nil, maxLength: nil),
        ParamDecl(name: "from", type: .string, description: "源币种", required: true, allowedValues: ["USD","CNY","EUR"], maxLength: 3),
        ParamDecl(name: "to", type: .string, description: "目标币种", required: true, allowedValues: ["USD","CNY","EUR"], maxLength: 3)
    ])
    let spec = ToolSpec(name: "convert_currency", description: "货币换算", schema: ConvertCurrencyTool.schema, parallelSafe: true)
    func run(argumentsJSON: String) async throws -> String {
        let a = (try parseArgs(argumentsJSON))["amount"] as? NSNumber ?? 0
        return "\(a) 已换算（demo 固定汇率 7.2）"
    }
}
