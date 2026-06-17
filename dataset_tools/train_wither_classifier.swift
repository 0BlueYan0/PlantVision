#!/usr/bin/env swift
// 訓練「枯萎程度 tile 分類器」並輸出 WitherClassifier.mlmodel（Stage B 的真模型）。
//
// 這是 Create ML.app GUI 的命令列替代：用 CreateML framework 從 tile 資料夾結構直接訓練
// 二元影像分類器（healthy / withered）。GUI 流程見 docs/wither-classifier-model.md。
//
// 輸入（由 dataset_tools/tile_images.py 產生）：
//   <tiles_dir>/train/{healthy,withered}/*.png   ← 訓練
//   <tiles_dir>/test/{healthy,withered}/*.png    ← 評估（可選，存在才跑）
//
// 用法：
//   swift dataset_tools/train_wither_classifier.swift <tiles_dir> [輸出模型路徑]
// 例（輸出預設寫到核心 Resources，取代佔位用的 stub）：
//   swift dataset_tools/train_wither_classifier.swift dataset_tools/lantana_tiles
//
// 註：CreateML 只在 macOS 上可用，需透過 Xcode 工具鏈執行
//     （本機請先 export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer）。

import CreateML
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("用法：swift train_wither_classifier.swift <tiles_dir> [輸出模型路徑]")
}

let fileManager = FileManager.default
let tilesDir = URL(fileURLWithPath: args[1])
let trainDir = tilesDir.appendingPathComponent("train")
let testDir = tilesDir.appendingPathComponent("test")

guard fileManager.fileExists(atPath: trainDir.path) else {
    fail("找不到訓練資料夾：\(trainDir.path)\n請先用 dataset_tools/tile_images.py 產生 train/{healthy,withered}/")
}

// 預設輸出到核心 Resources（取代佔位 stub）。腳本在 dataset_tools/ 內，其上一層即 repo 根目錄。
let defaultOutput = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()       // dataset_tools/
    .deletingLastPathComponent()       // repo 根目錄
    .appendingPathComponent("MacFrameRelay/Sources/MacFrameRelayCore/Resources/WitherClassifier.mlmodel")
let outputURL = args.count >= 3 ? URL(fileURLWithPath: args[2]) : defaultOutput

print("訓練資料：\(trainDir.path)")
let trainingSource = MLImageClassifier.DataSource.labeledDirectories(at: trainDir)

print("開始訓練 WitherClassifier（healthy / withered）…")
let classifier = try MLImageClassifier(trainingData: trainingSource)

// 訓練集表現
let trainingError = classifier.trainingMetrics.classificationError
print(String(format: "訓練集分類錯誤率：%.2f%%", trainingError * 100))

// 測試集評估（存在才跑）
if fileManager.fileExists(atPath: testDir.path) {
    let testSource = MLImageClassifier.DataSource.labeledDirectories(at: testDir)
    let evaluation = classifier.evaluation(on: testSource)
    print(String(format: "測試集分類錯誤率：%.2f%%（準確率 %.2f%%）",
                 evaluation.classificationError * 100,
                 (1 - evaluation.classificationError) * 100))
} else {
    print("（無 test/ 資料夾，略過測試集評估）")
}

let metadata = MLModelMetadata(
    author: "PlantVision",
    shortDescription: "馬纓丹枯萎程度 tile 二元分類器（healthy / withered）",
    version: "1.0"
)

try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try classifier.write(to: outputURL, metadata: metadata)
print("已輸出模型：\(outputURL.path)")
print("提醒：模型輸出的標籤需為 healthy / withered，且檔名固定為 WitherClassifier。")
