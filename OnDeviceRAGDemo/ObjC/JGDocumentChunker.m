#import "JGDocumentChunker.h"

@implementation JGDocumentChunker

/// 核心切分方法：实现"段落优先 + 超长段切句 + 尾部重叠"的切分逻辑。
- (NSArray<NSString *> *)chunkText:(NSString *)text
                      maxChunkSize:(NSUInteger)maxChunkSize
                           overlap:(NSUInteger)overlap {
    // 空文本直接返回空数组，避免后续产生空块
    if (text.length == 0) return @[];
    NSMutableArray<NSString *> *chunks = [NSMutableArray array];
    // 先按换行符把文档拆成"段落"——段落是最自然的语义边界
    NSArray<NSString *> *paras = [text componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]];
    NSMutableString *buffer = [NSMutableString string];
    // flush 闭包：把当前 buffer 累积的内容作为一个 chunk 收口
    void (^flush)(void) = ^{
        NSString *trimmed = [buffer stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [chunks addObject:trimmed];
        [buffer setString:@""];
    };
    for (NSString *raw in paras) {
        // 跳过纯空行
        NSString *para = [raw stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (para.length == 0) continue;
        if (para.length > maxChunkSize) {
            // 单段超长：退一步按句子切，保证每块都不超过 maxChunkSize
            NSArray<NSString *> *sentences = [self splitSentences:para];
            for (NSString *s in sentences) {
                // buffer 攒到接近上限且已有内容时，先收口成一块
                if (buffer.length + s.length + 1 > maxChunkSize && buffer.length > 0) {
                    flush();
                    // 重叠：把上一块的尾部 overlap 个字符带到新块开头，
                    // 让跨块的关键词/语义在新块里也能命中检索
                    if (overlap > 0 && chunks.lastObject.length > overlap) {
                        NSString *tail = [chunks.lastObject substringFromIndex:
                                          chunks.lastObject.length - overlap];
                        [buffer appendString:tail];
                    }
                }
                if (buffer.length > 0) [buffer appendString:@" "];
                [buffer appendString:s];
            }
        } else {
            // 普通段：追加进 buffer，超上限则先收口
            if (buffer.length + para.length + 1 > maxChunkSize && buffer.length > 0) flush();
            if (buffer.length > 0) [buffer appendString:@" "];
            [buffer appendString:para];
        }
    }
    flush(); // 收尾：把最后一段 buffer 也输出成块
    return [chunks copy];
}

/// 轻量分句：按中英文句末标点（。！？.!?）切句。
/// 不追求完美 NLP 分词，够 RAG 切块用即可。
- (NSArray<NSString *> *)splitSentences:(NSString *)text {
    NSCharacterSet *delim = [NSCharacterSet characterSetWithCharactersInString:@"。！？.!?"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        [cur appendFormat:@"%C", c];
        if ([delim characterIsMember:c]) {
            // 句末标点处切开，去掉空白后入队
            NSString *t = [cur stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length) [out addObject:t];
            [cur setString:@""];
        }
    }
    // 处理最后一段没有句末标点的尾巴
    NSString *t = [cur stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length) [out addObject:t];
    return [out copy];
}

@end
