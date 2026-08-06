import Foundation

/// 一个"以 MCP 为后端"的 Tool：它的 run 不是本地函数，而是向远程 MCP Server 发 JSON-RPC tools/call。
/// 这正是「移动端当 MCP Client 连云端」的形态——手机上只跑这个轻量 Client，Server 在云端。
struct MCPBackedTool: Tool {
    let spec: ToolSpec
    let serverURL: URL
    private let session: URLSession

    init(spec: ToolSpec, serverURL: URL) {
        self.spec = spec
        self.serverURL = serverURL
        // 演示：拦截 mcp.local 的请求，模拟云端 MCP Server 的响应。
        // 生产环境删掉 MockMCPURLProtocol，把 serverURL 指向你真实的云端 MCP 端点即可。
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockMCPURLProtocol.self]
        self.session = URLSession(configuration: cfg)
    }

    func run(argumentsJSON: String) async throws -> String {
        // 构造 JSON-RPC 2.0 请求：tools/call
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": spec.name,
                "arguments": try parseArgs(argumentsJSON)
            ]
        ]
        var req = URLRequest(url: serverURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await session.data(for: req)
        // 简化解析：远端返回 {"result":{"content":[{"type":"text","text":"..."}]}}
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            return "MCP 返回无法解析"
        }
        return text
    }
}

/// 演示用：把对 mcp.local 的 HTTP 请求在进程内拦截，模拟一个云端 MCP Server 的响应。
/// 这样 demo 不依赖真实网络就能跑通 MCP 路径，同时保留真实的 JSON-RPC 客户端代码。
final class MockMCPURLProtocol: URLProtocol {
    private static let handledHost = "mcp.local"
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == handledHost }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var responseText = "云端查询成功"
        if let body = request.httpBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let params = json["params"] as? [String: Any],
           let name = params["name"] as? String, name == "get_server_price" {
            responseText = "云端价格查询成功：iPhone 16 Pro 7999 元"
        }
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "id": 1,
            "result": ["content": [["type": "text", "text": responseText]]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let resp = HTTPURLResponse(
            url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
