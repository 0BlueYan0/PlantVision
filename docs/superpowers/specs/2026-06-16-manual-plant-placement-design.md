# 手動擺放植物 + 無追蹤空間標籤 — 設計文件

- 日期:2026-06-16
- 平台:visionOS (Vision Pro)
- 狀態:設計已核可,待產出實作計畫

## 目標

把現有的「生長動畫」(Growth)分頁替換成一個**手動擺放**體驗:使用者把一個 3D 植物模型放進空間、可拖曳移動,並在模型上直接顯示花/葉空間標籤。整個體驗**不需要物件追蹤 (ObjectTracking)**。

## 背景與現況

- `RootView` 左側工作列有四個分頁:Scan / Detail / **Growth(生長動畫)** / History。
- `GrowthView` 是純 2D 視窗頁,只切換 `GrowthStage`(發芽→長葉→開花→成熟)並播放示意動畫,不涉及空間。
- Immersive 空間 `SpatialPlantSceneView` 會分支:
  - 支援 ObjectTracking → `RealPlantTrackingView`(追蹤真實盆栽 + 烘焙錨點)。
  - 否則 → `SyntheticPlantSceneView`(程式化合成植物,依 `selectedStage`)。
- 既有可重用資產:
  - `馬纓丹_已原點.usdz`(掃描的那株,在 `PlantAnchor` bundle / `Bundle.module`)。
  - `SpatialLabelCatalog.profiles`:`lantana-camara` profile 內已有花 22 點、葉 14 點的**模型 local 座標**錨點,與 `.referenceobject` 同座標系。
  - 純函式 `NearestPartSelector.select(...)`(依頭部位置選最近候選,帶遲滯)。
  - `SpatialLabelBuilder`(載入 marker 模板、`makeCallout`、`makeLeader`)。
  - `SpatialPartLabel(part:plant:)`(花/葉精簡標籤 SwiftUI view)。
- `ObjectTrackingController.refreshCallouts()` 已示範:用 `WorldTrackingProvider.queryDeviceAnchor` 取頭部世界座標 → 把候選點由 model-local 投影到 world → `NearestPartSelector` 選最近 → 定位 callout。**`WorldTrackingProvider` 與 `ObjectTrackingProvider` 是兩回事,前者在模擬器也能運作。**

## 已確認的需求決策

1. **範圍**:新增**獨立**擺放體驗,現有掃描/ObjectTracking 流程完全不動。
2. **模型**:用現有的 `馬纓丹_已原點.usdz`。
3. **操作**:**只拖曳移動位置**(不旋轉、不縮放)。
4. **標籤**:沿用追蹤版的「**最近花/葉**」動態選取(依頭部位置每幀選最近一朵花/一片葉)。

## 整體架構

新增一個專屬、不需物件追蹤的 immersive space(獨立 space id),由「擺放」分頁的 2D 控制面板開啟。模型放在面前、可拖曳;花/葉 callout 掛在模型烘焙錨點上,用 `WorldTrackingProvider` 做最近選取。

選擇「獨立 space + 專屬 controller」而非改現有檔案的理由:
- 獨立 space id `PlantVisionPlacementImmersiveSpace` → `SpatialPlantSceneView`(追蹤/合成)零改動,符合「不動追蹤」。
- 專屬 `ManualPlacementController` 只依賴 `WorldTrackingProvider`,單一職責,不與 ObjectTracking 耦合。

## 元件設計

### 1. `Views/ManualPlacementView.swift`(新增,取代 GrowthView)
「擺放」分頁的 2D 控制面板。職責:

- **開啟空間**按鈕:`await dismissImmersiveSpace()`(關掉任何開著的空間)→ `await openImmersiveSpace(id: placementImmersiveSpaceID)`。
- **關閉空間**按鈕:`await dismissImmersiveSpace()`。
- **重置位置**按鈕:呼叫 appModel 觸發 reset 訊號(見 §5)。
- 操作說明文字:「拖曳植物移動位置;靠近不同花/葉,標籤會自動指向最近的那一個。」
- 狀態顯示:空間是否開啟、是否取得頭部追蹤(讀 controller phase / appModel 狀態)。

