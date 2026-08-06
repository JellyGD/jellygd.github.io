#import "JGRAGEngine.h"
#import "JGDocumentChunker.h"

@interface JGRAGEngine ()
@property (nonatomic, strong) id<JGEmbedding> embedding; // 向量化（建库+提问共用同一实例！）
@property (nonatomic, strong) id<JGLLMGenerator> llm;     // 本地生成
@property (nonatomic, strong) JGVectorStore *store;       // 向量库
@property (nonatomic, strong) JGDocumentChunker *chunker; // 切分器
@end

@implementation JGRAGEngine

/// 初始化：注入 embedding 与 llm，并持有向量库、切分器
- (instancetype)initWithEmbedding:(id<JGEmbedding>)embedding llm:(id<JGLLMGenerator>)llm {
    if (self = [super init]) {
        _embedding = embedding;
        _llm = llm;
        _store = [[JGVectorStore alloc] init];
        _chunker = [[JGDocumentChunker alloc] init];
    }
    return self;
}

/// ① 建库（离线，跑一次）：切分 + 向量化 + 入库
- (void)indexDocument:(NSString *)text sourceName:(NSString *)name {
    // 切 400 字/块，重叠 40 字，避免切断一个完整意思
    NSArray<NSString *> *chunks = [self.chunker chunkText:text maxChunkSize:400 overlap:40];
    for (NSString *c in chunks) {
        // 每块都用同一个 embedding 实例向量化（维度/空间一致，才能和提问向量比较）
        NSArray<NSNumber *> *v = [self.embedding embedText:c];
        [self.store addVector:v text:c source:name];
    }
    NSLog(@"[RAG] 索引完成：%@ 共 %ld 块", name, (long)chunks.count);
}

/// ② 检索 + 生成（每次提问）：召回 top-k → 拼 prompt → 流式生成
- (void)ask:(NSString *)question
        topK:(NSInteger)k
    maxTokens:(NSInteger)maxTokens
      onToken:(void (^)(NSString *))onToken {
    // 检索：问题必须用与建库相同的 embedding 模型向量化，否则向量空间不同、无法比较
    NSArray<NSNumber *> *q = [self.embedding embedText:question];
    NSArray<JGRetrievalResult *> *hits = [self.store search:q topK:k];

    // 拼 RAG prompt：系统约束 + 检索到的资料 + 用户问题
    NSString *prompt = [self buildPrompt:question hits:hits];

    // 生成：把 prompt 交给本地 LLM（OC 的 llama.cpp 封装，或桥接的 Swift LocalLLM）
    [self.llm generateWithPrompt:prompt maxTokens:maxTokens onToken:onToken];
}

/// 拼装 RAG prompt：这是"开卷考试"的关键——把考卷（问题）和资料（检索块）一起交给模型，
/// 并显式约束"只依据资料作答、不知道就说不知道"，从机制上抑制幻觉。
- (NSString *)buildPrompt:(NSString *)question hits:(NSArray<JGRetrievalResult *> *)hits {
    NSMutableString *ctx = [NSMutableString string];
    for (NSInteger i = 0; i < hits.count; i++) {
        [ctx appendFormat:@"\n[%ld] %@\n", (long)(i + 1), hits[i].text];
    }
    return [NSString stringWithFormat:
        @"你是一个只依据下面资料回答问题的助手。如果资料里没有答案，明确说\"资料中没有提到\"，不要编造。\n\n"
         "资料：%@\n\n"
         "用户问题：%@\n\n"
         "回答：", ctx, question];
}

/// 取消：透传给 LLM（停止正在进行的生成）
- (void)cancel { [self.llm cancel]; }

@end
