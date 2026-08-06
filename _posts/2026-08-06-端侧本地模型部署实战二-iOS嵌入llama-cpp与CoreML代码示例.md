---
title: 端侧本地模型部署实战（二）：把模型塞进 iPhone，难在哪
---

> 这是「部署实战篇」的第二篇，接[实战（一）](/2026/08/06/端侧本地模型部署-llama-cpp-部署配置与端云分工/)。
>
> （一）讲清了「模型能不能跑在端上、怎么配置、怎么算内存、端云怎么分工」。这一篇只解决一个问题：**把模型真正塞进 iPhone App，到底难在哪、怎么写**。
>
> 写法上我换了个路子：不先甩清单和表格，而是从一个会翻车的场景开场，把「本地模型」类比成你最熟的「解码器」。这样很多坑你其实早就踩过。

## 开场：地铁里没网，用户问了个问题

想象一个场景。

用户进地铁，过隧道，没信号。他打开你的 App，问了一句：「帮我总结这段聊天记录」。云端调不了——没网。但你早有准备：你把一个小模型塞进了 App，离线也能答。

听起来很美。但真到这一步，麻烦才刚开始：

- 模型文件 2GB，**手机内存本来就紧**，加载时系统可能直接把你进程杀掉（iOS 的 Jetsam）；
- 推理很**烫**，烫到触发温控降频，越跑越慢；
- 用户点了一下「不想等了」，**你得立刻停**，不能嘴上停了后台还在跑、内存还在涨；
- 切到后台再回来，**不能崩**，渲染目标不能乱。

如果你做过播放器，会发现这每一个坑都眼熟：**解码器占内存、解码发热、要能暂停/seek、前后台要管好渲染目标**。

所以先给一句话定调：**把本地模型塞进 App，本质就是「把一个解码器塞进 App」**。后面所有写法，我都用这个类比来讲——你会轻松很多。

## 第一步：把 C 库变成 Swift 能调的东西

llama.cpp 是个 **C 写的库**。Swift 不能直接 `import` 一个 C 工程，得先把它编译成 iOS 能用的形式，再告诉 Swift「这堆 C 函数你可以调了」。

坑在哪？两个：

1. **架构**。iPhone 是 `arm64`，模拟器可能是 `x86_64`，编译时要选对，不然真机跑不起来。
2. **要开 Metal**。不开的话推理全跑 CPU，又慢又烫。编译时把 `LLAMA_METAL=ON` 打开。

最简的编译方式（仓库自带脚本，出 `xcframework` 直接拖进 Xcode）：

```bash
cmake -B build-ios \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DLLAMA_METAL=ON \
  -DBUILD_SHARED_LIBS=OFF
cmake --build build-ios
```

产物 `libllama.a` 加进工程。然后建一个 Bridging Header，把 C 头文件暴露给 Swift：

```objc
// YourApp-Bridging-Header.h
#include "llama.h"
```

到这步，Swift 里就能直接调用 `llama_*` 那一堆 C 函数了。类比：**这等于你把「解码器」的接口导进了 App**。

## 第二步：包一个 LocalLLM 类——就是「建解码器 + 解码循环」

核心难点不是算法，是**生命周期**：加载一次、跑生成循环、用完好释放。和 「建一个解码器实例 → 喂数据 → 逐帧出画面 → 销毁」一模一样。

先说直觉，再给代码。LLM 生成循环干的事，用播放器的话翻译就是：

- **喂 prompt（encode）** = 把一整段要解码的数据一次性送进去；
- **循环采 token（decode）** = 像逐帧解码：每采一个 token，变成一段文字，再把它当「下一帧输入」喂回去，直到遇到「结束符」；
- **KV cache** = 已经解码过的帧缓冲，不用每帧重算；
- **流式回调** = 边生成边把文字抛给 UI，像边解码边渲染。

代码骨架（基于 llama.cpp 现代 C API；**具体函数签名以你集成的 `llama.h` 版本为准**）：

