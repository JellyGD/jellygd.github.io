import Foundation

/// 生成句柄：用于中途取消。
/// 类比播放器的「暂停 / 停止解码器」——用户反悔时立刻停，不能嘴上停了后台还在跑。
final class GenerateHandle: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool { lock.withLock { $0 } }
    func cancel() { lock.withLock { $0 = true } }
}

/// 把 llama.cpp（一个 C 库）包成 Swift 能直接用的「本地大模型」。
/// 核心类比：它就是一个塞进 App 的解码器——load = 建实例、generate = 解码循环、deinit = 销毁。
///
/// 采样参数：决定解码器每一步「从候选里挑哪个字」。
/// 类比：模型给了一张带概率的菜单，这几个旋钮就是点菜规则——
/// 敢不敢点冷门菜（温度）、菜单只留前几名还是留覆盖 90% 好评的（top_k/top_p）、今天抽号的随机数是几（seed）。
struct SamplingConfig {
    /// 温度：概率分布的形状。→0 越尖锐越确定(保守/易重复)，越高越发散(创意/易跑题)。temp=0 时退化成 argmax。
    var temperature: Float = 0.8
    /// top_k：只在概率最高的 k 个词里挑，过滤长尾荒谬词。k=1 = 纯贪心(永远选第一)。
    var topK: Int32 = 40
    /// top_p（核采样）：只取累计概率覆盖到 p 的最小词集，动态候选数，比固定 k 自适应。
    var topP: Float = 0.9
    /// 随机种子：固定即可复现(同样输入同样输出)；不固定则每次略有不同（llama.cpp 中 seed=0 即随机）。
    var seed: UInt32 = 12345

    /// 默认：通用聊天。
    static let `default` = SamplingConfig()
    /// 确定性：代码 / 分类 / JSON / 工具调用要靠谱可复现时用。temp=0 退化成 argmax，top_k=1 强制贪心。
    static let deterministic = SamplingConfig(temperature: 0, topK: 1, topP: 0.5, seed: 42)
    /// 创意：写文案 / 头脑风暴要多样时用。seed=0 = 每次随机。
    static let creative = SamplingConfig(temperature: 0.9, topK: 50, topP: 0.95, seed: 0)
}

/// ⚠️ llama.cpp 的 C API 跨版本有微调，下面函数名以你拉取的 `llama.h` 为准。
final class LocalLLM: @unchecked Sendable {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var sampler: OpaquePointer?
    private let lock = NSLock()

    var isLoaded: Bool { lock.withLock { model != nil && context != nil } }

