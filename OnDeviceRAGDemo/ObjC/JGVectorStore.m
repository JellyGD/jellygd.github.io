#import "JGVectorStore.h"

@interface JGVectorStore ()
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *vectors; // 所有块的向量
@property (nonatomic, strong) NSMutableArray<NSString *> *texts;  // 对应的原文
@property (nonatomic, strong) NSMutableArray<NSString *> *sources; // 对应的出处
@end

@implementation JGVectorStore

/// 初始化：建三个平行数组，下标对齐（vectors[i] ↔ texts[i] ↔ sources[i]）
- (instancetype)init {
    if (self = [super init]) {
        _vectors = [NSMutableArray array];
        _texts = [NSMutableArray array];
        _sources = [NSMutableArray array];
    }
    return self;
}

/// 入库：把一条 (向量, 原文, 出处) 追加到平行数组末尾
- (void)addVector:(NSArray<NSNumber *> *)vector
             text:(NSString *)text
           source:(nullable NSString *)source {
    [self.vectors addObject:vector];
    [self.texts addObject:text];
    [self.sources addObject:source ?: @""];
}

/// 返回库中块数
- (NSInteger)count { return self.vectors.count; }

/// 检索：遍历全库算余弦相似度，按分数降序排，截前 k 个。
/// 重点：暴力线性扫描（flat 检索）。知识量小没问题；量大要换 ANN 索引（IVF/HNSW）。
- (NSArray<JGRetrievalResult *> *)search:(NSArray<NSNumber *> *)query topK:(NSInteger)k {
    NSMutableArray<JGRetrievalResult *> *scored = [NSMutableArray array];
    for (NSInteger i = 0; i < self.vectors.count; i++) {
        float sim = [self cosine:query v:self.vectors[i]];
        JGRetrievalResult *r = [[JGRetrievalResult alloc] init];
        r.text = self.texts[i];
        r.source = self.sources[i];
        r.score = sim;
        [scored addObject:r];
    }
    // 按相似度降序排序（score 大的排前面）
    [scored sortUsingComparator:^NSComparisonResult(JGRetrievalResult *a, JGRetrievalResult *b) {
        return a.score > b.score ? NSOrderedAscending : NSOrderedDescending;
    }];
    // 只保留前 k 个（k<=0 表示全取）
    if (k > 0 && scored.count > k) {
        [scored removeObjectsInRange:NSMakeRange(k, scored.count - k)];
    }
    return [scored copy];
}

/// 余弦相似度：dot(a,b) / (|a|*|b|)。
/// 前置：向量已 L2 归一化时，分母都是 1，结果等价于点积，可直接用点积加速。
- (float)cosine:(NSArray<NSNumber *> *)a v:(NSArray<NSNumber *> *)b {
    if (a.count != b.count || a.count == 0) return 0; // 维度不一致不可比
    float dot = 0, na = 0, nb = 0;
    for (NSInteger i = 0; i < a.count; i++) {
        float x = a[i].floatValue, y = b[i].floatValue;
        dot += x * y; na += x * x; nb += y * y;
    }
    float denom = sqrtf(na) * sqrtf(nb);
    return denom > 0 ? dot / denom : 0;
}

@end

@implementation JGRetrievalResult
@end
