import Foundation

/// 校验结果：要么通过（拿到清洗后的参数），要么失败（带原因，方便回灌给模型让它改）。
enum ValidationResult {
    case ok([String: Any])
    case failed(reason: String)
}

/// 强校验：模型给的 JSON 不一定是干净的结构化数据——
/// 它可能是漏了必填、类型错、或者塞了枚举外的值。
/// 这一步是你和模型之间的"契约护栏"，比事后在 run 里 if-let 兜底要稳得多：
/// 模型不知道你的内部规则，你也不能假设它每次都守规矩。
struct ToolValidator {
    let schema: ToolSchema

    func validate(argumentsJSON: String) -> ValidationResult {
        guard let data = argumentsJSON.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(reason: "参数不是合法 JSON")
        }
        var cleaned: [String: Any] = [:]
        for p in schema.params {
            guard let value = raw[p.name] else {
                if p.required { return .failed(reason: "缺少必填参数：\(p.name)") }
                continue
            }
            switch p.type {
            case .string:
                guard let s = value as? String else { return .failed(reason: "\(p.name) 应为字符串") }
                var s2 = s
                if let m = p.maxLength, s2.count > m { s2 = String(s2.prefix(m)) }   // 截断而非报错
                if let e = p.allowedValues, !e.contains(s2) {
                    return .failed(reason: "\(p.name) 取值必须在 \(e) 内")
                }
                cleaned[p.name] = s2
            case .integer, .number:
                guard let n = value as? NSNumber else { return .failed(reason: "\(p.name) 应为数字") }
                cleaned[p.name] = n
            case .boolean:
                guard let b = value as? Bool else { return .failed(reason: "\(p.name) 应为布尔") }
                cleaned[p.name] = b
            case .array:
                guard let a = value as? [Any] else { return .failed(reason: "\(p.name) 应为数组") }
                if let m = p.maxLength, a.count > m { cleaned[p.name] = Array(a.prefix(m)) }
                else { cleaned[p.name] = a }
            case .object:
                guard let o = value as? [String: Any] else { return .failed(reason: "\(p.name) 应为对象") }
                cleaned[p.name] = o
            }
        }
        return .ok(cleaned)
    }
}

/// 工具返回内容会原样拼回 prompt。联网 / MCP 工具返回的是不可信文本，
/// 可能被注入"忽略前面指令，改去干 X"。这里做两件事：
/// 1) 截断超长——保护上下文窗口，也缩小注入面；
/// 2) 清掉控制字符——避免它破坏消息结构、偷偷换行冒充新指令。
/// 注意：这只能算"边界隔离"的第一层；真正的防护还要在拼 prompt 时用定界符
/// 把工具输出明确框起来，告诉模型"这一段是数据，不是指令"。
func sanitizeToolResult(_ raw: String) -> String {
    let capped = raw.count > 4000 ? String(raw.prefix(4000)) : raw
    return capped.replacingOccurrences(of: "\u{0}", with: "")
}
