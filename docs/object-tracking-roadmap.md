# PlantVision Object Tracking Roadmap

這份 roadmap 聚焦在目前的新目標：不是辨識很多種植物，而是追蹤固定的一株植物或它的花盆，讓 Vision Pro 裡的 UI 可以穩定跟著真實物體移動。

## 目標

- 固定追蹤同一盆植物或花盆。
- 在 visionOS `ImmersiveSpace` 內把植物資訊 UI 放在物體附近。
- 優先追求穩定的空間定位，不追求大量植物分類。
- Mac 端植物辨識保留為輔助，不作為 UI 跟隨的主要依據。

## 核心判斷

Object Tracking 適合追蹤預先建立 reference object 的固定實體物件。它不是植物品種分類器，不會看到任意植物就判斷品種。

對 PlantVision 來說，最務實的分工是：

- `ObjectTrackingProvider`：負責找到固定盆栽、花盆或底座的位置。
- `PlantDatabase`：負責顯示該固定植物的資料。
- Mac Core ML classifier：保留為辨識展示或未來多植物版本使用。

## Phase 1：決定追蹤目標

### 要做

1. 先嘗試追蹤「花盆 + 植物整體」。
2. 如果葉子造成追蹤不穩，改成只追蹤花盆。
3. 如果花盆太對稱或外觀太單調，貼一張小 marker card，改用 `ImageTrackingProvider`。
4. 不要把 UI 錨定在單片葉子上。

### 原因

植物葉片會晃動、遮擋、長大和變形，這些都會降低 Object Tracking 的穩定度。花盆、展示牌、底座或 marker card 通常比葉片更適合做空間錨定目標。

### 完成標準

明確決定 UI 要跟著哪個實體：

- 花盆中心
- 花盆上緣
- 植物上方固定 offset
- marker card
- 展示底座

## Phase 2：用 iPhone 14 Pro Max 掃描目標

### 要做

1. 用 iPhone 14 Pro Max 掃描選定目標。
2. 掃描時盡量包含花盆或底座。
3. 使用均勻光線和乾淨背景。
4. 避免葉片大幅晃動。
5. 匯出 `USDZ`。
6. 在 Mac 上預覽 `USDZ`，確認比例與外觀合理。

### 掃描建議

- 如果要追蹤整盆植物，掃描時包含花盆、植物主體和明顯外觀特徵。
- 如果整株不穩，改掃描花盆或底座。
- 如果花盆外型太對稱，加入不影響展示的小型視覺特徵，例如貼紙或 marker。

### 完成標準

取得一個可預覽的 `USDZ`，並且目標物的尺寸、方向和外觀特徵足夠清楚。

## Phase 3：產生 Reference Object

### 要做

1. 在 Mac 開啟 Create ML。
2. 建立 Object Tracking 相關專案。
3. 匯入 Phase 2 的 `USDZ`。
4. Viewing angle 先選較保守的 upright 類型。
5. Train。
6. 匯出 `.referenceobject`。
7. 命名成容易辨識的檔名，例如 `PlantPot.referenceobject`。

### 完成標準

取得 `PlantPot.referenceobject`，可加入 visionOS app resources。

## Phase 4：建立最小 Object Tracking Prototype

### 要做

1. 先建立最小測試，不急著接完整 PlantVision UI。
2. 把 `.referenceobject` 加進 Xcode target resources。
3. 在 `ImmersiveSpace` 啟動 `ARKitSession`。
4. 建立 `ObjectTrackingProvider`。
5. 監聽 anchor updates。
6. 偵測到 `.added` 或 `.updated` 時，在 anchor 位置放一個簡單 marker，例如小球或文字。
7. `anchor.isTracked == false` 時隱藏 marker 或顯示 lost 狀態。

### 完成標準

Vision Pro 能在實機上找到該盆植物或花盆，並且 marker 會跟著物體位置更新。

## Phase 5：把 PlantVision UI 綁到 Object Anchor

### 要做

1. 建立一個 parent entity 跟著 `ObjectAnchor`。
2. 把植物資訊 UI attachment 放到 parent entity 底下。
3. 設定固定 offset，例如在花盆上方 20 到 40 公分。
4. 讓 UI 面向使用者，不要完全照物體旋轉到不可讀。
5. 加 smoothing，降低 tracking 抖動。
6. tracking lost 時保留最後位置或淡出 UI。

### 完成標準

移動盆栽、改變觀看角度或靠近遠離時，UI 仍維持在植物附近，不明顯漂移。

## Phase 6：整理辨識與追蹤責任

### 固定一株植物版本

如果只展示固定一株，最簡單穩定的版本是：

1. Object Tracking 找到花盆或盆栽。
2. App 直接顯示該植物的固定資料。
3. 不必每次都跑 Mac 端分類。

### 未來多植物版本

如果之後要支援多株植物：

1. Mac 端 Core ML classifier 回傳 `plantID` 和 `confidence`。
2. visionOS 端用 `ObjectTrackingProvider` 或 `ImageTrackingProvider` 決定 UI 跟隨位置。
3. `plantID` 決定 UI 顯示哪一筆 `PlantDatabase`。

### 完成標準

程式內清楚分成：

- tracking：負責位置。
- recognition：負責植物身份。
- UI：負責顯示與跟隨。

## Phase 7：實機穩定性測試

### 測試項目

1. 正面能否找到目標。
2. 側面能否找到目標。
3. 距離 0.5 到 2 公尺內是否穩定。
4. 光線變暗是否仍可 tracking。
5. 葉子輕微晃動時是否仍可 tracking。
6. 花盆移動後 UI 是否跟著。
7. tracking lost 後是否能恢復。
8. UI 是否會抖動、漂移或遮住植物。

### 失敗時的調整順序

1. 改追蹤花盆，不追蹤葉片。
2. 加 marker card，改用 Image Tracking。
3. 改用手動放置 `WorldAnchor`。
4. 重新掃描 reference object。
5. 最後才考慮重新設計 UI 跟隨策略。

## 建議執行順序

1. 先用 iPhone 14 Pro Max 掃描「花盆 + 植物整體」。
2. 用 Create ML 產生 `.referenceobject`。
3. 在最小 prototype 裡測 Object Tracking 穩不穩。
4. 如果穩，再整合進 PlantVision。
5. 如果不穩，改追蹤花盆或 marker。
6. 等 tracking 穩定後，再決定 Mac classifier 是否需要參與正式流程。

## 不建議現在做的事

- 不要先做大量植物分類資料集。
- 不要先追求葉片級精準貼合。
- 不要把 Mac 螢幕辨識結果當成 3D 追蹤位置。
- 不要在 tracking 尚未穩定前投入完整 UI 動畫。

## 最小成功版本

最小可交付版本應該是：

1. Vision Pro 偵測到固定花盆或盆栽。
2. UI 出現在花盆上方固定位置。
3. 移動花盆時 UI 跟著移動。
4. tracking lost 時 UI 有合理狀態。
5. 顯示固定植物資料，不依賴 Mac 分類。

這個版本完成後，再把 Mac Core ML classifier 接回來作為進階辨識功能。