```swift
import Foundation

final class LocalLLM {
    private var model: OpaquePointer?   // llama_model*
    private var context: OpaquePointer? // llama_context*
    private var sampler: OpaquePointer? // llama_sampler*

    // 加载模型 = 建解码器实例（很重，别频繁调）
    func load(modelPath: String) throws {
        var modelParams = llama_model_default_params()
        guard let m = llama_model_load_from_file(modelPath, modelParams) else {
            throw NSError(domain: "LocalLLM", code: -1, userInfo: [NSLocalizedDescriptionKey: "模型加载失败"])
        }
        model = m

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 4096        // 上下文窗口 = 解码缓冲大小
        ctxParams.n_batch = 512
        ctxParams.n_gpu_layers = 99   // iOS 上尽量全卸载到 GPU(Metal)

        guard let c = llama_new_context_with_model(m, ctxParams) else {
            throw NSError(domain: "LocalLLM", code: -2, userInfo: [NSLocalizedDescriptionKey: "上下文创建失败"])
        }
        context = c

        // 采样器链：决定「怎么选下一个字」。顺序有讲究——
        // 先 top_k / top_p 截断候选集（砍掉荒谬/长尾词），再 temperature 调分布形状，最后 dist 提供随机性。
        // 实际代码里已抽成 SamplingConfig（.default / .deterministic / .creative），这里写死示意。
        var chain = llama_sampler_chain_default_params()
        sampler = llama_sampler_chain_init(chain)
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.8))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(12345))
    }

    // 生成 = 解码循环，每出一个片段就回调（流式）
    func generate(prompt: String, maxTokens: Int = 256,
                  onToken: @escaping (String) -> Void) throws {
        guard let context, let model, let sampler else {
            throw NSError(domain: "LocalLLM", code: -3, userInfo: [NSLocalizedDescriptionKey: "模型未加载"])
        }

        // 1) prompt 转成 token（像把原始数据切成可解码单元）
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count)
        let n = llama_tokenize(context, prompt, Int32(prompt.utf8.count),
                               &tokens, Int32(tokens.count), true, true)
        guard n > 0 else { throw NSError(domain: "LocalLLM", code: -4, userInfo: [NSLocalizedDescriptionKey: "tokenize 失败"]) }
        tokens.removeSubrange(Int(n)..<tokens.count)

        // 2) 把 prompt 一次性 encode 进去
        var promptBatch = llama_batch_init(Int32(tokens.count), 0, 1)
        for (i, tok) in tokens.enumerated() {
            promptBatch.token[i] = tok
            promptBatch.pos[i] = Int32(i)
            promptBatch.seq_id[i] = 0
            promptBatch.n_seq_id[i] = 1
            promptBatch.logits[i] = (i == tokens.count - 1) ? 1 : 0
        }
        llama_encode(context, promptBatch)

        // 3) 逐 token 解码：采样 → 出字 → 喂回去
        var genBatch = llama_batch_init(1, 0, 1)
        var prev: llama_token = 0
        var generated = 0
        while generated < maxTokens {
            let next: llama_token
            if generated == 0 {
                next = llama_sampler_sample(sampler, context, Int32(tokens.count) - 1)
            } else {
                genBatch.token[0] = prev
                genBatch.pos[0] = Int32(tokens.count + generated - 1)
                genBatch.seq_id[0] = 0
                genBatch.n_seq_id[0] = 1
                genBatch.logits[0] = 1
                llama_decode(context, genBatch)
                next = llama_sampler_sample(sampler, context, -1)
            }
            if llama_token_is_eog(model, next) { break }  // 遇到结束符 = 解码到尾
            onToken(tokenToPiece(next))
            prev = next
            generated += 1
        }
        llama_batch_free(promptBatch)
        llama_batch_free(genBatch)
    }

    // token → 文字片段（一个 token 可能只是半个词，UI 直接拼就行）
    private func tokenToPiece(_ token: llama_token) -> String {
        guard let context else { return "" }
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_token_to_piece(context, token, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            var big = [CChar](repeating: 0, count: Int(-n) + 1)
            llama_token_to_piece(context, token, &big, Int32(big.count), 0, false)
            return String(cString: big)
        }
        return String(cString: buf)
    }

    // 用完好释放 = 销毁解码器（不释放会内存泄漏，真机更易被 Jetsam）
    deinit {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }
}
```

读这段代码时，把它当成「解码器管理器」就不绕了：`load`=建实例、`generate`=解码循环、`onToken`=逐帧上屏、`deinit`=销毁。

### 采样器：四个旋钮决定输出性格

