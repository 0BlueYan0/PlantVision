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
1. 用 Reality Composer Pro 開 `PlantAnchor`（開 `Package.realitycomposerpro` 或其 Swift package）。
2. 開 `Scene.usda`。若場景空：把 `馬纓丹_已原點.usdz` 拖進 `Root`，Inspector 確認 Transform 為 identity。
3. 每朵外圍可見的花：工具列 Insert → Transform，於 Hierarchy 雙擊改名 `anchor_flower`（首個）/`anchor_flower_1`…，用 gizmo 把它移到那朵花上。
4. 每片外圍可見的葉：Insert → Transform，改名 `anchor_leaf`/`anchor_leaf_1`…，移到那片葉上。
5. Cmd+S 存檔。

## 抽座標並更新 catalog
6. 終端機執行：
   ```
   swift Scripts/extract_anchors.swift PlantAnchor/Sources/PlantAnchor/PlantAnchor.rkassets/Scene.usda
   ```
7. 把輸出的 `points: [...]` 分別貼進 `PlantVision/Spatial/PartAnchor.swift` 的 `SpatialLabelCatalog`
   對應 `PartAnchor(part: .flower, ...)` / `(part: .leaf, ...)` 的 `points`。
   （`labelOffset` 維持/微調，`part` 不變。）
8. 重新 build，實機確認 callout 落在正確的花/葉上。

## 微調
- 若整片標籤一致偏移一個常數 → 調該 profile 的 `frameCorrection`。
- 標籤外推方向/距離 → 調該 `PartAnchor` 的 `labelOffset`。
