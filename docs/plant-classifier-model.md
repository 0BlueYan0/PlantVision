# PlantVision 植物辨識模型教學

這份文件說明如何把植物辨識模型加入 Mac relay app，並訓練可被目前程式使用的 Core ML 影像分類模型。

## 目前架構

PlantVision 目前不直接從 Vision Pro 主鏡頭取影像。Mac app 會擷取 Vision Pro 鏡像畫面或指定視窗，接著在 Mac 端執行 Core ML 分類，再透過 Socket.IO relay 把辨識結果送回 visionOS app。

資料流如下：

1. `MacFrameRelayApp` 擷取指定螢幕或視窗。
2. `PlantImageClassifier` 使用 `PlantClassifier` Core ML 模型分類該 frame。
3. `FrameRelayMessage` 送出 `plantID`、`confidence`、frame 尺寸與時間。
4. visionOS app 用 `plantID` 對應 `PlantDatabase`，顯示植物資訊與空間標籤。

如果 Mac app 找不到模型，或模型分類失敗，程式會照舊送出成功抽幀訊息，visionOS app 會 fallback 到 demo 植物資料。

## 加入模型

模型檔名固定使用 `PlantClassifier`，支援以下任一格式：

- `PlantClassifier.mlpackage`
- `PlantClassifier.mlmodel`
- `PlantClassifier.mlmodelc`

放置路徑：

```text
MacFrameRelay/Sources/MacFrameRelayCore/Resources/PlantClassifier.mlpackage
```

也可以放 `.mlmodel` 或 `.mlmodelc`。Swift Package 會把 `Resources` 打包進 Mac app，程式會優先尋找 `.mlmodelc`，再找 `.mlpackage`，最後找 `.mlmodel`。

加入後先執行：

```bash
swift test --package-path MacFrameRelay
```

再重新 build Mac app：

```bash
swift build --package-path MacFrameRelay
```

## Label 命名規則

模型輸出的 label 必須對應 `PlantVision/Services/PlantDatabase.swift` 裡的 `Plant.id`。

目前內建 id：

- `monstera-deliciosa`
- `epipremnum-aureum`
- `sansevieria-trifasciata`

Create ML 的訓練資料夾名稱也要使用這些 id。範例：

```text
TrainingData/
  monstera-deliciosa/
    image-001.jpg
    image-002.jpg
  epipremnum-aureum/
    image-001.jpg
    image-002.jpg
  sansevieria-trifasciata/
    image-001.jpg
    image-002.jpg
```

如果你要新增植物，先在 `PlantDatabase.swift` 新增一筆植物資料，再用同樣的 `id` 當訓練資料夾名稱。

## 用 Create ML 訓練影像分類模型

這一版程式接的是「影像分類器」，也就是判斷整張 frame 最像哪一種植物。適合一次畫面只聚焦一盆植物的流程。

1. 開啟 Xcode。
2. 選擇 `Xcode > Open Developer Tool > Create ML`。
3. 建立新專案，選 `Image Classification`。
4. 把訓練資料夾拖到 `Training Data`。
5. 如果資料量足夠，另外準備 `Testing Data`，資料夾結構要和訓練資料相同。
6. 按 `Train`。
7. 到 `Evaluation` 檢查 precision、recall、testing accuracy。
8. 到 `Preview` 用沒看過的照片測試。
9. 從 `Output` 匯出模型，命名為 `PlantClassifier.mlpackage`。
10. 把模型放到 `MacFrameRelay/Sources/MacFrameRelayCore/Resources/`。

Apple 建議每個類別至少 10 張圖片，但真實專案應該準備更多，而且要涵蓋不同角度、距離、光線、背景、健康狀態和遮擋情境。若每類有 25 張以上，可以把大約 20% 移到 testing dataset。

## 資料收集建議

每個植物類別至少準備：

- 正面、側面、俯視角。
- 明亮散射光、室內偏暗、背光。
- 遠景整盆、近景葉片。
- 不同背景，例如桌面、窗邊、架上。
- 不同生長狀態，例如幼株、成熟株、修剪後。

避免資料偏差：

- 不要讓某一類有 1000 張、另一類只有 10 張。
- 不要每張都在同一個背景，否則模型可能學到背景而不是植物。
- 不要把同一張照片裁切成很多張後同時放進 training 和 testing。

## 使用流程

1. 啟動 Socket.IO relay server。
2. 開啟 MacFrameRelay app。
3. 設定 relay URL 和 pairing code。
4. 選擇 Vision Pro 鏡像視窗或螢幕。
5. 開啟自動擷取或手動擷取。
6. Mac app 狀態列若顯示 `已送出 Socket.IO JSON：<plantID> <confidence>%`，代表模型結果已送出。
7. visionOS app 會顯示對應植物與信心值。

如果狀態顯示 `Vision Pro 將使用 demo 結果`，代表沒有載入模型或分類失敗。先確認模型檔名、放置路徑、label 是否正確。

## 目前限制

目前接的是 image classifier，不是 object detector。因此它只能輸出一個最可能的植物類別，不會輸出畫面中每個物體的位置。

如果之後要辨識「畫面中的多個物體」或「植物在畫面哪裡」，需要改成物件偵測模型，並擴充 relay payload，例如：

```json
{
  "detections": [
    {
      "plantID": "monstera-deliciosa",
      "confidence": 0.91,
      "boundingBox": { "x": 0.12, "y": 0.20, "width": 0.45, "height": 0.50 }
    }
  ]
}
```

這會牽涉到 visionOS 端如何把 2D bounding box 對回空間錨點，應該獨立成下一階段。

## 參考

- Apple Core ML：<https://developer.apple.com/documentation/coreml/>
- Apple Vision `VNCoreMLRequest`：<https://developer.apple.com/documentation/vision/vncoremlrequest>
- Apple Create ML image classifier：<https://developer.apple.com/documentation/createml/creating-an-image-classifier-model>
- Apple runtime model compile：<https://developer.apple.com/documentation/coreml/core_ml_api/downloading_and_compiling_a_model_on_the_user_s_device>
