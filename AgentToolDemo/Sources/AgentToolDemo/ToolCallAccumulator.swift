import Foundation

/// 流式 Function Calling：模型不是一次性吐出完整 tool_call，而是分片流式输出。
/// 每个分片带 index，同一 index 的片段要拼到一起——这就是这个累加器存在的理由。
/// 即便你现在是一口气拿结果，用 index 累积也比"直接把字符串拼起来"稳：
/// 它为将来接流式本地模型（llama.cpp 也支持流式）留好了接口，不会出现半截 JSON 被误判。
struct StreamingToolCall: Sendable {
    var name: String?
    var arguments: String
}

actor ToolCallAccumulator {
    private var buffer: [Int: StreamingToolCall] = [:]

    /// 喂入一个分片。name 可能分多次到，arguments 同样是增量。
    func append(index: Int, nameDelta: String?, argsDelta: String?) {
        var call = buffer[index] ?? StreamingToolCall(name: nil, arguments: "")
        if let n = nameDelta { call.name = (call.name ?? "") + n }
        if let a = argsDelta { call.arguments += a }
        buffer[index] = call
    }

    /// 取当前所有"名字已到齐"的 tool_call，按 index 排序，保证回填顺序稳定。
    func collect() -> [(index: Int, name: String, arguments: String)] {
        buffer.compactMap { idx, call in
            guard let n = call.name else { return nil }
            return (idx, n, call.arguments)
        }.sorted { $0.index < $1.index }
    }
}
