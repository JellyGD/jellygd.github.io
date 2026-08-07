import Foundation

/// 参数类型——对应 JSON Schema 的基本类型。
/// 模型吐出来的永远是字符串，我们得像"判卷"一样把它还原成正确类型。
enum ParamType: String, Sendable {
    case string, integer, number, boolean, array, object
}

/// 一个参数的声明：它是给模型看的"填空题题干"，也是给校验器看的"判卷标准"。
/// 关键不在"描述清楚"，而在"把边界钉死"——required / 枚举白名单 / 长度上限，
/// 这三样才是让模型不乱填参数的真正护栏。
struct ParamDecl: Sendable {
    let name: String
    let type: ParamType
    let description: String
    let required: Bool
    /// 枚举白名单：模型只能从里面挑，不能自由发挥（最防乱填的一招）。
    let allowedValues: [String]?
    /// 字符串最大长度 / 数组最大项数。超出就截断或报错，别让它撑爆上下文。
    let maxLength: Int?
}

/// Tool 的完整参数表。一份声明，两份用途：
/// 1) toJSONSchema() 渲染成喂给模型的 JSON Schema；
/// 2) 直接拿来对模型给的 JSON 做强校验。
/// 把"给模型看"和"给自己校验"绑在同一份源头上，才不会两份对不上。
struct ToolSchema: Sendable {
    let params: [ParamDecl]

    func toJSONSchema() -> String {
        var props: [String: [String: Any]] = [:]
        var required: [String] = []
        for p in params {
            var node: [String: Any] = ["type": p.type.rawValue, "description": p.description]
            if let e = p.allowedValues { node["enum"] = e }
            if let m = p.maxLength { node["maxLength"] = m }
            props[p.name] = node
            if p.required { required.append(p.name) }
        }
        let root: [String: Any] = ["type": "object", "properties": props, "required": required]
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
