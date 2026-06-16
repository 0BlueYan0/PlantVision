# 最近花/葉動態立體標記 — 設計稿

- 日期：2026-06-16
- 分支：`worktree-plantanchor-swap`
- 狀態：待 review

## 1. 目標與背景

在 Vision Pro 的真實植物追蹤畫面中，把目前扁平的小圓點標記，換成從
Reality Composer Pro 烘焙好的立體發光 callout（發光球 + 環繞光暈 + 脈動動畫 + 引線 + 資訊標籤），
讓花/葉標記更有空間立體感。

為避免畫面擁擠，每株植株上**恆定只顯示一個花 callout + 一個葉 callout**，
分別黏在「離使用者頭部最近」的那朵花 / 那片葉；使用者繞行時 callout 平滑換位。

## 2. 現況

### 程式碼
- `PlantVision/Views/SpatialPlantSceneView.swift`
  - `RealPlantTrackingView`：實機 ObjectTracking 路徑，本設計的改動範圍。
  - `SyntheticPlantSceneView`：模擬器 fallback，**不在範圍內**。
- `PlantVision/Spatial/SpatialLabelBuilder.swift`：`makeMarker`（扁平圓點）、`makeLeader`、`makePartGroup`、`smoothed`。
- `PlantVision/Spatial/ObjectTrackingController.swift`：跑 ARKitSession + `ObjectTrackingProvider`，平滑並驅動每株 root。
- `PlantVision/Spatial/PartAnchor.swift`：`PlantPart`、`PartAnchor`、`ReferenceObjectProfile`、`SpatialLabelCatalog`。
- runtime 視覺**目前全程式化**，未載入任何 usdz；app 端尚無 RealityKitContent bundle。

### 資產
- `PlantAnchor/Sources/PlantAnchor/PlantAnchor.rkassets/MarkerTemplate.usda`
  - `FlowerMarker` / `LeafMarker`，各含 `AnchorGlow`(球 r=0.02)、`Halo`(12 球環繞、`rotateY` 0→360 動畫)、
    `LeaderLine`(斜向圓柱)、`LabelBacking`(佔位四邊形)；marker 本身有 scale 脈動 1.0↔1.12（180 frame / 60fps = 3s 循環）。
- `PlantAnchor` 套件**尚未被加進 `PlantVision.xcodeproj`**；`Package.swift` 未宣告 `.rkassets` 為資源，
  故 `Bundle.module`（`plantAnchorBundle`）目前無法解析（既有問題）。

### 作廢資料
- `SpatialLabelCatalog.profiles` 的座標（花 25 點、葉 10 點）是**舊模型（日日春）**的，需整批以新馬纓丹模型重標。
- `PlantDatabase` 目前只有 `lobelia-erinus`、`catharanthus-roseus`，**無馬纓丹**。

## 3. 已確認的決策

1. **接入方式**：載入 RCP 模板 — 接 `PlantAnchor` 進 Xcode、runtime clone `FlowerMarker`/`LeafMarker`、播放烘焙動畫。
2. **顯示數量**：每部位一個 callout，移除扁平圓點。
3. **選取時機**：動態跟隨 — 顯示離使用者最近的花/葉，使用者移動時換位，帶遲滯防抖。
4. **Parser**：納入範圍 — 從 RCP `Scene.usda` 自動抽 anchor 座標填進 catalog。
5. **RCP 標記操作指南**：定義命名規範並於最後交付詳細步驟。

## 4. 架構總覽

五個關注點，邊界清楚、可獨立理解：

| 層 | 職責 | 主要檔案 |
|---|---|---|
| 資料層 | 候選花/葉座標、植株設定 | `PartAnchor.swift`（+ parser 產出） |
| 渲染層 | 載入模板、組裝 callout group | `SpatialLabelBuilder.swift`、`SpatialPlantSceneView.swift` |
| 選取層 | 取頭部位置、挑最近候選、遲滯、移動 callout | `ObjectTrackingController.swift` + 新純函式 |
| Parser | `Scene.usda` → 座標 | `Scripts/extract_anchors.swift`（新增） |
| Xcode 接線 | 讓 app 能載入 MarkerTemplate | `PlantVision.xcodeproj`、`PlantAnchor/Package.swift` |

## 5. 元件設計

