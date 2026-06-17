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

private func makeClassifier() throws -> WitherImageClassifier {
    try WitherImageClassifier(modelURL: fixtureURL("TestWitherClassifier", "mlmodel"))
}

// MARK: - tileClassification 純函式（不需模型）

@Test
func tileClassificationMapsConfidentHealthy() {
    let result = WitherImageClassifier.tileClassification(
        label: WitherImageClassifier.healthyLabel, confidence: 0.95
    )
    #expect(result == .healthy)
}

@Test
func tileClassificationMapsConfidentWithered() {
    let result = WitherImageClassifier.tileClassification(
        label: WitherImageClassifier.witheredLabel, confidence: 0.95
    )
    #expect(result == .withered)
}

@Test
func tileClassificationIsNoPlantBelowThreshold() {
    // 信心低於門檻 → 視為沒有足夠把握的植物，不計入比例分母
    let result = WitherImageClassifier.tileClassification(
        label: WitherImageClassifier.witheredLabel, confidence: 0.55, threshold: 0.7
    )
    #expect(result == .noPlant)
}

@Test
func tileClassificationIsNoPlantForUnknownLabel() {
    // 未來模型若多了 background 類，非 healthy/withered 的標籤一律當 noPlant
    let result = WitherImageClassifier.tileClassification(label: "background", confidence: 0.99)
    #expect(result == .noPlant)
}

// MARK: - classifyTiles 整合（用 stub 模型 + 樣本圖）

@Test
func classifyTilesLabelsHealthyGreenTile() throws {
    let classifier = try makeClassifier()
    let results = classifier.classifyTiles([try fixtureImage("wither-healthy-sample", "png")])
    #expect(results == [.healthy])
}

@Test
func classifyTilesLabelsWitheredBrownTile() throws {
    let classifier = try makeClassifier()
    let results = classifier.classifyTiles([try fixtureImage("wither-withered-sample", "png")])
    #expect(results == [.withered])
}

@Test
func classifyTilesAndResolverProduceWitherRatio() throws {
    // 端到端（Mac 端）：兩塊枯 + 一塊健 → 比例 = 2/3
    let classifier = try makeClassifier()
    let tiles = [
        try fixtureImage("wither-withered-sample", "png"),
        try fixtureImage("wither-withered-sample", "png"),
        try fixtureImage("wither-healthy-sample", "png")
    ]
    let ratio = try #require(WitherScoreResolver.resolve(classifier.classifyTiles(tiles)))
    #expect(abs(ratio - 2.0 / 3.0) < 1e-9)
}

// MARK: - 共用模型查找器

@Test
func modelLocatorFindsBundledModelAndMissesUnknown() {
    // 核心 Resources 內建的 PlantClassifier 找得到；不存在的名稱回 nil（呼叫端再包成 modelNotFound）
    #expect(CoreMLModelLocator.findModelURL(named: "PlantClassifier") != nil)
    #expect(CoreMLModelLocator.findModelURL(named: "NoSuchModel") == nil)
}
