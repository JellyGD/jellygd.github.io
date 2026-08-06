#import "JGLLMGenerator.h"

@implementation JGDemoEchoLLM

/// 假加载：永远成功（它不需要任何模型文件）
- (BOOL)loadModelAtPath:(NSString *)path error:(NSError **)error { return YES; }

/// 假生成：不真正推理，先把拼好的 RAG prompt 回显，再吐一句占位回答。
/// 用处在你确认"检索到的块 + 问题"有没有被正确拼进 prompt —— 这一步通了再换真模型。
- (void)generateWithPrompt:(NSString *)prompt
                  maxTokens:(NSInteger)maxTokens
                    onToken:(void (^)(NSString *))onToken {
    if (onToken) {
        onToken(@"【DemoEchoLLM 回显 prompt】\n");
        onToken(prompt);
        onToken(@"\n\n（以上是送进 LLM 的 prompt；接真实模型后会变成正常回答）\n");
    }
}

/// 假取消：无操作
- (void)cancel {}

@end
