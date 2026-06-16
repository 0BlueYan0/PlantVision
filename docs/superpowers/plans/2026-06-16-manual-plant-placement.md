# 手動擺放植物 + 無追蹤空間標籤 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「生長動畫」分頁換成「手動擺放」——使用者把馬纓丹 3D 模型準確放在面前地板上、沿地板拖曳,花/葉空間標籤動態指向最近部位,完全不需物件追蹤。

**Architecture:** 新增一個獨立、不碰 ObjectTracking 的 immersive space(`PlantVisionPlacementImmersiveSpace`),由「擺放」分頁的 2D 面板開啟。`ManualPlacementSceneView` 載入 `馬纓丹_已原點.usdz`,用 `PlaneDetectionProvider` 找地板貼地放置,用 `WorldTrackingProvider` 取頭部位置每幀重選最近花/葉 callout(沿用純函式 `NearestPartSelector` 與 `SpatialLabelBuilder`)。現有掃描/追蹤路徑零改動。

**Tech Stack:** Swift, SwiftUI, RealityKit, ARKit(`WorldTrackingProvider` + `PlaneDetectionProvider`),visionOS。專案以**手動 file reference** 管理 `PlantVision.xcodeproj/project.pbxproj`(非同步群組),新增/刪除 Swift 檔都要手動改 pbxproj。

**Spec:** `docs/superpowers/specs/2026-06-16-manual-plant-placement-design.md`

---

## 驗證方式說明(務必先讀)

- 本 app target **沒有單元測試基礎建設**(XCTest 只在 MacFrameRelay 套件,純函式 `NearestPartSelector` 已被沿用且不改),且本功能幾乎全是 RealityKit/ARKit 整合碼,無法用單元測試覆蓋。
- 因此**每個 task 的驗證 = 編譯成功 + 最後一個 task 在 visionOS 模擬器手動 smoke test**。
- 編譯指令(每個 task 結尾跑):
  ```bash
  xcodebuild -project PlantVision.xcodeproj -scheme PlantVision \
    -destination 'generic/platform=visionOS Simulator' build
  ```
  預期:`** BUILD SUCCEEDED **`。
- 開工前先確認 scheme 名稱:
  ```bash
  xcodebuild -list -project PlantVision.xcodeproj
  ```
  預期 Schemes 內含 `PlantVision`(若不同名,後續指令的 `-scheme` 改成實際名稱)。

## 檔案結構

| 檔案 | 動作 | 責任 |
|---|---|---|
| `PlantVision/Stores/PlantVisionModel.swift` | 修改 | 加 `placementImmersiveSpaceID` 常數 + 重置訊號 token |
| `PlantVision/Spatial/ManualPlacementController.swift` | 新增 | 位置邏輯:plane→地板高度、貼地放置、拖曳 Y 鎖定、最近 callout 選取 |
| `PlantVision/Views/ManualPlacementSceneView.swift` | 新增 | immersive RealityView:載入模型、掛 callout、拖曳手勢、狀態標籤 |
| `PlantVision/Views/ManualPlacementView.swift` | 新增 | 「擺放」分頁 2D 控制面板:開/關空間、重置位置、說明 |
| `PlantVision/PlantVisionApp.swift` | 修改 | 註冊第二個 `ImmersiveSpace` |
| `PlantVision/Views/RootView.swift` | 修改 | `WorkbenchSection.growth` → `.place`,渲染 `ManualPlacementView` |
| `PlantVision/Views/GrowthView.swift` | 刪除 | 連同只它用到的 `PlantIllustration` |
| `PlantVision.xcodeproj/project.pbxproj` | 修改 | 註冊 3 個新檔、移除 GrowthView 4 筆 |

**UUID 配置(沿用既有手編序號規則,經確認未被使用):**

| 檔案 | PBXBuildFile UUID | PBXFileReference UUID |
|---|---|---|
| `Spatial/ManualPlacementController.swift` | `8A1000132C00000100000001` | `8A2000162C00000100000001` |
| `Views/ManualPlacementSceneView.swift` | `8A1000142C00000100000001` | `8A2000172C00000100000001` |
| `Views/ManualPlacementView.swift` | `8A1000152C00000100000001` | `8A2000182C00000100000001` |

---

### Task 1: PlantVisionModel — 加擺放空間 id 與重置訊號

**Files:**
- Modify: `PlantVision/Stores/PlantVisionModel.swift`

- [ ] **Step 1: 加擺放 immersive space id 常數**

在 `static let immersiveSpaceID = "PlantVisionImmersiveSpace"` 那行下方,加一行(檔案約第 5 行):

