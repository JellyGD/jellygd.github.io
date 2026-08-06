# LocalLLMDemo —— iOS 端侧本地大模型（可运行 Demo）

博客配套：[端侧本地模型部署实战（二）：把模型塞进 iPhone，难在哪](https://jellygd.github.io/2026/08/06/端侧本地模型部署实战二-iOS嵌入llama-cpp与CoreML代码示例/)

把 llama.cpp 真正塞进 iPhone：**XCFramework 集成 + 断点续传下载 + 真实流式聊天 UI**，
对应实战（一）的「断点续传 / 分层模型」和实战（二）的「解码器」类比。

## 目录结构

```
LocalLLMDemo/
├── build-llama-xcframework.sh      # 一键把 llama.cpp 编成 llama.xcframework
├── LocalLLMDemo-Bridging-Header.h  # 让 Swift 能调 C 接口
├── README.md
└── LocalLLMDemo/
    ├── LocalLLMDemoApp.swift       # @main 入口
    ├── Model/
    │   ├── ModelTypes.swift        # ChatMessage / ModelItem
    │   ├── ModelCatalog.swift      # 分层模型目录（小模型首发 + 大模型增强）
    │   ├── ModelStore.swift        # 本地落盘位置 / 是否已下载
    │   ├── ModelDownloader.swift   # 断点续传下载器（resumeData）
    │   └── LocalLLM.swift          # llama.cpp 的 Swift 封装（解码器）
    ├── ViewModels/
    │   └── ChatViewModel.swift     # 消息列表 / 加载 / 流式生成 / 停止
    └── Views/
        ├── ChatView.swift          # 真实聊天 UI（流式 + 可停止）
        └── ModelLibraryView.swift  # 模型库（分层下载 / 加载）
```

## 前置条件

- Xcode 15+，部署目标 iOS 16+（Apple Silicon 模拟器也能跑 Metal）
- 已 clone llama.cpp：`git clone https://github.com/ggml-org/llama.cpp.git`

## 三步跑起来

### 1. 编译 llama.xcframework

```bash
cd LocalLLMDemo
bash ./build-llama-xcframework.sh /path/to/llama.cpp
```

产物：`./llama.xcframework`（真机 arm64 + 模拟器 arm64/x86_64，已开 `LLAMA_METAL=ON`）。

### 2. 在 Xcode 里建工程并接好

1. 新建 **iOS App**（Interface: SwiftUI，Language: Swift），Product Name 填 `LocalLLMDemo`。
2. 把 `llama.xcframework` 拖进工程，勾选 **Embed & Sign**。
3. 把本仓库 `LocalLLMDemo/LocalLLMDemo/` 下的所有 `.swift` 文件 **Add to Target**。
4. 把 `LocalLLMDemo-Bridging-Header.h` 拖进工程，并在
   **Build Settings → Swift Compiler - General → Objective-C Bridging Header**
   填 `LocalLLMDemo/LocalLLMDemo-Bridging-Header.h`。
5. 若 `#import <llama/llama.h>` 报找不到，把 xcframework 的 `Headers` 目录加进
   **Build Settings → Header Search Paths**（设为 recursive）。

### 3. Run

选一台真机（Metal 走 GPU）或 Apple Silicon 模拟器，`Cmd+R`。
进「模型库」先下载小的（分层模型首发），下完点「加载并对话」即可**离线**聊。

## 三个核心文件

- **LocalLLM.swift**：llama.cpp 的 Swift 封装（解码器类比：`load` / `generate` / `deinit`），含取消句柄 `GenerateHandle`（对应播放器暂停）。
- **ModelDownloader.swift**：`URLSessionDownloadTask` 断点续传，处理了 iOS 偶发「resumeData 失效」的坑（失效就从头下，不打崩）。
- **ChatView.swift + ChatViewModel.swift**：SwiftUI 流式聊天 + 模型库页（分层下载）。

## ⚠️ 两点实话

1. **llama.cpp 的 C API 跨版本有微调**，编译前请以你拉取的 `llama.h` 为准（Demo 里已标注函数用法）。
2. **llama.cpp 默认走 Metal/GPU，不是 ANE**；要最省电走 ANE 请用 MLX Swift（见博客）。

## 换成你自己的模型

改 `ModelCatalog.swift` 里的 `downloadURL`（指向你的 GGUF，或者直接把 `.gguf` 丢进 App 沙盒 / Files）。
分层思路：首发小模型（如 1B）立刻可用，Wi-Fi 下后台再下大模型（如 3B）做增强。