回到上面那句「温度 + top_k + top_p + 随机种子」——它们不是装饰，是「每一步选哪个字」的全部规则。

先把根上讲透：LLM 生成是一个词一个词往外蹦的循环（代码里的 `while` 就是）。每一步，模型不是直接吐「下一个词」，而是给一张**「词汇表里每个词概率多少」的清单**。光有清单不够——到底抽哪个？这就是采样参数管的。

类比点菜：模型递给你一张带概率的菜单（鱼香肉丝 40%、宫保鸡丁 30%……），这四个旋钮就是点菜规则：

- **温度 temperature｜胆子大小**：softmax 前先除的数。`→0` 把概率差异放大、分布变尖，几乎只点最高概率那道菜 → 输出确定、保守、易重复；`0.7~1.0+` 把差异抹平、冷门菜也能上 → 更有创意、但易跑题。`temp=0` 时分布退化成「永远选第一」。
- **top_k｜候选池天花板**：只从概率最高的 k 个词里挑，其余直接扔，挡掉长尾荒谬词。`k=1` 就是纯贪心。
- **top_p（核采样）｜自适应候选集**：只取「累计概率加到 p 就够了」的最小词集合（`p=0.9` 即覆盖 90% 概率质量）。和 top_k 区别是它动态——高概率集中时只留两三个，分散时自动放宽。现在常和 top_k 一起用，取交集更保守。
- **随机种子 seed｜抽号起点**：采样里的随机性由随机数生成器决定，seed 就是起点。**固定 seed → 同样输入同样参数得到完全一样的输出（可复现）**；不固定则每次略有不同。

它们怎么配合（顺序见上面代码）：典型链路是 `logits → top_k / top_p 截断候选 → temperature 调形状 → dist 抽一个`。llama.cpp 里这四个就是 `llama_sampler` 链上的不同节点。

**实战怎么设（Demo 里已做成 `SamplingConfig` 的三个预设）**
- 要**靠谱、可复现**（代码、分类、JSON、工具调用）：用 `.deterministic`——`temp=0`、`top_k=1`、固定 seed。
- 要**创意、多样**（写文案、头脑风暴）：用 `.creative`——`temp≈0.9`、`top_p=0.95`、不固定 seed。
- ⚠️ 坑：别以为 `temp=0` 就「绝对确定」——只要还走采样链就一定有随机位；真要确定性请用 `top_k=1`（贪心）。端侧做「生成可控」（系列三主题）时，这几项是第一道可控杠杆。

## 第三步：让它在手机上「不崩、不烫、听使唤」

代码能跑只是开始。手机上的三个真实约束，对应播放器的三个老坑：

**1）别在主线程跑——推理会卡 UI**  
解码阻塞主线程会掉帧卡死。包一层后台任务：

```swift
Task.detached(priority: .userInitiated) {
    try? self.llm.generate(prompt: prompt) { piece in
        Task { @MainActor in self.output += piece }  // 回主线程刷新
    }
}
```

**2）内存是真的会爆——老机型尤其**  
模型权重 + KV cache 是真金白银占内存，不是磁盘大小。（一）里那个「权重 + KV 公式」不是摆设：算下来超出机型可用内存，系统直接 Jetsam 杀你。这就跟播放器解码内存峰值一样，必须按机型分级——高频入口常驻一个实例复用，低频能力懒加载。

**3）省电：能用 ANE 就别用 GPU**  
`n_gpu_layers=99` 是让 llama.cpp 走 **Metal**。但 Apple 芯片上还有更省电的 **ANE（神经引擎）**。类比：能用硬解（VideoToolbox）就别用软解。后面会说 MLX 就是走 ANE 的。

**4）可打断：用户反悔要立刻停**  
把 `generate` 放进 `Task`，用户点停止就 `task.cancel()`，循环里查 `Task.isCancelled` 提前退出。对应播放器的暂停/seek——「嘴上停了、后台还在跑」是最常犯的错。

**5）UI 流式渲染：增量，不要整段替换**

```swift
self.output += piece   // 只 append 新到的片段
```

每来一个 token 就整体 `set` 一次，文本长了会闪会卡。和播放逐帧渲染一个道理。

## 苹果自己的路：MLX（走 ANE，更省电）

