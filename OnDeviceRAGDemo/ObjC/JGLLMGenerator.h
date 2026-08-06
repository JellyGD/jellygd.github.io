#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 本地大模型生成协议。RAG 引擎只关心"给我拼好的 prompt，吐 token 回来"，
/// 不关心底层是 llama.cpp 还是 Core ML。这样 LLM 实现可替换：
/// 既能用 JGLLamaGenerator（llama.cpp C API，纯 OC），也能桥接你的 Swift LocalLLM。
@protocol JGLLMGenerator <NSObject>

/// 从本地路径加载模型。
/// @param path GGUF 模型文件本地路径
/// @param error 加载失败时的错误信息
/// @return 是否加载成功
- (BOOL)loadModelAtPath:(NSString *)path error:(NSError **)error;

/// 流式生成：把 prompt 交给模型，每产出一个 token 片段就回调 onToken。
/// @param prompt 已拼好的 RAG prompt（含检索资料 + 问题）
/// @param maxTokens 最多生成 token 数（防止无限生成）
/// @param onToken 逐片回调（用于 UI 流式渲染）
- (void)generateWithPrompt:(NSString *)prompt
                  maxTokens:(NSInteger)maxTokens
                    onToken:(void (^)(NSString *piece))onToken;

/// 取消当前生成（用户点"停止"时调用）
- (void)cancel;

@end

/// 测试用假 LLM：不加载/不推理，把拼好的 prompt 原文回显，并吐占位回答。
/// 用途：在没有 2GB 模型的情况下，单独验证"切分 → 向量化 → 检索 → 拼 prompt"整条链路。
@interface JGDemoEchoLLM : NSObject <JGLLMGenerator>
@end

NS_ASSUME_NONNULL_END
