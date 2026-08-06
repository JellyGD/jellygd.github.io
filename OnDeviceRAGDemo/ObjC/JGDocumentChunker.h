#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 文档切分器：把长文档切成可检索的小块（chunk）。
///
/// RAG 类比：考试资料不是整本书翻，而是按"页"（块）翻。
/// 块太大 → 检索不精准（一页里混了无关内容）；块太小 → 一个完整意思被切断，模型拼不回来。
/// 经验值：按语义段落优先切，单块 200~500 字，相邻块留少量重叠。
@interface JGDocumentChunker : NSObject

/// 把一段文本切成多个 chunk。
///
/// 切分策略：先按段落切；单段超过 maxChunkSize 时再按句子切，并保留 overlap 个字符的尾部重叠，
/// 避免把一个完整句子/语义拆到两个块里导致检索断裂。
/// @param text 原始文档全文
/// @param maxChunkSize 单块最大字符数（建议 200~500）
/// @param overlap 相邻块尾部重叠字符数（建议 0~50，帮助跨块语义连续）
/// @return 切好的文本块数组（已去除首尾空白）
- (NSArray<NSString *> *)chunkText:(NSString *)text
                      maxChunkSize:(NSUInteger)maxChunkSize
                           overlap:(NSUInteger)overlap;

@end

NS_ASSUME_NONNULL_END
