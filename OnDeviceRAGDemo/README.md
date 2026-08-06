# OnDeviceRAGDemo —— iOS 端侧 RAG（纯 Objective-C）

`LocalLLMDemo` 解决的是"把解码器塞进 App"；这个 Demo 在它前面加了一道**检索**，
把纯 OC 的 RAG 流水线跑通：**切分 → 本地向量化 → 本地向量库 → top-k 检索 → 拼 prompt → 本地 LLM 生成**。

整套代码是纯 OC。`JGLLamaGenerator` 直接调 llama.cpp 的 C API（与 `LocalLLMDemo` 的
`LocalLLM.swift` 等价，只是 OC 写法），所以你**不需要 Swift 互操作**就能跑通整条链路；
也可以选择桥接你已有的 Swift `LocalLLM`（见文末三步）。

## 文件职责

| 文件 | 角色 | 类比 |
|------|------|------|
| `JGDocumentChunker` | 长文档切小块 | 把"书"按页裁开 |
| `JGEmbedding` + `JGHashingEmbedding` | 演示用向量化（词哈希 TF，可跑无模型） | 翻书前先给每页贴标签 |
| `JGCoreMLEmbedding` | 真实端侧 embedding（Core ML 骨架） | 真正的语义标签机 |
| `JGVectorStore` | 本地向量库 + 余弦 top-k | 书架 + 按相关度取书 |
| `JGLLMGenerator` + `JGLLamaGenerator` | 纯 OC 的 llama.cpp 封装 | 解码器 |
| `JGDemoEchoLLM` | 假 LLM（回显 prompt，免模型验证链路） | 占位 |
| `JGRAGEngine` | 编排：检索 + 拼 prompt + 生成 | 开卷考试流程 |

## 三步跑起来（Xcode）

1. 新建 **iOS App**（Language: Objective-C），部署目标 iOS 16+。
2. 把 `ObjC/` 下所有 `.h/.m` 拖进工程 **Add to Target**。
3. 接 llama.cpp：
   - 用 `LocalLLMDemo/build-llama-xcframework.sh` 编出 `llama.xcframework`，拖进工程并 **Embed & Sign**；
   - 在 **Build Settings → Header Search Paths** 加 `llama.xcframework/ios-arm64/Headers`（recursive）。
   - 只用演示/hash 检索、不接真模型时，`JGLLamaGenerator.m` 可以暂时不参与编译。

## 最小用法（在 VC 里）

```objc
// 1) 先用"假 LLM"验证整条检索链路（不需要 2GB 模型）
id<JGLLMGenerator> llm = [[JGDemoEchoLLM alloc] init];
id<JGEmbedding> emb = [[JGHashingEmbedding alloc] initWithDimension:512];

JGRAGEngine *rag = [[JGRAGEngine alloc] initWithEmbedding:emb llm:llm];

// 2) 离线建库（一份文档调一次，可后台跑）
NSString *doc = @"项目 Omega 的 deadline 是 8 月 20 日，负责人是小张……";
[rag indexDocument:doc sourceName:@"我的笔记.md"];

// 3) 在线问答
[rag ask:@"项目 Omega 的 deadline 是哪天？"
       topK:3
   maxTokens:256
     onToken:^(NSString *piece) {
         // 用 JGDemoEchoLLM 时这里会回显拼好的 RAG prompt，
         // 你能直接看到"检索到的 [1][2][3] 块 + 问题"有没有拼对
         NSLog(@"%@", piece);
     }];
```

确认检索没问题后，把 `llm` 换成真模型即可出真实回答：

```objc
JGLLamaGenerator *llm = [[JGLLamaGenerator alloc] init];
NSError *e;
if ([llm loadModelAtPath:@"/path/to/your.gguf" error:&e]) {
    JGRAGEngine *rag = [[JGRAGEngine alloc] initWithEmbedding:emb llm:llm];
    [rag indexDocument:doc sourceName:@"我的笔记.md"];
    [rag ask:@"项目 Omega 的 deadline 是哪天？" topK:3 maxTokens:256 onToken:^(NSString *p){ /* UI 流式刷新 */ }];
}
```

## 把演示 embedding 换成真实的（关键一步）

`JGHashingEmbedding` 只能做"字面相似"，不是语义向量——同一个意思换种说法就翻不到。
真落地要用专用小模型：

1. 选一个端侧 embedding 模型（如 `bge-small-zh` / `bge-base-zh`，或 multilingual-e5-small），
   用 `ct2-coreml` / `python -m coremltools` 转成 `.mlmodel`，Xcode 编译成 `.mlmodelc`。
2. `JGCoreMLEmbedding.m` 已是可直接编译的骨架：
   - 输入特征名、输出特征名以你的模型为准（常见 `text` / `output`）；
   - 取 `MLMultiArray` 长度作为维度，必要时补一次 L2 归一化。
3. 把 `JGHashingEmbedding` 换成：
   ```objc
   id<JGEmbedding> emb = [[JGCoreMLEmbedding alloc] initWithModelURL:
       [[NSBundle mainBundle] URLForResource:@"bge-small" withExtension:@"mlmodelc"]];
   ```
   注意：**建库用的 embedding 和提问用的 embedding 必须是同一个模型**，否则向量空间不同，比不了。

## 桥接你已有的 Swift `LocalLLM`（可选）

如果你不想重复写 llama.cpp 封装，想直接复用 `LocalLLMDemo` 的 `LocalLLM.swift`：

1. 在 `LocalLLM.swift` 顶部加 `@objc` 并让它继承 `NSObject`：
   ```swift
   @objc final class LocalLLM: NSObject, @unchecked Sendable { ... }
   @objc func generate(...) ...   // 把要暴露的方法标 @objc
   ```
2. 在 OC 工程的 **Build Settings → Objective-C Generated Interface Header Name** 指向的
   `<ProductName>-Swift.h` 里 `#import` 它。
3. 写一个薄桥接类让 `LocalLLM` 遵守 `JGLLMGenerator` 协议（把 `generate(messages:...)` 改成
   接收拼好的 `prompt` 字符串即可），然后 `[[JGRAGEngine alloc] initWithEmbedding:emb llm:bridge]`。

## ⚠️ 两个实话

- **llama.cpp 的 C API 跨版本有微调**，`JGLLamaGenerator.m` 里的函数名/结构体以你拉取的
  `llama.h` 为准（和 `LocalLLMDemo` 的 README 同样的坑）。
- **RAG 成败七分在检索**：本地模型上下文窗口小，只能塞 top-k 这几段，所以 embedding 模型
  选得对不对、chunk 切得合不合理，直接决定答案质量。先把 `JGDemoEchoLLM` 的回显看明白，
  再上真模型，会省很多无谓的"模型在胡说"式调试。