### 5.1 資料層
- `PartAnchor.points` 語意更新：每個點 = **一朵花 / 一片葉的獨立位置**（候選），不再是點雲。
- `centroid`、`dotRadius` 退役（移除或標記 deprecated）。
- `labelOffset` 保留：決定資訊標籤相對 callout 外推的方向/距離。
- 新增馬纓丹 `Plant` 進 `PlantDatabase`，profile 的 `plantID` 指過去。

### 5.2 渲染層
- **模板載入（一次）**：`RealPlantTrackingView` 的 `RealityView` make 閉包（async）內
  `try? await Entity(named: "MarkerTemplate", in: plantAnchorBundle)`，取出 `FlowerMarker`/`LeafMarker`。
- **callout group 組裝**：新增
  `SpatialLabelBuilder.makeCallout(part:template:label:labelOffset:) -> Entity`
  - clone 模板（`clone(recursive: true)`），剝除子節點 `LeaderLine`、`LabelBacking`，本地 translate 歸零。
  - 加 `makeLeader(.zero → labelOffset)` 長引線。
  - 加 SwiftUI 資訊標籤（`SpatialPartLabel`，`BillboardComponent`）於 `labelOffset`。
  - 對 clone 播放其 `availableAnimations`（脈動 + Halo 旋轉），`.repeat()`。
  - group 的 `position` 由選取層每次更新（初始隱藏或置於第一候選）。
- 每株建兩個 callout group（flower、leaf），掛在 tracked root 下。
- **fallback**：模板載入失敗 → log + 退回簡化版程式化發光球（保留 `makeMarker` 精簡版），app 不空畫面。

### 5.3 選取層
- 在既有 ARKitSession 加 `WorldTrackingProvider`，以 `queryDeviceAnchor(atTimestamp:)` 取頭部世界 transform。
  （同一 session 的 provider 共用世界座標系，與 ObjectTracking 的物件 anchor 可直接比距離。）
- 新增純函式（比照 `smoothed`，可單元測試）：
  ```swift
  enum NearestPartSelector {
      /// 從候選世界座標中挑離 head 最近的 index，帶遲滯。
      /// - current: 目前選中 index（nil = 尚未選）
      /// - switchMargin: 另一候選需比目前近超過此值(公尺)才換手，避免抖動
      /// 回傳新的選中 index；無候選回 nil。
      static func select(candidatesWorld: [SIMD3<Float>],
                         headWorld: SIMD3<Float>,
                         current: Int?,
                         switchMargin: Float) -> Int?
  }
  ```
- controller 每次更新（節流 ~10–15Hz）對每株、每部位：
  1. 用 root 世界 transform 把候選 local 點轉世界座標。
  2. 取頭部世界座標。
  3. `NearestPartSelector.select(...)` 取選中 index（帶上次選擇做遲滯）。
  4. 設 `calloutGroup.position = localPoints[selected]`（group 是 root 子節點，自動跟追蹤框）。
  5. 無候選 / 尚無頭部位置 → `calloutGroup.isEnabled = false`。
- 預設參數（可調）：`switchMargin ≈ 0.05`（5cm）、更新率 ~10–15Hz。
- 綁定擴充：controller 需要每株的「候選 local 點（分花/葉）+ 對應 callout group」，
  由 View 在建場景時一併注入（擴充現有 `bind(roots:)`）。

### 5.4 Parser
- 新增 `Scripts/extract_anchors.swift`，以 `swift Scripts/extract_anchors.swift <Scene.usda>` 執行（免專案整合）。
- 讀 `.usda` 文字，比對 prim 名稱：
  - 花：符合 `^anchor_flower(_\d+)?$`
  - 葉：符合 `^anchor_leaf(_\d+)?$`
- 取各 prim 的 `float3 xformOp:translate`，輸出可貼進 `SpatialLabelCatalog` 的 Swift `points: [...]` 陣列文字（含數量統計）。
- 範圍內僅「輸出可貼上的陣列」；自動改寫 catalog 檔列為未來可選。

### 5.5 Xcode 接線（前置、風險最高）
- 把 `PlantAnchor` 加進 `PlantVision.xcodeproj` 當 local Swift Package 依賴，並連結到 app target。
- 修 `PlantAnchor/Package.swift` 讓 `.rkassets` 被當資源處理，使 `Bundle.module` 可解析（visionOS RealityKitContent 慣例）。
- 風險：pbxproj 程式化編輯易錯，可能需在 Xcode UI 手動加 package（與既有雙建置系統痛點一致）。
  此步驟若卡住會回報，不硬改。

