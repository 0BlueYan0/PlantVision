# 馬纓丹枯萎程度資料集 — 收集與標註指引

這份工具用來建立 PlantVision「枯萎程度 tile 分類器」的訓練資料。
分成三步：**下載原始素材 → 整理／分類 → 切 tile 標註**。

---

## 1. 下載原始素材

在這個資料夾執行（需要 Python 3，macOS 內建即有）：

```bash
cd dataset_tools
python3 download_lantana_dataset.py --count 300 --size medium
```

完成後會得到：

```
dataset_tools/lantana_raw/
  images/          # 下載的馬纓丹照片
  manifest.csv     # 每張圖的授權、出處、拍攝地點（請保留，授權需要）
```

參數：`--count` 目標張數、`--size medium|large`、`--max-per-observation` 同一株最多取幾張。
可重複執行續傳，已下載的會自動跳過。

> 來源是 iNaturalist 上 CC 授權（cc0 / cc-by / cc-by-nc）、已被社群驗證物種的觀察照片。

---

## 2. 整理／分類（這步只有你能做）

下載到的是**野外各種狀態的馬纓丹**，**沒有**現成的健康/枯萎標籤，所以要人工整理。
把整理好的整張圖放到 `lantana_raw/sorted/` 底下的兩個資料夾（`tile_images.py` 預設讀這裡）：

1. 先刪掉不堪用的：純花朵特寫、距離太遠看不出葉片、根本不是馬纓丹的誤判。
2. 依葉片狀態粗分兩類（先二元就好，之後要分級再細切），放到對應資料夾：
   - `lantana_raw/sorted/healthy/` — 葉片翠綠、飽滿、無明顯黃化枯斑
   - `lantana_raw/sorted/withered/` — 明顯黃化、枯褐、捲曲、壞死的葉片

> ⚠️ 重要提醒：iNaturalist 上大家都拍漂亮開花的植株，**枯萎樣本會偏少**。
> 你很可能需要自己補拍枯掉的馬纓丹，數量才會夠、兩類才會平衡。

---

## 3. 切 tile 並擺成訓練結構

你的 `resolveScene` 是把畫面切成重疊小塊（tiles）分類的。枯萎分類器同理，
訓練資料要以 **tile（小塊）** 為單位，而不是整張植株。直接用切圖腳本：

```bash
python3 tile_images.py            # 預設讀 lantana_raw/sorted/，輸出到 lantana_tiles/
python3 tile_images.py --selftest # 只驗證切塊幾何與 Swift 端一致（不需 Pillow）
```

需要 Pillow：`python3 -m pip install Pillow`。產出結構：

```
lantana_tiles/
  train/
    healthy/     # 健康葉片的小塊
    withered/    # 枯萎葉片的小塊
  test/
    healthy/
    withered/
```

- 切塊幾何**完全對齊** Mac 端推論的 `PlantImageClassifier.tileRects`（`--selftest` 會驗證）。
- `train` 與 `test` **以來源圖為單位分組**（預設 8:2），同一張圖的 tile 不會同時落在兩邊（避免資料洩漏）。
- 兩類數量盡量接近（各至少幾百個 tile 會比較穩）。

## 4. 訓練模型

```bash
# CreateML 命令列（需 Xcode 工具鏈；本機請先 export DEVELOPER_DIR=...）
swift train_wither_classifier.swift lantana_tiles
```

預設會把 `WitherClassifier.mlmodel` 寫到 `MacFrameRelay/Sources/MacFrameRelayCore/Resources/`，
取代佔位用的樸素顏色基準線。細節與 Create ML.app GUI 備案見 `docs/wither-classifier-model.md`。

---

## 授權與引用

`manifest.csv` 已記錄每張圖的授權與作者。課堂／demo 使用 CC-BY-NC 沒問題，
但請保留 manifest、需要時附上出處。若日後要商用，重跑下載時把 `--licenses` 改成 `cc0,cc-by`。

## 一個務實建議

野外照片的取景、光線跟你實際用 Vision Pro 鏡像截圖的條件差很多。
模型「看過的」越接近「上線時看到的」越準，所以**自己用實際 setup 補拍**幾十張不同枯萎程度的馬纓丹，
價值往往高於上百張取景不符的野外照。兩者混用效果最好。