找到:
```swift
    static let immersiveSpaceID = "PlantVisionImmersiveSpace"
    static let plantDetailWindowID = "PlantVisionPlantDetailWindow"
```
改成:
```swift
    static let immersiveSpaceID = "PlantVisionImmersiveSpace"
    static let placementImmersiveSpaceID = "PlantVisionPlacementImmersiveSpace"
    static let plantDetailWindowID = "PlantVisionPlantDetailWindow"
```

- [ ] **Step 2: 加重置訊號 published 屬性**

找到:
```swift
    @Published var selectedStage: GrowthStage = .sprout
    @Published var isGrowthPlaying = false
```
改成(在其後加一行):
```swift
    @Published var selectedStage: GrowthStage = .sprout
    @Published var isGrowthPlaying = false
    /// 「擺放」面板 → 場景的重置訊號;遞增即要求把植物拉回使用者面前的地板。
    @Published private(set) var placementResetToken: Int = 0
```

- [ ] **Step 3: 加重置方法**

找到:
```swift
    func toggleGrowthPlayback() {
```
在它前面加:
```swift
    /// 「擺放」分頁按「拉回面前」時呼叫;場景以 onChange 觀察 token 變化後重新放置。
    func requestPlacementReset() {
        placementResetToken += 1
    }

    func toggleGrowthPlayback() {
```

- [ ] **Step 4: 編譯驗證**

Run:
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add PlantVision/Stores/PlantVisionModel.swift
git commit -m "feat(placement): PlantVisionModel 加擺放空間 id 與重置訊號"
```

---

### Task 2: ManualPlacementController（位置/地板/最近選取邏輯）

**Files:**
- Create: `PlantVision/Spatial/ManualPlacementController.swift`
- Modify: `PlantVision.xcodeproj/project.pbxproj`

- [ ] **Step 1: 建立 controller 檔案**

建立 `PlantVision/Spatial/ManualPlacementController.swift`,內容:

```swift
import ARKit
import RealityKit
import QuartzCore
import simd