## 6. 資料流

```
SpatialLabelCatalog.profiles
  └─(每 profile)→ tracked root（ObjectTracking 驅動，平滑）
        ├─ flowerCallout group ─ clone FlowerMarker(發光球+光暈+脈動) + 長引線 + SwiftUI 花標籤
        └─ leafCallout   group ─ clone LeafMarker  + 長引線 + SwiftUI 葉標籤

每 ~10–15Hz：
  headWorld ← WorldTrackingProvider
  for 部位 in [flower, leaf]:
     candidatesWorld ← rootWorldTransform × points
     idx ← NearestPartSelector.select(candidatesWorld, headWorld, current, margin)
     calloutGroup.position ← points[idx]   (或 isEnabled=false)
```

## 7. RCP 標記工作流（命名規範 + 步驟）

**命名規範（parser 依此辨識，務必遵守）**
- 花的錨點：`anchor_flower`、`anchor_flower_1`、`anchor_flower_2`…（第一個無數字後綴）
- 葉的錨點：`anchor_leaf`、`anchor_leaf_1`、`anchor_leaf_2`…
- 每個錨點 = 一個空 `Transform`，擺在一朵花/一片葉的位置。

**座標系前提**
- 錨點座標必須與追蹤用的 `.referenceobject` **同一座標系**。
- 作法：把 `馬纓丹_已原點.usdz` 以 **identity transform**（translate 0,0,0、無旋轉縮放）放在 `Root` 下，
  所有 `anchor_*` 直接當 `Root` 的子節點 → 其 `translate` 即模型 local 座標（公尺），與 referenceobject 一致。

**步驟（細節於最後交付時再完整說明一次）**
1. 用 RCP 開 `PlantAnchor` 套件，開 `Scene.usda`。
2. 若場景沒有模型：把 `馬纓丹_已原點.usdz` 拖進 `Root`，確認其 Transform 為 identity。
3. 對每朵外圍可見的花：Insert → Transform，命名 `anchor_flower`(首個)/`anchor_flower_1`…，用 gizmo 移到該花上。
4. 對每片外圍可見的葉：Insert → Transform，命名 `anchor_leaf`/`anchor_leaf_1`…，移到該葉上。
5. 存檔（Cmd+S）。
6. 執行 `swift Scripts/extract_anchors.swift <Scene.usda 路徑>`，把輸出貼進 `SpatialLabelCatalog`。

## 8. 錯誤處理
- 模板載入失敗 → log + 程式化發光球 fallback。
- 候選為空 / 尚無頭部位置 → 該 callout 隱藏。
- 找不到模板子節點 `FlowerMarker`/`LeafMarker` → log + fallback。
- Parser 找不到任何 anchor → 印警告與 0 計數，不產出空陣列覆蓋。

## 9. 測試策略
- 純函式單元測試：`NearestPartSelector.select`（含遲滯：等距不換手、超過 margin 才換、空候選回 nil）、
  既有 `smoothed`、`makeLeader` 幾何。
- Parser：對一份小型 `.usda` fixture 驗證解析出的座標與數量。
- clone / 動畫 / ARKit 頭部追蹤：屬 RealityKit + 實機，靠 Vision Pro 視覺驗證（CI 無法測）。

## 10. 不做（YAGNI）
- 模擬器合成場景（`SyntheticPlantSceneView`）。
- 手勢切換候選、每點都顯示 callout、模板自帶 LabelBacking 當文字。
- 動態（即時影像）偵測花/葉位置；仍用烘焙座標。
- Parser 自動改寫 catalog 檔（先只輸出貼上用文字）。

## 11. 前置 / 開放項目
- **前置**：Xcode 接線完成、`PlantAnchor` 套件可載入（否則 runtime 載不到模板）。
- **資料刷新**（與程式平行）：新馬纓丹座標、`PlantDatabase` 加馬纓丹、profile `plantID` 更新、
  確認 `.referenceobject`（追蹤用）與新模型一致。
- 程式可先以結構與舊/假座標完成並編譯；正確視覺需等新座標就位。
