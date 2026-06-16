import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MacFrameRelayCore

private func fixtureURL(_ name: String, _ ext: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: ext))
}

private func fixtureImage(_ name: String, _ ext: String) throws -> CGImage {
    let url = try fixtureURL(name, ext)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

private func makeClassifier() throws -> PlantImageClassifier {
    try PlantImageClassifier(modelURL: fixtureURL("TestPlantClassifier", "mlmodel"))
}

/// 把植物圖縮小貼到背景圖中央，模擬植物只佔鏡像畫面一小部分的情況
private func compositeImage(plant: CGImage, background: CGImage, widthFraction: CGFloat) throws -> CGImage {
    let width = background.width
    let height = background.height
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
    let plantWidth = CGFloat(width) * widthFraction
    let plantHeight = plantWidth * CGFloat(plant.height) / CGFloat(plant.width)
    context.draw(plant, in: CGRect(
        x: (CGFloat(width) - plantWidth) / 2,
        y: (CGFloat(height) - plantHeight) / 2,
        width: plantWidth,
        height: plantHeight
    ))
    return try #require(context.makeImage())
}

@Test
func classifySceneDetectsPlantOccupyingSmallPartOfFrame() throws {
    // 驗證滑動窗能偵測「只佔畫面一小塊」的植物（這也是 classifyScene 相對 classify 的存在理由）。
    // 用馬纓丹當受測樣本：整株花葉均勻，縮到 25% 寬時各區塊仍清楚是植物。
    let classifier = try makeClassifier()
    let composite = try compositeImage(
        plant: fixtureImage("lantana-sample", "jpeg"),
        background: fixtureImage("background-sample", "jpg"),
        widthFraction: 0.25
    )

    let result = try #require(try classifier.classifyScene(composite))

    #expect(result.label == "lantana-camara")
    #expect(result.confidence >= 0.9)
}

@Test
func classifySceneDetectsFullFramePlant() throws {
    let classifier = try makeClassifier()

    let result = try #require(try classifier.classifyScene(fixtureImage("pelargonium-sample", "jpeg")))

    #expect(result.label == "pelargonium-hortorum")
    #expect(result.confidence >= 0.9)
}

@Test
func classifySceneDetectsFullFrameLantana() throws {
    let classifier = try makeClassifier()

    let result = try #require(try classifier.classifyScene(fixtureImage("lantana-sample", "jpeg")))

    #expect(result.label == "lantana-camara")
    #expect(result.confidence >= 0.9)
}

@Test
func classifySceneReportsBackgroundForPlainScene() throws {
    let classifier = try makeClassifier()

    let result = try #require(try classifier.classifyScene(fixtureImage("background-sample", "jpg")))

    #expect(result.label == PlantImageClassifier.backgroundLabel)
}

@Test
func classifySceneRejectsSingleTileFalsePositive() throws {
    // 火星地表照：單一區塊會出現某植物類的高信心誤判，
    // 需靠「至少兩個區塊同時高信心」的規則濾掉
    let classifier = try makeClassifier()

    let result = try #require(try classifier.classifyScene(fixtureImage("mars-sample", "jpg")))

    #expect(result.label == PlantImageClassifier.backgroundLabel)
}

// MARK: - resolveScene 決策規則（用實機 held-out 觀察到的真實票數）

private let bg = PlantImageClassifier.backgroundLabel

@Test
func resolveScenePicksClearWinnerEvenWhenBothPlantsFireSomeTiles() {
    // 兩類都有 ≥0.9 的塊，但 馬纓丹 大幅領先 → 應判 馬纓丹（票數取自早期實機觀察，與植物種類無關）
    let result = PlantImageClassifier.resolveScene(
        bestConfidence: ["lantana-camara": 1.0, "pelargonium-hortorum": 1.0, bg: 0.04],
        confidentTileCounts: ["lantana-camara": 23, "pelargonium-hortorum": 5]
    )
    #expect(result?.label == "lantana-camara")
}

@Test
func resolveSceneReportsUncertainOnNearTie() {
    // 天竺葵×14 vs 馬纓丹×15，差距只有 1 → 兩類拉鋸，不該硬選
    let result = PlantImageClassifier.resolveScene(
        bestConfidence: ["lantana-camara": 1.0, "pelargonium-hortorum": 1.0, bg: 0.02],
        confidentTileCounts: ["lantana-camara": 15, "pelargonium-hortorum": 14]
    )
    #expect(result?.label == bg)  // 不確定 → 落到 background
}

@Test
func resolveSceneReportsUncertainOnTheRealHeldOutMisclassification() {
    // 馬纓丹×6 vs 天竺葵×4 原本被硬判成 馬纓丹（margin 調校前的真實誤判）
    // 差距 2 < margin 3 → 應改判為不確定，而非錯誤的 馬纓丹
    let result = PlantImageClassifier.resolveScene(
        bestConfidence: ["lantana-camara": 1.0, "pelargonium-hortorum": 0.99, bg: 0.71],
        confidentTileCounts: ["lantana-camara": 6, "pelargonium-hortorum": 4]
    )
    #expect(result?.label != "lantana-camara")
    #expect(result?.label == bg)
}

@Test
func resolveSceneAcceptsLoneSmallPlantWithFewTiles() {
    // 只有一種植物達標（無競爭者）→ 不套 margin gate，保留小佔比植物偵測
    let result = PlantImageClassifier.resolveScene(
        bestConfidence: ["lantana-camara": 1.0, bg: 0.30],
        confidentTileCounts: ["lantana-camara": 2]
    )
    #expect(result?.label == "lantana-camara")
}

@Test
func resolveSceneFallsBackToBackgroundWhenNoPlantQualifies() {
    let result = PlantImageClassifier.resolveScene(
        bestConfidence: ["lantana-camara": 0.4, bg: 1.0],
        confidentTileCounts: [bg: 16]
    )
    #expect(result?.label == bg)
}