/// 「手動擺放」場景的位置邏輯:用 PlaneDetection 找地板、把模型貼地放在使用者面前,
/// 並用 WorldTracking 的頭部位置每幀重選最近花/葉 callout。完全不依賴 ObjectTracking。
@MainActor
final class ManualPlacementController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case needsAuthorization   // 世界感測權限被拒(改用 fallback 地板)
        case locatingFloor        // 已啟動平面偵測,尚未找到地板
        case ready                // 地板就緒(或模擬器 fallback),可操作
        case failed(String)
    }

    /// 一株植物的候選點與對應 callout 實體(刻意不引用 ObjectTrackingController 的同名型別,保持解耦)。
    struct CalloutBinding {
        let flowerPoints: [SIMD3<Float>]
        let leafPoints: [SIMD3<Float>]
        let flowerCallout: Entity
        let leafCallout: Entity
    }

    @Published private(set) var phase: Phase = .idle

    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])

    private var root: Entity?
    private var binding: CalloutBinding?
    /// 模型底部相對 root 原點的 Y(由場景算 visualBounds 提供),用來讓底部剛好踩地。
    private var baseOffset: Float = 0
    /// 偵測到的地板世界 Y;nil = 尚未取得,用 fallback。
    private var floorHeight: Float?
    /// 已鎖定 .floor 分類的平面後,只有 .floor 平面能再更新地板高度。
    private var floorLocked = false
    private let fallbackFloor: Float = 0
    /// 起始放置時,植物離使用者前方距離(公尺)。
    private let spawnDistance: Float = 1.0

    // 最近選取狀態(帶遲滯)。
    private var selectionFlower: Int?
    private var selectionLeaf: Int?
    private let switchMargin: Float = 0.05

    /// 保留 RealityView scene-update 訂閱,避免被釋放。
    var updateSubscription: EventSubscription?

    /// View 在建好場景後注入 draggable root、callout binding、貼地偏移。
    func bind(root: Entity, binding: CalloutBinding, baseOffset: Float) {
        self.root = root
        self.binding = binding
        self.baseOffset = baseOffset
        root.isEnabled = false   // 地板/位置確定前先隱藏
    }

    /// 拖曳手勢用:植物 root 應鎖定的世界 Y(地板高度扣掉貼地偏移)。
    func floorLockedY() -> Float {
        (floorHeight ?? fallbackFloor) - baseOffset
    }

    func start() async {
        let auths = WorldTrackingProvider.requiredAuthorizations + PlaneDetectionProvider.requiredAuthorizations
        let status = await session.requestAuthorization(for: auths)
        guard status.values.allSatisfy({ $0 == .allowed }) else {
            phase = .needsAuthorization
            floorHeight = fallbackFloor
            placeInFront()
            return
        }

        if PlaneDetectionProvider.isSupported {
            do {
                try await session.run([worldTracking, planeDetection])
            } catch {
                phase = .failed("啟動 ARKit session 失敗:\(error.localizedDescription)")
                floorHeight = fallbackFloor
                placeInFront()
                return
            }
            phase = .locatingFloor
            placeInFront()   // 先用 fallback 高度放,偵測到地板再校正 Y
            for await update in planeDetection.anchorUpdates {
                handlePlane(update)
            }
        } else {
            // 模擬器:無平面偵測,只跑頭部追蹤 + fallback 地板。
            try? await session.run([worldTracking])
            floorHeight = fallbackFloor
            phase = .ready
            placeInFront()
        }
    }

    func stop() {
        session.stop()
    }

    /// 重置:把植物重新放回使用者面前的地板。
    func resetPosition() {
        placeInFront()
    }

    /// 依當下頭部位置,把花/葉 callout 移到最近候選(帶遲滯)。由 SceneEvents.Update 每幀呼叫。
    func refreshCallouts() {
        guard let root, root.isEnabled, let b = binding,
              let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let h = device.originFromAnchorTransform.columns.3
        let headWorld = SIMD3<Float>(h.x, h.y, h.z)
        let m = root.transform.matrix
        func world(_ pts: [SIMD3<Float>]) -> [SIMD3<Float>] {
            pts.map { p in
                let w = m * SIMD4<Float>(p.x, p.y, p.z, 1)
                return SIMD3<Float>(w.x, w.y, w.z)
            }
        }
        let f = NearestPartSelector.select(candidatesWorld: world(b.flowerPoints),
                                           headWorld: headWorld, current: selectionFlower, switchMargin: switchMargin)
        let l = NearestPartSelector.select(candidatesWorld: world(b.leafPoints),
                                           headWorld: headWorld, current: selectionLeaf, switchMargin: switchMargin)
        selectionFlower = f
        selectionLeaf = l
        if let f { b.flowerCallout.position = b.flowerPoints[f]; b.flowerCallout.isEnabled = true }
        else { b.flowerCallout.isEnabled = false }
        if let l { b.leafCallout.position = b.leafPoints[l]; b.leafCallout.isEnabled = true }
        else { b.leafCallout.isEnabled = false }
    }

    // MARK: - Private

    private func handlePlane(_ update: AnchorUpdate<PlaneAnchor>) {
        guard update.event != .removed else { return }
        let anchor = update.anchor
        guard anchor.alignment == .horizontal else { return }
        let y = anchor.originFromAnchorTransform.columns.3.y
        if anchor.classification == .floor {
            floorLocked = true
            setFloor(y)                                   // 地板分類最權威
        } else if !floorLocked, floorHeight == nil || y < floorHeight! {
            setFloor(y)                                   // 尚無地板時,取目前最低的水平面當估計
        }
    }

    private func setFloor(_ y: Float) {
        floorHeight = y
        phase = .ready
        if let root { root.position.y = floorLockedY() } // 只校正高度,X/Z 維持
    }

    /// 把 root 放到使用者面前的地板:頭部水平位置 + 朝向前方 spawnDistance,Y = 地板高度 − 貼地偏移。
    private func placeInFront() {
        guard let root else { return }
        var x: Float = 0
        var z: Float = -spawnDistance
        if let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let m = device.originFromAnchorTransform
            let pos = m.columns.3
            var fwd = SIMD3<Float>(-m.columns.2.x, 0, -m.columns.2.z)   // 頭部前方投影到水平面
            fwd = simd_length(fwd) > 1e-4 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, -1)
            x = pos.x + fwd.x * spawnDistance
            z = pos.z + fwd.z * spawnDistance
        }
        root.position = SIMD3<Float>(x, floorLockedY(), z)
        root.isEnabled = true
    }
}
```

- [ ] **Step 2: 在 pbxproj 註冊 — PBXBuildFile**

找到這行(PlantTracker referenceobject 的 build file,在 `PBXBuildFile` 區段末):
```
		8A1000122C00000100000001 /* Resources/PlantTracker.referenceobject in Resources */ = {isa = PBXBuildFile; fileRef = 8A2000152C00000100000001 /* Resources/PlantTracker.referenceobject */; };
```
在它**後面**插入:
```
		8A1000132C00000100000001 /* Spatial/ManualPlacementController.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A2000162C00000100000001 /* Spatial/ManualPlacementController.swift */; };
