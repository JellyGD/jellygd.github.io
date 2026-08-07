import Foundation

/// 工具的风险等级——权限管理的"策略表"。编排循环在执行前看这一级，
/// 决定要不要把决定权交回给用户。四级对应移动端最自然的四种处置。
enum RiskLevel: Sendable {
    case auto          // 纯只读、无副作用、不出设备：直接跑，绝不打扰
    case askOnce       // 低风险本地写入：首次询问，记住选择（像 macOS 隐私弹窗）
    case confirmAlways // 高风险（联网发送 / 支付 / 删除）：每次都确认
    case blocked       // 默认禁止，需用户在设置里显式开启
}

extension RiskLevel: CustomStringConvertible {
    var description: String {
        switch self {
        case .auto:          return "自动放行"
        case .askOnce:       return "首次询问"
        case .confirmAlways: return "每次确认"
        case .blocked:       return "已禁用"
        }
    }
}

/// 确认机制的抽象：把"问用户"这件事从编排循环里抽出来。
/// 真实 App 里它是 SwiftUI 的 .confirmationDialog；demo 里用脚本化实现演示。
protocol ConfirmationProvider: Sendable {
    func request(toolName: String, arguments: String, level: RiskLevel) async -> Bool
}

/// 记住"首次询问"后的选择，避免同一会话里反复打扰——权限管理的关键优化点。
/// 真实实现应持久化到磁盘（UserDefaults / Keychain），这里用 actor 隔离内存状态演示。
actor PermissionMemory {
    private var remembered: [String: Bool] = [:]
    /// 根据风险等级给出最终是否放行：
    /// - auto 直接放行；blocked 直接拒绝；
    /// - confirmAlways 每次都问；askOnce 首次问、之后记住。
    func decide(toolName: String, level: RiskLevel, ask: @Sendable () async -> Bool) async -> Bool {
        switch level {
        case .auto:           return true
        case .blocked:        return false
        case .confirmAlways:  return await ask()
        case .askOnce:
            if let cached = remembered[toolName] { return cached }
            let ok = await ask()
            remembered[toolName] = ok
            return ok
        }
    }
}

/// 日志型确认器：打印并默认批准。让基础场景也能看到"闸门在生效"，不中断流程。
struct LoggingApprover: ConfirmationProvider {
    func request(toolName: String, arguments: String, level: RiskLevel) async -> Bool {
        print("    🔒 [\(level)] 需用户确认：\(toolName) \(arguments) → 用户批准")
        return true
    }
}

/// 脚本化确认器：按预设决定批准/拒绝，用于演示拒绝路径。
actor ScriptedApprover: ConfirmationProvider {
    private let decisions: [String: Bool]
    init(_ decisions: [String: Bool] = [:]) { self.decisions = decisions }
    func request(toolName: String, arguments: String, level: RiskLevel) async -> Bool {
        let ok = decisions[toolName] ?? true
        print("    🔒 [\(level)] 需用户确认：\(toolName) \(arguments) → 用户\(ok ? "批准" : "拒绝")")
        return ok
    }
}
