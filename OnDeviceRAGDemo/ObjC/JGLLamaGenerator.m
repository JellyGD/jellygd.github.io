#import "JGLLamaGenerator.h"
#import <llama/llama.h>

@interface JGLLamaGenerator ()
@property (nonatomic, assign) void *model;   // llama_model*：模型权重
@property (nonatomic, assign) void *context; // llama_context*：KV cache + 推理状态
@property (nonatomic, assign) void *sampler; // llama_sampler*：采样策略链
@property (nonatomic, assign) BOOL cancelled; // 取消标志，生成循环每轮检查
@end

@implementation JGLLamaGenerator

/// 加载 GGUF 模型并创建上下文 + 采样器链。
/// 重点：n_ctx 决定上下文窗口（要装下 RAG prompt + 回答）；n_gpu_layers 决定卸载到 GPU 的层数，
/// iOS 上尽量全卸载到 Apple GPU（Metal）以提速省电。
- (BOOL)loadModelAtPath:(NSString *)path error:(NSError **)error {
    // 先确认文件存在，给出明确错误而非崩溃在 C 层
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) *error = [NSError errorWithDomain:@"JGRAG" code:1
                            userInfo:@{NSLocalizedDescriptionKey:
                            [NSString stringWithFormat:@"模型文件不存在: %@", path]}];
        return NO;
    }

    // 1) 加载模型权重
    struct llama_model_params mparams = llama_model_default_params();
    self.model = llama_model_load_from_file(path.UTF8String, mparams);
    if (!self.model) {
        if (error) *error = [NSError errorWithDomain:@"JGRAG" code:2
                            userInfo:@{NSLocalizedDescriptionKey: @"模型加载失败"}];
        return NO;
    }

    // 2) 创建上下文（KV cache 大小、batch、GPU 层数等关键参数都在这里）
    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx = 4096;     // 上下文窗口
    cparams.n_batch = 512;    // 一次送进模型的 token 批大小
    cparams.n_ubatch = 512;   // 单批内再细分（影响内存峰值）
    cparams.n_gpu_layers = 99; // iOS 尽量全卸载到 GPU(Metal)
    self.context = llama_new_context_with_model((struct llama_model *)self.model, cparams);
    if (!self.context) {
        llama_model_free((struct llama_model *)self.model);
        self.model = NULL;
        if (error) *error = [NSError errorWithDomain:@"JGRAG" code:3
                            userInfo:@{NSLocalizedDescriptionKey: @"上下文创建失败"}];
        return NO;
    }

    // 3) 采样器链：先 top_k/top_p 截断候选集，再 temperature 调形状，最后 dist 提供随机性（官方推荐顺序）
    struct llama_sampler_chain_params chain = llama_sampler_chain_default_params();
    self.sampler = llama_sampler_chain_init(chain);
    llama_sampler_chain_add((struct llama_sampler *)self.sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add((struct llama_sampler *)self.sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add((struct llama_sampler *)self.sampler, llama_sampler_init_temp(0.8f));
    llama_sampler_chain_add((struct llama_sampler *)self.sampler, llama_sampler_init_dist(12345));
    self.cancelled = NO;
    return YES;
}

/// 流式生成主循环：先 tokenize 整个 prompt，再逐 token 解码（采样→出字→喂回）。
/// 重点：RAG 成败在检索，这里只负责"看着资料答题"，prompt 拼得好不好全看 JGRAGEngine。
- (void)generateWithPrompt:(NSString *)prompt
                  maxTokens:(NSInteger)maxTokens
                    onToken:(void (^)(NSString *))onToken {
    if (!self.context || !self.model || !self.sampler) return;
    self.cancelled = NO;

    // tokenize 分两步：第一次拿到所需长度，第二次真正填充（llama 经典用法）
    const char *p = prompt.UTF8String;
    int nPrompt = (int)strlen(p);
    int cap = llama_tokenize((struct llama_context *)self.context, p, nPrompt, NULL, 0, true, true);
    if (cap <= 0) return;
    NSMutableData *toks = [NSMutableData dataWithLength:sizeof(llama_token) * (cap + 8)];
    llama_token *tokens = (llama_token *)toks.mutableBytes;
    int n = llama_tokenize((struct llama_context *)self.context, p, nPrompt, tokens, cap + 8, true, true);
    if (n <= 0) return;

    llama_seq_id seq0 = 0; // 单序列（RAG 用单轮对话即可）

    // 1) 把整个 prompt 一次性 encode 进模型（只取最后一位的 logits 用于首 token 采样）
    struct llama_batch batch = llama_batch_init(n, 0, 1);
    for (int i = 0; i < n; i++) {
        batch.token[i] = tokens[i];
        batch.pos[i] = i;
        batch.seq_id[i] = &seq0;
        batch.n_seq_id[i] = 1;
        batch.logits[i] = (i == n - 1) ? 1 : 0; // 仅最后一位需要 logits
    }
    llama_encode((struct llama_context *)self.context, batch);

    struct llama_batch genBatch = llama_batch_init(1, 0, 1);

    // 2) 逐 token 解码循环
    llama_token prev = 0;
    int generated = 0;
    while (generated < maxTokens) {
        if (self.cancelled) break; // 用户点停止 → 立刻跳出循环
        llama_token next;
        if (generated == 0) {
            // 首 token：基于 prompt 末位 logits 采样
            next = llama_sampler_sample((struct llama_sampler *)self.sampler,
                                        (struct llama_context *)self.context, n - 1);
        } else {
            // 后续 token：把上一 token 喂回去，再采样
            genBatch.token[0] = prev;
            genBatch.pos[0] = n + generated - 1;
            genBatch.seq_id[0] = &seq0;
            genBatch.n_seq_id[0] = 1;
            genBatch.logits[0] = 1;
            llama_decode((struct llama_context *)self.context, genBatch);
            next = llama_sampler_sample((struct llama_sampler *)self.sampler,
                                        (struct llama_context *)self.context, -1);
        }
        llama_sampler_accept((struct llama_sampler *)self.sampler, next, true);
        if (llama_token_is_eog((struct llama_model *)self.model, next)) break; // 遇结束符停止
        NSString *piece = [self tokenToPiece:next];
        if (piece.length && onToken) onToken(piece); // 把片段回传给 UI
        prev = next;
        generated++;
    }

    llama_batch_free(batch);
    llama_batch_free(genBatch);
}

/// 把一个 token 解码成可读字符串（UTF-8）。llama 返回的 piece 可能跨多个字节，需两段式取长度再拷贝。
- (NSString *)tokenToPiece:(llama_token)token {
    if (!self.context) return @"";
    int n = llama_token_to_piece((struct llama_context *)self.context, token, NULL, 0, 0, false);
    if (n <= 0) return @"";
    NSMutableData *buf = [NSMutableData dataWithLength:sizeof(char) * (n + 1)];
    char *c = (char *)buf.mutableBytes;
    llama_token_to_piece((struct llama_context *)self.context, token, c, n, 0, false);
    return [NSString stringWithUTF8String:c];
}

/// 取消当前生成
- (void)cancel { self.cancelled = YES; }

/// 释放资源：采样器 → 上下文 → 模型，顺序与创建相反
- (void)unload {
    if (self.sampler) { llama_sampler_free((struct llama_sampler *)self.sampler); self.sampler = NULL; }
    if (self.context) { llama_free((struct llama_context *)self.context); self.context = NULL; }
    if (self.model)   { llama_model_free((struct llama_model *)self.model); self.model = NULL; }
}

/// dealloc 时自动释放，避免内存/句柄泄漏
- (void)dealloc { [self unload]; }

@end
