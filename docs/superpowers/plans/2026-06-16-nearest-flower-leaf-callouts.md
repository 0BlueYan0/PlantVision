# 最近花/葉動態立體標記 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Vision Pro 真實植物追蹤畫面，用 RCP 烘焙的立體發光 callout 取代扁平圓點，且只顯示離使用者最近的一朵花 + 一片葉，隨頭部移動動態換位。

**Architecture:** 五層 —— parser（`Scene.usda`→座標）、純選取邏輯（最近+遲滯）、資料（PlantDatabase/PartAnchor）、渲染（clone MarkerTemplate）、選取整合（WorldTracking + 每幀重選）。前兩層可 headless 單元測試；渲染/整合靠 build + 實機驗證。

**Tech Stack:** Swift 6 / RealityKit / ARKit（ObjectTracking + WorldTracking）/ visionOS / simd。測試：`swiftc` 直接編譯純邏輯檔（app 無 XCTest target）。

設計稿：`docs/superpowers/specs/2026-06-16-nearest-flower-leaf-callouts-design.md`

---

## 測試說明（重要）
PlantVision app（Xcode 專案）**沒有 XCTest target**，既有測試都在 `MacFrameRelay` SPM 套件。為避免動 pbxproj，純邏輯（parser、NearestPartSelector）採「**獨立 `swiftc` 編譯 + 斷言**」的輕量 harness，可在 macOS host headless 跑。RealityKit/ARKit 程式碼無法 headless 測，以 build + 實機檢查表驗證。

路徑慣例：本計畫所有指令以 repo 根（worktree）為工作目錄。

---

## Task 1: Anchor 座標 parser + 測試

**Files:**
- Create: `Scripts/extract_anchors.swift`
- Create: `Scripts/fixtures/sample_scene.usda`
- Create: `Scripts/test_extract_anchors.sh`

- [ ] **Step 1: 寫 fixture（先有測試資料）**

建 `Scripts/fixtures/sample_scene.usda`：
```usda
#usda 1.0
( defaultPrim = "Root" upAxis = "Y" )
def Xform "Root"
{
    def Xform "anchor_flower" ( active = true )
    {
        float3 xformOp:translate = (0.10000, 1.20000, 0.30000)
        uniform token[] xformOpOrder = ["xformOp:translate"]
    }
    def Xform "anchor_flower_1" ( active = true )
    {
        float3 xformOp:translate = (0.40000, 1.50000, -0.20000)
        uniform token[] xformOpOrder = ["xformOp:translate"]
    }
    def Xform "anchor_leaf" ( active = true )
    {
        float3 xformOp:translate = (-0.10000, 1.10000, 0.05000)
        uniform token[] xformOpOrder = ["xformOp:translate"]
    }
    def Xform "ignore_me" ( active = true )
    {
        float3 xformOp:translate = (9.0, 9.0, 9.0)
    }
}
```

- [ ] **Step 2: 寫測試（先失敗）**

建 `Scripts/test_extract_anchors.sh`：
```bash
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT=$(swift "$DIR/extract_anchors.swift" "$DIR/fixtures/sample_scene.usda" 2>/tmp/anchors_err.txt || true)
ERR=$(cat /tmp/anchors_err.txt)

fail=0
echo "$OUT" | grep -q "SIMD3<Float>(0.10000, 1.20000, 0.30000)" || { echo "FAIL: 缺 flower 點1"; fail=1; }
echo "$OUT" | grep -q "SIMD3<Float>(0.40000, 1.50000, -0.20000)" || { echo "FAIL: 缺 flower 點2"; fail=1; }
echo "$OUT" | grep -q "SIMD3<Float>(-0.10000, 1.10000, 0.05000)" || { echo "FAIL: 缺 leaf 點1"; fail=1; }
echo "$OUT" | grep -q "9.00000" && { echo "FAIL: 不該收 ignore_me"; fail=1; } || true
echo "$ERR" | grep -q "花 2 點" || { echo "FAIL: 花數量不符 ($ERR)"; fail=1; }
echo "$ERR" | grep -q "葉 1 點" || { echo "FAIL: 葉數量不符 ($ERR)"; fail=1; }
[ "$fail" = "0" ] && echo "ALL TESTS PASSED" || exit 1
```
執行 `chmod +x Scripts/test_extract_anchors.sh && Scripts/test_extract_anchors.sh`
預期：FAIL（`extract_anchors.swift` 尚不存在 → swift 報錯，grep 失敗）

