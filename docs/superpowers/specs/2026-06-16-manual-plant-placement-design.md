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
3. **擺放**:植物**準確站在地板上**——出現在使用者面前的地板,**沿地板平面拖曳移動**(只改 X/Z,高度鎖定在地面;不旋轉、不縮放)。
4. **標籤**:沿用追蹤版的「**最近花/葉**」動態選取(依頭部位置每幀選最近一朵花/一片葉)。
5. **地板偵測**:用 **`PlaneDetectionProvider`**(水平面/地板,與 ObjectTracking 不同 provider,仍符合「不需物件追蹤」)貼合真實地板;**模擬器不支援平面偵測時退回固定地板高度**(假設 immersive 世界原點約在腳下地面,floor Y = 0),讓 app 仍可操作與測試。

## 整體架構

新增一個專屬、不需物件追蹤的 immersive space(獨立 space id),由「擺放」分頁的 2D 控制面板開啟。模型**貼合地板站立**、可沿地板拖曳;花/葉 callout 掛在模型烘焙錨點上,用 `WorldTrackingProvider` 做最近選取,用 `PlaneDetectionProvider` 取得地板高度。

選擇「獨立 space + 專屬 controller」而非改現有檔案的理由:
- 獨立 space id `PlantVisionPlacementImmersiveSpace` → `SpatialPlantSceneView`(追蹤/合成)零改動,符合「不動追蹤」。
- 專屬 `ManualPlacementController` 只依賴 `WorldTrackingProvider` + `PlaneDetectionProvider`,單一職責,不與 ObjectTracking 耦合。

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
  3. 計算模型底部:`model.visualBounds(relativeTo: root)` 取 `min.y`,當作「貼地偏移」(讓 root.position.y + min.y == 地板高度,即模型底部剛好踩地)。
  4. 建立 draggable root(命名,如 `placement-root`)。**初始位置等到地板高度確定後再放**(見 §3 起始放置流程);在地板確定前可先 `isEnabled = false` 或放預設高度。把模型加為子節點。
  5. 取 `lantana-camara` profile;對其 `parts` 用 `SpatialLabelBuilder.makeCallout(part:template:label:labelOffset:)` 建花、葉 callout,加為 root 子節點。
  6. root 加 `InputTargetComponent()` + `CollisionComponent`(由模型 bounds 產生)以接收拖曳。
  7. `content.subscribe(to: SceneEvents.Update.self)` → `controller.refreshCallouts()`(訂閱存到 controller 避免被釋放)。
  8. 狀態提示 attachment(沿用 `SpatialTrackingStatusLabel` 或簡化版)。
- 手勢(**沿地板拖曳**):`.gesture(DragGesture().targetedToAnyEntity().onChanged/.onEnded)`,把拖曳位移轉到場景座標後**只更新 root.position 的 X/Z;Y 鎖定 = 地板高度 − 貼地偏移**(永遠踩在地面)。用起始位置 + 轉換後水平位移計算。
- `attachments`:花/葉 `SpatialPartLabel(part:plant:)`(plant = `PlantDatabase.plant(id: "lantana-camara")`)、狀態標籤。
- `.task { await controller.start() }`、`.onDisappear { controller.stop() }`。
- 觀察 appModel 的 reset 訊號(透過 `update:` closure 或 `onChange`)→ 還原 root.transform。

### 3. `Spatial/ManualPlacementController.swift`(新增)
`@MainActor final class ... : ObservableObject`。職責:

- 持有 `WorldTrackingProvider` + `PlaneDetectionProvider`(`.horizontal`) + `ARKitSession`(**僅** world tracking + plane detection,無 ObjectTracking)。
- `Phase` enum:`idle / needsAuthorization / locatingFloor / ready / failed(String)`(+ 視需要 `unsupported`)。
- 狀態:`floorHeight: Float?`(偵測到的地板世界 Y;nil = 尚未取得,用 fallback)、`baseOffset: Float`(模型底部相對 root 原點的 Y,由 §2 步驟 3 算出)。
- `bind(root:binding:baseOffset:)`:接收 draggable root、callout binding、貼地偏移。為**不耦合到 `ObjectTrackingController`**,在此 controller(或共用檔)自定義一個同欄位的 `CalloutBinding` struct(flowerPoints / leafPoints / flowerCallout / leafCallout),不引用 `ObjectTrackingController.PlantCalloutBinding`。
- `start()`:
  - 請求 `WorldTrackingProvider.requiredAuthorizations + PlaneDetectionProvider.requiredAuthorizations`(世界感測)。
  - 若 `PlaneDetectionProvider.isSupported`(實機):`session.run([worldTracking, planeDetection])`,phase = `locatingFloor`;消費 `planeDetection.anchorUpdates`,取**水平、低於頭部、面積最大**(或 classification = floor)的平面 Y 當 `floorHeight`,取得後 phase = `ready` 並做「起始放置」。
  - 若**不支援**(模擬器):`session.run([worldTracking])`,`floorHeight = 0`(fallback,假設世界原點在地面),phase = `ready` 並做「起始放置」。
