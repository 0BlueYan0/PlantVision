#!/usr/bin/env swift
// 產生「枯萎分類器」的測試替身（stub）模型與樣本圖。
//
// 真模型（Stage B）要用實際馬纓丹 tile 訓練；在那之前，這支腳本用 CreateML 在
// 合成的色塊上訓練一個極小的二元分類器（綠＝healthy、褐/黃＝withered），
// 讓 Stage C/D/E 的管線與單元測試先能跑起來。它是「樸素的顏色基準線」：
// 枯葉確實偏褐黃，所以這個替身雖簡陋仍有一點真實訊號。
//
// 用法：
//   swift dataset_tools/make_test_wither_model.swift <輸出模型路徑> <樣本圖輸出資料夾>
// 例：
//   swift dataset_tools/make_test_wither_model.swift \
//     MacFrameRelay/Tests/MacFrameRelayCoreTests/Resources/TestWitherClassifier.mlmodel \
//     MacFrameRelay/Tests/MacFrameRelayCoreTests/Resources
//
// 註：CreateML 只在 macOS 上可用，需透過 Xcode 工具鏈執行
//     （本機請先 export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer）。

import CoreGraphics
import CreateML
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - 參數

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("用法：swift make_test_wither_model.swift <模型輸出路徑> <樣本圖資料夾>\n".utf8))
    exit(2)
}
let modelOutputURL = URL(fileURLWithPath: args[1])
let fixturesDirURL = URL(fileURLWithPath: args[2])

let tileSize = 256
let imagesPerClass = 20

// MARK: - 影像工具

func makeImage(baseRGB: (Double, Double, Double), seed: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: tileSize, height: tileSize, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // 每張圖在同一色相內做亮度/色度抖動，給特徵抽取器一點變化（避免完全均勻的退化特徵）。
    var generator = SystemRandomNumberGenerator()
    func jitter(_ value: Double, _ amount: Double) -> Double {
        min(1, max(0, value + Double.random(in: -amount...amount, using: &generator)))
    }
    let r = jitter(baseRGB.0, 0.08)
    let g = jitter(baseRGB.1, 0.08)
    let b = jitter(baseRGB.2, 0.08)
    context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))

    // 灑幾塊同色相、深淺不同的方塊，做出葉面般的紋理。
    for _ in 0..<14 {
        let shade = Double.random(in: -0.18...0.18, using: &generator)
        context.setFillColor(CGColor(
            red: min(1, max(0, r + shade)),
            green: min(1, max(0, g + shade)),
            blue: min(1, max(0, b + shade)),
            alpha: 1
        ))
        let side = Double.random(in: 24...80, using: &generator)
        let x = Double.random(in: 0...(Double(tileSize) - side), using: &generator)
        let y = Double.random(in: 0...(Double(tileSize) - side), using: &generator)
        context.fill(CGRect(x: x, y: y, width: side, height: side))
    }
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// healthy = 翠綠；withered = 枯褐偏黃
let healthyRGB = (0.18, 0.55, 0.20)
let witheredRGB = (0.55, 0.40, 0.13)

// MARK: - 生成訓練資料夾

let fileManager = FileManager.default
let workDir = fileManager.temporaryDirectory.appendingPathComponent("wither-stub-\(UUID().uuidString)")
let healthyDir = workDir.appendingPathComponent("healthy")
let witheredDir = workDir.appendingPathComponent("withered")
try fileManager.createDirectory(at: healthyDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: witheredDir, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: workDir) }

for i in 0..<imagesPerClass {
    writePNG(makeImage(baseRGB: healthyRGB, seed: i), to: healthyDir.appendingPathComponent("healthy-\(i).png"))
    writePNG(makeImage(baseRGB: witheredRGB, seed: i), to: witheredDir.appendingPathComponent("withered-\(i).png"))
}
print("已生成合成訓練資料：\(workDir.path)")

// MARK: - 訓練並輸出模型

let dataSource = MLImageClassifier.DataSource.labeledDirectories(at: workDir)
print("開始訓練 stub 枯萎分類器…")
let classifier = try MLImageClassifier(trainingData: dataSource)
try fileManager.createDirectory(at: modelOutputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try classifier.write(to: modelOutputURL)
print("已輸出模型：\(modelOutputURL.path)")

// MARK: - 輸出單元測試用的樣本圖（乾淨、無雜訊，便於穩定判定）

func writeSolid(rgb: (Double, Double, Double), to url: URL) {
    let context = CGContext(
        data: nil, width: tileSize, height: tileSize, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
    writePNG(context.makeImage()!, to: url)
}

try fileManager.createDirectory(at: fixturesDirURL, withIntermediateDirectories: true)
writeSolid(rgb: healthyRGB, to: fixturesDirURL.appendingPathComponent("wither-healthy-sample.png"))
writeSolid(rgb: witheredRGB, to: fixturesDirURL.appendingPathComponent("wither-withered-sample.png"))
print("已輸出樣本圖：wither-healthy-sample.png / wither-withered-sample.png 於 \(fixturesDirURL.path)")
print("完成。")