- [ ] **Step 3: 寫 parser**

建 `Scripts/extract_anchors.swift`：
```swift
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
```

- [ ] **Step 4: 跑測試（應通過）**

執行 `Scripts/test_extract_anchors.sh`
預期：`ALL TESTS PASSED`

- [ ] **Step 5: Commit**
```bash
git add Scripts/extract_anchors.swift Scripts/fixtures/sample_scene.usda Scripts/test_extract_anchors.sh
git commit -m "feat(tools): 新增 Scene.usda anchor 座標 parser 與測試"
```

---

## Task 2: NearestPartSelector 純選取邏輯 + 測試

**Files:**
- Create: `PlantVision/Spatial/NearestPartSelector.swift`
- Create: `Scripts/test_nearest_selector.swift`

- [ ] **Step 1: 寫測試（先失敗）**

建 `Scripts/test_nearest_selector.swift`：
```swift
import simd
import Foundation

@main
enum NearestPartSelectorTests {
    static func main() {
        var fail = 0
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL: \(m)"); fail += 1 } }
        let head = SIMD3<Float>(0, 0, 0)

        check(NearestPartSelector.select(candidatesWorld: [], headWorld: head, current: nil, switchMargin: 0.05) == nil,
              "空候選回 nil")
        let pts = [SIMD3<Float>(1,0,0), SIMD3<Float>(0.2,0,0), SIMD3<Float>(2,0,0)]
        check(NearestPartSelector.select(candidatesWorld: pts, headWorld: head, current: nil, switchMargin: 0.05) == 1,
              "首次選最近=1")
        let near = [SIMD3<Float>(1,0,0), SIMD3<Float>(0.98,0,0)]
        check(NearestPartSelector.select(candidatesWorld: near, headWorld: head, current: 0, switchMargin: 0.05) == 0,
              "差<margin 維持目前=0")
        let far = [SIMD3<Float>(1,0,0), SIMD3<Float>(0.5,0,0)]
        check(NearestPartSelector.select(candidatesWorld: far, headWorld: head, current: 0, switchMargin: 0.05) == 1,
              "差>margin 換手=1")
        check(NearestPartSelector.select(candidatesWorld: far, headWorld: head, current: 99, switchMargin: 0.05) == 1,
              "越界 current 重新挑=1")

        if fail == 0 { print("ALL TESTS PASSED") } else { exit(1) }
    }
}
```

- [ ] **Step 2: 跑測試（應失敗，型別未定義）**

Run:
```bash
swiftc PlantVision/Spatial/NearestPartSelector.swift Scripts/test_nearest_selector.swift -o /tmp/npsel 2>&1 | head
```
預期：編譯失敗（找不到 `NearestPartSelector` / 檔案不存在）

- [ ] **Step 3: 寫實作**

建 `PlantVision/Spatial/NearestPartSelector.swift`：
```swift
import simd

/// 從候選點挑離使用者頭部最近的一個，帶遲滯避免在近等距點間抖動。
/// 純數學，不依賴 RealityKit/ARKit，可獨立單元測試。
enum NearestPartSelector {
    /// - candidatesWorld: 候選點世界座標
    /// - headWorld: 頭部世界座標
    /// - current: 目前選中 index（nil = 尚未選）
    /// - switchMargin: 另一候選需比目前選中近超過此距離(公尺)才換手
    /// - Returns: 新選中 index；候選為空回 nil
    static func select(candidatesWorld: [SIMD3<Float>],
                       headWorld: SIMD3<Float>,
                       current: Int?,
                       switchMargin: Float) -> Int? {
        guard !candidatesWorld.isEmpty else { return nil }
        var bestIndex = 0
        var bestDist = simd_distance(candidatesWorld[0], headWorld)
        for i in 1..<candidatesWorld.count {
            let d = simd_distance(candidatesWorld[i], headWorld)
            if d < bestDist { bestDist = d; bestIndex = i }
        }
        if let cur = current, cur >= 0, cur < candidatesWorld.count {
            let curDist = simd_distance(candidatesWorld[cur], headWorld)
            if curDist - bestDist <= switchMargin { return cur }
        }
        return bestIndex
    }
}
```

