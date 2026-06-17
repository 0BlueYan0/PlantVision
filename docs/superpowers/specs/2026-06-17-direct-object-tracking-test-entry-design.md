# 設計:Place 頁直接啟動物件追蹤(測試入口)

日期:2026-06-17
分支:`worktree-tracking-test-entry`

## 目標

在「擺放(Place)」頁面新增一個**測試用**入口,讓開發者**跳過 Mac relay / Demo 的植物辨識流程**,直接啟動 ARKit 物件追蹤,把花/葉空間標籤貼到真實盆栽上。

明確不是放在第一個頁面(Scan);Place 頁符合「非第一頁」的需求。

## 背景:目前 object tracking 為什麼被辨識流程綁住

物件追蹤的 immersive space(`PlantVisionModel.immersiveSpaceID` → `SpatialPlantSceneView` → `RealPlantTrackingView`)目前**只能從 Scan 頁開啟**,且兩個入口都被辨識結果鎖住:

- `ScanView.swift:142` heroPanel「開啟空間」按鈕:`.disabled(appModel.currentResult == nil)`。
- `ScanView.swift:216` 結果卡「放置空間標籤」按鈕:整個 `resultPanel` 只在 `currentResult != nil` 時出現。

也就是說,目前**必須先跑完 Mac relay 連線或 Demo 樣本拿到 `currentResult`**,才能進入物件追蹤。

但追蹤本身**不依賴** `currentResult`:
- `RealPlantTrackingView` / `ObjectTrackingController` 從 `SpatialLabelCatalog.profiles` 載入 `.referenceobject` 並驅動標籤,標籤文字來自 `SpatialLabelCatalog.profiles → PlantDatabase.plant(id:)`(固定為馬纓丹),與 `currentResult` 無關。

因此「跳過辨識直接追蹤」在技術上就是:**新增一個不受 `currentResult` 限制、直接開 `immersiveSpaceID` 的入口**。

## 設計(方案 A:重用現有追蹤空間)

只動 `PlantVision/Views/ManualPlacementView.swift`,不新增 immersive space、不新增場景檔。

### UI

在 `controls` 區塊現有按鈕下方,以 `Divider()` 分隔出一個「測試」區塊,放一顆按鈕:

- 標題:「直接啟動物件追蹤(跳過辨識)」,systemImage 例如 `viewfinder` 或 `arkit`。
- 樣式:`.bordered`(次要動作,與「擺放模型」這個主要動作區隔)。
- 行為:`Task { isTransitioning = true; await dismissImmersiveSpace(); let result = await openImmersiveSpace(id: PlantVisionModel.immersiveSpaceID); ...; isTransitioning = false }`——沿用現有「擺放模型」按鈕「先關再開」避免並發 open/dismiss 的模式。
- **不**加 `currentResult` 的 disabled 條件——這正是要繞過的東西。
- 旁附一行說明 `Label`:點明「測試用:跳過 Mac 辨識,直接用物件追蹤把花/葉標籤貼到真實植物」。

### 狀態管理

把現有的 `@State private var isSpaceOpen: Bool` 換成列舉,記錄「目前從本頁開了哪一種空間」:

```swift
private enum OpenSpace { case none, model, tracking }
@State private var openSpace: OpenSpace = .none
```

- 「開啟空間並擺放(模型)」成功後設 `openSpace = .model`。
- 「直接啟動物件追蹤」成功後設 `openSpace = .tracking`。
- 「把植物拉回面前」(reset):`.disabled(openSpace != .model || isTransitioning)`——reset 只對模型擺放有意義(它 bump `placementResetToken`,只有 `ManualPlacementSceneView` 觀察;追蹤場景會忽略,即使誤按也無害,但仍以 disabled 表達語意)。
- 「關閉空間」:`.disabled(openSpace == .none || isTransitioning)`,行為維持呼叫 `dismissImmersiveSpace()`(與 space id 無關,關閉當前開啟的任一空間),成功後設 `openSpace = .none`。