```

- [ ] **Step 3: 在 pbxproj 註冊 — PBXFileReference**

找到這行(PlantTracker referenceobject 的 file ref):
```
		8A2000152C00000100000001 /* Resources/PlantTracker.referenceobject */ = {isa = PBXFileReference; lastKnownFileType = file.referenceobject; path = Resources/PlantTracker.referenceobject; sourceTree = "<group>"; };
```
在它**後面**插入:
```
		8A2000162C00000100000001 /* Spatial/ManualPlacementController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Spatial/ManualPlacementController.swift; sourceTree = "<group>"; };
```

- [ ] **Step 4: 在 pbxproj 註冊 — PBXGroup(PlantVision 群組)**

找到這行(群組內的 SpatialPartLabel):
```
				8A2000132C00000100000001 /* Views/SpatialPartLabel.swift */,
```
在它**後面**插入:
```
				8A2000162C00000100000001 /* Spatial/ManualPlacementController.swift */,
```

- [ ] **Step 5: 在 pbxproj 註冊 — PBXSourcesBuildPhase**

找到這行(Sources 階段的 SpatialPartLabel):
```
				8A1000102C00000100000001 /* Views/SpatialPartLabel.swift in Sources */,
```
在它**後面**插入:
```
				8A1000132C00000100000001 /* Spatial/ManualPlacementController.swift in Sources */,
```

- [ ] **Step 6: 編譯驗證(controller 可獨立編譯)**

Run:
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **`(若報 `PlaneDetectionProvider` / `PlaneAnchor` 相關 API 錯誤,表示該 visionOS SDK API 名稱有出入,對照 Xcode 自動完成修正後再 build)

- [ ] **Step 7: Commit**

```bash
git add PlantVision/Spatial/ManualPlacementController.swift PlantVision.xcodeproj/project.pbxproj
git commit -m "feat(placement): ManualPlacementController 地板偵測/貼地/最近選取"
```

---

### Task 3: ManualPlacementSceneView（immersive 場景 + 狀態標籤）

**Files:**
- Create: `PlantVision/Views/ManualPlacementSceneView.swift`
- Modify: `PlantVision.xcodeproj/project.pbxproj`

- [ ] **Step 1: 建立場景檔案**

建立 `PlantVision/Views/ManualPlacementSceneView.swift`,內容:

