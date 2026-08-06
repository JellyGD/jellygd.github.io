#import "JGEmbedding.h"
#import <CoreML/CoreML.h>

@interface JGCoreMLEmbedding ()
@property (nonatomic, strong) MLModel *model; // 已加载的 Core ML 模型
@property (nonatomic, assign) NSInteger dim;   // 输出向量维度（需与模型一致）
@end

@implementation JGCoreMLEmbedding

/// 从 .mlmodelc 加载模型并准备推理。
/// 注意：维度 _dim 需与模型实际输出长度一致；真实接入时建议从首次 prediction 的
/// MLMultiArray 长度读取，此处固定 768 仅作占位演示。
- (nullable instancetype)initWithModelURL:(NSURL *)modelURL {
    if (self = [super init]) {
        NSError *err = nil;
        // 按 URL 加载编译好的模型（也可放 App bundle 用 [MLModel modelWithContentsOfURL:]）
        _model = [MLModel modelWithContentsOfURL:modelURL error:&err];
        if (!_model) { NSLog(@"[RAG] embedding 模型加载失败: %@", err); return nil; }
        // ⚠️ 维度需与你的模型输出一致；真实值从模型输出 MLMultiArray 长度取（见 embedText:）
        _dim = 768;
    }
    return self;
}

/// 返回维度（建库/检索用同一实例保持一致）
- (NSInteger)dimension { return _dim; }

/// 用 Core ML 把文本编码成语义向量。
/// 重点：输入/输出的特征名（这里是 text / output）以你转换出来的模型为准，必要时改。
- (NSArray<NSNumber *> *)embedText:(NSString *)text {
    NSError *err = nil;
    // 构造输入：多数 sentence-embedding 模型吃一个字符串特征
    MLFeatureValue *inputValue = [MLFeatureValue featureValueWithString:text];
    MLDictionaryFeatureProvider *input =
        [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{@"text": inputValue} error:&err];
    if (err) { NSLog(@"[RAG] 构造输入失败: %@", err); return nil; }

    // 推理：拿到输出 feature provider
    id<MLFeatureProvider> out = [_model predictionFromFeatures:input error:&err];
    if (err) { NSLog(@"[RAG] 预测失败: %@", err); return nil; }

    // 取输出：通常是一个 (1, dim) 或 (dim,) 的 MLMultiArray
    MLFeatureValue *fv = [out featureValueForName:@"output"];
    MLMultiArray *ma = fv.multiArrayValue;
    if (!ma) return nil;

    // 把 MLMultiArray 拷成 NSArray<NSNumber*>，统一上层接口
    NSMutableArray<NSNumber *> *v = [NSMutableArray arrayWithCapacity:ma.count];
    for (NSUInteger i = 0; i < ma.count; i++) [v addObject:@(ma[i].floatValue)];

    // 多数模型已做 L2 归一化；若你的模型未归一化，在这里补一次（同 JGHashingEmbedding）
    return [v copy];
}

@end
