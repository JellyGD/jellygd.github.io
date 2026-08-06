import Foundation
import Combine

/// 聊天界面背后的逻辑：管消息列表、加载模型、流式生成、停止。
/// @MainActor：所有 UI 状态都在主线程更新。
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isGenerating: Bool = false
    @Published var statusText: String = "未加载模型"
    @Published var loadedItemID: String?

    private let llm = LocalLLM()
    private var handle: GenerateHandle?
    private var assistantIndex: Int?

    /// 从模型库点「加载并对话」时调用
    func load(_ item: ModelItem) {
        guard !llm.isLoaded else { return }
        statusText = "加载中：\(item.name)…"

        // 在主线程快照需要跨线程用的引用，再交给后台 Task
        let llm = self.llm
        let path = ModelStore.shared.localURL(for: item).path
        let name = item.name
        let id = item.id

        Task.detached(priority: .userInitiated) {
            do {
                try llm.load(modelPath: path)
                await MainActor.run {
                    self.statusText = "已加载：\(name)"
                    self.loadedItemID = id
                }
            } catch {
                await MainActor.run {
                    self.statusText = "加载失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, llm.isLoaded, !isGenerating else { return }
        inputText = ""

        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: ""))
        let idx = messages.count - 1

        isGenerating = true
        let handle = GenerateHandle()
        self.handle = handle
        let history = messages   // 在主线程快照，传给后台线程安全
        let llm = self.llm

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try llm.generate(messages: history, handle: handle) { piece in
                    // 每出一个片段，回主线程增量拼到 assistant 消息里（对应逐帧渲染）
                    Task { @MainActor in
                        guard let self else { return }
                        self.messages[idx].text += piece
                    }
                }
            } catch {
                Task { @MainActor in
                    if let self { self.statusText = "生成出错：\(error.localizedDescription)" }
                }
            }
            await MainActor.run { [weak self] in
                self?.isGenerating = false
                self?.handle = nil
            }
        }
    }

    /// 用户反悔：立刻停（对应暂停解码器）
    func stop() { handle?.cancel() }
}
