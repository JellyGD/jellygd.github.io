#import <Foundation/Foundation.h>
#import "JGLLMGenerator.h"

NS_ASSUME_NONNULL_BEGIN

/// 纯 Objective-C 的 llama.cpp 封装（与 LocalLLMDemo 里的 LocalLLM.swift 等价，只是 OC 写法）。
///
/// 直接调 llama.cpp 的 C API，不需要 Swift 互操作，因此整个 RAG Demo 可以是纯 OC 工程。
/// ⚠️ llama.cpp 的 C API 跨版本有微调，函数名/结构体以你拉取的 llama.h 为准。
/// 编译时需把 llama.xcframework 加进工程，并在 Build Settings 的 Header Search Paths 指向 llama.h。
@interface JGLLamaGenerator : NSObject <JGLLMGenerator>

/// 释放模型/上下文/采样器资源（也可等 dealloc 自动调）
- (void)unload;

@end

NS_ASSUME_NONNULL_END