- [ ] **Step 4: 跑測試（應通過）**

Run:
```bash
swiftc PlantVision/Spatial/NearestPartSelector.swift Scripts/test_nearest_selector.swift -o /tmp/npsel && /tmp/npsel
```
預期：`ALL TESTS PASSED`

- [ ] **Step 5: Commit**
```bash
git add PlantVision/Spatial/NearestPartSelector.swift Scripts/test_nearest_selector.swift
git commit -m "feat(spatial): 新增 NearestPartSelector 最近候選+遲滯選取（含測試）"
```

---

## Task 3: PlantDatabase 加馬纓丹 + profile plantID

**Files:**
- Modify: `PlantVision/Services/PlantDatabase.swift`
- Modify: `PlantVision/Spatial/PartAnchor.swift`（`SpatialLabelCatalog` 的 `plantID`）

- [ ] **Step 1: 加馬纓丹 Plant**

在 `PlantDatabase.swift` 的 `plants` 陣列加一筆（沿用既有 `Plant` 欄位格式，參考 `catharanthus-roseus` 那筆）：
```swift
        Plant(
            id: "lantana-camara",
            chineseName: "馬纓丹",
            scientificName: "Lantana camara"
            // 其餘欄位比照同陣列其他 Plant 填寫（若有 description/category 等，依現有格式補齊）
        ),
```
> 注意：先讀 `PlantDatabase.swift` 確認 `Plant` 完整欄位，缺的欄位照其他筆格式補，不可留空 placeholder。

- [ ] **Step 2: profile plantID 指向馬纓丹**

`PartAnchor.swift` 的 `SpatialLabelCatalog.profiles` 那筆，把
`plantID: "catharanthus-roseus"` 改成 `plantID: "lantana-camara"`。

- [ ] **Step 3: 驗證可解析**

Run（headless 檢查語法/查得到）：
```bash
grep -n "lantana-camara" PlantVision/Services/PlantDatabase.swift PlantVision/Spatial/PartAnchor.swift
```
預期：兩個檔各出現一次。（完整編譯於 Task 7 build 時一併驗證。）

- [ ] **Step 4: Commit**
```bash
git add PlantVision/Services/PlantDatabase.swift PlantVision/Spatial/PartAnchor.swift
git commit -m "feat(data): 新增馬纓丹植物並將 profile 指向之"
```

---

## Task 4: Xcode 接線 + 模板載入 smoke test（風險最高）

**Files:**
- Modify: `PlantAnchor/Package.swift`（必要時宣告 rkassets 資源）
- Modify: `PlantVision.xcodeproj/project.pbxproj`（加 PlantAnchor 套件依賴）
- Temp: 在 `RealPlantTrackingView` 加暫時的 debug 載入

- [ ] **Step 1: 把 PlantAnchor 加進 Xcode 專案**

在 Xcode 開 `PlantVision.xcodeproj` → 選 PlantVision target → General → Frameworks/Libraries →
「+」→ Add Other → Add Package Dependency → 選本機 `PlantAnchor` 資料夾 → 連結到 PlantVision target。
（程式化改 pbxproj 易錯；此步建議用 Xcode UI。若用 UI 完成，pbxproj 會自動更新。）

- [ ] **Step 2: 確認 Bundle.module 可解析**