依賴:`@EnvironmentObject PlantVisionModel`、`@Environment(\.openImmersiveSpace)`、`@Environment(\.dismissImmersiveSpace)`。

### 2. `Views/ManualPlacementSceneView.swift`(新增)
新 immersive space 的 RealityView 內容。職責:

- `make` 階段:
  1. `await SpatialLabelBuilder.loadMarkerTemplates()` 取得花/葉 marker 模板。
  2. 載入模型:`try await Entity(named: "馬纓丹_已原點", in: plantAnchorBundle)`。
  3. 建立 draggable root(命名,如 `placement-root`),`position = 預設 transform`(常數,約 `[0, 1.1, -1.0]`)。把模型加為子節點。
  4. 取 `lantana-camara` profile;對其 `parts` 用 `SpatialLabelBuilder.makeCallout(part:template:label:labelOffset:)` 建花、葉 callout,加為 root 子節點。
  5. root 加 `InputTargetComponent()` + `CollisionComponent`(由模型 bounds 產生)以接收拖曳。
  6. `content.subscribe(to: SceneEvents.Update.self)` → `controller.refreshCallouts()`(訂閱存到 controller 避免被釋放)。
  7. 狀態提示 attachment(沿用 `SpatialTrackingStatusLabel` 或簡化版)。
- 手勢:`.gesture(DragGesture().targetedToAnyEntity().onChanged/.onEnded)`,**只更新 root.position**(用起始位置 + 轉換後位移)。
- `attachments`:花/葉 `SpatialPartLabel(part:plant:)`(plant = `PlantDatabase.plant(id: "lantana-camara")`)、狀態標籤。
- `.task { await controller.start() }`、`.onDisappear { controller.stop() }`。
- 觀察 appModel 的 reset 訊號(透過 `update:` closure 或 `onChange`)→ 還原 root.transform。

### 3. `Spatial/ManualPlacementController.swift`(新增)
`@MainActor final class ... : ObservableObject`。職責:

- 持有 `WorldTrackingProvider` + `ARKitSession`(**僅** world tracking,無 ObjectTracking)。
- `Phase` enum:`idle / needsAuthorization / ready / failed(String)`(+ 視需要 `unsupported`)。
- `bind(root:binding:)`:接收 draggable root 與 callout binding。為**不耦合到 `ObjectTrackingController`**,在此 controller(或共用檔)自定義一個同欄位的 `CalloutBinding` struct(flowerPoints / leafPoints / flowerCallout / leafCallout),不引用 `ObjectTrackingController.PlantCalloutBinding`。
- `start()`:請求 `WorldTrackingProvider.requiredAuthorizations`、`session.run([worldTracking])`、設 phase。
- `stop()`:`session.stop()`。
- `refreshCallouts()`:`queryDeviceAnchor` 取頭部世界座標 → 把 binding 候選點由 root.transform 投影到 world → `NearestPartSelector.select` 選最近 → 定位/啟用 callout。沿用純函式 `NearestPartSelector`。
- `resetPosition()` / 預設 transform 常數:還原 root 位置。

### 4. `PlantVisionApp.swift`(修改)
新增第二個 `ImmersiveSpace(id: PlantVisionModel.placementImmersiveSpaceID) { ManualPlacementSceneView().environmentObject(appModel) }`。現有 `ImmersiveSpace` 保留不動。

