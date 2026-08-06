#import "JGEmbedding.h"

@implementation JGHashingEmbedding {
    NSInteger _dim; // 向量维度，建库/检索必须保持一致
}

/// 初始化：记录维度
- (instancetype)initWithDimension:(NSInteger)dimension {
    if (self = [super init]) _dim = dimension;
    return self;
}

/// 返回维度（建库和提问用同一个实例，维度自然一致）
- (NSInteger)dimension { return _dim; }

/// 把文本编码成"词哈希 TF"向量并 L2 归一化。
/// 重点：它不表示语义，只表示"哪些词出现了/出现了几次"，所以只能做字面相似检索。
- (NSArray<NSNumber *> *)embedText:(NSString *)text {
    // 预填 0：向量是定长 _dim 的
    NSMutableArray<NSNumber *> *v = [NSMutableArray arrayWithCapacity:_dim];
    for (NSInteger i = 0; i < _dim; i++) [v addObject:@(0.0f)];

    // 词元化：统一小写；英文数字按"词"聚合，CJK 按"字"切（中文没有词间空格）
    NSString *lower = [text lowercaseString];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        BOOL isWord = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        BOOL isHan = (c >= 0x4e00 && c <= 0x9fff);
        if (isWord || isHan) {
            [cur appendFormat:@"%C", c]; // 连续字母/数字/汉字积累成一个词元
        } else if (cur.length) {
            [words addObject:[cur copy]]; // 遇标点/空白断词
            [cur setString:@""];
        }
    }
    if (cur.length) [words addObject:[cur copy]];

    // hashing trick：把每个词哈希到一个桶下标，桶里累加词频（TF）。
    // 维度远小于词表，不同词可能撞同一桶（冲突），但演示足够。
    for (NSString *w in words) {
        NSInteger bucket = (NSInteger)[self hashWord:w] % _dim;
        if (bucket < 0) bucket += _dim; // 处理取模负值
        v[bucket] = @(v[bucket].floatValue + 1.0f);
    }

    // L2 归一化：除以向量模长，让余弦相似度退化为"方向"比较（= 词重叠比例）
    float norm = 0;
    for (NSNumber *n in v) norm += n.floatValue * n.floatValue;
    norm = sqrtf(norm);
    if (norm > 0) {
        for (NSInteger i = 0; i < _dim; i++) v[i] = @(v[i].floatValue / norm);
    }
    return [v copy];
}

/// djb2 哈希：把字符串稳定映射成一个无符号整数，仅用于给词分桶。
- (NSUInteger)hashWord:(NSString *)w {
    NSUInteger h = 5381;
    for (NSUInteger i = 0; i < w.length; i++) {
        h = ((h << 5) + h) + [w characterAtIndex:i]; // h = h*33 + c
    }
    return h;
}

@end