Build PlantVision target（Xcode Cmd+B，visionOS destination）。
- 若 `plantAnchorBundle = Bundle.module` 編譯通過 → 進 Step 3。
- 若報錯（`Bundle has no member module`）→ 改 `PlantAnchor/Package.swift`，在 target 宣告資源讓 SwiftPM 產生 `Bundle.module`：
```swift
.target(
    name: "PlantAnchor",
    dependencies: [],
    resources: [ .copy("PlantAnchor.rkassets") ]
)
```
重新 build。（RealityKitContent 慣例：Xcode 會以 RealityKit 規則處理 `.rkassets`。）

- [ ] **Step 3: 暫時 debug 載入，確認模板讀得到**

在 `RealPlantTrackingView` 的 `RealityView` make 閉包**最前面**暫時加：
```swift
import PlantAnchor
// ...
if let t = try? await Entity(named: "MarkerTemplate", in: plantAnchorBundle) {
    print("[PlantVision] MarkerTemplate loaded; children=\(t.children.map(\.name))")
} else {
    print("[PlantVision] MarkerTemplate FAILED to load")
}
```

- [ ] **Step 4: 實機/模擬器跑一次看 log**

預期 console：`MarkerTemplate loaded; children=[..., "FlowerMarker", "LeafMarker", ...]`（含 Materials）。
若 FAILED：檢查 rkassets 是否進了 bundle、資源宣告、target 連結。**此步驗證點是「模板能載入」，過了才繼續。**

- [ ] **Step 5: 移除暫時 debug 程式碼並 commit**

刪掉 Step 3 的暫時 print（保留 `import PlantAnchor`）。
```bash
git add -A
git commit -m "build: 將 PlantAnchor 套件接進 PlantVision，確認 MarkerTemplate 可載入"
```

---

## Task 5: 渲染 — SpatialLabelBuilder.makeCallout（新增，不破壞舊）

**Files:**
- Modify: `PlantVision/Spatial/SpatialLabelBuilder.swift`

- [ ] **Step 1: 加 callout 組裝與模板載入 helper**

在 `SpatialLabelBuilder` 內新增（保留既有 `makeMarker`/`makeLeader`/`makePartGroup` 暫不動）：
```swift
import PlantAnchor   // 檔案頂端

extension SpatialLabelBuilder {

    /// 載入並取出兩個 marker 模板；失敗回 (nil, nil)，由 makeCallout 走 fallback。
    @MainActor
    static func loadMarkerTemplates() async -> (flower: Entity?, leaf: Entity?) {
        guard let root = try? await Entity(named: "MarkerTemplate", in: plantAnchorBundle) else {
            return (nil, nil)
        }
        return (root.findEntity(named: "FlowerMarker"), root.findEntity(named: "LeafMarker"))
    }

    /// 組一個部位 callout：clone 模板（發光球+光暈+脈動）+ 長引線 + SwiftUI 標籤。
    /// `template` 為 nil 時退回程式化發光球。group.position 由選取層每幀更新。
    @MainActor
    static func makeCallout(part: PlantPart,
                            template: Entity?,
                            label: Entity?,
                            labelOffset: SIMD3<Float>) -> Entity {
        let group = Entity()
        group.name = "callout-\(part.rawValue)"
        group.isEnabled = false   // 選取層選到候選前先隱藏

        let marker: Entity
        if let template {
            let clone = template.clone(recursive: true)
            clone.position = .zero
            // 剝除模板自帶的短引線/標籤底板，改用我們自己的長引線+SwiftUI標籤（避免花葉標籤重疊）
            clone.findEntity(named: "LeaderLine")?.removeFromParent()
            clone.findEntity(named: "LabelBacking")?.removeFromParent()
            playAllAnimations(on: clone)   // 脈動 + Halo 旋轉，循環
            marker = clone
        } else {
            marker = makeMarker(radius: 0.02, color: UIColor(part.markerColor))
        }
        group.addChild(marker)

        group.addChild(makeLeader(from: .zero, to: labelOffset, color: UIColor(part.markerColor)))

        if let label {
            label.position = labelOffset
            label.components.set(BillboardComponent())
            group.addChild(label)
        }
        return group
    }

    /// 遞迴播放整個子樹上所有 USD 烘焙動畫，循環。
    @MainActor
    static func playAllAnimations(on entity: Entity) {
        for anim in entity.availableAnimations {
            entity.playAnimation(anim.repeat(), transitionDuration: 0, startsPaused: false)
        }
        for child in entity.children { playAllAnimations(on: child) }
    }
}
```