### 5. `Stores/PlantVisionModel.swift`(修改)
- 新增 `static let placementImmersiveSpaceID = "PlantVisionPlacementImmersiveSpace"`。
- 新增面板 → 場景的 reset 訊號:`@Published private(set) var placementResetToken: Int = 0` + `func requestPlacementReset() { placementResetToken += 1 }`。場景觀察此 token 變化即還原位置。
- 其餘 growth 相關狀態/方法(`selectedStage`、`toggleGrowthPlayback`、`setStage`、`startGrowthPlayback`、`isGrowthPlaying`)**保留不動**,仍服務 `SyntheticPlantSceneView`。

### 6. `Views/RootView.swift`(修改)
- `WorkbenchSection` 的 `growth` → 改為 `place`:
  - `title`:「Place」(rail 顯示)/ 內容頁標題「擺放」。
  - `systemImage`:改為擺放語意圖示(如 `hand.draw` 或 `move.3d`;`cube` 也可)。
  - `accessibilityLabel`:「開啟手動擺放工作區」。
- `sectionContent` 的對應 case 渲染 `ManualPlacementView()`。

### 7. `Views/GrowthView.swift`(刪除)
連同 `PlantIllustration`(只被 GrowthView 使用)一併移除。

## 重用(不修改)

`SpatialLabelBuilder`、`SpatialPartLabel`、`NearestPartSelector`、`SpatialLabelCatalog`、`PlantDatabase`、`PlantPart`、`馬纓丹_已原點.usdz`、marker 模板、`SyntheticPlantSceneView`、`RealPlantTrackingView`、`ObjectTrackingController`。

## DRY 取捨

`refreshCallouts` 的「local→world 投影 + 選最近 + 定位 callout」迴圈會與 `ObjectTrackingController.refreshCallouts` 有約 15 行重複。**為不動追蹤路徑,接受此重複**(`ObjectTrackingController` 不改),選點數學仍共用純函式 `NearestPartSelector`。

## 資料流

```
ManualPlacementView (2D 面板)
  └─ openImmersiveSpace(placementImmersiveSpaceID)
       └─ ManualPlacementSceneView (RealityView)
            ├─ 載入 馬纓丹.usdz → draggable root (預設 transform)
            ├─ SpatialLabelCatalog[lantana-camara] → makeCallout → root 子節點
            ├─ DragGesture → 更新 root.position
            ├─ SceneEvents.Update → controller.refreshCallouts()
            │     └─ WorldTracking 頭部位置 → NearestPartSelector → 定位花/葉 callout
            └─ 觀察 appModel.placementResetToken → 還原 root.transform
  └─ requestPlacementReset() / dismissImmersiveSpace()
```

## 錯誤處理

- **模型載入失敗**:`Entity(named:in:)` throw → controller phase = `failed`,狀態標籤顯示錯誤訊息;不 crash。
- **頭部追蹤未授權 / `queryDeviceAnchor` 回 nil**:`refreshCallouts` 早退、callout 維持上一次位置(或預設代表點),狀態標籤提示需要權限。
- **空間已開啟衝突**:開啟前先 `dismissImmersiveSpace()`,避免 `openImmersiveSpace` 因已有空間而失敗。

## 測試與驗證

- **模擬器可跑**:`WorldTrackingProvider` 在模擬器有效(頭部約在原點),拖曳與標籤邏輯可在模擬器驗證——這是相對追蹤版的一大優勢。
- 既有純函式單元測試(`NearestPartSelector`)不受影響。
- **建置**:新增的三個 Swift 檔需手動加入 `PlantVision.xcodeproj/project.pbxproj`(Xcode 不會自動納入;見專案慣例),否則會報 "Cannot find in scope"。實作後以 `xcodebuild`(visionOS 模擬器 destination)驗證可編譯。

## 非目標 (Out of Scope)

- 不移除 / 不修改 ObjectTracking 追蹤路徑與合成 fallback 場景。
- 不做旋轉 / 縮放手勢。
- 不做平面偵測 / 落地對齊(模型可懸浮,由使用者拖到想要的位置)。
- 不新增第二個植物模型(但程式結構以「單一 profile 取自 catalog」實作,日後替換成本低)。
