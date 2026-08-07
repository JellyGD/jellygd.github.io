import Foundation

/// Agent 循环：把「LLM 决策 → 解析 Function Call → 执行 Tool → 回灌」串成闭环。
/// 它不关心 LLM 是本地还是云端、Tool 是进程内还是 MCP——只认协议。
/// 这是「Agent 自驱」的心脏：模型自己决定下一步调哪个工具，循环到自己觉得能回答为止。
///
/// 深入（一）相比基础版多做了五件事：
/// 1) 调工具前先强校验参数（schema 存在时），失败就把原因回灌，而非让 run 崩；
/// 2) 权限门：高风险工具先让用户确认（askOnce / confirmAlways / blocked），被拒不执行；
/// 3) 同一轮多个 tool_call：先看每个工具的 parallelSafe 标记再决定并行/串行；
/// 4) 并行时受 maxConcurrency 上限约束，别无脑全开吃光端侧资源；
/// 5) 工具结果回填前先做注入防护（sanitize），不可信输出先隔离。
struct AgentLoop {
    let llm: any LLMClient
    let registry: ToolRegistry
    /// 确认机制：把"问用户"抽出来，真实 App 是 SwiftUI 弹窗，demo 用脚本化实现。
    let approver: any ConfirmationProvider
    /// 权限记忆：记住 askOnce 的选择，避免同一会话反复打扰。
    let permission: PermissionMemory
    /// 同一轮并行工具的最大数量：保护端侧 CPU/内存，也避免打爆同一外部 API。
    static let maxConcurrency = 4

    init(llm: any LLMClient, registry: ToolRegistry,
         approver: any ConfirmationProvider = LoggingApprover(),
         permission: PermissionMemory = PermissionMemory()) {
        self.llm = llm
        self.registry = registry
        self.approver = approver
        self.permission = permission
    }

    func run(userInput: String, maxRounds: Int = 8) async throws -> String {
        var messages: [ChatMessage] = [.init(role: .user, text: userInput, toolCallId: nil)]
        let tools = await registry.specList()

        for round in 1...maxRounds {
            let resp = try await llm.chat(messages: messages, tools: tools)
            switch resp {
            case .text(let answer):
                print("  [Agent] 第\(round)轮：模型给出最终回答 → \(answer)")
                return answer

            case .toolCall(let name, let argsJSON, let id):
                let result = try await execute(name: name, argsJSON: argsJSON, tools: tools)
                print("  [Agent]    ↳ \(name) → \(result)")
                messages.append(.init(role: .tool, text: result, toolCallId: id))

            case .toolCalls(let calls):
                try await runMultiCall(calls, tools: tools, into: &messages, round: round)
            }
        }
        throw AgentError.maxRoundsExceeded
    }

    /// 执行单个工具：先过权限门（高风险需用户确认），再校验、执行、注入防护。
    /// 单调用路径（.toolCall）走这里；多调用路径在 runMultiCall 里先确认、再直调 runAndSanitize。
    private func execute(name: String, argsJSON: String, tools: [ToolSpec]) async throws -> String {
        guard let spec = tools.first(where: { $0.name == name }) else {
            return try await runAndSanitize(name: name, argsJSON: argsJSON, tools: tools)
        }
        let approved = await permission.decide(toolName: name, level: spec.riskLevel) {
            await approver.request(toolName: name, arguments: argsJSON, level: spec.riskLevel)
        }
        if !approved {
            return "用户拒绝了执行 \(name)，请换种方式或告知用户。"
        }
        return try await runAndSanitize(name: name, argsJSON: argsJSON, tools: tools)
    }