- [ ] **Step 2: 編譯通過（隨 Task 7 build 一起；此步先靜態檢查）**

Run:
```bash
grep -n "func makeCallout\|func loadMarkerTemplates\|func playAllAnimations" PlantVision/Spatial/SpatialLabelBuilder.swift
```
預期：三個函式各出現一次。

- [ ] **Step 3: Commit**
```bash
git add PlantVision/Spatial/SpatialLabelBuilder.swift
git commit -m "feat(spatial): 新增 makeCallout/載入模板/播放動畫（暫與舊路徑並存）"
```

> 註：clone 後 `availableAnimations` 是否帶到脈動/Halo 取決於 USD 動畫綁定。若 Task 7 實機驗證發現不動，套用 **附錄 A 的程式化脈動 fallback**。

---

## Task 6: 選取整合 — ObjectTrackingController

**Files:**
- Modify: `PlantVision/Spatial/ObjectTrackingController.swift`

- [ ] **Step 1: 加 WorldTracking、binding 型別與狀態**

檔案頂端加 `import QuartzCore`。在類別內加：
```swift
    /// 一株植物的候選點與對應 callout 實體。
    struct PlantCalloutBinding {
        let flowerPoints: [SIMD3<Float>]
        let leafPoints: [SIMD3<Float>]
        let flowerCallout: Entity
        let leafCallout: Entity
    }

    private let worldTracking = WorldTrackingProvider()
    private var callouts: [String: PlantCalloutBinding] = [:]
    private var selection: [String: (flower: Int?, leaf: Int?)] = [:]
    private let switchMargin: Float = 0.05

    /// View 注入每株的候選點 + callout 實體（key = referenceObjectID）。
    func bindCallouts(_ bindings: [String: PlantCalloutBinding]) {
        self.callouts = bindings
        self.selection = [:]
    }
```

- [ ] **Step 2: session 加入 WorldTracking**

把 `start(...)` 內的授權與 run 改成同時涵蓋 WorldTracking：
```swift
        let auths = ObjectTrackingProvider.requiredAuthorizations + WorldTrackingProvider.requiredAuthorizations
        let status = await session.requestAuthorization(for: auths)
        guard status.values.allSatisfy({ $0 == .allowed }) else {
            phase = .needsAuthorization
            return
        }

        let provider = ObjectTrackingProvider(referenceObjects: loaded.map(\.reference))
        do {
            try await session.run([provider, worldTracking])
        } catch {
            phase = .failed("啟動 ARKit session 失敗:\(error.localizedDescription)")
            return
        }
```

- [ ] **Step 3: 加每幀重選 callout 的方法**

在類別內加（由 View 的 scene-update 每幀呼叫）：
```swift
    /// 依當下頭部位置，把每株的花/葉 callout 移到最近候選（帶遲滯）。
    func refreshCallouts() {
        guard let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let h = device.originFromAnchorTransform.columns.3
        let headWorld = SIMD3<Float>(h.x, h.y, h.z)

        for (id, b) in callouts {
            guard let root = roots[id], root.isEnabled else {
                b.flowerCallout.isEnabled = false
                b.leafCallout.isEnabled = false
                continue
            }
            let m = root.transform.matrix
            func world(_ pts: [SIMD3<Float>]) -> [SIMD3<Float>] {
                pts.map { p in let w = m * SIMD4<Float>(p.x, p.y, p.z, 1); return SIMD3<Float>(w.x, w.y, w.z) }
            }
            let sel = selection[id] ?? (nil, nil)
            let f = NearestPartSelector.select(candidatesWorld: world(b.flowerPoints),
                                               headWorld: headWorld, current: sel.flower, switchMargin: switchMargin)
            let l = NearestPartSelector.select(candidatesWorld: world(b.leafPoints),
                                               headWorld: headWorld, current: sel.leaf, switchMargin: switchMargin)
            selection[id] = (f, l)
            if let f { b.flowerCallout.position = b.flowerPoints[f]; b.flowerCallout.isEnabled = true }
            else { b.flowerCallout.isEnabled = false }
            if let l { b.leafCallout.position = b.leafPoints[l]; b.leafCallout.isEnabled = true }
            else { b.leafCallout.isEnabled = false }
        }
    }
```