```swift
import ARKit
import RealityKit
import SwiftUI
import PlantAnchor

/// 「手動擺放」immersive 場景:載入植物 USDZ、貼地放在面前、可沿地板拖曳,
/// 花/葉空間標籤用頭部位置動態指向最近的一個。不需物件追蹤。
struct ManualPlacementSceneView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @StateObject private var controller = ManualPlacementController()

    private struct LabelSlot: Identifiable {
        let id: String
        let part: PlantPart
        let plant: Plant
    }

    private var profile: ReferenceObjectProfile? { SpatialLabelCatalog.profiles.first }

    private var plant: Plant {
        guard let id = profile?.plantID, let p = PlantDatabase.plant(id: id) else {
            return PlantDatabase.primaryPlant
        }
        return p
    }

    private var labelSlots: [LabelSlot] {
        (profile?.parts ?? []).map { anchor in
            LabelSlot(id: "place-label-\(anchor.part.rawValue)", part: anchor.part, plant: plant)
        }
    }

    var body: some View {
        RealityView { content, attachments in
            let templates = await SpatialLabelBuilder.loadMarkerTemplates()

            let root = Entity()
            root.name = "placement-root"

            // 載入植物模型,加為 root 子節點,並算出底部偏移(讓底部踩地)。
            var baseOffset: Float = 0
            if let model = try? await Entity(named: "馬纓丹_已原點", in: plantAnchorBundle) {
                root.addChild(model)
                baseOffset = model.visualBounds(relativeTo: root).min.y
            }

            var flowerCallout: Entity?
            var leafCallout: Entity?
            var flowerPoints: [SIMD3<Float>] = []
            var leafPoints: [SIMD3<Float>] = []

            for anchor in profile?.parts ?? [] {
                let label = attachments.entity(for: "place-label-\(anchor.part.rawValue)")
                let callout = SpatialLabelBuilder.makeCallout(
                    part: anchor.part,
                    template: anchor.part == .flower ? templates.flower : templates.leaf,
                    label: label,
                    labelOffset: anchor.labelOffset)
                root.addChild(callout)
                switch anchor.part {
                case .flower: flowerCallout = callout; flowerPoints = anchor.points
                case .leaf:   leafCallout = callout;   leafPoints = anchor.points
                }
            }

            // 讓 root 可被拖曳:加碰撞形狀 + 輸入目標。
            let bounds = root.visualBounds(relativeTo: root)
            let shape = ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
            root.components.set(CollisionComponent(shapes: [shape]))
            root.components.set(InputTargetComponent())

            content.add(root)

            if let f = flowerCallout, let l = leafCallout {
                controller.bind(
                    root: root,
                    binding: .init(flowerPoints: flowerPoints, leafPoints: leafPoints,
                                   flowerCallout: f, leafCallout: l),
                    baseOffset: baseOffset)
            }

            controller.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                controller.refreshCallouts()
            }

            if let status = attachments.entity(for: "placement-status") {
                status.name = "placement-status"
                status.position = [0, 1.4, -1.2]
                content.add(status)
            }
        } update: { content, _ in
            // 就緒後把狀態提示收起來。
            if let status = content.entities.first(where: { $0.name == "placement-status" }) {
                status.isEnabled = (controller.phase != .ready)
            }
        } attachments: {
            ForEach(labelSlots) { slot in
                Attachment(id: slot.id) {
                    SpatialPartLabel(part: slot.part, plant: slot.plant)
                }
            }
            Attachment(id: "placement-status") {
                ManualPlacementStatusLabel(phase: controller.phase)
            }
        }
        // 沿地板拖曳:把拖曳點轉到場景座標,只取水平 X/Z,Y 永遠鎖在地面。
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == "placement-root" else { return }
                    let p = value.convert(value.location3D, from: .local, to: .scene)
                    value.entity.position = [p.x, controller.floorLockedY(), p.z]
                }
        )
        .task { await controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: appModel.placementResetToken) { _, _ in
            controller.resetPosition()
        }
    }
}

/// 擺放場景的狀態提示,固定浮在使用者前方。
struct ManualPlacementStatusLabel: View {
    let phase: ManualPlacementController.Phase

    private var text: String {
        switch phase {
        case .idle: "準備中…"
        case .needsAuthorization: "需要「世界感測」權限才能偵測地板,目前用預設地板高度。可到設定開啟。"
        case .locatingFloor: "正在尋找地板…請看向地面一兩秒。"
        case .ready: "已就緒。捏住植物可沿地板拖曳移動。"
        case .failed(let reason): "啟動失敗:\(reason)"
        }
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: 360)
            .glassBackgroundEffect()
    }
}
```

- [ ] **Step 2: 在 pbxproj 註冊 — PBXBuildFile**

找到剛在 Task 2 加的這行:
```
		8A1000132C00000100000001 /* Spatial/ManualPlacementController.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A2000162C00000100000001 /* Spatial/ManualPlacementController.swift */; };
```
在它**後面**插入:
```
		8A1000142C00000100000001 /* Views/ManualPlacementSceneView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A2000172C00000100000001 /* Views/ManualPlacementSceneView.swift */; };
```

- [ ] **Step 3: 在 pbxproj 註冊 — PBXFileReference**

找到 Task 2 加的:
```
		8A2000162C00000100000001 /* Spatial/ManualPlacementController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Spatial/ManualPlacementController.swift; sourceTree = "<group>"; };
```
在它**後面**插入:
```
		8A2000172C00000100000001 /* Views/ManualPlacementSceneView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/ManualPlacementSceneView.swift; sourceTree = "<group>"; };
```

- [ ] **Step 4: 在 pbxproj 註冊 — PBXGroup**

找到 Task 2 加的:
```
				8A2000162C00000100000001 /* Spatial/ManualPlacementController.swift */,
```
在它**後面**插入:
```
				8A2000172C00000100000001 /* Views/ManualPlacementSceneView.swift */,
```

- [ ] **Step 5: 在 pbxproj 註冊 — PBXSourcesBuildPhase**

找到 Task 2 加的:
```
				8A1000132C00000100000001 /* Spatial/ManualPlacementController.swift in Sources */,
```
在它**後面**插入:
```
				8A1000142C00000100000001 /* Views/ManualPlacementSceneView.swift in Sources */,
```

- [ ] **Step 6: 編譯驗證**

Run:
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **`(若 `value.convert(... .local ... .scene)` 報錯,改用 Apple 範例慣例:`value.convert(value.location3D, from: .local, to: value.entity.parent!)`,語意相同)

- [ ] **Step 7: Commit**

```bash
git add PlantVision/Views/ManualPlacementSceneView.swift PlantVision.xcodeproj/project.pbxproj
git commit -m "feat(placement): ManualPlacementSceneView immersive 場景 + 狀態標籤"
```

---

### Task 4: ManualPlacementView（「擺放」分頁 2D 面板）

**Files:**
- Create: `PlantVision/Views/ManualPlacementView.swift`
- Modify: `PlantVision.xcodeproj/project.pbxproj`

- [ ] **Step 1: 建立面板檔案**

建立 `PlantVision/Views/ManualPlacementView.swift`,內容:

```swift
import SwiftUI