兩個入口互斥靠「先 `dismissImmersiveSpace()` 再 open」保證:從本頁切換時一律先關掉舊空間。

### 資料流

1. 使用者在 Place 頁點「直接啟動物件追蹤」。
2. `ManualPlacementView` 關掉任何已開空間 → 開 `immersiveSpaceID`。
3. `SpatialPlantSceneView` 依 `ObjectTrackingProvider.isSupported` 分流:
   - 實機:`RealPlantTrackingView` → `ObjectTrackingController.start(holdProvider:)`,載入 catalog 的 `.referenceobject`、求授權、消費 `anchorUpdates`、把花/葉 callout 貼到追到的盆栽。
   - 模擬器/不支援:fallback 到 `SyntheticPlantSceneView`(現有合成示意場景)。
4. 全程不經過 `PlantVisionModel` 的 relay / recognition 路徑。

## 邊界與錯誤處理

- **模擬器**:`SpatialPlantSceneView` 既有 fallback 會顯示合成植物示意,不會崩潰。測試者在模擬器看到的是 fallback,屬預期。
- **授權 / Info.plist**:此入口重用既有追蹤路徑,授權與 usage string 需求與 Scan 開啟時完全相同;不在本變更新增 entitlement。若世界感測授權缺失,`ObjectTrackingController` 已有 `.needsAuthorization` 階段與狀態提示(`SpatialTrackingStatusLabel`)。
- **缺 `.referenceobject` 資產**:`ObjectTrackingController` 已處理 `.missingAsset` 階段並顯示提示。
- **標籤文字**:無辨識結果時,標籤文字取自 `SpatialLabelCatalog`(固定馬纓丹)。測試入口接受此預設,不引入新文字來源。
- **系統手勢關閉空間**:沿用現有已知限制(`ManualPlacementView.swift:11-13` 的 TODO)——若使用者用數位錶冠/home 關空間,`openSpace` 不會自動歸零;再按 close 為 no-op,無害。本變更不擴大也不修正此既有限制。

## 涉及檔案

| 檔案 | 變更 |
|------|------|
| `PlantVision/Views/ManualPlacementView.swift` | 唯一變更檔:`isSpaceOpen: Bool` → `openSpace: OpenSpace` 列舉;新增「測試」區塊與「直接啟動物件追蹤」按鈕;調整 reset / close 按鈕的 disabled 條件。 |

不新增檔案、不改 `PlantVisionApp.swift`、不改 `ObjectTrackingController` / `SpatialPlantSceneView` / `PlantVisionModel`。

## 測試

- **編譯 / 邏輯**:本變更為純 SwiftUI 接線,無可抽出的純函式邏輯,以編譯通過 + 既有測試不回歸為主。`swift build`(對齊專案雙建置系統)應通過。
- **手動(模擬器)**:Place 頁出現新按鈕;按下後進入 fallback 合成場景而非崩潰;「關閉空間」可關;「拉回面前」在追蹤模式為 disabled。
- **手動(實機 Vision Pro,必要)**:不先做任何 Scan / Demo / relay,直接從 Place 頁按「直接啟動物件追蹤」即進入追蹤;花/葉標籤貼到真實盆栽;關閉/重開正常。

## 非目標(Out of scope)

- 不做自由輸入文字的自訂標籤(使用者已選「只貼花/葉標籤到真實植物」)。
- 不在追蹤模式同時放虛擬模型。
- 不新增模式切換 UI(使用者已選「加第二顆按鈕」)。
- 不重構 Scan 頁既有入口、不解除 Scan 那兩顆按鈕的 `currentResult` 限制。
- 不新增 entitlement / 不改授權設定。

## 假設

- 既有從 Scan 開啟物件追蹤的路徑在實機上可正常運作(授權與 `.referenceobject` 已就緒);本入口只是換一個觸發點,不修復既有追蹤問題。
