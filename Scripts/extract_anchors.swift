import Foundation

// 用法: swift Scripts/extract_anchors.swift <Scene.usda 路徑>
// 解析 anchor_flower* / anchor_leaf* 的 xformOp:translate，輸出可貼進 SpatialLabelCatalog 的 points 陣列。

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("用法: swift extract_anchors.swift <Scene.usda>\n".utf8)); exit(2)
}
guard let text = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) else {
    FileHandle.standardError.write(Data("讀取失敗\n".utf8)); exit(1)
}

enum Kind { case flower, leaf }
struct Anchor { let kind: Kind; let name: String; let p: (Float, Float, Float) }

func parseTriple(_ s: String) -> (Float, Float, Float)? {
    guard let o = s.firstIndex(of: "("), let c = s.lastIndex(of: ")"), o < c else { return nil }
    let parts = s[s.index(after: o)..<c].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 3, let x = Float(parts[0]), let y = Float(parts[1]), let z = Float(parts[2]) else { return nil }
    return (x, y, z)
}

var anchors: [Anchor] = []
var kind: Kind?; var name = ""; var captured = false
for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if line.hasPrefix("def "), let f = line.firstIndex(of: "\""), let l = line.lastIndex(of: "\""), f != l {
        let n = String(line[line.index(after: f)..<l])
        if n == "anchor_flower" || n.hasPrefix("anchor_flower_") { kind = .flower; name = n; captured = false }
        else if n == "anchor_leaf" || n.hasPrefix("anchor_leaf_") { kind = .leaf; name = n; captured = false }
        else { kind = nil }
        continue
    }
    if let k = kind, !captured, line.contains("xformOp:translate"), line.contains("="),
       !line.contains("timeSamples"), let t = parseTriple(line) {
        anchors.append(Anchor(kind: k, name: name, p: t)); captured = true
    }
}

let flowers = anchors.filter { $0.kind == .flower }
let leaves = anchors.filter { $0.kind == .leaf }
func emit(_ arr: [Anchor]) {
    print("points: [")
    for a in arr { print(String(format: "    SIMD3<Float>(%.5f, %.5f, %.5f),  // %@", a.p.0, a.p.1, a.p.2, a.name)) }
    print("],")
}
FileHandle.standardError.write(Data("解析完成：花 \(flowers.count) 點、葉 \(leaves.count) 點\n".utf8))
print("// ==== flower (\(flowers.count)) ===="); emit(flowers)
print("// ==== leaf (\(leaves.count)) ===="); emit(leaves)