如果你的 App 是纯 Apple 生态、最在意续航，本地 LLM 在 iOS 上现在更主流的是 **MLX Swift**——Apple 官方的 ML 框架，把模型跑在 **ANE** 上，纯 Swift、流式友好：

```swift
import MLXLLM
import MLX

// 加载一个转成 MLX 格式的 4bit 模型（具体 API 以 mlx-swift-examples 版本为准）
let model = try await ModelContainer.load(hosted: .qwen2_5_3b_instruct_4bit)

let messages: [[String: String]] = [["role": "user", "content": "解释一下梯度下降"]]
for await part in model.generate(messages: messages, parameters: GenerateParameters(temperature: 0.8)) {
    if case .chunk(let piece) = part { /* 流式片段，拼到 UI */ }
}
```

模型来源：用 `mlx_lm.convert` 把 Hugging Face 的权重转成 MLX 格式再打进 App。

**怎么选 A 还是 B？** 就一句直觉：

- 想和安卓/桌面**共用一套 llama.cpp 逻辑** → 走 llama.cpp（上面的 `LocalLLM`）；
- 纯 Apple、**要最省电** → 走 MLX Swift（走 ANE），Core ML 是零第三方依赖的备选。 但是现在的模型不兼容，需要做转换。 

## 收口：这条线和前面怎么连

- **模型从哪来**：（一）讲的「断点续传 / GGUF 分片 / 分层模型」下载下来的 GGUF，就是这里 `load(modelPath:)` 读的文件。分层模型 = 先下发小 GGUF 立刻能用、后台再下大 GGUF 做增强，然后换 `LocalLLM` 实例。
- **端云协同**：`LocalLLM` 跑不动（机型太老 / 模型太大 / 弱网需联网知识）时，按（一）的端云分工标准回云端大模型——路由逻辑不变。
- **体验**：不崩、不烫、可打断、流式——全是系列（二）讲过的端侧体验，只是从「认知」落成了「代码」。

## 配套 Demo：一套能直接跑的代码

前面那些代码块，散着看容易「好像懂了、一跑就废」。所以我把这一篇补成了一个**完整可运行的 Demo 工程**，放在仓库 `LocalLLMDemo/` 目录（[点这里看](https://github.com/JellyGD/jellygd.github.io/tree/master/LocalLLMDemo)）。它把三个你最关心的东西都填实了：

- **XCFramework 集成**：`build-llama-xcframework.sh` 一条命令把 llama.cpp 编成 `llama.xcframework`（真机 `arm64` + 模拟器 `arm64/x86_64`，开了 `LLAMA_METAL=ON`）；README 里写了怎么拖进 Xcode、「Embed & Sign」、设 Bridging Header。这就把「解码器的接口导进 App」那一步彻底落地。
- **下载管理器**：`ModelDownloader` 用 `URLSessionDownloadTask` 做**断点续传**——暂停/退出时存 `resumeData`，恢复时接着下；还处理了 iOS 那个「resumeData 偶尔失效」的坑（失效就从头下，不打崩）。这正是实战（一）说的「断点续传必须有」的代码版。
- **真实聊天 UI**：`ChatView` + `ChatViewModel` + `LocalLLM`，流式输出、可停止、模型库页能按「分层模型」先下小的立刻聊、Wi-Fi 再下大的增强。

工程里 `LocalLLM` 就是上面那套「解码器」封装的完整版（多了取消句柄 `GenerateHandle`，对应播放器的暂停）；`ModelCatalog` 给了两个分层模型示例，`ModelStore` 管落盘。想直接拿来改，照 README 三步就能 Run。

> ⚠️ 两点实话：① llama.cpp 的 C API 跨版本有微调，**编译前请以你拉取的 `llama.h` 为准**（Demo 里已标注）；② llama.cpp 默认走 **Metal/GPU**，不是 ANE——要最省电走 ANE 请用 MLX（见上）。

## 下一篇

回到系列（三）：**AI Agent 生成是不可控的，如何让生成符合预期**——约束解码、结构化输出与 schema 校验、Tool Calling 可靠性、Plan 校验、回滚与重规划。

---

*如果在 iOS 上集成 llama.cpp 踩过坑（XCFramework 架构不对、Metal 没生效、Jetsam 杀进程），欢迎评论区交流。*
