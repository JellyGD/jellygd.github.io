import Foundation

/// 本地模型仓库：GGUF 落盘位置 + 是否已下载 + 占用大小。
/// 类比：这是「解码器文件」在 App 里的家（Application Support，不会被清缓存清掉）。
final class ModelStore {
    static let shared = ModelStore()

    private let dir: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func localURL(for item: ModelItem) -> URL {
        dir.appendingPathComponent(item.id + ".gguf")
    }

    func isDownloaded(_ item: ModelItem) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: item).path)
    }

    func localSize(_ item: ModelItem) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: localURL(for: item).path)[.size] as? Int64) ?? 0
    }
}