    /// 同一轮多个 tool_call 的执行策略：
    /// 1) 先「串行确认」——确认是用户交互边界，不能并行问，问完记下放行结果；
    /// 2) 被拒的直接回填拒因，不进执行；
    /// 3) 批准的再按 parallelSafe 决定并行/串行（此处不再过权限门）。
    /// 真正的数据依赖（B 要 A 的结果当参数）模型在同一轮填不出，会自然落到下一轮。
    private func runMultiCall(_ calls: [(name: String, argumentsJSON: String, id: String)],
                              tools: [ToolSpec],
                              into messages: inout [ChatMessage],
                              round: Int) async throws {
        let specByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        // 1) 串行确认：把需要用户拍板的先问完（确认是串行边界，不能并行问用户）
        var approved: [(call: (name: String, argumentsJSON: String, id: String), ok: Bool)] = []
        for call in calls {
            let level = specByName[call.name]?.riskLevel ?? .auto
            let ok = await permission.decide(toolName: call.name, level: level) {
                await approver.request(toolName: call.name, arguments: call.argumentsJSON, level: level)
            }
            approved.append((call, ok))
        }

        // 2) 被拒的：回填拒因，不执行
        let toRun = approved.compactMap { $0.ok ? $0.call : nil }
        for (call, ok) in approved where !ok {
            print("  [Agent]    ↳ \(call.name) → 用户拒绝，跳过")
            messages.append(.init(role: .tool, text: "用户拒绝了执行 \(call.name)。", toolCallId: call.id))
        }

        // 3) 批准的：按并行/串行策略执行（不再过权限门）
        let allSafe = toRun.allSatisfy { specByName[$0.name]?.parallelSafe ?? false }
        if allSafe {
            print("  [Agent] 第\(round)轮：本轮 \(toRun.count) 个调用全为只读幂等 → 并行执行（上限 \(Self.maxConcurrency)）")
            let limiter = ConcurrencyLimiter(limit: Self.maxConcurrency)
            let collected = try await withThrowingTaskGroup(of: (String, String, String).self) { group in
                for call in toRun {
                    group.addTask {
                        await limiter.acquire()
                        defer { Task { await limiter.release() } }
                        let r = try await self.runAndSanitize(name: call.name, argsJSON: call.argumentsJSON, tools: tools)
                        return (call.id, call.name, r)
                    }
                }
                var out: [(String, String, String)] = []
                for try await item in group { out.append(item) }
                return out.sorted { $0.0 < $1.0 }
            }
            for (id, name, r) in collected {
                print("  [Agent]    ↳ \(name) → \(r)")
                messages.append(.init(role: .tool, text: r, toolCallId: id))
            }
        } else {
            print("  [Agent] 第\(round)轮：本轮含副作用/非幂等调用 → 按序串行执行")
            for call in toRun {
                let r = try await runAndSanitize(name: call.name, argsJSON: call.argumentsJSON, tools: tools)
                print("  [Agent]    ↳ \(call.name) → \(r)")
                messages.append(.init(role: .tool, text: r, toolCallId: call.id))
            }
        }
    }

    /// 不含权限门的真正执行：强校验 → 执行 → 注入防护。
    private func runAndSanitize(name: String, argsJSON: String, tools: [ToolSpec]) async throws -> String {
        if let spec = tools.first(where: { $0.name == name }),
           let schema = spec.schema {
            switch ToolValidator(schema: schema).validate(argumentsJSON: argsJSON) {
            case .ok:
                break
            case .failed(let reason):
                // 错误回退：不崩溃，把失败原因作为 tool 结果喂回，模型可重试或道歉。
                return "工具参数校验失败：\(reason)。请修正后重试。"
            }
        }
        do {
            let raw = try await registry.run(name: name, argumentsJSON: argsJSON)
            return sanitizeToolResult(raw)   // prompt injection 防护：不可信输出先隔离
        } catch {
            return "工具执行出错：\(error.localizedDescription)。请换种方式或告知用户。"
        }
    }
}

/// 极简并发信号量：限制同一轮并行工具的最大数量，保护端侧资源。
/// 用 actor 隔离 slots 的读写，避免在 TaskGroup 里竞态。
actor ConcurrencyLimiter {
    private var slots: Int
    init(limit: Int) { self.slots = max(1, limit) }
    func acquire() async {
        while slots == 0 { try? await Task.sleep(nanoseconds: 1_000_000) }
        slots -= 1
    }
    func release() { slots += 1 }
}