/// 「擺放」分頁:手動把 3D 植物模型放到地板上(不需物件追蹤)的 2D 控制面板。
struct ManualPlacementView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var isSpaceOpen = false

    var body: some View {
        NavigationStack {
            HStack(spacing: 24) {
                preview
                controls
            }
            .padding(28)
            .navigationTitle("擺放")
        }
    }

    private var preview: some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 120))
                .foregroundStyle(.green)
                .padding()
            Text("手動擺放植物")
                .font(.largeTitle.weight(.bold))
            Text("把馬纓丹的 3D 模型放到你面前的地板上;靠近不同部位時,花/葉空間標籤會自動指向最近的那一個。不需要掃描或物件追蹤。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .glassBackgroundEffect()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("擺放控制")
                .font(.title2.weight(.semibold))

            Button {
                Task {
                    await dismissImmersiveSpace()   // 關掉任何已開的空間,避免衝突
                    let result = await openImmersiveSpace(id: PlantVisionModel.placementImmersiveSpaceID)
                    isSpaceOpen = (result == .opened)
                }
            } label: {
                Label("開啟空間並擺放", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                appModel.requestPlacementReset()
            } label: {
                Label("把植物拉回面前", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isSpaceOpen)

            Button {
                Task {
                    await dismissImmersiveSpace()
                    isSpaceOpen = false
                }
            } label: {
                Label("關閉空間", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isSpaceOpen)

            Divider()

            Label("拖曳植物可沿地板移動位置", systemImage: "hand.draw")
            Label("實機會貼合真實地板;模擬器用預設地板高度", systemImage: "ruler")
            Label("花/葉標籤指向離你最近的部位", systemImage: "tag")
        }
        .font(.callout)
        .frame(width: 360, alignment: .leading)
        .padding(22)
        .glassBackgroundEffect()
    }
}
```

- [ ] **Step 2: 在 pbxproj 註冊 — PBXBuildFile**

找到 Task 3 加的:
```
		8A1000142C00000100000001 /* Views/ManualPlacementSceneView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A2000172C00000100000001 /* Views/ManualPlacementSceneView.swift */; };
```
在它**後面**插入:
```
		8A1000152C00000100000001 /* Views/ManualPlacementView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A2000182C00000100000001 /* Views/ManualPlacementView.swift */; };
```

- [ ] **Step 3: 在 pbxproj 註冊 — PBXFileReference**

找到 Task 3 加的:
```
		8A2000172C00000100000001 /* Views/ManualPlacementSceneView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/ManualPlacementSceneView.swift; sourceTree = "<group>"; };
```
在它**後面**插入:
```
		8A2000182C00000100000001 /* Views/ManualPlacementView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/ManualPlacementView.swift; sourceTree = "<group>"; };
```

- [ ] **Step 4: 在 pbxproj 註冊 — PBXGroup**

找到 Task 3 加的:
```
				8A2000172C00000100000001 /* Views/ManualPlacementSceneView.swift */,
```
在它**後面**插入:
```
				8A2000182C00000100000001 /* Views/ManualPlacementView.swift */,
```

- [ ] **Step 5: 在 pbxproj 註冊 — PBXSourcesBuildPhase**

找到 Task 3 加的:
```
				8A1000142C00000100000001 /* Views/ManualPlacementSceneView.swift in Sources */,
```
在它**後面**插入:
```
				8A1000152C00000100000001 /* Views/ManualPlacementView.swift in Sources */,
```

- [ ] **Step 6: 編譯驗證**

Run:
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add PlantVision/Views/ManualPlacementView.swift PlantVision.xcodeproj/project.pbxproj
git commit -m "feat(placement): ManualPlacementView 擺放分頁 2D 控制面板"
```

---

### Task 5: 在 App 註冊第二個 ImmersiveSpace

**Files:**
- Modify: `PlantVision/PlantVisionApp.swift`

- [ ] **Step 1: 加入擺放用 ImmersiveSpace**

