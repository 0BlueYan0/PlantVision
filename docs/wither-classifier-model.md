# 馬纓丹枯萎程度模型（WitherClassifier）

這份文件說明「枯萎程度 tile 分類器」如何訓練與接入。它與植物辨識的 `PlantClassifier`
**完全獨立**——兩個模型各跑各的，只是在 Mac 端共用同一批切好的 tiles。

## 設計重點

枯萎程度是**面積比例**問題，不是「數幾塊枯掉」：

1. Mac 端把每幀切成重疊小塊（與 `PlantImageClassifier.tileRects` 同一套幾何）。
2. `WitherClassifier` 對每個 tile 判 `healthy` / `withered`；信心不足的 tile 視為「無植物」。
3. `WitherScoreResolver` 算出 **枯萎比例 = 枯萎 tile ÷（健康＋枯萎 tile）**，有植物的 tile 太少則回報不確定。
4. `TemporalWitherSmoother` 在時間窗內**取平均**壓抖動（連續值，不用多數決）。
5. `WitherLevel` 把比例分級（0 健康 / 1 輕微 / 2 中度 / 3 嚴重），隨 `frameResult` 送到 visionOS 顯示。

## 模型規格

- **固定檔名 `WitherClassifier`**，查找順序 `.mlmodelc → .mlpackage → .mlmodel`，
  放在 `MacFrameRelay/Sources/MacFrameRelayCore/Resources/`（經 `Bundle.module`）。
- **輸出標籤必須是 `healthy` 與 `withered`**（對應 `WitherImageClassifier` 的常數）。
- 找不到模型時，Mac app 只是不送枯萎欄位（向後相容），不影響植物辨識。

> 目前 Resources 內的 `WitherClassifier.mlmodel` 是**佔位用的樸素顏色基準線**
> （綠＝健康、褐黃＝枯萎），由 `dataset_tools/make_test_wither_model.swift` 產生，
> 讓整條管線在真模型就緒前即可端到端運作。請用下述流程訓練的真模型取代它。

## 資料與訓練流程

完整步驟見 `dataset_tools/README_dataset.md`，摘要：

```bash
cd dataset_tools

# 1) 下載原始素材（iNaturalist，CC 授權）
python3 download_lantana_dataset.py --count 300 --size medium

# 2) 人工分類成 lantana_raw/sorted/{healthy,withered}/（只有你能判斷）

# 3) 切成與推論一致的 tile（train/test 以來源圖為單位分組，避免洩漏）
python3 tile_images.py

# 4) 用 CreateML 命令列訓練並輸出 WitherClassifier.mlmodel（預設寫到核心 Resources）
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # 視環境而定
swift train_wither_classifier.swift lantana_tiles
```

`tile_images.py --selftest` 會驗證切塊幾何與 Swift 端釘住的 `tileRects` 一致；
切塊邏輯一旦與推論走樣會立刻被抓到。

### Create ML.app GUI 備案

也可用 Xcode 內建的 Create ML.app：`Image Classification` 專案，把
`lantana_tiles/train` 拖到 Training Data、`lantana_tiles/test` 拖到 Testing Data，
訓練後從 Output 匯出，命名為 `WitherClassifier.mlpackage`，放到核心 Resources。

## 收集建議

- 兩類數量盡量平衡；iNaturalist 多是漂亮開花株，**枯萎樣本通常偏少**，建議自行補拍。
- 取景／光線越接近實際 Vision Pro 鏡像截圖越準；自拍的實機樣本價值高於取景不符的野外照。
- 不要把同一張圖切出的 tile 同時放進 train 與 test（`tile_images.py` 已以來源圖為單位分組處理）。