- **起始放置流程**:地板高度確定後,把 root 放到「使用者面前的地板」——讀 `queryDeviceAnchor` 取頭部水平位置(X/Z),沿頭部前方 ~1m 投影到地板,`root.position = (headX, floorHeight − baseOffset, headZ−1m 之類)`,並 `root.isEnabled = true`。head 取不到時退回固定 X/Z 常數。
- `stop()`:`session.stop()`。
- `refreshCallouts()`:`queryDeviceAnchor` 取頭部世界座標 → 把 binding 候選點由 root.transform 投影到 world → `NearestPartSelector.select` 選最近 → 定位/啟用 callout。沿用純函式 `NearestPartSelector`。
- `floorLockedY()`:回傳 `floorHeight(或 fallback) − baseOffset`,供拖曳手勢鎖定 Y。
- `resetPosition()`:重跑「起始放置流程」,把植物拉回使用者面前地板。

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
            ├─ 載入 馬纓丹.usdz → draggable root,算貼地偏移(visualBounds.min.y)
            ├─ SpatialLabelCatalog[lantana-camara] → makeCallout → root 子節點
            ├─ controller.start()
            │     ├─ PlaneDetection(實機) → floorHeight;不支援(模擬器) → floorHeight = 0
            │     └─ 起始放置:WorldTracking 頭部 X/Z + 前方 1m,Y = floorHeight − baseOffset
            ├─ DragGesture(沿地板) → 更新 root.position X/Z;Y = controller.floorLockedY()
            ├─ SceneEvents.Update → controller.refreshCallouts()
            │     └─ WorldTracking 頭部位置 → NearestPartSelector → 定位花/葉 callout
            └─ 觀察 appModel.placementResetToken → controller.resetPosition()
  └─ requestPlacementReset() / dismissImmersiveSpace()
```

## 錯誤處理

- **模型載入失敗**:`Entity(named:in:)` throw → controller phase = `failed`,狀態標籤顯示錯誤訊息;不 crash。
- **平面偵測不支援(模擬器)**:`PlaneDetectionProvider.isSupported == false` → 不啟動該 provider,`floorHeight = 0` fallback,phase 仍可到 `ready`,植物放在假設地面。
- **平面偵測未授權**:授權被拒 → phase = `needsAuthorization`,退回 fallback 地板高度仍可操作,狀態標籤提示需「世界感測」權限。
- **地板尚未偵測到**:phase = `locatingFloor` 期間 root 先隱藏或暫放;取得首個合適平面後才放置並顯示。
- **頭部追蹤未授權 / `queryDeviceAnchor` 回 nil**:起始放置退回固定 X/Z 常數;`refreshCallouts` 早退、callout 維持上一次位置,狀態標籤提示需要權限。
- **空間已開啟衝突**:開啟前先 `dismissImmersiveSpace()`,避免 `openImmersiveSpace` 因已有空間而失敗。

## 測試與驗證

- **模擬器可跑(降級)**:`WorldTrackingProvider` 在模擬器有效(頭部約在原點);`PlaneDetectionProvider` 在模擬器**不支援**,自動走 fallback(floor Y = 0),拖曳與標籤邏輯仍可在模擬器驗證。真實貼地需實機 Vision Pro。
- 既有純函式單元測試(`NearestPartSelector`)不受影響。貼地偏移/Y 鎖定可考慮抽成純函式以便加測(選配)。
- **建置**:新增的三個 Swift 檔需手動加入 `PlantVision.xcodeproj/project.pbxproj`(Xcode 不會自動納入;見專案慣例),否則會報 "Cannot find in scope"。實作後以 `xcodebuild`(visionOS 模擬器 destination)驗證可編譯。

## 非目標 (Out of Scope)

- 不移除 / 不修改 ObjectTracking 追蹤路徑與合成 fallback 場景。
- 不做旋轉 / 縮放手勢(只沿地板平移)。
- 不做垂直面/桌面擺放、不做多平面切換(只貼地板;站在最先取得的合適水平面)。
- 不做 tap-to-place 點選定位(出現在面前地板 + 拖曳;重置鈕拉回面前)。
- 不新增第二個植物模型(但程式結構以「單一 profile 取自 catalog」實作,日後替換成本低)。
