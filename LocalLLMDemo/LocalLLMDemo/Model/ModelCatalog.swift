import Foundation

/// 分层模型目录：先下小的立刻能用、Wi-Fi 下大的做增强（对应实战（一）分层交付）。
/// 这里的 URL 是 Hugging Face 上的示例 GGUF，换成你自己的即可。
enum ModelCatalog {
    static let mini = ModelItem(
        id: "llama3.2-1b-q4",
        name: "Llama-3.2-1B (Q4_K_M)",
        detail: "约 0.9GB，旧机型 / 弱网也能跑，离线首选",
        sizeBytes: 900 * 1024 * 1024,
        downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!,
        minDeviceRAMGB: 2,
        isDefaultRecommended: true
    )

    static let standard = ModelItem(
        id: "llama3.2-3b-q4",
        name: "Llama-3.2-3B (Q4_K_M)",
        detail: "约 2.0GB，能力强一档，建议 4GB 以上可用内存机型",
        sizeBytes: 2048 * 1024 * 1024,
        downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
        minDeviceRAMGB: 4,
        isDefaultRecommended: false
    )

    static let all: [ModelItem] = [mini, standard]
}
