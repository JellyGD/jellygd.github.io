#import <Foundation/Foundation.h>
#import "JGEmbedding.h"
#import "JGVectorStore.h"
#import "JGLLMGenerator.h"

NS_ASSUME_NONNULL_BEGIN

/// RAG 引擎：把"检索"和"生成"串起来，对外提供 index（建库）和 ask（问答）两个入口。
///
/// 类比：检索 = 考前翻书找相关页；生成 = 看着这几页答题。
/// 成败七分在检索（翻得准不准），三分在生成（答得好不好）。
@interface JGRAGEngine : NSObject

/// 依赖注入：传入 embedding 实现（向量化）和 llm 实现（生成）。
/// 二者都面向协议，方便演示用假实现 / 真实模型实现自由替换。
- (instancetype)initWithEmbedding:(id<JGEmbedding>)embedding
                              llm:(id<JGLLMGenerator>)llm;

/// 离线建库：切分文档 → 逐块向量化 → 入库。一份文档调用一次。
/// 通常在 App 启动或文档更新时执行（可放后台，避免卡 UI）。
- (void)indexDocument:(NSString *)text sourceName:(NSString *)name;

/// 在线问答：检索 top-k → 拼 RAG prompt → 调本地 LLM 流式生成。
/// @param question 用户问题
/// @param k 检索召回的块数（一般 3~8）
/// @param maxTokens 最多生成 token 数
/// @param onToken 逐片回调（用于 UI 流式渲染回答）
- (void)ask:(NSString *)question
        topK:(NSInteger)k
    maxTokens:(NSInteger)maxTokens
      onToken:(void (^)(NSString *piece))onToken;

/// 取消当前问答（透传给 LLM）
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