- [ ] **Step 4: 靜態檢查**

Run:
```bash
grep -n "func bindCallouts\|func refreshCallouts\|WorldTrackingProvider\|import QuartzCore" PlantVision/Spatial/ObjectTrackingController.swift
```
預期：各項都在。

- [ ] **Step 5: Commit**
```bash
git add PlantVision/Spatial/ObjectTrackingController.swift
git commit -m "feat(spatial): controller 加 WorldTracking 與每幀最近 callout 重選"
```

---

## Task 7: 切換 View 到 callout + 清理舊路徑（build + 實機驗證）

**Files:**
- Modify: `PlantVision/Views/SpatialPlantSceneView.swift`（`RealPlantTrackingView`）
- Modify: `PlantVision/Spatial/SpatialLabelBuilder.swift`（移除 `makePartGroup`）
- Modify: `PlantVision/Spatial/PartAnchor.swift`（移除 `centroid`/`dotRadius`，更新 `points` 註解）

- [ ] **Step 1: 改 RealPlantTrackingView 用 callout**

把 `RealityView` 的 make 閉包改成：載入模板 → 每株建 flower/leaf 兩個 callout group → 收集 binding → `bindCallouts` → 訂閱 scene update 每幀 `refreshCallouts`。完整 make 閉包：
```swift
        RealityView { content, attachments in
            let templates = await SpatialLabelBuilder.loadMarkerTemplates()
            var roots: [String: Entity] = [:]
            var bindings: [String: ObjectTrackingController.PlantCalloutBinding] = [:]

            for profile in SpatialLabelCatalog.profiles {
                let root = Entity()
                root.name = "tracked-\(profile.referenceObjectID)"
                let correction = Entity()
                correction.position = profile.frameCorrection
                root.addChild(correction)

                var flowerCallout: Entity?
                var leafCallout: Entity?
                var flowerPoints: [SIMD3<Float>] = []
                var leafPoints: [SIMD3<Float>] = []

                for anchor in profile.parts {
                    let label = attachments.entity(for: "label-\(profile.referenceObjectID)-\(anchor.part.rawValue)")
                    let callout = SpatialLabelBuilder.makeCallout(
                        part: anchor.part,
                        template: anchor.part == .flower ? templates.flower : templates.leaf,
                        label: label,
                        labelOffset: anchor.labelOffset)
                    correction.addChild(callout)
                    switch anchor.part {
                    case .flower: flowerCallout = callout; flowerPoints = anchor.points
                    case .leaf:   leafCallout = callout;   leafPoints = anchor.points
                    }
                }

                content.add(root)
                roots[profile.referenceObjectID] = root
                if let f = flowerCallout, let l = leafCallout {
                    bindings[profile.referenceObjectID] = .init(
                        flowerPoints: flowerPoints, leafPoints: leafPoints,
                        flowerCallout: f, leafCallout: l)
                }
            }
            controller.bind(roots: roots)
            controller.bindCallouts(bindings)

            controller.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                controller.refreshCallouts()
            }

            if let status = attachments.entity(for: "tracking-status") {
                status.name = "tracking-status"
                status.position = [0, 1.4, -1.2]
                content.add(status)
            }
        } update: { content, _ in
            if let status = content.entities.first(where: { $0.name == "tracking-status" }) {
                status.isEnabled = (controller.phase != .tracking)
            }
        } attachments: {
            ForEach(labelSlots) { slot in
                Attachment(id: slot.id) { SpatialPartLabel(part: slot.part, plant: slot.plant) }
            }
            Attachment(id: "tracking-status") {
                SpatialTrackingStatusLabel(phase: controller.phase)
            }
        }
        .task { await controller.start(holdProvider: { appModel.isHolding }) }
        .onDisappear { controller.stop() }
```

