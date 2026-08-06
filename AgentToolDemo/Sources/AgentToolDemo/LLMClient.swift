import Foundation

/// LLM 客户端抽象：Agent 循环只认这个协议，不关心背后是本地模型还是云端。
protocol LLMClient: Sendable {
    /// 给定对话历史 + 可用 Tool 列表，返回一轮输出（文本或一次 Function Call）。
    func chat(messages: [ChatMessage], tools: [ToolSpec]) async throws -> LLMResponse
}

/// 脚本化 Mock：让 demo 不依赖 2GB 模型也能跑通整条链路。
/// 它按预设脚本逐步"假装"模型在发 Function Call，最后给自然语言答案。
actor ScriptedLLM: LLMClient {
    private var script: [LLMResponse]
    private var i = 0
    init(_ script: [LLMResponse]) { self.script = script }
    func chat(messages: [ChatMessage], tools: [ToolSpec]) async throws -> LLMResponse {
        if i < script.count { defer { i += 1 }; return script[i] }
        return .text("（已无更多脚本，结束）")
    }
}

/// 真实接入本地 llama.cpp 的适配骨架（需要 llama.xcframework + 模型文件）。
/// 这里不 import LocalLLM，只演示"函数调用范式"怎么落到你现有 LocalLLM.generate 上：
///   1) 把 tools 的 schema 拼进 system prompt（或走模型自带的 tool-calling 格式）；
///   2) 让模型吐出 JSON 形式的 function_call；
///   3) 用 JSON 解析出 name + arguments，交回 Agent 循环。
/// 集成细节见仓库 LocalLLMDemo/ 与「系列（二）」文章。
final class LocalLLMClient: LLMClient {
    func chat(messages: [ChatMessage], tools: [ToolSpec]) async throws -> LLMResponse {
        fatalError("需要集成 llama.xcframework：把 tools 拼进 prompt，解析模型返回的 JSON tool_call。")
    }
}
