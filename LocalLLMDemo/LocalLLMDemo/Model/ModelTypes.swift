import Foundation

enum Role: String, Codable, Sendable {
    case user, assistant, system
}

/// 一条聊天消息（UI 列表的一个单元格）
struct ChatMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let role: Role
    var text: String
    init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// 一个可下载的本地模型（分层模型目录里的一项）
struct ModelItem: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let sizeBytes: Int64
    let downloadURL: URL
    let minDeviceRAMGB: Int
    let isDefaultRecommended: Bool
}