- [ ] **Step 2: controller 加保留訂閱用屬性**

在 `ObjectTrackingController` 加（避免 EventSubscription 被釋放）：
```swift
    var updateSubscription: EventSubscription?
```
頂端確保 `import RealityKit`（已有）。

- [ ] **Step 3: 移除舊 makePartGroup 與 PartAnchor 廢欄位**

- `SpatialLabelBuilder.swift`：刪除 `makePartGroup(_:label:)` 整個方法（已無人呼叫）。保留 `makeMarker`/`makeLeader`/`smoothed`。
- `PartAnchor.swift`：刪除 `dotRadius` 儲存屬性與 `centroid` 計算屬性；把 `points` 註解改為「每個點 = 一朵花/一片葉的獨立候選位置」。
- `PartAnchor.swift` 的 `SpatialLabelCatalog` 兩筆 `PartAnchor(...)`：移除 `dotRadius: 0.008` 那行。

- [ ] **Step 4: Build**

Run（或在 Xcode Cmd+B，visionOS destination）：
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS' build 2>&1 | tail -20
```
預期：`BUILD SUCCEEDED`。
（若 `PlantVision` scheme 未共用導致 xcodebuild 找不到：先在 Xcode 勾選 scheme 的 Shared，或直接以 Xcode 建置。修正所有編譯錯誤至綠燈。）

- [ ] **Step 5: 實機驗證檢查表（Vision Pro）**

對著真實馬纓丹（需有對應 `.referenceobject` 且座標已更新，見 Task 8 / 前置）逐項確認：
1. 追蹤鎖定後，畫面出現**一個花 callout + 一個葉 callout**，無扁平小圓點。
2. callout 是**發光球 + 環繞光暈**，且球有**脈動**、光暈有**旋轉**（若無動畫 → 套附錄 A）。
3. 引線從 callout 指向**面向使用者**的資訊標籤；花/葉兩標籤**不重疊**。
4. **繞著植物走**時，花/葉 callout 會**移到當下最近的**那朵花/片葉，且不在近等距點間快速抖動。
5. 暫時 lost / 移開時 callout 隱藏，重新追到恢復。

- [ ] **Step 6: Commit**
```bash
git add -A
git commit -m "feat(spatial): RealPlantTrackingView 切換為動態最近花/葉立體 callout，移除舊圓點路徑"
```

---

## Task 8: RCP 標記操作指南（交付文件）

**Files:**
- Create: `docs/superpowers/rcp-anchor-marking-guide.md`

- [ ] **Step 1: 寫指南**

建 `docs/superpowers/rcp-anchor-marking-guide.md`，內容涵蓋：命名規範、座標系前提、逐步操作、跑 parser、貼回 catalog。完整步驟：

```markdown
# RCP 花/葉錨點標記指南（馬纓丹）

## 命名規範（parser 依此辨識，務必照做）
- 花：`anchor_flower`、`anchor_flower_1`、`anchor_flower_2`…（第一個無數字後綴）
- 葉：`anchor_leaf`、`anchor_leaf_1`、`anchor_leaf_2`…
- 每個錨點 = 一個空 Transform，擺在「一朵花 / 一片葉」上（外圍可見者）。

## 座標系前提
錨點座標必須與追蹤用的 `.referenceobject` 同一座標系：
- 把 `馬纓丹_已原點.usdz` 以 identity transform（translate 0,0,0、無旋轉縮放）放在 `Root` 下。
- 所有 `anchor_*` 直接當 `Root` 的子節點（不要放進模型節點底下）。

