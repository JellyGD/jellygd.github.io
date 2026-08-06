import SwiftUI

struct ModelLibraryView: View {
    @ObservedObject var vm: ChatViewModel
    @State private var progress: [String: Double] = [:]
    @State private var active: [String: Bool] = [:]

    var body: some View {
        List(ModelCatalog.all) { item in
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(.headline)
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                Text("约 \(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file)) · 建议 ≥\(item.minDeviceRAMGB)GB 可用内存")
                    .font(.caption2).foregroundStyle(.tertiary)

                HStack(spacing: 12) {
                    if ModelStore.shared.isDownloaded(item) {
                        if vm.loadedItemID == item.id {
                            Label("已加载", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("加载并对话") { vm.load(item) }
                                .buttonStyle(.borderedProminent)
                        }
                    } else if active[item.id] == true {
                        ProgressView(value: progress[item.id] ?? 0) {
                            Text("下载中 \(Int((progress[item.id] ?? 0) * 100))%")
                        }
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                        Button("暂停") {
                            ModelDownloader.shared.pause(item.id)
                            active[item.id] = false
                        }
                    } else {
                        Button(ModelDownloader.shared.hasResumeData(item.id)
                               ? "继续（断点续传）" : "下载") {
                            start(item)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .navigationTitle("模型库")
    }

    private func start(_ item: ModelItem) {
        active[item.id] = true
        ModelDownloader.shared.fetch(
            item: item,
            progress: { frac, _, _ in
                Task { @MainActor in self.progress[item.id] = frac }
            },
            completion: { result in
                Task { @MainActor in
                    self.active[item.id] = false
                    switch result {
                    case .success:
                        self.progress[item.id] = 1
                    case .failure(let e):
                        self.progress[item.id] = -1
                        print("下载失败：\(e.localizedDescription)")
                    }
                }
            }
        )
    }
}
