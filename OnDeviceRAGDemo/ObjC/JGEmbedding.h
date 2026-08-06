#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 向量化协议：把一段文本映射成一个定长浮点向量。
///
/// 这是端侧 RAG"翻书翻得准不准"的决定因素——向量化质量直接决定检索命中率。
/// 端侧必须用"小、量化、专用"的 embedding 模型（如 bge-small、多语言小模型），
/// 不能拿云端那个大模型顺手做 embedding，否则又大又慢、还可能把数据送出设备。
@protocol JGEmbedding <NSObject>

/// 向量维度。实现类必须返回固定不变的值（建库和检索要用同一维度才能比较）。
- (NSInteger)dimension;

/// 把一段文本编码成向量。
/// @param text 待向量化的文本（通常是某个 chunk 或用户问题）
/// @return 定长浮点向量，用 NSArray<NSNumber*> 承载（便于 ARC 管理），建议已做归一化以便余弦比较
- (NSArray<NSNumber *> *)embedText:(NSString *)text;

@end

/// 演示用实现：基于词哈希（hashing trick）的 TF 向量 + L2 归一化。
///
/// ⚠️ 只能做"字面相似"检索（词重叠越多越像），不是真正的语义向量。
/// 用途：不下载任何模型即可跑通整条流水线、验证检索/拼 prompt 逻辑。
/// 真实落地务必换成 JGCoreMLEmbedding，或用 ONNX Runtime 跑专用 embedding 模型。
@interface JGHashingEmbedding : NSObject <JGEmbedding>
/// 用指定维度初始化（维度越大，哈希冲突越少，但向量越稀疏）
- (instancetype)initWithDimension:(NSInteger)dimension;
@end

/// 真实端侧 embedding：用 Core ML 跑一个 sentence-embedding 模型（如 bge-small 转 Core ML）。
/// .m 里是可直接编译的骨架，把 .mlmodelc 放进去即可产出语义向量。
@interface JGCoreMLEmbedding : NSObject <JGEmbedding>
/// 从编译好的 Core ML 模型 URL 加载（.mlmodel 需先编译成 .mlmodelc）
- (nullable instancetype)initWithModelURL:(NSURL *)modelURL;
@end

NS_ASSUME_NONNULL_END