    /// 加载模型 = 建解码器实例（很重，别频繁调；首次会占住权重 + KV 缓冲）
    func load(modelPath: String, contextSize: Int32 = 4096, gpuLayers: Int32 = 99,
              sampling: SamplingConfig = .default) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw LLMError.modelNotFound(path: modelPath)
        }

        var mparams = llama_model_default_params()
        guard let m = llama_model_load_from_file(modelPath, mparams) else {
            throw LLMError.loadFailed
        }

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(contextSize)
        cparams.n_batch = 512
        cparams.n_ubatch = 512
        cparams.n_gpu_layers = UInt32(gpuLayers)   // iOS 上尽量全卸载到 GPU(Metal)

        guard let c = llama_new_context_with_model(m, cparams) else {
            llama_model_free(m)
            throw LLMError.contextFailed
        }

        // 采样器链：决定「怎么选下一个字」。顺序有讲究——
        // 先 top_k / top_p 截断候选集（砍掉荒谬/长尾词），
        // 再 temperature 调分布形状，最后 dist 提供随机性（官方推荐顺序）。
        // ⚠️ temp=0 时分布退化成 argmax，但只要有采样链就仍有随机位；
        //    要绝对确定请用 top_k=1（贪心），见 SamplingConfig.deterministic。
        var chain = llama_sampler_chain_default_params()
        let s = llama_sampler_chain_init(chain)
        llama_sampler_chain_add(s, llama_sampler_init_top_k(sampling.topK))
        llama_sampler_chain_add(s, llama_sampler_init_top_p(sampling.topP, 1))
        llama_sampler_chain_add(s, llama_sampler_init_temp(sampling.temperature))
        llama_sampler_chain_add(s, llama_sampler_init_dist(sampling.seed))

        lock.withLock {
            model = m; context = c; sampler = s
        }
    }

    /// 释放 = 销毁解码器（不释放会内存泄漏，真机更易被 Jetsam 杀）
    func unload() {
        lock.withLock {
            if let sampler { llama_sampler_free(sampler) }
            if let context { llama_free(context) }
            if let model { llama_model_free(model) }
            sampler = nil; context = nil; model = nil
        }
    }

    /// 同步生成循环：在后台线程调用，配合 handle 可取消；每出一个片段就回调 onToken（流式）。
    func generate(messages: [ChatMessage], maxTokens: Int32 = 512,
                  handle: GenerateHandle,
                  onToken: @escaping (String) -> Void) throws {
        guard let context, let model, let sampler else { throw LLMError.notLoaded }

        let prompt = Self.format(messages: messages)

        // 1) prompt 转 token（像把原始数据切成可解码单元）
        let nPrompt = prompt.utf8.count
        var tokens = [llama_token](repeating: 0, count: nPrompt + 8)
        let n = llama_tokenize(context, prompt, Int32(nPrompt), &tokens, Int32(tokens.count), true, true)
        guard n > 0 else { throw LLMError.tokenizeFailed }
        tokens.removeSubrange(Int(n)..<tokens.count)

        // 所有 token 都属于序列 0，下面用同一个指针即可
        var seqId: llama_seq_id = 0
        let seqPtr = withUnsafeMutablePointer(to: &seqId) { $0 }

        // 2) 把 prompt 一次性 encode 进去
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        for i in 0..<Int(n) {
            batch.token[i] = tokens[i]
            batch.pos[i] = Int32(i)
            batch.seq_id[i] = seqPtr
            batch.n_seq_id[i] = 1
            batch.logits[i] = (i == Int(n) - 1) ? 1 : 0
        }
        llama_encode(context, batch)

        var genBatch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(batch); llama_batch_free(genBatch) }

        // 3) 逐 token 解码：采样 → 出字 → 喂回去
        var prev: llama_token = 0
        var generated: Int32 = 0
        while generated < maxTokens {
            if handle.isCancelled { break }   // 用户点停止 → 立刻停（对应暂停解码器）

            let next: llama_token
            if generated == 0 {
                next = llama_sampler_sample(sampler, context, n - 1)
            } else {
                genBatch.token[0] = prev
                genBatch.pos[0] = Int32(tokens.count) + generated - 1
                genBatch.seq_id[0] = seqPtr
                genBatch.n_seq_id[0] = 1
                genBatch.logits[0] = 1
                llama_decode(context, genBatch)
                next = llama_sampler_sample(sampler, context, -1)
            }
            llama_sampler_accept(sampler, next, true)
            if llama_token_is_eog(model, next) { break }   // 遇到结束符 = 解码到尾
            onToken(tokenToPiece(next))
            prev = next
            generated += 1
        }
    }

    /// token → 文字片段（一个 token 可能只是半个词，UI 直接拼即可）
    private func tokenToPiece(_ token: llama_token) -> String {
        guard let context else { return "" }
        var buf = [CChar](repeating: 0, count: 128)
        var n = llama_token_to_piece(context, token, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            buf = [CChar](repeating: 0, count: Int(-n) + 1)
            n = llama_token_to_piece(context, token, &buf, Int32(buf.count), 0, false)
        }
        return String(cString: buf)
    }

    /// 极简拼装；生产请用 llama_chat_apply_template（按模型自带的 chat template）
    static func format(messages: [ChatMessage]) -> String {
        messages.map { m in
            let who = m.role == .user ? "User" : (m.role == .assistant ? "Assistant" : "System")
            return "\(who): \(m.text)"
        }.joined(separator: "\n") + "\nAssistant:"
    }

    deinit { unload() }
}

enum LLMError: LocalizedError {
    case modelNotFound(path: String)
    case loadFailed
    case contextFailed
    case notLoaded
    case tokenizeFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let p): return "模型文件不存在：\(p)"
        case .loadFailed:           return "模型加载失败"
        case .contextFailed:        return "上下文创建失败"
        case .notLoaded:            return "模型未加载"
        case .tokenizeFailed:       return "prompt 分词失败"
        }
    }
}