## 步驟
1. 用 Reality Composer Pro 開 `PlantAnchor`（開 Package.realitycomposerpro 或其 Swift package）。
2. 開 `Scene.usda`。若場景空：把 `馬纓丹_已原點.usdz` 拖進 `Root`，Inspector 確認 Transform 為 identity。
3. 每朵外圍可見的花：工具列 Insert → Transform，於 Hierarchy 雙擊改名 `anchor_flower`（首個）/`anchor_flower_1`…，用 gizmo 把它移到那朵花上。
4. 每片外圍可見的葉：Insert → Transform，改名 `anchor_leaf`/`anchor_leaf_1`…，移到那片葉上。
5. Cmd+S 存檔。

## 抽座標並更新 catalog
6. 終端機執行：
   `swift Scripts/extract_anchors.swift PlantAnchor/Sources/PlantAnchor/PlantAnchor.rkassets/Scene.usda`
7. 把輸出的 `points: [...]` 分別貼進 `PartAnchor.swift` 的 `SpatialLabelCatalog`
   對應 `PartAnchor(part: .flower, ...)` / `(part: .leaf, ...)` 的 `points`。
   （`labelOffset` 維持/微調，`part` 不變。）
8. 重新 build，實機確認 callout 落在正確的花/葉上。

## 微調
- 若整片標籤一致偏移一個常數 → 調該 profile 的 `frameCorrection`。
- 標籤外推方向/距離 → 調該 `PartAnchor` 的 `labelOffset`。
```

- [ ] **Step 2: Commit**
```bash
git add docs/superpowers/rcp-anchor-marking-guide.md
git commit -m "docs: 新增 RCP 花/葉錨點標記操作指南"
```

---

## 附錄 A：程式化脈動 fallback（僅當烘焙動畫 clone 後不動時）

把 `makeCallout` 內的 `playAllAnimations(on: clone)` 換成下列程式化動畫（脈動 + 光暈旋轉），不依賴 USD 烘焙動畫：
```swift
// 脈動：marker 整體 scale 1.0↔1.12，3 秒循環
var pulseUp = clone.transform; pulseUp.scale = SIMD3<Float>(repeating: 1.12)
if let pulse = try? AnimationResource.generate(with: FromToByAnimation(
        from: clone.transform, to: pulseUp,
        duration: 1.5, timing: .easeInOut, isAdditive: false,
        bindTarget: .transform).repeatingForever(autoreverses: true)) {
    clone.playAnimation(pulse)
}
// 光暈旋轉：Halo 繞 Y 軸
if let halo = clone.findEntity(named: "Halo") {
    var spun = halo.transform; spun.rotation = simd_quatf(angle: .pi, axis: [0,1,0])
    if let spin = try? AnimationResource.generate(with: FromToByAnimation(
            from: halo.transform, to: spun,
            duration: 3.0, timing: .linear, isAdditive: false,
            bindTarget: .transform).repeatingForever(autoreverses: false)) {
        halo.playAnimation(spin)
    }
}
```

---

## Self-Review 結果
- **Spec 覆蓋**：parser(§5.4)→T1；NearestPartSelector(§5.3)→T2；資料/PlantDatabase(§5.1)→T3；Xcode 接線(§5.5)→T4；渲染 makeCallout(§5.2)→T5；選取整合(§5.3)→T6；View 切換+清理→T7；RCP 指南(§7)→T8。錯誤處理(§8)落在 T5 fallback、T6 隱藏邏輯、T7 檢查表。測試(§9)落在 T1/T2/附錄。皆有對應任務。
- **Placeholder**：除 T3 Plant 欄位需「依現有格式補齊」（已明確要求先讀檔對齊、不可留空）外無 TBD。
- **型別一致**：`makeCallout`、`loadMarkerTemplates`、`playAllAnimations`、`refreshCallouts`、`bindCallouts`、`PlantCalloutBinding`、`NearestPartSelector.select`、`updateSubscription` 命名跨任務一致。
- **已知風險**：USD 動畫 clone 行為（附錄 A 備援）、`Bundle.module` 解析（T4 Step 2 備援）、`PlantVision` scheme 未共用（T7 Step 4 備註）。