找到:
```swift
        ImmersiveSpace(id: PlantVisionModel.immersiveSpaceID) {
            SpatialPlantSceneView()
                .environmentObject(appModel)
        }
    }
}
```
改成:
```swift
        ImmersiveSpace(id: PlantVisionModel.immersiveSpaceID) {
            SpatialPlantSceneView()
                .environmentObject(appModel)
        }

        ImmersiveSpace(id: PlantVisionModel.placementImmersiveSpaceID) {
            ManualPlacementSceneView()
                .environmentObject(appModel)
        }
    }
}
```

- [ ] **Step 2: 編譯驗證**

Run:
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PlantVision/PlantVisionApp.swift
git commit -m "feat(placement): App 註冊擺放用 ImmersiveSpace"
```

---

### Task 6: RootView 把 Growth 分頁換成 Place

**Files:**
- Modify: `PlantVision/Views/RootView.swift`

- [ ] **Step 1: 改 sectionContent 的 case**

找到:
```swift
        case .growth:
            GrowthView()
```
改成:
```swift
        case .place:
            ManualPlacementView()
```

- [ ] **Step 2: 改列舉 case 名稱**

找到:
```swift
private enum WorkbenchSection: String, CaseIterable, Identifiable {
    case scan
    case detail
    case growth
    case history
```
改成:
```swift
private enum WorkbenchSection: String, CaseIterable, Identifiable {
    case scan
    case detail
    case place
    case history
```

- [ ] **Step 3: 改 title**

找到:
```swift
        case .scan: "Scan"
        case .detail: "Detail"
        case .growth: "Growth"
        case .history: "History"
```
改成:
```swift
        case .scan: "Scan"
        case .detail: "Detail"
        case .place: "Place"
        case .history: "History"
```

- [ ] **Step 4: 改 systemImage**

找到:
```swift
        case .scan: "viewfinder"
        case .detail: "leaf"
        case .growth: "cube"
        case .history: "clock.arrow.circlepath"
```
改成:
```swift
        case .scan: "viewfinder"
        case .detail: "leaf"
        case .place: "move.3d"
        case .history: "clock.arrow.circlepath"
```

- [ ] **Step 5: 改 accessibilityLabel**

找到:
```swift
        case .scan: "開啟掃描工作區"
        case .detail: "開啟植物資訊"
        case .growth: "開啟生長動畫"
        case .history: "開啟歷史紀錄"
```
改成:
```swift
        case .scan: "開啟掃描工作區"
        case .detail: "開啟植物資訊"
        case .place: "開啟手動擺放工作區"
        case .history: "開啟歷史紀錄"
```

- [ ] **Step 6: 編譯驗證(此時 GrowthView 仍存在,只是不再被引用)**

Run:
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add PlantVision/Views/RootView.swift
git commit -m "feat(placement): RootView Growth 分頁改為 Place(手動擺放)"
```

---

### Task 7: 刪除 GrowthView 並清掉 pbxproj 殘留

**Files:**
- Delete: `PlantVision/Views/GrowthView.swift`
- Modify: `PlantVision.xcodeproj/project.pbxproj`

- [ ] **Step 1: 確認沒有殘留引用**

Run:
```bash
grep -rn "GrowthView\|PlantIllustration" PlantVision/ || echo "無殘留引用"
```
Expected: 只剩 `PlantVision/Views/GrowthView.swift` 自己(或顯示「無殘留引用」)。若 `RootView` 還有引用,回到 Task 6 修正。

- [ ] **Step 2: 刪除檔案**

Run:
```bash
git rm PlantVision/Views/GrowthView.swift
```

- [ ] **Step 3: 移除 pbxproj — PBXBuildFile 行**

刪除這一整行:
```
		8A1000092C00000100000001 /* Views/GrowthView.swift in Sources */ = {isa = PBXBuildFile; fileRef = 8A2000092C00000100000001 /* Views/GrowthView.swift */; };
```

- [ ] **Step 4: 移除 pbxproj — PBXFileReference 行**

刪除這一整行:
```
		8A2000092C00000100000001 /* Views/GrowthView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/GrowthView.swift; sourceTree = "<group>"; };
```

- [ ] **Step 5: 移除 pbxproj — PBXGroup 行**

刪除這一整行:
```
				8A2000092C00000100000001 /* Views/GrowthView.swift */,
```

- [ ] **Step 6: 移除 pbxproj — PBXSourcesBuildPhase 行**

刪除這一整行:
```
				8A1000092C00000100000001 /* Views/GrowthView.swift in Sources */,
```

- [ ] **Step 7: 編譯驗證**

Run:
```bash
xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'generic/platform=visionOS Simulator' build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(placement): 移除 GrowthView 與 pbxproj 殘留"
```

---

### Task 8: 模擬器手動 smoke test 與微調

**Files:**
- 可能微調:`PlantVision/Spatial/ManualPlacementController.swift`(`spawnDistance`),`PlantVision/Views/ManualPlacementSceneView.swift`(模型大小/位置)

- [ ] **Step 1: 在 visionOS 模擬器執行 app**

用 Xcode 開 `PlantVision.xcodeproj`,選 visionOS 模擬器 run(或 `xcodebuild ... -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build`,再從模擬器啟動)。

- [ ] **Step 2: 驗證互動流程**

逐項確認(模擬器走 fallback 地板 y=0):
- 左側工作列出現「Place」分頁(圖示 `move.3d`),點開是「擺放」面板,**Growth 分頁已消失**。
- 按「開啟空間並擺放」→ 進入 immersive,馬纓丹模型出現在面前、**站在地面(底部不穿地、不懸浮過高)**。
- 模型上出現一個花 callout + 一個葉 callout(發光球 + 引線 + 文字標籤),文字為馬纓丹的花/葉說明。
- 移動視線(模擬器用滑鼠/WASD)靠近不同花/葉,callout 會切到最近的那一個。
- 用拖曳手勢移動模型,模型**沿地面平移、高度不變**;標籤跟著移動。
- 按「把植物拉回面前」→ 模型回到面前地面。
- 按「關閉空間」→ 退出 immersive。

- [ ] **Step 3: 微調(若需要)**

- 模型太遠/太近 → 調 `ManualPlacementController.spawnDistance`。
- 模型穿地或浮空(且 `馬纓丹_已原點.usdz` 原點不在底部)→ 確認 `baseOffset = model.visualBounds(relativeTo: root).min.y` 邏輯;必要時在場景對 model 設 `position.y` 校正。
- 模型過大/過小(USDZ 內含非 1 的 scale,導致標籤錨點對不上花葉)→ 在場景載入後對 model 設一致 scale,並注意錨點是物件 local 座標,scale 會一起影響,需同步驗證標籤位置。
- 標籤整片一致偏移 → 與追蹤版相同,屬常數平移,可在場景對 callout 群加共同位移(對應 spec 的 `frameCorrection` 概念)。

- [ ] **Step 4: 若有微調則 Commit**

```bash
git add -A
git commit -m "fix(placement): 模擬器驗證後微調模型位置/距離"
```

- [ ] **Step 5: 實機備註(無實機則略過)**

實機 Vision Pro 上 `PlaneDetectionProvider` 會生效:首次需授權「世界感測」;看向地面一兩秒後植物應吸附到真實地板高度。若拒絕授權,狀態標籤提示並退回 fallback 高度。

---

## Self-Review(計畫對照 spec)

**Spec 覆蓋檢查:**
- 範圍(獨立體驗、不動追蹤)→ Task 2–5 全走新檔/新 space,未改 `SpatialPlantSceneView`/`ObjectTrackingController`。✓
- 模型(馬纓丹 USDZ)→ Task 3 `Entity(named: "馬纓丹_已原點", in: plantAnchorBundle)`。✓
- 擺放(貼地、沿地板拖曳、Y 鎖定)→ Task 2 `floorLockedY()`/`placeInFront()`、Task 3 拖曳手勢鎖 Y。✓
- 標籤(最近花/葉動態)→ Task 2 `refreshCallouts()` 沿用 `NearestPartSelector`。✓
- 地板偵測(PlaneDetection + 模擬器 fallback)→ Task 2 `start()` 分支。✓
- 取代 Growth 分頁 → Task 6 改 `WorkbenchSection`、Task 7 刪 `GrowthView`。✓
- 保留 growth 模型/合成場景 → 未動 `PlantVisionModel` 的 `selectedStage`/playback、未動 `SyntheticPlantSceneView`。✓
- pbxproj 手動註冊 → Task 2–4 新增、Task 7 移除,UUID 明列。✓
- 重置位置 → Task 1 token、Task 3 `onChange` → `resetPosition()`、Task 4 按鈕。✓

**型別/命名一致性:** `placementImmersiveSpaceID`、`placementResetToken`、`requestPlacementReset()`、`ManualPlacementController`、`CalloutBinding`、`floorLockedY()`、`refreshCallouts()`、`placement-root`、`place-label-<part>`、`placement-status`、`ManualPlacementStatusLabel`、`WorkbenchSection.place` — 全計畫一致。✓

**已知風險(已在 Task 8 給對策):** visionOS plane/drag API 名稱細節、USDZ 內建 scale/原點是否為 1/底部、模擬器 WorldTracking 頭部 pose 是否可用。皆有 fallback 或微調步驟,不致卡死。
