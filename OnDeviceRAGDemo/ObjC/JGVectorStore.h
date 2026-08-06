#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 一次检索命中的结果：命中的原文块 + 出处 + 相关度分数。
@interface JGRetrievalResult : NSObject
@property (nonatomic, copy) NSString *text;   // 命中的原文块
@property (nonatomic, copy, nullable) NSString *source; // 出处（建库时传入的文档名）
@property (nonatomic, assign) float score; // 余弦相似度 [0,1]，越大越相关
@end

/// 本地向量库：存储"向量 + 原文"，按余弦相似度取 top-k 最近邻。
///
/// 演示用纯内存实现（简单、够理解原理）。
/// 真实场景若知识量大或需持久化，换成 SQLite + sqlite-vec / FAISS / LanceDB：
/// 内存实现每次启动要重建索引，且无法跨会话保留数据。
@interface JGVectorStore : NSObject

/// 入库：把一个 chunk 的向量和原文一起存下。
/// @param vector 该 chunk 的向量（必须与 embedding 维度一致）
/// @param text 原文块（检索命中后拼进 prompt 的就是它）
/// @param source 出处名（可选，问答时可用于标注引用来源）
- (void)addVector:(NSArray<NSNumber *> *)vector
             text:(NSString *)text
           source:(nullable NSString *)source;

/// 检索：取与 query 向量最相似的 k 个块，按相似度降序返回。
/// @param query 问题的向量（必须用与建库相同的 embedding 模型产出）
/// @param k 返回数量（一般 3~8；k 太大→prompt 过长、模型注意力被稀释）
- (NSArray<JGRetrievalResult *> *)search:(NSArray<NSNumber *> *)query
                                    topK:(NSInteger)k;

/// 当前库中向量/块数量
- (NSInteger)count;

@end

NS_ASSUME_NONNULL_END
